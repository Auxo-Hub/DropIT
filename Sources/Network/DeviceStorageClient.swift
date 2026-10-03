import Foundation

/// Forwards file operations to a phone's storage server.
///
/// The phone speaks the same `/fs/*` shape as the Mac's own bridge, so this is a thin,
/// well-typed client: build a request, send it over the LAN, translate failures into
/// errors the UI can show.
public final class DeviceStorageClient {

    public enum ClientError: LocalizedError {
        case providerUnavailable
        case badResponse(String)
        case http(Int, String)

        public var errorDescription: String? {
            switch self {
            case .providerUnavailable:
                return "This phone is no longer connected"
            case .badResponse(let detail):
                return detail
            case .http(let code, let detail):
                return detail.isEmpty ? "The phone returned HTTP \(code)" : detail
            }
        }
    }

    public struct Entry: Identifiable, Hashable {
        public let id: String
        public let name: String
        public let path: String
        public let isDirectory: Bool
        public let size: Int64
        public let formattedSize: String
        public let modified: String
        public let isHidden: Bool
        public let isSymlink: Bool
    }

    public struct Listing {
        public let path: String
        public let entries: [Entry]
    }

    private let provider: DeviceStorageProvider
    private let session: URLSession

    public init(provider: DeviceStorageProvider, session: URLSession = .shared) {
        self.provider = provider
        self.session = session
    }

    private var baseURL: URL {
        URL(string: "http://\(provider.address):\(provider.port)")!
    }

    private func makeRequest(_ path: String, query: [String: String] = [:], method: String = "GET", body: Data? = nil) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw ClientError.badResponse("Could not build a request for the phone")
        }
        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: "secret", value: provider.secret))
        for (key, value) in query where !value.isEmpty {
            items.append(URLQueryItem(name: key, value: value))
        }
        components.queryItems = items

        guard let url = components.url else {
            throw ClientError.badResponse("Could not build a request for the phone")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(provider.secret, forHTTPHeaderField: "x-dropit-mac")
        if let body = body { request.httpBody = body }
        return request
    }

    private func send(_ request: URLRequest) throws -> Data {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Data, Error> = .failure(ClientError.providerUnavailable)
        session.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error = error {
                result = .failure(ClientError.badResponse(
                    "Could not reach the phone at \(self.provider.address):\(self.provider.port) - \(error.localizedDescription)"
                ))
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = data ?? Data()
            guard (200..<300).contains(status) else {
                result = .failure(ClientError.http(status, Self.errorMessage(from: body)))
                return
            }
            result = .success(body)
        }.resume()

        _ = semaphore.wait(timeout: .now() + 45)
        return try result.get()
    }

    private static func errorMessage(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(decoding: data.prefix(200), as: UTF8.self)
        }
        return object["error"] as? String ?? "Request failed"
    }

    // MARK: - Operations

    public func roots() throws -> [Entry] {
        let data = try send(try makeRequest("fs/roots"))
        return try Self.parseEntries(from: data, key: "roots")
    }

    public func list(path: String) throws -> Listing {
        let data = try send(try makeRequest("fs/list", query: ["path": path]))
        let object = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        return Listing(
            path: object["path"] as? String ?? path,
            entries: try Self.parseEntries(from: data, key: "entries")
        )
    }

    public func createDirectory(path: String, name: String) throws {
        let body = try JSONSerialization.data(withJSONObject: ["path": path, "name": name], options: [.withoutEscapingSlashes])
        _ = try send(try makeRequest("fs/mkdir", method: "POST", body: body))
    }

    public func rename(path: String, to name: String) throws {
        let body = try JSONSerialization.data(withJSONObject: ["path": path, "name": name], options: [.withoutEscapingSlashes])
        _ = try send(try makeRequest("fs/rename", method: "POST", body: body))
    }

    public func delete(path: String) throws {
        let body = try JSONSerialization.data(withJSONObject: ["path": path])
        _ = try send(try makeRequest("fs/delete", method: "POST", body: body))
    }

    /// Downloads a file from the phone, reporting progress so the UI can show a bar.
    /// Uses a byte range so a large file that drops can be resumed on the next attempt.
    public func download(
        path: String,
        startOffset: Int64,
        to destination: URL,
        progress: @escaping (Int64, Int64?) -> Void
    ) throws {
        var query: [String: String] = ["path": path]
        if startOffset > 0 { query["resume"] = "\(startOffset)" }

        var request = try makeRequest("fs/read", query: query)
        request.timeoutInterval = 600
        if startOffset > 0 {
            request.setValue("bytes=\(startOffset)-", forHTTPHeaderField: "Range")
        }

        let semaphore = DispatchSemaphore(value: 0)
        var failure: Error?
        var handle: FileHandle?
        var total: Int64?

        let task = session.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            let http = response as? HTTPURLResponse
            if let error = error {
                failure = ClientError.badResponse("Transfer failed: \(error.localizedDescription)")
                return
            }
            guard let status = http?.statusCode, (200..<300).contains(status) else {
                failure = ClientError.http(http?.statusCode ?? 0, Self.errorMessage(from: data ?? Data()))
                return
            }
            if let range = http?.value(forHTTPHeaderField: "Content-Range"),
               let size = Self.totalSize(fromContentRange: range) {
                total = size
            } else if let length = http?.value(forHTTPHeaderField: "Content-Length").flatMap(Int64.init) {
                total = (startOffset > 0 ? startOffset : 0) + length
            }

            do {
                let fileManager = FileManager.default
                if startOffset > 0, fileManager.fileExists(atPath: destination.path) {
                    handle = try FileHandle(forWritingTo: destination)
                    try handle?.seekToEnd()
                } else {
                    fileManager.createFile(atPath: destination.path, contents: nil)
                    handle = try FileHandle(forWritingTo: destination)
                }
                if let data = data {
                    try handle?.write(contentsOf: data)
                    progress(startOffset + Int64(data.count), total)
                }
            } catch {
                failure = ClientError.badResponse("Could not save the file: \(error.localizedDescription)")
            }
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 620)
        try? handle?.close()

        if let failure = failure { throw failure }
    }

    /// Uploads a Mac file to the phone, reporting progress.
    public func upload(
        fileURL: URL,
        toDirectory path: String,
        progress: @escaping (Int64, Int64) -> Void
    ) throws {
        let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
        let request = try makeRequest(
            "fs/write",
            query: ["path": path, "name": fileURL.lastPathComponent],
            method: "POST"
        )
        var uploaded: Int64 = 0

        let semaphore = DispatchSemaphore(value: 0)
        var failure: Error?

        let task = session.uploadTask(with: request, fromFile: fileURL) { _, response, error in
            defer { semaphore.signal() }
            if let error = error {
                failure = ClientError.badResponse("Upload failed: \(error.localizedDescription)")
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if !(200..<300).contains(status) {
                failure = ClientError.http(status, "The phone refused the upload")
            }
        }
        task.resume()

        // Poll the task so the UI can show progress; URLSession does not report it.
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now(), repeating: .milliseconds(120))
        timer.setEventHandler {
            let sent = task.countOfBytesSent
            if sent > uploaded {
                uploaded = Int64(sent)
                progress(uploaded, size)
            }
        }
        timer.resume()
        _ = semaphore.wait(timeout: .now() + 600)
        timer.cancel()
        progress(size, size)

        if let failure = failure { throw failure }
    }

    // MARK: - Parsing

    private static func parseEntries(from data: Data, key: String = "entries") throws -> [Entry] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClientError.badResponse("The phone sent a response Dropit could not read")
        }
        let raw = object[key] as? [[String: Any]] ?? []
        return raw.map { item in
            let name = item["name"] as? String ?? "item"
            let path = item["path"] as? String ?? name
            return Entry(
                id: path,
                name: name,
                path: path,
                isDirectory: (item["isDirectory"] as? Bool) ?? false,
                size: (item["size"] as? NSNumber)?.int64Value ?? 0,
                formattedSize: item["formattedSize"] as? String ?? "",
                modified: item["modified"] as? String ?? "",
                isHidden: (item["isHidden"] as? Bool) ?? false,
                isSymlink: (item["isSymlink"] as? Bool) ?? false
            )
        }
    }

    private static func totalSize(fromContentRange range: String) -> Int64? {
        guard let slash = range.lastIndex(of: "/") else { return nil }
        return Int64(range[range.index(after: slash)...])
    }
}
