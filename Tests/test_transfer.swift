import Foundation
import Network
import CommonCrypto
import Darwin

@main
struct TestRunner {
    static func main() throws {
        print("🧪 Starting DropQR 2.0 Comprehensive Verification Tests...")

        // Helper SHA-256
        func sha256(data: Data) -> String {
            var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
            data.withUnsafeBytes {
                _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
            }
            return hash.map { String(format: "%02x", $0) }.joined()
        }

        // 1. Test FileMIME
        print("\n--- 1. Testing FileMIME ---")
        let testURL = URL(fileURLWithPath: "/tmp/sample.mp4")
        let mime = FileMIME.mimeType(for: testURL)
        assert(mime == "video/mp4", "MIME type should be video/mp4, got \(mime)")
        let sizeFormatted = FileMIME.formatBytes(10485760) // 10 MB
        assert(!sizeFormatted.isEmpty, "Formatted size empty")
        print("✅ FileMIME passed: \(mime), \(sizeFormatted)")

        // 2. Test NetworkHelper
        print("\n--- 2. Testing NetworkHelper ---")
        let preferredIP = NetworkHelper.getPreferredIP()
        assert(!preferredIP.isEmpty, "Preferred IP should not be empty")
        print("✅ NetworkHelper passed: preferredIP=\(preferredIP)")

        // 3. Test QRCodeGenerator
        print("\n--- 3. Testing QRCodeGenerator ---")
        let qrImage = QRCodeGenerator.generateImage(from: "http://\(preferredIP):8080/", size: 200)
        assert(qrImage != nil, "QR Code generator returned nil")
        print("✅ QRCodeGenerator passed")

        // 4. Test ReceiverWebTemplate
        print("\n--- 4. Testing ReceiverWebTemplate ---")
        let html = ReceiverWebTemplate.html()
        assert(html.contains("/api/sync"), "HTML must contain /api/sync")
        assert(html.contains("/api/upload"), "HTML must contain /api/upload")
        assert(html.contains("downloadSingleFile"), "HTML must contain download handler")
        print("✅ ReceiverWebTemplate passed (\(html.utf8.count) bytes)")

        // 5. Test HTTPServer Multi-File Sharing & Direct Streaming
        print("\n--- 5. Testing Multi-File Streaming & Sync ---")
        let tempDir = FileManager.default.temporaryDirectory
        let sample1 = tempDir.appendingPathComponent("dropqr_test_file1.bin")
        let sample2 = tempDir.appendingPathComponent("dropqr_test_file2.txt")
        
        let data1 = Data((0..<256 * 1024).map { UInt8($0 % 255) })
        let data2 = Data("Hello DropQR Bidirectional Transfer!".utf8)
        try data1.write(to: sample1)
        try data2.write(to: sample2)
        defer {
            try? FileManager.default.removeItem(at: sample1)
            try? FileManager.default.removeItem(at: sample2)
        }

        let item1 = TransferFileItem(url: sample1)
        let item2 = TransferFileItem(url: sample2)

        let server = HTTPServer()
        let customDownloadsDir = tempDir.appendingPathComponent("dropqr_downloads_test_\(UUID().uuidString)")
        server.downloadsDirectory = customDownloadsDir
        try FileManager.default.createDirectory(at: customDownloadsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: customDownloadsDir) }

        var fileReceivedItem: ReceivedFileItem?
        server.onFileReceived = { item in
            print("Server received incoming file: \(item.name) (\(item.formattedSize))")
            fileReceivedItem = item
        }

        let port = try server.start(preferredPort: 0)
        server.updateSharedFiles([item1, item2])
        print("Server running on port \(port)")

        // Helpers for HTTP requests over Darwin BSD sockets
        func httpSocketRequest(req: String) -> String {
            let sock = socket(AF_INET, SOCK_STREAM, 0)
            guard sock >= 0 else { return "" }
            defer { close(sock) }
            
            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = in_port_t(port).bigEndian
            inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr)
            
            let res = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.stride))
                }
            }
            guard res == 0 else { return "" }
            
            let reqData = req.data(using: .utf8)!
            _ = reqData.withUnsafeBytes { Darwin.write(sock, $0.baseAddress!, reqData.count) }
            
            var respData = Data()
            var buf = [UInt8](repeating: 0, count: 4096)
            while true {
                let n = Darwin.read(sock, &buf, buf.count)
                if n <= 0 { break }
                respData.append(buf, count: n)
            }
            return String(decoding: respData, as: UTF8.self)
        }
        
        func httpSocketBinary(req: String) -> Data {
            let sock = socket(AF_INET, SOCK_STREAM, 0)
            guard sock >= 0 else { return Data() }
            defer { close(sock) }
            
            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = in_port_t(port).bigEndian
            inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr)
            
            let res = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.stride))
                }
            }
            guard res == 0 else { return Data() }
            
            let reqData = req.data(using: .utf8)!
            _ = reqData.withUnsafeBytes { Darwin.write(sock, $0.baseAddress!, reqData.count) }
            
            var respData = Data()
            var buf = [UInt8](repeating: 0, count: 16384)
            while true {
                let n = Darwin.read(sock, &buf, buf.count)
                if n <= 0 { break }
                respData.append(buf, count: n)
            }
            // Strip HTTP header
            let sep = Data([0x0D, 0x0A, 0x0D, 0x0A])
            if let r = respData.range(of: sep) {
                return respData.subdata(in: r.upperBound..<respData.count)
            }
            return Data()
        }

        // Test GET /api/sync
        let syncReq = "GET /api/sync HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\nConnection: close\r\n\r\n"
        let syncResponseStr = httpSocketRequest(req: syncReq)
        assert(syncResponseStr.contains("dropqr_test_file1.bin"), "Sync response did not contain sample1: \(syncResponseStr)")
        assert(syncResponseStr.contains("dropqr_test_file2.txt"), "Sync response did not contain sample2: \(syncResponseStr)")
        print("✅ Multi-file /api/sync verified successfully")

        // Test GET /download/:id for item1
        let dlReq = "GET /download/\(item1.id) HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\nConnection: close\r\n\r\n"
        let downloadedBytes = httpSocketBinary(req: dlReq)
        assert(downloadedBytes.count == data1.count, "Downloaded size mismatch")
        assert(sha256(data: downloadedBytes) == sha256(data: data1), "Downloaded content SHA-256 mismatch")
        print("✅ Multi-file download by ID verified bit-for-bit!")

        // 6. Test Receiver-to-Mac Binary Upload (POST /api/upload)
        print("\n--- 6. Testing Receiver-to-Mac Upload ---")
        let uploadPayload = Data("Test upload payload from phone to Mac 🚀".utf8)
        var uploadResp = ""
        
        let clientSock = socket(AF_INET, SOCK_STREAM, 0)
        assert(clientSock >= 0, "Failed to create test socket")
        
        var serverAddr = sockaddr_in()
        serverAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
        serverAddr.sin_family = sa_family_t(AF_INET)
        serverAddr.sin_port = in_port_t(port).bigEndian
        inet_pton(AF_INET, "127.0.0.1", &serverAddr.sin_addr)
        
        let connRes = withUnsafePointer(to: &serverAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(clientSock, $0, socklen_t(MemoryLayout<sockaddr_in>.stride))
            }
        }
        assert(connRes == 0, "Failed to connect to test server on port \(port): \(String(cString: strerror(errno)))")
        
        let reqHeader = "POST /api/upload?name=mobile_photo.jpg&size=\(uploadPayload.count) HTTP/1.1\r\n" +
                        "Host: 127.0.0.1:\(port)\r\n" +
                        "Content-Length: \(uploadPayload.count)\r\n" +
                        "Connection: close\r\n\r\n"
        var fullReq = reqHeader.data(using: .utf8)!
        fullReq.append(uploadPayload)
        
        _ = fullReq.withUnsafeBytes { raw in
            Darwin.write(clientSock, raw.baseAddress!, fullReq.count)
        }
        
        var respBuf = [UInt8](repeating: 0, count: 4096)
        let bytesRecv = Darwin.read(clientSock, &respBuf, respBuf.count)
        if bytesRecv > 0 {
            uploadResp = String(decoding: respBuf.prefix(bytesRecv), as: UTF8.self)
        }
        close(clientSock)
        
        // Pump runloop so main queue callbacks execute
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        assert(uploadResp.contains("200 OK"), "Upload response should be 200 OK, got: \(uploadResp)")
        assert(fileReceivedItem != nil, "onFileReceived callback was not called")
        assert(fileReceivedItem?.name == "mobile_photo.jpg", "Uploaded file name mismatch")
        
        let savedFile = customDownloadsDir.appendingPathComponent("mobile_photo.jpg")
        assert(FileManager.default.fileExists(atPath: savedFile.path), "Saved file does not exist on disk")
        let savedData = try Data(contentsOf: savedFile)
        assert(savedData == uploadPayload, "Uploaded file content on disk mismatch")
        print("✅ Receiver-to-Mac upload verified bit-for-bit on disk!")

        // 7. Test Device Registration & Listing
        print("\n--- 7. Testing Device Registration & Listing ---")
        let regReq = "POST /api/register-device HTTP/1.1\r\n" +
                     "Host: 127.0.0.1:\(port)\r\n" +
                     "x-device-id: test_phone_007\r\n" +
                     "x-device-name: iPhone%2015%20Pro\r\n" +
                     "User-Agent: Mozilla/5.0 (iPhone)\r\n" +
                     "Content-Length: 0\r\n" +
                     "Connection: close\r\n\r\n"
        let regResp = httpSocketRequest(req: regReq)
        assert(regResp.contains("200 OK"), "Register device failed: \(regResp)")
        assert(regResp.contains("test_phone_007"), "Register device did not return deviceId: \(regResp)")
        
        let devicesReq = "GET /api/devices HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\nConnection: close\r\n\r\n"
        let devicesResp = httpSocketRequest(req: devicesReq)
        assert(devicesResp.contains("200 OK"), "Get devices failed: \(devicesResp)")
        assert(devicesResp.contains("iPhone 15 Pro"), "Devices list does not contain registered iPhone: \(devicesResp)")
        assert(devicesResp.contains("Host Mac"), "Devices list does not contain Host Mac: \(devicesResp)")
        print("✅ Device registration and listing verified")

        // 8. Test Device Disconnection (Host Disconnect & Receiver Disconnect)
        print("\n--- 8. Testing Device Disconnection ---")
        // Disconnect from host
        server.disconnectDevice(id: "test_phone_007")
        let syncBlockedReq = "GET /api/sync HTTP/1.1\r\n" +
                             "Host: 127.0.0.1:\(port)\r\n" +
                             "x-device-id: test_phone_007\r\n" +
                             "Connection: close\r\n\r\n"
        let syncBlockedResp = httpSocketRequest(req: syncBlockedReq)
        assert(syncBlockedResp.contains("\"disconnected\":true"), "Sync did not report disconnected for blocked device: \(syncBlockedResp)")
        
        // Receiver disconnects self
        let selfDiscReq = "POST /api/disconnect HTTP/1.1\r\n" +
                          "Host: 127.0.0.1:\(port)\r\n" +
                          "x-device-id: test_phone_999\r\n" +
                          "Content-Length: 0\r\n" +
                          "Connection: close\r\n\r\n"
        let selfDiscResp = httpSocketRequest(req: selfDiscReq)
        assert(selfDiscResp.contains("\"disconnected\":true"), "Self-disconnect failed: \(selfDiscResp)")
        print("✅ Disconnection from host and receiver verified")

        // 9. Test Transfer History
        print("\n--- 9. Testing Transfer History ---")
        let histReq = "GET /api/history HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\nConnection: close\r\n\r\n"
        let histResp = httpSocketRequest(req: histReq)
        assert(histResp.contains("200 OK"), "Get history failed: \(histResp)")
        assert(histResp.contains("mobile_photo.jpg"), "History does not contain mobile_photo.jpg: \(histResp)")
        print("✅ Transfer history verified")

        // 10. Test Targeted Device-to-Device Transfer
        print("\n--- 10. Testing Targeted Device-to-Device Transfer ---")
        let peerData = Data("Peer to Peer Transfer Payload".utf8)
        let peerSock = socket(AF_INET, SOCK_STREAM, 0)
        assert(peerSock >= 0, "Failed to create socket")
        var peerAddr = sockaddr_in()
        peerAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
        peerAddr.sin_family = sa_family_t(AF_INET)
        peerAddr.sin_port = in_port_t(port).bigEndian
        inet_pton(AF_INET, "127.0.0.1", &peerAddr.sin_addr)
        let peerConnRes = withUnsafePointer(to: &peerAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(peerSock, $0, socklen_t(MemoryLayout<sockaddr_in>.stride))
            }
        }
        assert(peerConnRes == 0, "Failed to connect to server for peer upload")
        
        let peerUploadReq = "POST /api/upload?name=peer_doc.pdf&size=\(peerData.count) HTTP/1.1\r\n" +
                            "Host: 127.0.0.1:\(port)\r\n" +
                            "Content-Type: application/octet-stream\r\n" +
                            "Content-Length: \(peerData.count)\r\n" +
                            "x-device-id: receiver_phone_a\r\n" +
                            "x-device-name: Phone%20A\r\n" +
                            "x-target-device-id: receiver_phone_b\r\n" +
                            "x-target-device-name: Phone%20B\r\n" +
                            "Connection: close\r\n\r\n"
        _ = peerUploadReq.withCString { write(peerSock, $0, strlen($0)) }
        _ = peerData.withUnsafeBytes { write(peerSock, $0.baseAddress!, peerData.count) }
        
        var peerRespBuf = [UInt8](repeating: 0, count: 2048)
        let peerRecv = read(peerSock, &peerRespBuf, peerRespBuf.count)
        close(peerSock)
        let peerRespStr = String(decoding: peerRespBuf.prefix(peerRecv), as: UTF8.self)
        assert(peerRespStr.contains("200 OK"), "Peer upload failed: \(peerRespStr)")
        
        // Check Phone B sync sees the file
        let syncPhoneBReq = "GET /api/sync HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\nx-device-id: receiver_phone_b\r\nConnection: close\r\n\r\n"
        let syncPhoneBResp = httpSocketRequest(req: syncPhoneBReq)
        assert(syncPhoneBResp.contains("peer_doc.pdf"), "Target device Phone B did not see targeted file: \(syncPhoneBResp)")
        assert(syncPhoneBResp.contains("\"isForMe\":true"), "File is not marked isForMe for Phone B: \(syncPhoneBResp)")
        assert(syncPhoneBResp.contains("receiver_phone_a"), "Sender Phone A ID not present in sync response: \(syncPhoneBResp)")
        
        // Check Phone C (different receiver) sync does NOT see the file targeted to Phone B
        let syncPhoneCReq = "GET /api/sync HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\nx-device-id: receiver_phone_c\r\nConnection: close\r\n\r\n"
        let syncPhoneCResp = httpSocketRequest(req: syncPhoneCReq)
        assert(!syncPhoneCResp.contains("peer_doc.pdf"), "Untargeted device Phone C saw targeted file when it shouldn't: \(syncPhoneCResp)")
        print("✅ Targeted device-to-device transfer verified (visible only to target peer)")

        server.stop()
        print("\n🎉 ALL DROPIT TESTS PASSED! 🎉\n")
    }
}
