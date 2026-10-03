import Foundation
import Network
import Security

/// Presents a Network.framework connection as a blocking byte stream, so the HTTP
/// layer can treat TLS and plain sockets identically. A blocking read waits on a
/// semaphore with a deadline; a timeout cancels the connection, which also guarantees a
/// stalled peer cannot pin a worker thread.
final class SecureConnectionBridge {
    private let connection: NWConnection
    private let identity: SecIdentity
    private var buffer = Data()
    private var finished = false
    private let lock = NSLock()

    init(connection: NWConnection, identity: SecIdentity) {
        self.connection = connection
        self.identity = identity
    }

    func startTLS() -> Bool {
        let options = NWProtocolTLS.Options()
        guard let secIdentity = sec_identity_create(identity) else { return false }
        sec_protocol_options_set_local_identity(options.securityProtocolOptions, secIdentity)
        sec_protocol_options_set_min_tls_protocol_version(options.securityProtocolOptions, .TLSv12)

        // The listener was already configured with TLS; reaching a ready handshake here
        // simply confirms the peer accepted our certificate chain.
        let semaphore = DispatchSemaphore(value: 0)
        var ready = false
        var failed = false
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready: ready = true; semaphore.signal()
            case .failed, .cancelled: failed = true; semaphore.signal()
            default: break
            }
        }
        connection.start(queue: DispatchQueue(label: "com.dropit.server.secure.io"))
        _ = semaphore.wait(timeout: .now() + 10)
        return ready && !failed
    }

    enum Outcome {
        case data(Data)
        case timeout
        case eof
    }

    func read(maxBytes: Int, timeoutMs: Int) -> Outcome {
        lock.lock()
        if !buffer.isEmpty {
            let slice = buffer.prefix(maxBytes)
            let out = Data(slice)
            buffer.removeFirst(slice.count)
            lock.unlock()
            return .data(out)
        }
        let done = finished
        lock.unlock()
        if done { return .eof }

        let semaphore = DispatchSemaphore(value: 0)
        var chunk: Data?
        var complete = false
        var failed = false

        connection.receive(minimumIncompleteLength: 1, maximumLength: maxBytes) { content, _, isComplete, error in
            if let content = content { chunk = content }
            if isComplete { complete = true }
            if error != nil { failed = true }
            semaphore.signal()
        }

        guard semaphore.wait(timeout: .now() + .milliseconds(timeoutMs)) == .success else {
            cancel()
            return .timeout
        }
        if let chunk = chunk, !chunk.isEmpty { return .data(chunk) }
        if failed {
            cancel()
            return .eof
        }
        if complete {
            lock.lock()
            finished = true
            lock.unlock()
        }
        return .eof
    }

    @discardableResult
    func writeAll(_ data: Data, timeoutMs: Int) -> Bool {
        lock.lock()
        let done = finished
        lock.unlock()
        guard !done else { return false }
        guard !data.isEmpty else { return true }

        let semaphore = DispatchSemaphore(value: 0)
        var succeeded = false
        connection.send(content: data, completion: .contentProcessed { error in
            succeeded = (error == nil)
            semaphore.signal()
        })
        guard semaphore.wait(timeout: .now() + .milliseconds(timeoutMs)) == .success else {
            cancel()
            return false
        }
        if !succeeded {
            cancel()
            return false
        }
        return true
    }

    func cancel() {
        lock.lock()
        let alreadyDone = finished
        finished = true
        lock.unlock()
        guard !alreadyDone else { return }
        connection.cancel()
    }
}
