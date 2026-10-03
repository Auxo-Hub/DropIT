import Foundation
import Network

public struct NetworkInterfaceInfo: Identifiable, Hashable {
    public var id: String { "\(name)-\(ip)" }
    public let name: String
    public let ip: String
    public let displayName: String
    public let isWiFi: Bool
    
    public init(name: String, ip: String) {
        self.name = name
        self.ip = ip
        let lower = name.lowercased()
        let isWifi = lower.starts(with: "en0") || lower.contains("wi-fi") || lower.contains("wlan")
        self.isWiFi = isWifi
        
        if isWifi {
            self.displayName = "Wi-Fi (\(ip))"
        } else if lower.starts(with: "en") {
            self.displayName = "Ethernet / LAN (\(ip))"
        } else if lower.starts(with: "bridge") {
            self.displayName = "Bridge (\(ip))"
        } else if lower.starts(with: "utun") {
            self.displayName = "VPN / Tunnel (\(ip))"
        } else {
            self.displayName = "\(name) (\(ip))"
        }
    }
}

public class NetworkHelper {
    public static func getAvailableInterfaces() -> [NetworkInterfaceInfo] {
        var interfaces = [NetworkInterfaceInfo]()
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            guard let addrPtr = ptr.pointee.ifa_addr else { continue }
            let addr = addrPtr.pointee

            // Look for running, active, non-loopback IPv4 interfaces
            if (flags & (IFF_UP | IFF_RUNNING | IFF_LOOPBACK)) == (IFF_UP | IFF_RUNNING) {
                if addr.sa_family == UInt8(AF_INET) {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    var addrCopy = addr
                    if getnameinfo(&addrCopy, socklen_t(addrCopy.sa_len),
                                   &hostname, socklen_t(hostname.count),
                                   nil, 0, NI_NUMERICHOST) == 0 {
                        let name = String(cString: ptr.pointee.ifa_name)
                        let ip = String(cString: hostname)
                        
                        // Ignore loopback and link-local (169.254.x.x) addresses
                        if ip != "127.0.0.1" && !ip.hasPrefix("169.254.") {
                            let info = NetworkInterfaceInfo(name: name, ip: ip)
                            // Avoid duplicates
                            if !interfaces.contains(where: { $0.ip == ip }) {
                                interfaces.append(info)
                            }
                        }
                    }
                }
            }
        }
        
        // Sort with Wi-Fi first, then Ethernet
        interfaces.sort { a, b in
            if a.isWiFi && !b.isWiFi { return true }
            if !a.isWiFi && b.isWiFi { return false }
            return a.name < b.name
        }
        
        return interfaces
    }
    
    public static func getPreferredIP() -> String {
        let interfaces = getAvailableInterfaces()
        if let wifi = interfaces.first(where: { $0.isWiFi }) {
            return wifi.ip
        }
        return interfaces.first?.ip ?? "127.0.0.1"
    }
}
