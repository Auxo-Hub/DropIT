import Foundation

/// A phone that has registered itself as a storage provider.
///
/// The Android app runs its own small HTTP server and hands the Mac a random secret at
/// registration time. Every proxied request carries that secret, so another machine on
/// the same Wi-Fi cannot browse the phone even though it can reach the phone's port.
public struct DeviceStorageProvider: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let model: String
    public let manufacturer: String
    public let address: String
    public let port: UInt16
    public let secret: String
    public let lastSeen: Date
    public let supportsAllFilesAccess: Bool

    public var displayName: String {
        let model = model.trimmingCharacters(in: .whitespaces)
        if model.isEmpty { return name }
        return "\(name) (\(model))"
    }
}

/// Keeps track of phones that offer their storage to this Mac.
public final class DeviceProviderRegistry {

    private let lock = NSLock()
    private var providers: [String: DeviceStorageProvider] = [:]
    /// Providers that have not checked in for this long are dropped.
    private let expiry: TimeInterval = 90

    public init() {}

    public func register(
        id: String,
        name: String,
        model: String,
        manufacturer: String,
        address: String,
        port: UInt16,
        secret: String,
        supportsAllFilesAccess: Bool
    ) -> DeviceStorageProvider {
        let provider = DeviceStorageProvider(
            id: id,
            name: name.isEmpty ? "Android device" : name,
            model: model,
            manufacturer: manufacturer,
            address: address,
            port: port,
            secret: secret,
            lastSeen: Date(),
            supportsAllFilesAccess: supportsAllFilesAccess
        )
        lock.lock()
        providers[id] = provider
        pruneLocked()
        lock.unlock()
        return provider
    }

    public func provider(id: String) -> DeviceStorageProvider? {
        lock.lock()
        defer { lock.unlock() }
        return providers[id]
    }

    public func all() -> [DeviceStorageProvider] {
        lock.lock()
        defer { lock.unlock() }
        return providers.values.sorted { $0.lastSeen > $1.lastSeen }
    }

    public func remove(id: String) {
        lock.lock()
        providers.removeValue(forKey: id)
        lock.unlock()
    }

    public func removeAll() {
        lock.lock()
        providers.removeAll()
        lock.unlock()
    }

    private func pruneLocked() {
        let cutoff = Date().addingTimeInterval(-expiry)
        providers = providers.filter { $0.value.lastSeen >= cutoff }
    }
}
