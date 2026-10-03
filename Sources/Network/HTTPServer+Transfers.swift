import Foundation

extension HTTPServer {

    // MARK: - Byte ranges

    struct ByteRange {
        let start: Int64
        let end: Int64
        let isPartial: Bool
    }

    /// Parses a single-range `Range: bytes=a-b` header. Multi-range requests are
    /// deliberately ignored and served in full, which is always a valid response.
    static func parseRange(_ header: String?, totalSize: Int64) -> ByteRange? {
        guard let header = header, totalSize > 0 else { return nil }
        let trimmed = header.trimmingCharacters(in: .whitespaces).lowercased()
        guard trimmed.hasPrefix("bytes=") else { return nil }
        let spec = trimmed.dropFirst(6)
        guard !spec.contains(",") else { return nil }
        let parts = spec.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard let firstText = parts.first, let first = Int64(firstText) else { return nil }

        let lastText: Int64? = parts.count > 1 ? Int64(parts[1]) : nil

        if first < 0 {
            // suffix range: bytes=-N means the final N bytes
            guard let last = lastText, last > 0 else { return nil }
            let length = min(last, totalSize)
            guard length > 0 else { return nil }
            return ByteRange(start: totalSize - length, end: totalSize - 1, isPartial: true)
        }
        guard first < totalSize else { return nil }
        let end = min(lastText ?? (totalSize - 1), totalSize - 1)
        guard end >= first else { return nil }
        return ByteRange(start: first, end: end, isPartial: true)
    }

    // MARK: - Shared file downloads

    func serveDownload(request: Request, connection: ClientConnection) {
        let currentFiles = sharedFiles
        var target: TransferFileItem?

        if let fileId = request.query["id"] {
            target = currentFiles.first { $0.id == fileId }
        } else {
            // "/download/<id>" splits into ["", "download", "<id>"]
            let segments = request.path.split(separator: "/").map(String.init)
            if segments.count >= 3, segments[1] == "download" {
                target = currentFiles.first { $0.id == segments[2] }
            } else if currentFiles.count == 1 {
                target = currentFiles.first
            }
        }

        guard let item = target else {
            send(connection: connection, status: "404 Not Found",
                 headers: ["Content-Type": "text/plain"], body: Data("File not found".utf8))
            return
        }

        stream(
            url: item.url,
            connection: connection,
            mime: item.mimeType,
            downloadName: item.name,
            rangeHeader: request.headers["range"],
            deviceId: request.deviceId,
            deviceName: request.deviceName,
            // `stream` runs synchronously, so capturing self strongly here cannot form
            // a retain cycle and keeps the capture consistent with the outer closure.
            onCompletion: { _, fileSize in
                self.recordHistory(
                    deviceId: request.deviceId, deviceName: request.deviceName,
                    fileName: item.name, fileSize: fileSize,
                    direction: .sentToDevice,
                    targetDeviceId: item.targetDeviceId, targetDeviceName: item.targetDeviceName
                )
                DispatchQueue.main.async {
                    self.onOutgoingProgress?(item.name, 1.0, fileSize, fileSize, 0)
                }
            },
            onProgress: { progress, sent, total, speed in
                DispatchQueue.main.async {
                    self.onOutgoingProgress?(item.name, progress, sent, total, speed)
                }
            }
        )
    }

    // MARK: - Core streaming routine

    /// Streams a file, honouring `Range` so interrupted downloads can resume. Resumed
    /// requests are answered with `206 Partial Content` and a `Content-Range` header.
    func stream(
        url: URL,
        connection: ClientConnection,
        mime: String,
        downloadName: String?,
        rangeHeader: String?,
        deviceId: String,
        deviceName: String,
        onCompletion: ((Int64, Int64) -> Void)?,
        onProgress: ((Double, Int64, Int64, Double) -> Void)?
    ) {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attributes?[.size] as? Int64) ?? 0
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            send(connection: connection, status: "404 Not Found",
                 headers: ["Content-Type": "text/plain"], body: Data("Cannot read file".utf8))
            return
        }
        defer { try? handle.close() }

        let requested = HTTPServer.parseRange(rangeHeader, totalSize: fileSize)
        let start = requested?.start ?? 0
        let end = requested?.end ?? max(fileSize - 1, 0)
        let contentLength = fileSize > 0 ? (end - start + 1) : 0

        if start > 0 {
            try? handle.seek(toOffset: UInt64(start))
        }

        let encoded = downloadName?.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        var headers: [String: String] = [
            "Content-Type": mime,
            "Content-Length": "\(contentLength)",
            "Accept-Ranges": "bytes",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Expose-Headers": "Content-Length, Content-Range, Accept-Ranges"
        ]
        if let requested = requested, requested.isPartial {
            headers["Content-Range"] = "bytes \(requested.start)-\(requested.end)/\(fileSize)"
        }
        if let name = downloadName {
            headers["Content-Disposition"] =
                "attachment; filename=\"\(name.replacingOccurrences(of: "\"", with: ""))\"; filename*=UTF-8''\(encoded)"
        }

        let status = (requested?.isPartial ?? false) ? "206 Partial Content" : "200 OK"
        sendHeader(connection: connection, status: status, headers: headers)
        guard contentLength > 0 else { return }

        let chunkSize = 64 * 1024
        var sentTotal: Int64 = 0
        var lastReport = Date()
        var lastReportedBytes: Int64 = 0

        while sentTotal < contentLength {
            let remaining = contentLength - sentTotal
            let want = Int(remaining < Int64(chunkSize) ? remaining : Int64(chunkSize))
            let chunk = handle.readData(ofLength: want)
            if chunk.isEmpty { break }
            guard connection.writeAll(chunk) else { return }
            sentTotal += Int64(chunk.count)

            let now = Date()
            let elapsed = now.timeIntervalSince(lastReport)
            if elapsed >= 0.2 || sentTotal >= contentLength {
                let speed = elapsed > 0 ? Double(sentTotal - lastReportedBytes) / elapsed : 0
                let progress = min(1.0, Double(start + sentTotal) / Double(fileSize))
                lastReport = now
                lastReportedBytes = sentTotal
                onProgress?(progress, start + sentTotal, fileSize, speed)
            }
        }

        if sentTotal >= contentLength {
            onCompletion?(start + sentTotal, fileSize)
        }
    }

    func sendHeader(connection: ClientConnection, status: String, headers: [String: String]) {
        var header = "HTTP/1.1 \(status)\r\n"
        for (key, value) in headers {
            header += "\(key): \(value)\r\n"
        }
        if headers["Access-Control-Allow-Origin"] == nil {
            header += "Access-Control-Allow-Origin: *\r\n"
        }
        header += "Connection: close\r\n\r\n"
        _ = connection.writeAll(Data(header.utf8))
    }

    // MARK: - Resumable uploads

    private var partialsDirectory: URL {
        return downloadsDirectory.appendingPathComponent(".dropit-partials", isDirectory: true)
    }

    private func partialURL(for name: String) -> URL {
        let safe = name.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
        return partialsDirectory.appendingPathComponent(safe + ".part")
    }

    func serveUploadStatus(connection: ClientConnection, name: String) {
        let url = partialURL(for: name)
        let offset: Int64
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int64 {
            offset = size
        } else {
            offset = 0
        }
        sendJSON(connection: connection, object: [
            "name": name,
            "offset": offset,
            "resumable": offset > 0
        ])
    }

    func handleUpload(request: Request, connection: ClientConnection) {
        let rawName = request.query["name"] ?? request.headers["x-file-name"] ?? "upload_\(Int(Date().timeIntervalSince1970))"
        let cleanName = (rawName.removingPercentEncoding ?? rawName)
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")

        let expectedSize = Int64(request.query["size"] ?? "") ?? 0
        let startOffset = Int64(request.query["offset"] ?? "") ?? 0

        try? FileManager.default.createDirectory(at: partialsDirectory, withIntermediateDirectories: true)
        let partURL = partialURL(for: cleanName)

        if startOffset <= 0 {
            try? FileManager.default.removeItem(at: partURL)
            if !FileManager.default.createFile(atPath: partURL.path, contents: nil) {
                sendError(connection: connection, status: "500 Internal Server Error", message: "Cannot create upload file")
                return
            }
        }
        guard let handle = try? FileHandle(forWritingTo: partURL) else {
            sendError(connection: connection, status: "500 Internal Server Error", message: "Cannot open upload file")
            return
        }
        defer { try? handle.close() }

        if startOffset > 0 {
            let existing = (try? FileManager.default.attributesOfItem(atPath: partURL.path)[.size] as? Int64) ?? 0
            if existing < startOffset {
                sendJSON(connection: connection, object: [
                    "status": "reset", "offset": existing
                ])
                return
            }
            try? handle.seek(toOffset: UInt64(existing))
        }

        var written: Int64 = startOffset
        let key = "\(request.deviceId):\(cleanName)"
        partialsLock.lock()
        activeUploads[key] = written
        partialsLock.unlock()

        let chunk = [UInt8](repeating: 0, count: 64 * 1024)
        var lastReport = Date()
        var lastReported: Int64 = 0

        // A chunked upload sends only part of the file per request, so this request's
        // Content-Length is authoritative for how much body to consume. `expectedSize`
        // is the size of the whole file and decides when the upload is complete.
        let contentLength = Int64(request.headers["content-length"] ?? "") ?? 0
        let wanted = contentLength > 0
            ? contentLength
            : max(expectedSize - startOffset, 0)

        var received: Int64 = 0

        // Bytes that arrived in the same read as the request headers are already off the
        // socket, so they must be consumed before reading more.
        var pending = pendingInitialBody
        pendingInitialBody = Data()

        uploadLoop: while received < wanted {
            if !pending.isEmpty {
                let take = Int(min(Int64(pending.count), wanted - received))
                let piece = Data(pending.prefix(take))
                pending.removeFirst(take)
                handle.write(piece)
                received += Int64(take)
                written += Int64(take)
                continue
            }
            switch connection.read(maxBytes: chunk.count, timeoutMs: 20_000) {
            case .data(let data):
                handle.write(data)
                received += Int64(data.count)
                written += Int64(data.count)

                let now = Date()
                let elapsed = now.timeIntervalSince(lastReport)
                if elapsed >= 0.2 {
                    let speed = elapsed > 0 ? Double(written - lastReported) / elapsed : 0
                    let progress = expectedSize > 0 ? min(1.0, Double(written) / Double(expectedSize)) : 0
                    lastReport = now
                    lastReported = written
                    let snapshot = written
                    let expected = expectedSize
                    DispatchQueue.main.async { [weak self] in
                        self?.onIncomingProgress?(cleanName, progress, snapshot, expected, speed)
                    }
                }
            case .timeout, .eof:
                break uploadLoop
            }
        }

        partialsLock.lock()
        activeUploads.removeValue(forKey: key)
        partialsLock.unlock()

        let totalWritten = (try? FileManager.default.attributesOfItem(atPath: partURL.path)[.size] as? Int64) ?? written

        if expectedSize > 0, totalWritten < expectedSize {
            // Interrupted: keep the partial file so the device can resume later.
            sendJSON(connection: connection, object: [
                "status": "incomplete", "offset": totalWritten, "resumable": true
            ])
            return
        }

        let destination = resolveDestinationURL(for: cleanName)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: partURL, to: destination)
        } catch {
            sendError(connection: connection, status: "500 Internal Server Error", message: "Could not finalize upload")
            return
        }

        let targetDeviceId = request.headers["x-target-device-id"] ?? request.query["targetDeviceId"] ?? request.query["target"]
        let rawTargetName = request.headers["x-target-device-name"] ?? request.query["targetDeviceName"] ?? request.query["targetName"]
        let targetDeviceName = rawTargetName?.removingPercentEncoding ?? rawTargetName

        let item = ReceivedFileItem(
            name: destination.lastPathComponent,
            size: totalWritten,
            savedPath: destination.path,
            senderIP: connection.remoteIP
        )
        recordHistory(
            deviceId: request.deviceId, deviceName: request.deviceName,
            fileName: destination.lastPathComponent, fileSize: totalWritten,
            direction: .receivedFromDevice,
            targetDeviceId: targetDeviceId, targetDeviceName: targetDeviceName
        )

        if let targetId = targetDeviceId, !targetId.isEmpty, targetId != "host_mac" {
            appendSharedFile(TransferFileItem(
                url: destination,
                targetDeviceId: targetId,
                targetDeviceName: targetDeviceName,
                senderDeviceId: request.deviceId,
                senderDeviceName: request.deviceName
            ))
        }

        DispatchQueue.main.async { [weak self] in
            self?.onIncomingProgress?(cleanName, 1.0, totalWritten, totalWritten, 0)
            self?.onFileReceived?(item)
        }

        sendJSON(connection: connection, object: [
            "status": "ok", "offset": totalWritten, "savedAs": destination.lastPathComponent
        ])
    }

    func resolveDestinationURL(for fileName: String) -> URL {
        let base = downloadsDirectory
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        var target = base.appendingPathComponent(fileName)
        if !FileManager.default.fileExists(atPath: target.path) { return target }
        let ext = target.pathExtension
        let stem = target.deletingPathExtension().lastPathComponent
        var counter = 1
        while true {
            let candidate = ext.isEmpty ? "\(stem) (\(counter))" : "\(stem) (\(counter)).\(ext)"
            target = base.appendingPathComponent(candidate)
            if !FileManager.default.fileExists(atPath: target.path) { return target }
            counter += 1
        }
    }
}
