import Darwin
import Foundation
import SystemConfiguration

struct NetworkInterfaceSnapshot: Sendable, Identifiable {
    var id: String { name }
    var name: String                 // BSD 名，如 en0
    var displayName: String          // 如 "Wi-Fi"
    var kind: String                 // 如 "IEEE80211" / "Ethernet"
    var isUp: Bool = false
    var isLoopback: Bool = false
    var isVirtual: Bool = false

    var macAddress: String?
    var ipv4: [String] = []
    var ipv6: [String] = []
    var linkSpeed: UInt64 = 0        // bit/s

    var bytesIn: UInt64 = 0
    var bytesOut: UInt64 = 0
    var packetsIn: UInt64 = 0
    var packetsOut: UInt64 = 0
    var errorsIn: UInt64 = 0
    var errorsOut: UInt64 = 0

    var receiveRate: Double = 0      // 字节/秒
    var sendRate: Double = 0

    var hasTraffic: Bool { bytesIn > 0 || bytesOut > 0 }
}

/// 网络吞吐来自 `getifaddrs` 的 `AF_LINK` 项（`if_data`）差分。
final class NetworkSampler {

    private struct Counters {
        var bytesIn: UInt64 = 0, bytesOut: UInt64 = 0
    }

    private var previous: [String: Counters] = [:]
    private var lastSampleTime = Date()
    private var displayNames: [String: (name: String, kind: String)] = [:]
    private var displayNamesLoadedAt = Date.distantPast

    func sample() -> [NetworkInterfaceSnapshot] {
        let now = Date()
        let elapsed = max(0.001, now.timeIntervalSince(lastSampleTime))
        lastSampleTime = now
        refreshDisplayNamesIfNeeded()

        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let head else { return [] }
        defer { freeifaddrs(head) }

        var interfaces: [String: NetworkInterfaceSnapshot] = [:]
        var current: [String: Counters] = [:]

        for ptr in sequence(first: head, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let namePtr = ifa.ifa_name else { continue }
            let name = String(cString: namePtr)
            let flags = Int32(ifa.ifa_flags)

            var entry = interfaces[name] ?? {
                let meta = displayNames[name]
                var s = NetworkInterfaceSnapshot(
                    name: name,
                    displayName: meta?.name ?? name,
                    kind: meta?.kind ?? "—"
                )
                s.isLoopback = (flags & IFF_LOOPBACK) != 0
                s.isVirtual = Self.virtualPrefixes.contains { name.hasPrefix($0) }
                return s
            }()
            entry.isUp = (flags & IFF_UP) != 0 && (flags & IFF_RUNNING) != 0

            guard let addr = ifa.ifa_addr else { interfaces[name] = entry; continue }
            switch Int32(addr.pointee.sa_family) {
            case AF_LINK:
                if let data = ifa.ifa_data?.assumingMemoryBound(to: if_data.self) {
                    entry.bytesIn = UInt64(data.pointee.ifi_ibytes)
                    entry.bytesOut = UInt64(data.pointee.ifi_obytes)
                    entry.packetsIn = UInt64(data.pointee.ifi_ipackets)
                    entry.packetsOut = UInt64(data.pointee.ifi_opackets)
                    entry.errorsIn = UInt64(data.pointee.ifi_ierrors)
                    entry.errorsOut = UInt64(data.pointee.ifi_oerrors)
                    entry.linkSpeed = UInt64(data.pointee.ifi_baudrate)
                    current[name] = Counters(bytesIn: entry.bytesIn, bytesOut: entry.bytesOut)
                }
                entry.macAddress = Self.macAddress(from: addr)
            case AF_INET:
                if let ip = Self.presentation(addr) { entry.ipv4.append(ip) }
            case AF_INET6:
                if let ip = Self.presentation(addr) { entry.ipv6.append(ip) }
            default:
                break
            }
            interfaces[name] = entry
        }

        for (name, counters) in current {
            guard var entry = interfaces[name], let old = previous[name] else { continue }
            // 计数器可能因接口重置而回退，回退时按 0 处理
            entry.receiveRate = counters.bytesIn >= old.bytesIn ? Double(counters.bytesIn - old.bytesIn) / elapsed : 0
            entry.sendRate = counters.bytesOut >= old.bytesOut ? Double(counters.bytesOut - old.bytesOut) / elapsed : 0
            interfaces[name] = entry
        }
        previous = current

        return interfaces.values.sorted { lhs, rhs in
            if lhs.isLoopback != rhs.isLoopback { return !lhs.isLoopback }
            if lhs.isVirtual != rhs.isVirtual { return !lhs.isVirtual }
            if lhs.bytesIn + lhs.bytesOut != rhs.bytesIn + rhs.bytesOut {
                return lhs.bytesIn + lhs.bytesOut > rhs.bytesIn + rhs.bytesOut
            }
            return lhs.name < rhs.name
        }
    }

    /// utun/llw 之类是系统自建的虚拟接口，默认折叠。
    private static let virtualPrefixes = ["utun", "llw", "awdl", "bridge", "gif", "stf", "ap", "anpi", "vmenet"]

    private func refreshDisplayNamesIfNeeded() {
        guard Date().timeIntervalSince(displayNamesLoadedAt) > 30 else { return }
        displayNamesLoadedAt = Date()
        guard let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return }
        var map: [String: (name: String, kind: String)] = [:]
        for interface in all {
            guard let bsd = SCNetworkInterfaceGetBSDName(interface) as String? else { continue }
            let display = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String? ?? bsd
            let kind = SCNetworkInterfaceGetInterfaceType(interface) as String? ?? "—"
            map[bsd] = (display, kind)
        }
        displayNames = map
    }

    private static func presentation(_ addr: UnsafeMutablePointer<sockaddr>) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let length = socklen_t(addr.pointee.sa_len)
        guard getnameinfo(addr, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { return nil }
        var result = String(cBuffer: host)
        if let percent = result.firstIndex(of: "%") { result = String(result[..<percent]) }  // 去掉 IPv6 的 scope id
        return result.isEmpty ? nil : result
    }

    private static func macAddress(from addr: UnsafeMutablePointer<sockaddr>) -> String? {
        addr.withMemoryRebound(to: sockaddr_dl.self, capacity: 1) { dl -> String? in
            let length = Int(dl.pointee.sdl_alen)
            guard length == 6 else { return nil }
            let base = UnsafeRawPointer(dl).advanced(by: MemoryLayout<sockaddr_dl>.offset(of: \.sdl_data)!)
            let bytes = base.advanced(by: Int(dl.pointee.sdl_nlen)).assumingMemoryBound(to: UInt8.self)
            return (0..<6).map { String(format: "%02x", bytes[$0]) }.joined(separator: ":")
        }
    }
}
