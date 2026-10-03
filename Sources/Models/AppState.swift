import Foundation
import SwiftUI
import AppKit
import Combine

public struct TransferFileItem: Identifiable, Hashable {
    public let id: String
    public let url: URL
    public let name: String
    public let size: Int64
    public let formattedSize: String
    public let mimeType: String
    public let symbol: String
    public let targetDeviceId: String? // nil or "all" = everyone
    public let targetDeviceName: String?
    public let senderDeviceId: String? // nil or "host_mac" = Host Mac
    public let senderDeviceName: String?
    
    public init(url: URL, targetDeviceId: String? = nil, targetDeviceName: String? = nil, senderDeviceId: String? = nil, senderDeviceName: String? = nil) {
        self.id = UUID().uuidString
        self.url = url
        self.name = url.lastPathComponent
        let s = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        self.size = s
        self.formattedSize = FileMIME.formatBytes(s)
        self.mimeType = FileMIME.mimeType(for: url)
        self.symbol = FileMIME.sfSymbolName(for: url)
        self.targetDeviceId = targetDeviceId
        self.targetDeviceName = targetDeviceName
        self.senderDeviceId = senderDeviceId
        self.senderDeviceName = senderDeviceName
    }
}

public struct ReceivedFileItem: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let size: Int64
    public let formattedSize: String
    public let savedPath: String
    public let receivedAt: Date
    public let senderIP: String
    public let symbol: String
    
    public init(name: String, size: Int64, savedPath: String, senderIP: String) {
        self.id = UUID().uuidString
        self.name = name
        self.size = size
        self.formattedSize = FileMIME.formatBytes(size)
        self.savedPath = savedPath
        self.receivedAt = Date()
        self.senderIP = senderIP
        self.symbol = FileMIME.sfSymbolName(for: URL(fileURLWithPath: name))
    }
}

public struct ConnectedDevice: Identifiable, Hashable, Codable {
    public let id: String
    public var name: String
    public var ip: String
    public var userAgent: String
    public var firstConnected: Date
    public var lastActive: Date
    public var isBlocked: Bool
    public var isHost: Bool
    
    public init(id: String, name: String, ip: String, userAgent: String, firstConnected: Date = Date(), lastActive: Date = Date(), isBlocked: Bool = false, isHost: Bool = false) {
        self.id = id
        self.name = name
        self.ip = ip
        self.userAgent = userAgent
        self.firstConnected = firstConnected
        self.lastActive = lastActive
        self.isBlocked = isBlocked
        self.isHost = isHost
    }
    
    public var iconName: String {
        if isHost { return "display" }
        let lower = name.lowercased() + " " + userAgent.lowercased()
        if lower.contains("iphone") { return "iphone" }
        if lower.contains("ipad") { return "ipad" }
        if lower.contains("android") { return "smartphone" }
        if lower.contains("macintosh") || lower.contains("mac os") { return "laptopcomputer" }
        if lower.contains("windows") { return "desktopcomputer" }
        if lower.contains("linux") { return "terminal" }
        return "network"
    }
}

public enum TransferDirection: String, Codable {
    case sentToDevice
    case receivedFromDevice
    
    public var label: String {
        switch self {
        case .sentToDevice: return "Sent to Device"
        case .receivedFromDevice: return "Received on Mac"
        }
    }
}

public struct DeviceFileRecord: Identifiable, Hashable, Codable {
    public let id: String
    public let deviceId: String
    public let deviceName: String
    public let fileName: String
    public let fileSize: Int64
    public let formattedSize: String
    public let direction: TransferDirection
    public let timestamp: Date
    public let symbol: String
    public let targetDeviceId: String?
    public let targetDeviceName: String?
    
    public init(id: String = UUID().uuidString, deviceId: String, deviceName: String, fileName: String, fileSize: Int64, direction: TransferDirection, timestamp: Date = Date(), targetDeviceId: String? = nil, targetDeviceName: String? = nil) {
        self.id = id
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.fileName = fileName
        self.fileSize = fileSize
        self.formattedSize = FileMIME.formatBytes(fileSize)
        self.direction = direction
        self.timestamp = timestamp
        self.symbol = FileMIME.sfSymbolName(for: URL(fileURLWithPath: fileName))
        self.targetDeviceId = targetDeviceId
        self.targetDeviceName = targetDeviceName
    }
}

public struct ActiveTransferProgress: Equatable {
    public let fileName: String
    public let progress: Double // 0.0 to 1.0
    public let bytesTransferred: Int64
    public let totalBytes: Int64
    public let speedFormatted: String
    public let isReceiving: Bool // true for incoming upload from phone, false for outgoing download to phone
}

public class AppState: ObservableObject {
    @Published public var isSessionActive: Bool = false
    @Published public var sharedFiles: [TransferFileItem] = []
    @Published public var receivedFiles: [ReceivedFileItem] = []
    @Published public var connectedClients: [String] = []
    @Published public var devices: [ConnectedDevice] = []
    @Published public var transferHistory: [DeviceFileRecord] = []
    @Published public var activeTransfer: ActiveTransferProgress?
    
    @Published public var availableInterfaces: [NetworkInterfaceInfo] = []
    @Published public var selectedInterface: NetworkInterfaceInfo?
    @Published public var serverPort: UInt16 = 0
    @Published public var serverURLString: String = ""
    @Published public var secureURLString: String = ""
    @Published public var isSecureAvailable: Bool = false
    @Published public var useSecureConnection: Bool = false
    @Published public var qrCodeImage: NSImage?
    @Published public var showCopiedAlert: Bool = false
    @Published public var certificateInfo: TLSCertificateInfo?
    @Published public var sessionTokenString: String = ""
    @Published public var sharedFolders: [String] = [FileManager.default.homeDirectoryForCurrentUser.path]
    @Published public var lastErrorMessage: String?
    @Published public var deviceProviders: [DeviceStorageProvider] = []
    
    public let downloadsFolder: URL
    private var server: HTTPServer?
    
    public init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.downloadsFolder = home.appendingPathComponent("Downloads/Dropit", isDirectory: true)
        try? FileManager.default.createDirectory(at: downloadsFolder, withIntermediateDirectories: true)
        
        refreshInterfaces()
    }
    
    public func refreshInterfaces() {
        let interfaces = NetworkHelper.getAvailableInterfaces()
        self.availableInterfaces = interfaces
        if selectedInterface == nil || !interfaces.contains(where: { $0.ip == selectedInterface?.ip }) {
            self.selectedInterface = interfaces.first(where: { $0.isWiFi }) ?? interfaces.first
        }
    }
    
    public func startSession(with files: [URL] = []) {
        refreshInterfaces()
        
        let newServer = HTTPServer()
        let ip = selectedInterface?.ip ?? NetworkHelper.getPreferredIP()
        newServer.localIP = ip
        newServer.downloadsDirectory = self.downloadsFolder
        
        // Register callbacks
        newServer.onClientConnected = { [weak self] clientIP in
            guard let self = self else { return }
            if !self.connectedClients.contains(clientIP) {
                self.connectedClients.append(clientIP)
            }
        }
        
        newServer.onOutgoingProgress = { [weak self] fileName, progress, sent, total, speed in
            guard let self = self else { return }
            if progress >= 1.0 {
                self.activeTransfer = nil
            } else {
                self.activeTransfer = ActiveTransferProgress(
                    fileName: fileName,
                    progress: progress,
                    bytesTransferred: sent,
                    totalBytes: total,
                    speedFormatted: "\(FileMIME.formatBytes(Int64(speed)))/s",
                    isReceiving: false
                )
            }
        }
        
        newServer.onIncomingProgress = { [weak self] fileName, progress, received, total, speed in
            guard let self = self else { return }
            if progress >= 1.0 {
                self.activeTransfer = nil
            } else {
                self.activeTransfer = ActiveTransferProgress(
                    fileName: fileName,
                    progress: progress,
                    bytesTransferred: received,
                    totalBytes: total,
                    speedFormatted: "\(FileMIME.formatBytes(Int64(speed)))/s",
                    isReceiving: true
                )
            }
        }
        
        newServer.onDevicesChanged = { [weak self] updatedDevices in
            guard let self = self else { return }
            self.devices = updatedDevices
            self.connectedClients = updatedDevices.filter { !$0.isBlocked }.map { $0.ip }
        }
        
        newServer.onHistoryChanged = { [weak self] history in
            guard let self = self else { return }
            self.transferHistory = history
        }
        
        newServer.onSharedFilesChanged = { [weak self] files in
            guard let self = self else { return }
            self.sharedFiles = files
        }

        newServer.onDeviceProvidersChanged = { [weak self] providers in
            DispatchQueue.main.async {
                self?.deviceProviders = providers
            }
        }
        
        newServer.onFileReceived = { [weak self] item in
            guard let self = self else { return }
            self.receivedFiles.insert(item, at: 0)
            self.activeTransfer = nil
            NSSound(named: "Glass")?.play()
        }
        
        do {
            let ips = ([ip] + NetworkHelper.getAvailableInterfaces().map { $0.ip })
                .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            let identity = TLSCertificateManager.shared.identity(covering: ips)
            newServer.fileSystem.setRoots(sharedFolders.map { URL(fileURLWithPath: $0) })

            let endpoints = try newServer.start(preferredPort: 0, tlsIdentity: identity)
            self.serverPort = endpoints.plainPort
            self.isSecureAvailable = endpoints.securePort != nil
            self.sessionTokenString = newServer.sessionToken
            self.certificateInfo = identity != nil ? TLSCertificateManager.shared.info(covering: ips) : nil
            self.server = newServer
            self.isSessionActive = true
            updateServerURLs()

            // Let phones on this network find the Mac without any manual setup.
            newServer.discovery.start(port: endpoints.plainPort, token: newServer.sessionToken)

            if !files.isEmpty {
                addSharedFiles(files)
            }
        } catch {
            self.lastErrorMessage = "Could not start the transfer server: \(error.localizedDescription)"
            print("Failed to start server: \(error)")
        }
    }

    /// Issues a new pairing code. Old QR codes stop admitting new devices, but devices
    /// already connected to this session keep working.
    public func refreshPairingCode() {
        guard let server = server else { return }
        server.rotateSessionToken()
        self.sessionTokenString = server.sessionToken
        updateServerURLs()
    }

    public func setUseSecureConnection(_ enabled: Bool) {
        self.useSecureConnection = enabled && isSecureAvailable
        updateServerURLs()
    }

    public func activeURLString() -> String {
        return (useSecureConnection && isSecureAvailable) ? secureURLString : serverURLString
    }

    public func setSharedFolders(_ folders: [String]) {
        self.sharedFolders = folders
        server?.fileSystem.setRoots(folders.map { URL(fileURLWithPath: $0) })
    }
    
    public func addSharedFiles(_ urls: [URL], targetDevice: ConnectedDevice? = nil) {
        for url in urls {
            // Avoid exact duplicate path entries for same target
            if !sharedFiles.contains(where: { $0.url.path == url.path && $0.targetDeviceId == targetDevice?.id }) {
                let item = TransferFileItem(
                    url: url,
                    targetDeviceId: targetDevice?.id,
                    targetDeviceName: targetDevice?.name,
                    senderDeviceId: "host_mac",
                    senderDeviceName: "Host Mac"
                )
                sharedFiles.append(item)
            }
        }
        server?.updateSharedFiles(sharedFiles)
    }
    
    public func removeSharedFile(id: String) {
        sharedFiles.removeAll(where: { $0.id == id })
        server?.updateSharedFiles(sharedFiles)
    }
    
    public func updateSelectedInterface(_ interface: NetworkInterfaceInfo) {
        self.selectedInterface = interface
        server?.localIP = interface.ip
        updateServerURLs()
    }

    private func updateServerURLs() {
        let ip = selectedInterface?.ip ?? NetworkHelper.getPreferredIP()
        let token = sessionTokenString
        var plain = "http://\(ip):\(serverPort)/"
        var secure = ""
        if isSecureAvailable, let securePort = server?.securePort, securePort > 0 {
            secure = "https://\(ip):\(securePort)/"
        }
        if !token.isEmpty {
            plain += "?token=\(token)"
            if !secure.isEmpty { secure += "?token=\(token)" }
        }
        self.serverURLString = plain
        self.secureURLString = secure
        if !isSecureAvailable { self.useSecureConnection = false }
        let active = activeURLString()
        self.qrCodeImage = active.isEmpty ? nil : QRCodeGenerator.generateImage(from: active, size: 280)
    }
    
    public func copyLink() {
        let link = activeURLString()
        guard !link.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link, forType: .string)
        self.showCopiedAlert = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.showCopiedAlert = false
        }
    }

    public func openInBrowser() {
        let link = activeURLString()
        guard let url = URL(string: link) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Reveals the generated certificate so the user can add it to a phone's trust store.
    public func revealCertificateInFinder() {
        guard let der = TLSCertificateManager.shared.certificateData(covering: []) else { return }
        let dir = downloadsFolder
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = dir.appendingPathComponent("Dropit-Local-CA.crt")
        do {
            let pem = "-----BEGIN CERTIFICATE-----\n"
                + der.base64EncodedString().chunked(every: 64).joined(separator: "\n")
                + "\n-----END CERTIFICATE-----\n"
            try Data(pem.utf8).write(to: target)
            NSWorkspace.shared.selectFile(target.path, inFileViewerRootedAtPath: dir.path)
        } catch {
            lastErrorMessage = "Could not write the certificate: \(error.localizedDescription)"
        }
    }
    
    public func openDownloadsFolder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: downloadsFolder.path)
    }
    
    public func showInFinder(filePath: String) {
        NSWorkspace.shared.selectFile(filePath, inFileViewerRootedAtPath: downloadsFolder.path)
    }
    
    public func disconnectDevice(id: String) {
        server?.disconnectDevice(id: id)
    }
    
    public func history(for deviceId: String) -> [DeviceFileRecord] {
        return transferHistory.filter { $0.deviceId == deviceId }
    }
    
    public func endSession() {
        server?.stop()
        server = nil
        isSessionActive = false
        sharedFiles.removeAll()
        connectedClients.removeAll()
        devices.removeAll()
        transferHistory.removeAll()
        activeTransfer = nil
        deviceProviders.removeAll()
        serverPort = 0
        serverURLString = ""
        secureURLString = ""
        isSecureAvailable = false
        useSecureConnection = false
        qrCodeImage = nil
        sessionTokenString = ""
    }
}
