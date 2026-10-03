import Foundation
import Darwin

/// A single client connection, either a plain accepted socket or a TLS-secured
/// Network.framework connection. The HTTP layer only ever talks to this type.
final class ClientConnection {
    enum ReadOutcome {
        case data(Data)
        case timeout
        case eof
    }

    let remoteIP: String
    let isSecure: Bool

    private let fd: Int32
    private let bridge: SecureConnectionBridge?
    private var closed = false

    init(fd: Int32, remoteIP: String) {
        self.fd = fd
        self.bridge = nil
        self.remoteIP = remoteIP
        self.isSecure = false

        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
    }

    init(bridge: SecureConnectionBridge, remoteIP: String) {
        self.fd = -1
        self.bridge = bridge
        self.remoteIP = remoteIP
        self.isSecure = true
    }

    // MARK: - Reading

    func read(maxBytes: Int, timeoutMs: Int) -> ReadOutcome {
        guard !closed, maxBytes > 0 else { return .eof }

        if let bridge = bridge {
            switch bridge.read(maxBytes: maxBytes, timeoutMs: timeoutMs) {
            case .data(let payload): return .data(payload)
            case .timeout: return .timeout
            case .eof: return .eof
            }
        }

        guard waitFor(events: Int16(POLLIN), timeoutMs: timeoutMs) else {
            cancel()
            return .timeout
        }
        var buffer = [UInt8](repeating: 0, count: maxBytes)
        let count = buffer.withUnsafeMutableBytes { raw in
            Darwin.read(fd, raw.baseAddress, maxBytes)
        }
        if count > 0 { return .data(Data(buffer[0..<count])) }
        if count == 0 { return .eof }
        if errno == EINTR { return .eof }
        cancel()
        return .timeout
    }

    /// Consumes up to `count` unread request-body bytes.
    @discardableResult
    func discard(_ count: Int) -> Int {
        var remaining = count
        let scratch = [UInt8](repeating: 0, count: 32 * 1024)
        while remaining > 0 {
            switch read(maxBytes: min(remaining, scratch.count), timeoutMs: 2000) {
            case .data(let data):
                remaining -= data.count
            case .timeout, .eof:
                return count - remaining
            }
        }
        return count
    }

    // MARK: - Writing

    @discardableResult
    func writeAll(_ data: Data) -> Bool {
        guard !closed else { return false }
        guard !data.isEmpty else { return true }

        if let bridge = bridge {
            return bridge.writeAll(data, timeoutMs: 60_000)
        }

        return data.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return true }
            var sent = 0
            while sent < data.count {
                let n = Darwin.write(fd, base.advanced(by: sent), data.count - sent)
                if n > 0 {
                    sent += n
                    continue
                }
                if n < 0 && errno == EINTR { continue }
                if n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) && waitFor(events: Int16(POLLOUT), timeoutMs: 60_000) {
                    continue
                }
                cancel()
                return false
            }
            return true
        }
    }

    // MARK: - Lifecycle

    func cancel() {
        guard !closed else { return }
        closed = true
        if let bridge = bridge {
            bridge.cancel()
        } else if fd >= 0 {
            Darwin.close(fd)
        }
    }

    // MARK: - Socket helpers

    private func waitFor(events: Int16, timeoutMs: Int) -> Bool {
        var descriptor = pollfd(fd: fd, events: events, revents: 0)
        while true {
            let result = poll(&descriptor, 1, Int32(clamping: timeoutMs))
            if result > 0 { return true }
            if result == 0 { return false }
            if errno == EINTR { continue }
            return false
        }
    }
}
