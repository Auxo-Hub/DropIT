import Foundation

extension HTTPServer {

    private func decodeJSONObject(_ data: Data) -> [String: String] {
        guard !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        var result: [String: String] = [:]
        for (key, value) in object {
            if let text = value as? String {
                result[key] = text
            } else if let number = value as? NSNumber {
                result[key] = number.stringValue
            }
        }
        return result
    }

    // MARK: - List

    func serveList(request: Request, connection: ClientConnection) {
        let path = request.query["path"] ?? ""
        do {
            let entries = try fileSystem.list(at: path)
            let formatter = ISO8601DateFormatter()
            let payload: [[String: Any]] = entries.map { entry in
                [
                    "name": entry.name,
                    "path": entry.path,
                    "isDirectory": entry.isDirectory,
                    "size": entry.size,
                    "formattedSize": entry.isDirectory ? "" : FileMIME.formatBytes(entry.size),
                    "modified": entry.modified.map { formatter.string(from: $0) } ?? "",
                    "isHidden": entry.isHidden,
                    "isSymlink": entry.isSymlink
                ]
            }
            sendJSON(connection: connection, object: [
                "path": path,
                "parent": parentPath(for: path),
                "entries": payload,
                "roots": fileSystem.rootPaths()
            ])
        } catch {
            sendError(connection: connection, status: statusCode(for: error), message: error.localizedDescription)
        }
    }

    private func parentPath(for path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed == "/" || trimmed == "~" { return "" }
        if trimmed == "~/" { return "~" }
        if trimmed.hasSuffix("/") { return String(trimmed.dropLast()) }
        let ns = trimmed as NSString
        let parent = ns.deletingLastPathComponent
        return parent == trimmed ? "" : parent
    }

    // MARK: - Device storage providers

    /// A phone registers itself and receives a secret that authorises later requests
    /// against its own storage server. The secret is only ever sent back to the phone
    /// that asked for it, over the session token it already proved it knows.
    func handleProviderRegistration(request: Request, connection: ClientConnection) {
        let body = readBody(connection, headers: request.headers, limit: 64 * 1024) ?? Data()
        let fields = decodeJSONObject(body)

        let name = fields["name"] ?? "Android device"
        let model = fields["model"] ?? ""
        let manufacturer = fields["manufacturer"] ?? ""
        guard let port = UInt16(fields["port"] ?? ""), port > 0 else {
            sendError(connection: connection, status: "400 Bad Request", message: "The phone did not report a port")
            return
        }

        // Reuse the registration when the same phone returns, so its entry does not
        // multiply, but hand back a fresh secret each time.
        let existing = providers.all().first { existing in
            existing.address == connection.remoteIP && existing.port == port
        }
        let id = existing?.id ?? "prov_" + UUID().uuidString
        let secret = UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "")

        // Ask the phone what it can do, so the Mac can show whether the user has also
        // enabled all-files access. A failure here is not important, so it is best effort.
        let allFiles = Self.probeAllFilesAccess(address: connection.remoteIP, port: port, secret: secret)

        let provider = providers.register(
            id: id,
            name: name,
            model: model,
            manufacturer: manufacturer,
            address: connection.remoteIP,
            port: port,
            secret: secret,
            supportsAllFilesAccess: allFiles
        )

        DispatchQueue.main.async { [weak self] in
            self?.onDeviceProvidersChanged?(self?.providers.all() ?? [])
        }

        sendJSON(connection: connection, object: [
            "status": "ok",
            "id": provider.id,
            "secret": provider.secret,
            "name": "Dropit Mac",
            "displayName": "Dropit Mac"
        ])
    }

    /// Synchronous capability probe; returns false when the phone cannot be reached.
    private static func probeAllFilesAccess(address: String, port: UInt16, secret: String) -> Bool {
        guard let url = URL(string: "http://\(address):\(port)/status?secret=\(secret)") else { return false }
        let semaphore = DispatchSemaphore(value: 0)
        var result = false
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        request.setValue(secret, forHTTPHeaderField: "x-dropit-mac")
        URLSession.shared.dataTask(with: request) { data, response, _ in
            defer { semaphore.signal() }
            guard let data = data,
                  (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            result = (object["allFilesAccess"] as? Bool) ?? false
        }.resume()
        _ = semaphore.wait(timeout: .now() + 4)
        return result
    }

    private func statusCode(for error: Error) -> String {
        switch error {
        case FileSystemBridge.BridgeError.notFound:
            return "404 Not Found"
        case FileSystemBridge.BridgeError.outsideAllowedRoots:
            return "403 Forbidden"
        case FileSystemBridge.BridgeError.alreadyExists:
            return "409 Conflict"
        case FileSystemBridge.BridgeError.notADirectory, FileSystemBridge.BridgeError.notAFile:
            return "400 Bad Request"
        default:
            return "400 Bad Request"
        }
    }

    // MARK: - Read / download

    func serveFsRead(request: Request, connection: ClientConnection) {
        let path = request.query["path"] ?? ""
        guard let url = try? fileSystem.resolve(path) else {
            sendError(connection: connection, status: "403 Forbidden", message: "Path is not shared")
            return
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            sendError(connection: connection, status: "404 Not Found", message: "No such file")
            return
        }
        stream(
            url: url,
            connection: connection,
            mime: FileMIME.mimeType(for: url),
            downloadName: request.query["download"] == "1" ? url.lastPathComponent : nil,
            rangeHeader: request.headers["range"],
            deviceId: request.deviceId,
            deviceName: request.deviceName,
            onCompletion: nil,
            onProgress: nil
        )
    }

    // MARK: - Write

    func serveFsWrite(request: Request, connection: ClientConnection) {
        let path = request.query["path"] ?? ""
        let name = request.query["name"] ?? ""
        guard let body = readBody(connection, headers: request.headers, limit: 512 * 1024 * 1024) else {
            sendError(connection: connection, status: "400 Bad Request", message: "Could not read request body")
            return
        }
        do {
            let target = try fileSystem.writeFile(at: path, name: name, contents: body)
            let size = (try? FileManager.default.attributesOfItem(atPath: target.path)[.size] as? Int64) ?? Int64(body.count)
            recordHistory(
                deviceId: request.deviceId, deviceName: request.deviceName,
                fileName: target.lastPathComponent, fileSize: size,
                direction: .receivedFromDevice
            )
            sendJSON(connection: connection, object: [
                "status": "ok", "name": target.lastPathComponent,
                "path": target.path, "size": size
            ])
        } catch {
            sendError(connection: connection, status: statusCode(for: error), message: error.localizedDescription)
        }
    }

    // MARK: - Mkdir

    func serveFsMkdir(request: Request, connection: ClientConnection) {
        let payload = decodeJSONObject(readBody(connection, headers: request.headers, limit: 64 * 1024) ?? Data())
        do {
            let target = try fileSystem.createDirectory(
                at: payload["path"] ?? "",
                name: payload["name"] ?? ""
            )
            sendJSON(connection: connection, object: [
                "status": "ok", "name": target.lastPathComponent, "path": target.path
            ])
        } catch {
            sendError(connection: connection, status: statusCode(for: error), message: error.localizedDescription)
        }
    }

    // MARK: - Rename

    func serveFsRename(request: Request, connection: ClientConnection) {
        let payload = decodeJSONObject(readBody(connection, headers: request.headers, limit: 64 * 1024) ?? Data())
        do {
            let target = try fileSystem.rename(
                at: payload["path"] ?? "",
                to: payload["name"] ?? ""
            )
            sendJSON(connection: connection, object: [
                "status": "ok", "name": target.lastPathComponent, "path": target.path
            ])
        } catch {
            sendError(connection: connection, status: statusCode(for: error), message: error.localizedDescription)
        }
    }

    // MARK: - Delete

    func serveFsDelete(request: Request, connection: ClientConnection) {
        let payload = decodeJSONObject(readBody(connection, headers: request.headers, limit: 64 * 1024) ?? Data())
        do {
            try fileSystem.delete(at: payload["path"] ?? "")
            sendJSON(connection: connection, object: ["status": "ok"])
        } catch {
            sendError(connection: connection, status: statusCode(for: error), message: error.localizedDescription)
        }
    }
}
