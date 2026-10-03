import Foundation
import Network
import Security

public final class HTTPServer {

    public struct Endpoints {
        public let plainPort: UInt16
        public let securePort: UInt16?
    }

    // MARK: - State

    public var localIP: String = "127.0.0.1"
    public var plainPort: UInt16 = 0
    public var securePort: UInt16 = 0
    public var downloadsDirectory: URL = FileManager.default.temporaryDirectory
    public let fileSystem = FileSystemBridge()
    public let providers = DeviceProviderRegistry()
    public let discovery = DiscoveryResponder()

    private var serverFd: Int32 = -1
    private var secureListener: NWListener?
    private var listenSource: DispatchSourceRead?

    private let serverQueue = DispatchQueue(label: "com.dropit.server.listen", qos: .userInitiated)
    private let workerQueue = DispatchQueue(label: "com.dropit.server.worker", qos: .userInitiated, attributes: .concurrent)

    private let sharedFilesLock = NSLock()
    private var internalSharedFiles: [TransferFileItem] = []

    public var sharedFiles: [TransferFileItem] {
        get {
            sharedFilesLock.lock()
            defer { sharedFilesLock.unlock() }
            return internalSharedFiles
        }
        set {
            sharedFilesLock.lock()
            internalSharedFiles = newValue
            sharedFilesLock.unlock()
        }
    }

    private let devicesLock = NSLock()
    private var internalDevices: [String: ConnectedDevice] = [:]
    private var blockedDeviceIds = Set<String>()

    private let historyLock = NSLock()
    private var internalHistory: [DeviceFileRecord] = []

    let partialsLock = NSLock()
    var activeUploads: [String: Int64] = [:]

    private let sessionLock = NSLock()
    private var internalSessionToken = UUID().uuidString

    // MARK: - Callbacks

    public var onClientConnected: ((String) -> Void)?
    public var onOutgoingProgress: ((String, Double, Int64, Int64, Double) -> Void)?
    public var onIncomingProgress: ((String, Double, Int64, Int64, Double) -> Void)?
    public var onFileReceived: ((ReceivedFileItem) -> Void)?
    public var onDevicesChanged: (([ConnectedDevice]) -> Void)?
    public var onHistoryChanged: (([DeviceFileRecord]) -> Void)?
    public var onSharedFilesChanged: (([TransferFileItem]) -> Void)?
    public var onError: ((String) -> Void)?
    public var onDeviceProvidersChanged: (([DeviceStorageProvider]) -> Void)?

    // MARK: - Init

    public init() {}

    // MARK: - Session token

    public var sessionToken: String {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        return internalSessionToken
    }

    /// Issues a fresh token. Links (and QR codes) carrying the previous token stop
    /// admitting new devices, while devices already in the session keep working.
    @discardableResult
    public func rotateSessionToken() -> String {
        sessionLock.lock()
        internalSessionToken = UUID().uuidString
        let token = internalSessionToken
        sessionLock.unlock()
        return token
    }

    // MARK: - Shared files

    public func updateSharedFiles(_ files: [TransferFileItem]) {
        sharedFiles = files
    }

    public func appendSharedFile(_ item: TransferFileItem) {
        sharedFilesLock.lock()
        internalSharedFiles.append(item)
        let copy = internalSharedFiles
        sharedFilesLock.unlock()
        DispatchQueue.main.async { [weak self] in
            self?.onSharedFilesChanged?(copy)
        }
    }

    // MARK: - Devices

    public func disconnectDevice(id: String) {
        devicesLock.lock()
        blockedDeviceIds.insert(id)
        if var dev = internalDevices[id] {
            dev.isBlocked = true
            internalDevices[id] = dev
        }
        let devList = deviceListSnapshot()
        devicesLock.unlock()
        DispatchQueue.main.async { [weak self] in
            self?.onDevicesChanged?(devList)
        }
    }

    public func isDeviceBlocked(id: String) -> Bool {
        devicesLock.lock()
        defer { devicesLock.unlock() }
        return blockedDeviceIds.contains(id)
    }

    public func getConnectedDevicesList() -> [ConnectedDevice] {
        devicesLock.lock()
        defer { devicesLock.unlock() }
        return deviceListSnapshot()
    }

    /// Caller must hold `devicesLock`.
    private func deviceListSnapshot() -> [ConnectedDevice] {
        var list = Array(internalDevices.values).sorted { $0.firstConnected > $1.firstConnected }
        if !list.contains(where: { $0.isHost }) {
            list.append(ConnectedDevice(
                id: "host_mac", name: "Host Mac", ip: localIP,
                userAgent: "macOS Dropit", firstConnected: Date(), lastActive: Date(),
                isBlocked: false, isHost: true
            ))
        }
        return list
    }

    @discardableResult
    public func registerOrUpdateDevice(id: String, name: String, ip: String, userAgent: String) -> ConnectedDevice {
        devicesLock.lock()
        var dev = internalDevices[id] ?? ConnectedDevice(id: id, name: name, ip: ip, userAgent: userAgent)
        if !name.isEmpty && name != "Unknown Device" { dev.name = name }
        dev.ip = ip
        if !userAgent.isEmpty { dev.userAgent = userAgent }
        dev.lastActive = Date()
        if blockedDeviceIds.contains(id) { dev.isBlocked = true }
        internalDevices[id] = dev
        let list = deviceListSnapshot()
        devicesLock.unlock()

        DispatchQueue.main.async { [weak self] in
            self?.onDevicesChanged?(list)
        }
        return dev
    }

    private func isKnownDevice(_ id: String) -> Bool {
        devicesLock.lock()
        defer { devicesLock.unlock() }
        return internalDevices[id] != nil
    }

    // MARK: - History

    public func getHistoryList() -> [DeviceFileRecord] {
        historyLock.lock()
        defer { historyLock.unlock() }
        return internalHistory
    }

    public func recordHistory(deviceId: String, deviceName: String, fileName: String, fileSize: Int64, direction: TransferDirection, targetDeviceId: String? = nil, targetDeviceName: String? = nil) {
        let record = DeviceFileRecord(
            deviceId: deviceId, deviceName: deviceName, fileName: fileName,
            fileSize: fileSize, direction: direction,
            targetDeviceId: targetDeviceId, targetDeviceName: targetDeviceName
        )
        historyLock.lock()
        internalHistory.insert(record, at: 0)
        let copy = internalHistory
        historyLock.unlock()
        DispatchQueue.main.async { [weak self] in
            self?.onHistoryChanged?(copy)
        }
    }

    // MARK: - Lifecycle

    public func start(preferredPort: UInt16 = 0, tlsIdentity: SecIdentity?) throws -> Endpoints {
        stop()

        let plain = try startPlainListener(port: preferredPort)

        var secure: UInt16?
        if let identity = tlsIdentity {
            if let bound = try? startSecureListener(identity: identity), bound > 0 {
                secure = bound
            }
        }

        plainPort = plain
        securePort = secure ?? 0
        return Endpoints(plainPort: plain, securePort: secure)
    }

    // MARK: - Plain listener (BSD sockets)

    private func startPlainListener(port: UInt16) throws -> UInt16 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw NSError(domain: "com.dropit.server", code: Int(errno), userInfo: [
                NSLocalizedDescriptionKey: "Could not create socket: \(String(cString: strerror(errno)))"
            ])
        }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        address.sin_addr.s_addr = in_addr_t(0)

        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.stride))
            }
        }
        guard bound == 0 else {
            let code = errno
            close(fd)
            throw NSError(domain: "com.dropit.server", code: Int(code), userInfo: [
                NSLocalizedDescriptionKey: "Could not bind port \(port): \(String(cString: strerror(code)))"
            ])
        }
        guard listen(fd, 128) == 0 else {
            let code = errno
            close(fd)
            throw NSError(domain: "com.dropit.server", code: Int(code), userInfo: [
                NSLocalizedDescriptionKey: "Could not listen on port \(port): \(String(cString: strerror(code)))"
            ])
        }

        var actual = sockaddr_in()
        var actualLength = socklen_t(MemoryLayout<sockaddr_in>.stride)
        let named = withUnsafeMutablePointer(to: &actual) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &actualLength)
            }
        }
        let resolvedPort = (named == 0) ? UInt16(bigEndian: actual.sin_port) : port

        let flags = fcntl(fd, F_GETFL, 0)
        if flags >= 0 { _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK) }

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: serverQueue)
        source.setEventHandler { [weak self] in
            self?.acceptPlainConnections(fd: fd)
        }
        source.setCancelHandler { close(fd) }
        source.resume()

        serverFd = fd
        listenSource = source
        return resolvedPort
    }

    public func stop() {
        listenSource?.cancel()
        listenSource = nil
        serverFd = -1
        secureListener?.cancel()
        secureListener = nil
        plainPort = 0
        securePort = 0

        devicesLock.lock()
        internalDevices.removeAll()
        blockedDeviceIds.removeAll()
        devicesLock.unlock()

        historyLock.lock()
        internalHistory.removeAll()
        historyLock.unlock()

        partialsLock.lock()
        activeUploads.removeAll()
        partialsLock.unlock()
    }

    private func acceptPlainConnections(fd: Int32) {
        while true {
            var clientAddress = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.stride)
            let clientFd = withUnsafeMutablePointer(to: &clientAddress) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    accept(fd, $0, &length)
                }
            }
            if clientFd < 0 { break }

            var ipBuffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            inet_ntop(AF_INET, &clientAddress.sin_addr, &ipBuffer, socklen_t(INET_ADDRSTRLEN))
            let remoteIP = String(cString: ipBuffer)

            workerQueue.async { [weak self] in
                self?.handleClient(ClientConnection(fd: clientFd, remoteIP: remoteIP))
            }
        }
    }

    // MARK: - Secure listener (Network.framework, TLS)

    /// Network.framework is the only public way to terminate TLS from an ad-hoc Swift
    /// server, so HTTPS is offered opportunistically: if the listener cannot start the
    /// app simply keeps serving plain HTTP and reports no secure endpoint.
    private func startSecureListener(identity: SecIdentity) throws -> UInt16 {
        let tls = NWProtocolTLS.Options()
        if let secIdentity = sec_identity_create(identity) {
            sec_protocol_options_set_local_identity(tls.securityProtocolOptions, secIdentity)
        }
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)

        let parameters = NWParameters()
        parameters.defaultProtocolStack.applicationProtocols.insert(tls, at: 0)

        let listener = try NWListener(using: parameters)
        let bound = DispatchSemaphore(value: 0)
        var failure: NWError?
        var resolvedPort: UInt16 = 0

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                resolvedPort = listener.port?.rawValue ?? 0
                bound.signal()
            case .failed(let error):
                failure = error
                bound.signal()
            case .cancelled:
                bound.signal()
            default:
                break
            }
        }
        listener.start(queue: serverQueue)
        _ = bound.wait(timeout: .now() + 5)

        if let failure = failure {
            listener.cancel()
            throw NSError(domain: "com.dropit.server", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "HTTPS listener unavailable: \(failure)"
            ])
        }
        guard resolvedPort > 0 else {
            listener.cancel()
            throw NSError(domain: "com.dropit.server", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "HTTPS listener did not report a port"
            ])
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleSecureConnection(connection, identity: identity)
        }
        secureListener = listener
        return resolvedPort
    }

    private func handleSecureConnection(_ connection: NWConnection, identity: SecIdentity) {
        let queue = DispatchQueue(label: "com.dropit.server.secure")
        connection.start(queue: queue)
        let remoteIP = Self.peerHost(of: connection) ?? "unknown"
        let bridge = SecureConnectionBridge(connection: connection, identity: identity)
        workerQueue.async { [weak self] in
            guard let self = self, bridge.startTLS() else { return }
            let client = ClientConnection(bridge: bridge, remoteIP: remoteIP)
            self.handleClient(client)
        }
    }

    private static func peerHost(of connection: NWConnection) -> String? {
        if let endpoint = connection.currentPath?.remoteEndpoint,
           case .hostPort(let host, _) = endpoint {
            return host.debugDescription
        }
        if case .hostPort(let host, _) = connection.endpoint {
            return host.debugDescription
        }
        return nil
    }

    // MARK: - Request handling

    struct Request {
        let method: String
        let path: String
        let query: [String: String]
        let headers: [String: String]
        let deviceId: String
        let deviceName: String
        let userAgent: String
    }

    private func handleClient(_ connection: ClientConnection) {
        defer { connection.cancel() }

        guard let request = readRequest(connection) else { return }
        if let error = onError { error("[\(request.method)] \(request.path)") }

        if request.method == "OPTIONS" {
            send(connection: connection, status: "204 No Content", headers: [
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
                "Access-Control-Allow-Headers": "*",
                "Access-Control-Max-Age": "86400"
            ], body: Data())
            return
        }

        if request.path == "/favicon.ico" || request.path.contains("apple-touch-icon") {
            send(connection: connection, status: "204 No Content", headers: [
                "Access-Control-Allow-Origin": "*"
            ], body: Data())
            return
        }

        if request.path == "/cert.crt" || request.path == "/api/cert" {
            serveCertificate(connection: connection)
            return
        }

        // A device that is not yet part of the session must present the current pairing
        // token, so refreshing the QR code stops old codes from admitting new devices
        // while already-connected devices keep working. This runs before the device is
        // registered, otherwise every request would look like a returning device.
        if !isKnownDevice(request.deviceId) {
            guard let token = request.query["token"], token == sessionToken else {
                send(connection: connection, status: "403 Forbidden", headers: [
                    "Content-Type": "text/html; charset=utf-8",
                    "Cache-Control": "no-store"
                ], body: Data(HTTPServer.expiredQRPage.utf8))
                return
            }
        }

        if isDeviceBlocked(id: request.deviceId) {
            send(connection: connection, status: "403 Forbidden", headers: [
                "Content-Type": "application/json"
            ], body: Data("{\"disconnected\":true,\"error\":\"You have been disconnected from this session\"}".utf8))
            return
        }

        _ = registerOrUpdateDevice(
            id: request.deviceId, name: request.deviceName,
            ip: connection.remoteIP, userAgent: request.userAgent
        )

        // "/download/<id>" is a prefix route rather than an exact path.
        if request.method == "GET", request.path.hasPrefix("/download/") {
            serveDownload(request: request, connection: connection)
            return
        }

        switch (request.method, request.path) {
        case ("GET", "/"):
            serveIndex(connection: connection)
        case ("POST", "/api/notify-open"):
            let ip = connection.remoteIP
            DispatchQueue.main.async { [weak self] in self?.onClientConnected?(ip) }
            sendJSON(connection: connection, object: ["status": "ok"])

        case ("POST", "/api/register-device"):
            let dev = registerOrUpdateDevice(
                id: request.deviceId, name: request.deviceName,
                ip: connection.remoteIP, userAgent: request.userAgent
            )
            sendJSON(connection: connection, object: [
                "status": dev.isBlocked ? "blocked" : "ok",
                "deviceId": dev.id, "deviceName": dev.name, "isBlocked": dev.isBlocked
            ])

        case ("GET", "/api/devices"):
            let devices: [[String: Any]] = getConnectedDevicesList().map { dev in
                [
                    "id": dev.id, "name": dev.name, "ip": dev.ip, "icon": dev.iconName,
                    "isBlocked": dev.isBlocked, "isHost": dev.isHost,
                    "firstConnected": ISO8601DateFormatter().string(from: dev.firstConnected),
                    "lastActive": ISO8601DateFormatter().string(from: dev.lastActive)
                ]
            }
            sendJSON(connection: connection, object: ["devices": devices])

        case ("POST", "/api/disconnect"):
            disconnectDevice(id: request.deviceId)
            sendJSON(connection: connection, object: ["status": "ok", "disconnected": true])

        case ("GET", "/api/history"):
            let formatter = ISO8601DateFormatter()
            let history: [[String: Any]] = getHistoryList().map { rec in
                var entry: [String: Any] = [
                    "id": rec.id, "deviceId": rec.deviceId, "deviceName": rec.deviceName,
                    "fileName": rec.fileName, "fileSize": rec.fileSize,
                    "formattedSize": rec.formattedSize, "direction": rec.direction.rawValue,
                    "timestamp": formatter.string(from: rec.timestamp), "symbol": rec.symbol
                ]
                if let tid = rec.targetDeviceId { entry["targetDeviceId"] = tid }
                if let tname = rec.targetDeviceName { entry["targetDeviceName"] = tname }
                return entry
            }
            sendJSON(connection: connection, object: ["history": history])

        case ("GET", "/api/sync"), ("GET", "/api/files"):
            serveSync(connection: connection, callerDeviceId: request.deviceId)

        case ("GET", "/api/upload-status"):
            serveUploadStatus(connection: connection, name: request.query["name"] ?? "")

        case ("POST", "/api/upload"):
            handleUpload(request: request, connection: connection)


        case ("POST", "/api/device-provider/register"):
            handleProviderRegistration(request: request, connection: connection)

        case ("GET", "/api/device-providers"):
            let list = providers.all().map { provider in
                [
                    "id": provider.id,
                    "name": provider.name,
                    "displayName": provider.displayName,
                    "model": provider.model,
                    "manufacturer": provider.manufacturer,
                    "address": provider.address,
                    "port": Int(provider.port),
                    "lastSeen": ISO8601DateFormatter().string(from: provider.lastSeen),
                    "supportsAllFilesAccess": provider.supportsAllFilesAccess
                ]
            }
            sendJSON(connection: connection, object: ["providers": list])

        case ("POST", "/api/device-provider/remove"):
            let body = readBody(connection, headers: request.headers, limit: 16 * 1024) ?? Data()
            let id = (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["id"] as? String ?? ""
            providers.remove(id: id)
            sendJSON(connection: connection, object: ["status": "ok"])

        case ("GET", "/api/fs/roots"):
            sendJSON(connection: connection, object: ["roots": fileSystem.rootPaths()])
        case ("GET", "/api/fs/list"):
            serveList(request: request, connection: connection)

        case ("GET", "/api/fs/read"):
            serveFsRead(request: request, connection: connection)

        case ("POST", "/api/fs/mkdir"):
            serveFsMkdir(request: request, connection: connection)

        case ("POST", "/api/fs/rename"):
            serveFsRename(request: request, connection: connection)

        case ("POST", "/api/fs/delete"):
            serveFsDelete(request: request, connection: connection)

        case ("POST", "/api/fs/write"):
            serveFsWrite(request: request, connection: connection)

        default:
            send(connection: connection, status: "404 Not Found",
                 headers: ["Content-Type": "text/plain"], body: Data("Not Found".utf8))
        }
    }

    private func readRequest(_ connection: ClientConnection) -> Request? {
        let delimiter = Data([0x0D, 0x0A, 0x0D, 0x0A])
        var buffer = Data()
        var headerRange: Range<Data.Index>?
        var budgetMs = 5000

        while budgetMs > 0 {
            switch connection.read(maxBytes: 8192, timeoutMs: 1000) {
            case .data(let chunk):
                buffer.append(chunk)
                if let range = buffer.range(of: delimiter) {
                    headerRange = range
                    break
                }
                if buffer.count > 65536 { return nil }
            case .timeout:
                budgetMs -= 1000
            case .eof:
                return nil
            }
            if headerRange != nil { break }
        }

        guard let range = headerRange,
              let headerString = String(data: buffer.subdata(in: 0..<range.upperBound), encoding: .utf8) else { return nil }

        let initialBody = buffer.subdata(in: range.upperBound..<buffer.count)
        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        let components = URLComponents(string: parts[1])
        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] {
            if let value = item.value { query[item.name] = value }
        }

        let deviceId = headers["x-device-id"] ?? query["deviceId"] ?? query["id"]
            ?? "device_\(connection.remoteIP.replacingOccurrences(of: ".", with: "_"))"
        let rawName = headers["x-device-name"] ?? query["deviceName"] ?? query["name2"] ?? "Device (\(connection.remoteIP))"
        let deviceName = rawName.removingPercentEncoding ?? rawName

        pendingInitialBody = initialBody
        return Request(
            method: parts[0].uppercased(),
            path: components?.path ?? "/",
            query: query,
            headers: headers,
            deviceId: deviceId,
            deviceName: deviceName,
            userAgent: headers["user-agent"] ?? ""
        )
    }

    /// Body bytes that arrived alongside the request headers.
    var pendingInitialBody = Data()

    func readBody(_ connection: ClientConnection, headers: [String: String], limit: Int) -> Data? {
        var body = pendingInitialBody
        pendingInitialBody = Data()
        guard let lengthText = headers["content-length"], let length = Int(lengthText), length > 0 else {
            return body.isEmpty ? Data() : body
        }
        let capped = min(length, limit)
        body.reserveCapacity(capped)
        var total = body.count
        while total < capped {
            switch connection.read(maxBytes: min(64 * 1024, capped - total), timeoutMs: 15_000) {
            case .data(let chunk):
                body.append(chunk)
                total += chunk.count
            case .timeout, .eof:
                return total > 0 ? body : nil
            }
        }
        if body.count > limit {
            connection.discard(body.count - limit)
            body = body.prefix(limit)
        }
        return body
    }

    // MARK: - Core handlers

    private func serveIndex(connection: ClientConnection) {
        let data = Data(ReceiverWebTemplate.html(context: webContext).utf8)
        send(connection: connection, status: "200 OK", headers: [
            "Content-Type": "text/html; charset=utf-8",
            "Content-Length": "\(data.count)",
            "Cache-Control": "no-cache, no-store, must-revalidate",
            "Access-Control-Allow-Origin": "*"
        ], body: data)
    }

    private var webContext: ReceiverWebTemplate.Context {
        let ips = ([localIP] + NetworkHelper.getAvailableInterfaces().map { $0.ip })
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return ReceiverWebTemplate.Context(
            sessionToken: sessionToken,
            secureAvailable: securePort > 0,
            hostNames: ["This Mac"] + ips
        )
    }

    private func serveCertificate(connection: ClientConnection) {
        let ips = [localIP] + NetworkHelper.getAvailableInterfaces().map { $0.ip }
        guard let der = TLSCertificateManager.shared.certificateData(covering: ips) else {
            send(connection: connection, status: "404 Not Found",
                 headers: ["Content-Type": "text/plain"], body: Data("No certificate".utf8))
            return
        }
        let pem = "-----BEGIN CERTIFICATE-----\n"
            + der.base64EncodedString().chunked(every: 64).joined(separator: "\n")
            + "\n-----END CERTIFICATE-----\n"
        let body = Data(pem.utf8)
        send(connection: connection, status: "200 OK", headers: [
            "Content-Type": "application/x-x509-ca-cert",
            "Content-Length": "\(body.count)",
            "Content-Disposition": "attachment; filename=\"Dropit-Local-CA.crt\"",
            "Access-Control-Allow-Origin": "*"
        ], body: body)
    }

    private func serveSync(connection: ClientConnection, callerDeviceId: String) {
        let visible = sharedFiles.filter { item in
            if callerDeviceId == "host_mac" { return true }
            guard let target = item.targetDeviceId, !target.isEmpty, target != "all" else { return true }
            return target == callerDeviceId || item.senderDeviceId == callerDeviceId
        }
        let files: [[String: Any]] = visible.map { item in
            [
                "id": item.id, "name": item.name, "size": item.size,
                "formattedSize": item.formattedSize, "mime": item.mimeType, "symbol": item.symbol,
                "senderDeviceId": item.senderDeviceId ?? "host_mac",
                "senderDeviceName": item.senderDeviceName ?? "Host Mac",
                "targetDeviceId": item.targetDeviceId ?? "all",
                "targetDeviceName": item.targetDeviceName ?? "Everyone",
                "isForMe": (item.targetDeviceId == callerDeviceId)
            ]
        }
        sendJSON(connection: connection, object: ["sessionActive": true, "files": files])
    }

    private static let expiredQRPage = """
    <!DOCTYPE html><html><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <title>Dropit - Code expired</title>
    <style>
      body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;background:#000;color:#fff;
           display:flex;align-items:center;justify-content:center;height:100vh;margin:0;text-align:center;padding:24px}
      .box{max-width:340px}
      .icon{width:64px;height:64px;margin:0 auto 18px;border-radius:20px;background:rgba(255,159,10,.15);
            border:1px solid rgba(255,159,10,.35);display:flex;align-items:center;justify-content:center;font-size:30px}
      h1{font-size:20px;margin:0 0 10px}
      p{color:#8e8e93;font-size:14px;line-height:1.5;margin:0}
    </style></head><body><div class="box">
      <div class="icon">&#8635;</div>
      <h1>This code has expired</h1>
      <p>The host Mac refreshed its pairing code. Ask for a new QR code on the Mac and scan it again.</p>
    </div></body></html>
    """

    // MARK: - Sending

    func send(connection: ClientConnection, status: String, headers: [String: String], body: Data) {
        var header = "HTTP/1.1 \(status)\r\n"
        for (key, value) in headers {
            header += "\(key): \(value)\r\n"
        }
        if headers["Content-Length"] == nil {
            header += "Content-Length: \(body.count)\r\n"
        }
        if headers["Access-Control-Allow-Origin"] == nil {
            header += "Access-Control-Allow-Origin: *\r\n"
        }
        header += "Connection: close\r\n\r\n"
        var payload = Data(header.utf8)
        payload.append(body)
        _ = connection.writeAll(payload)
    }

    func sendJSON(connection: ClientConnection, object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        send(connection: connection, status: "200 OK", headers: [
            "Content-Type": "application/json",
            "Content-Length": "\(data.count)",
            "Cache-Control": "no-store"
        ], body: data)
    }

    func sendError(connection: ClientConnection, status: String, message: String) {
        send(connection: connection, status: status, headers: [
            "Content-Type": "application/json",
            "Cache-Control": "no-store"
        ], body: Data("{\"error\":\(jsonString(message))}".utf8))
    }

    private func jsonString(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let array = String(data: data, encoding: .utf8) else { return "\"\"" }
        return String(array.dropFirst().dropLast())
    }
}

extension String {
    func chunked(every size: Int) -> [String] {
        guard size > 0, count > size else { return [self] }
        var result: [String] = []
        var index = startIndex
        while index < endIndex {
            let next = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
            result.append(String(self[index..<next]))
            index = next
        }
        return result
    }
}
