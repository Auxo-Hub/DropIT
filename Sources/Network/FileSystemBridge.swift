import Foundation

/// Exposes a restricted view of the Mac's file system to connected devices.
/// Every path is canonicalised and confined to the allowed roots so a crafted
/// request cannot escape via `..` or a symlink.
public final class FileSystemBridge {

    public struct Entry: Identifiable {
        public let id: String
        public let name: String
        public let path: String
        public let isDirectory: Bool
        public let size: Int64
        public let modified: Date?
        public let isHidden: Bool
        public let isSymlink: Bool
    }

    public enum BridgeError: LocalizedError {
        case outsideAllowedRoots
        case notFound
        case notADirectory
        case notAFile
        case nameRequired
        case alreadyExists
        case ioFailure(String)

        public var errorDescription: String? {
            switch self {
            case .outsideAllowedRoots: return "Path is outside the folders shared by Dropit"
            case .notFound: return "No such file or folder"
            case .notADirectory: return "Not a folder"
            case .notAFile: return "Not a file"
            case .nameRequired: return "A name is required"
            case .alreadyExists: return "An item with that name already exists"
            case .ioFailure(let detail): return detail
            }
        }
    }

    /// Sensitive locations never exposed, even though they sit inside the home folder.
    private static let deniedNames: Set<String> = [
        ".ssh", ".gnupg", ".aws", ".azure", ".kube", ".docker",
        ".config", ".password-store", "Library/Keychains", "Library/Application Support"
    ]

    private let fileManager = FileManager.default
    private let rootsLock = NSLock()
    private var allowedRoots: [URL]

    public init(roots: [URL] = [FileManager.default.homeDirectoryForCurrentUser]) {
        self.allowedRoots = roots
            .map { $0.standardizedFileURL }
            .sorted { $0.path.count > $1.path.count }
    }

    public func setRoots(_ roots: [URL]) {
        rootsLock.lock()
        allowedRoots = roots.map { $0.standardizedFileURL }.sorted { $0.path.count > $1.path.count }
        rootsLock.unlock()
    }

    public func rootPaths() -> [String] {
        rootsLock.lock()
        let paths = allowedRoots.map { $0.path }
        rootsLock.unlock()
        return paths
    }

    // MARK: - Path resolution

    /// Resolves a client supplied path. Accepts either a path relative to the Mac's
    /// home folder (e.g. "Documents/notes.txt") or an absolute path inside a root.
    public func resolve(_ rawPath: String) throws -> URL {
        rootsLock.lock()
        let roots = allowedRoots
        rootsLock.unlock()
        guard !roots.isEmpty else { throw BridgeError.outsideAllowedRoots }

        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "/" || trimmed == "~" {
            return roots[0].resolvingSymlinksInPath().standardizedFileURL
        }

        let decoded = trimmed.removingPercentEncoding ?? trimmed
        let expanded = (decoded as NSString).expandingTildeInPath

        var candidate: URL
        if expanded.hasPrefix("/") {
            candidate = URL(fileURLWithPath: expanded)
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            candidate = home.appendingPathComponent(expanded)
        }

        // Resolve symlinks so `..` and links cannot be used to break out of a root.
        let canonical = candidate.resolvingSymlinksInPath().standardizedFileURL

        let isAllowed = roots.contains { root in
            canonical.path == root.path || canonical.path.hasPrefix(root.path + "/")
        }
        guard isAllowed else { throw BridgeError.outsideAllowedRoots }
        guard !isDenied(canonical) else { throw BridgeError.outsideAllowedRoots }
        return canonical
    }

    private func isDenied(_ url: URL) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().path
        var relative = url.path
        if relative.hasPrefix(home + "/") {
            relative = String(relative.dropFirst(home.count + 1))
        }
        for denied in FileSystemBridge.deniedNames {
            if relative == denied || relative.hasPrefix(denied + "/") { return true }
        }
        return false
    }

    // MARK: - Operations

    public func list(at rawPath: String) throws -> [Entry] {
        let url = try resolve(rawPath)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw BridgeError.notFound
        }
        guard isDirectory.boolValue else { throw BridgeError.notADirectory }

        let keys: [URLResourceKey] = [
            .isDirectoryKey, .fileSizeKey, .contentModificationDateKey,
            .isHiddenKey, .isSymbolicLinkKey, .nameKey
        ]
        let contents = try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsSubdirectoryDescendants]
        )

        var entries: [Entry] = []
        for child in contents {
            let values = try? child.resourceValues(forKeys: Set(keys))
            let isChildDirectory = values?.isDirectory ?? false
            let isSymlink = (values?.isSymbolicLink ?? false)
            let size = Int64(values?.fileSize ?? 0)
            entries.append(Entry(
                id: child.path,
                name: child.lastPathComponent,
                path: child.path,
                isDirectory: isChildDirectory,
                size: isChildDirectory ? 0 : size,
                modified: values?.contentModificationDate,
                isHidden: (values?.isHidden ?? false) || child.lastPathComponent.hasPrefix("."),
                isSymlink: isSymlink
            ))
        }

        entries.sort { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            if lhs.isHidden != rhs.isHidden { return !lhs.isHidden }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        return entries
    }

    public func createDirectory(at rawPath: String, name: String) throws -> URL {
        let safeName = try sanitizedComponent(name)
        let parent = try resolve(rawPath)
        let target = parent.appendingPathComponent(safeName)
        guard !fileManager.fileExists(atPath: target.path) else { throw BridgeError.alreadyExists }
        try fileManager.createDirectory(at: target, withIntermediateDirectories: false)
        return target
    }

    public func writeFile(at rawPath: String, name: String, contents: Data) throws -> URL {
        let safeName = try sanitizedComponent(name)
        let parent = try resolve(rawPath)
        let target = parent.appendingPathComponent(safeName)
        if fileManager.fileExists(atPath: target.path) {
            guard !((try? target.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false) else {
                throw BridgeError.alreadyExists
            }
        }
        try contents.write(to: target, options: .atomic)
        return target
    }

    public func delete(at rawPath: String) throws {
        let url = try resolve(rawPath)
        guard fileManager.fileExists(atPath: url.path) else { throw BridgeError.notFound }
        try fileManager.removeItem(at: url)
    }

    @discardableResult
    public func rename(at rawPath: String, to newName: String) throws -> URL {
        let url = try resolve(rawPath)
        guard fileManager.fileExists(atPath: url.path) else { throw BridgeError.notFound }
        let safeName = try sanitizedComponent(newName)
        let target = url.deletingLastPathComponent().appendingPathComponent(safeName)
        guard !fileManager.fileExists(atPath: target.path) else { throw BridgeError.alreadyExists }
        try fileManager.moveItem(at: url, to: target)
        return target
    }

    public func exists(at rawPath: String) -> Bool {
        guard let url = try? resolve(rawPath) else { return false }
        return fileManager.fileExists(atPath: url.path)
    }

    public func url(for rawPath: String) -> URL? {
        return try? resolve(rawPath)
    }

    private func sanitizedComponent(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw BridgeError.nameRequired }
        guard !trimmed.contains("/"), !trimmed.contains("\\"), trimmed != ".", trimmed != ".." else {
            throw BridgeError.nameRequired
        }
        return trimmed
    }
}
