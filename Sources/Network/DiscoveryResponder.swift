import Foundation
import Darwin

/// Answers the phone's UDP discovery probe so the app can find this Mac without the user
/// typing an address or scanning a QR code. The reply carries the plain HTTP port and the
/// session token, which the phone needs in order to register itself.
public final class DiscoveryResponder {

    public static let port: UInt16 = 8911
    private static let probe = "DROPIT_DISCOVER_V1"
    private static let reply = "DROPIT_HERE_V1"

    private var socketFd: Int32 = -1
    private var source: DispatchSourceRead?
    private let queue = DispatchQueue(label: "com.dropit.discovery", qos: .utility)

    public init() {}

    public var isRunning: Bool { socketFd >= 0 }

    public func start(port: UInt16, token: String) {
        stop()
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        #if canImport(Darwin)
        setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))
        #endif

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        address.sin_addr.s_addr = in_addr_t(0)

        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.stride))
            }
        }
        guard bound == 0 else {
            NSLog("Dropit: discovery responder could not bind UDP \(port) (errno \(errno))")
            close(fd)
            return
        }

        socketFd = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.handle(token: token, port: port)
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    public func stop() {
        source?.cancel()
        source = nil
        socketFd = -1
    }

    private func handle(token: String, port: UInt16) {
        var buffer = [UInt8](repeating: 0, count: 2048)
        var from = sockaddr_in()
        var fromLength = socklen_t(MemoryLayout<sockaddr_in>.stride)

        let received = withUnsafeMutablePointer(to: &from) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                recvfrom(socketFd, &buffer, buffer.count, 0, $0, &fromLength)
            }
        }
        guard received > 0 else { return }
        let text = String(decoding: buffer[0..<received], as: UTF8.self)
        guard text.trimmingCharacters(in: .whitespacesAndNewlines) == Self.probe else { return }

        let payload = "\(Self.reply) port=\(port) token=\(token)"
        let bytes = Array(payload.utf8)
        var destination = from
        withUnsafeMutablePointer(to: &destination) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                sendto(socketFd, bytes, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.stride))
            }
        }
    }
}
