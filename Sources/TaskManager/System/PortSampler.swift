import Darwin
import Foundation

/// 一个正在监听的 TCP 端口。
struct ListeningPort: Sendable, Identifiable, Hashable {
    var id: String { "\(address)-\(port)-\(pid)" }

    var port: Int
    /// 监听地址：`127.0.0.1` / `::1` / `*`（所有网络接口）
    var address: String
    var isIPv6: Bool
    var pid: pid_t
    /// netstat 报的进程名。它会被截断，只在按 pid 找不到进程行时兜底显示。
    var processName: String

    var isLoopback: Bool {
        address.hasPrefix("127.") || address == "::1" || address == "localhost"
    }
    var isAnyAddress: Bool { address == "*" || address == "0.0.0.0" || address == "::" }
    /// 能不能用本机浏览器打开。绑在别的网卡地址上的（比如 192.168.x）不给链接。
    var isLocallyReachable: Bool { isLoopback || isAnyAddress }

    var url: URL? {
        guard isLocallyReachable else { return nil }
        return URL(string: "http://127.0.0.1:\(port)")
    }

    /// 展示用的 `地址:端口`。IPv6 按惯例加方括号。
    var endpoint: String {
        isIPv6 && address.contains(":") ? "[\(address)]:\(port)" : "\(address):\(port)"
    }

    @MainActor
    var scopeText: String { isAnyAddress ? L("所有网络接口") : (isLoopback ? L("仅本机") : L("指定地址")) }
}

/// 「网络端口」页的数据源。
///
/// 用 `netstat -anv -p tcp` 而不是 `lsof`：非 root 时 lsof 只看得到自己的进程，
/// 而 netstat 能列出所有用户的监听套接字，还自带 `process:pid` 列。整条命令 ~10ms。
final class PortSampler {

    /// 端口变化比 CPU 慢得多，没必要每拍都 fork 一次 netstat。
    private static let minimumInterval: TimeInterval = 3

    private var cached: [ListeningPort] = []
    private var lastSample = Date.distantPast

    func sample(force: Bool = false) -> [ListeningPort] {
        if !force, Date().timeIntervalSince(lastSample) < Self.minimumInterval {
            return cached
        }
        cached = Self.load()
        lastSample = Date()
        return cached
    }

    /// 下一次 `sample()` 强制重新采集。
    func invalidate() {
        lastSample = .distantPast
    }

    static func load() -> [ListeningPort] {
        guard let output = Shell.run("/usr/sbin/netstat", ["-anv", "-p", "tcp"], timeout: 5) else { return [] }

        var seen = Set<String>()
        var result: [ListeningPort] = []

        for line in output.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            // proto recvq sendq local foreign state rxbytes txbytes rhiwat shiwat process:pid + 8 列尾巴
            guard fields.count >= 15,
                  fields[0].hasPrefix("tcp"),
                  fields[5] == "LISTEN" else { continue }

            // 进程名可能带空格（真实存在的例子：`Codex (Service):39994`），所以这一列必须从右边数。
            guard let owner = Self.parseOwner(fields[fields.count - 9]) else { continue }
            guard let (address, port) = Self.parseLocalAddress(fields[3]) else { continue }

            let entry = ListeningPort(
                port: port,
                address: address,
                isIPv6: fields[0].hasSuffix("6"),
                pid: owner.pid,
                processName: owner.name
            )
            guard seen.insert(entry.id).inserted else { continue }   // 同一端口可能有多个 fd
            result.append(entry)
        }

        return result.sorted { ($0.port, $0.address) < ($1.port, $1.address) }
    }

    // MARK: - 解析

    /// `MooTraderBackend:87478` → (名字, pid)。名字里可能有冒号，所以从最后一个冒号切。
    private static func parseOwner(_ field: String) -> (name: String, pid: pid_t)? {
        guard let separator = field.lastIndex(of: ":") else { return nil }
        guard let pid = pid_t(field[field.index(after: separator)...]) else { return nil }
        return (String(field[..<separator]), pid)
    }

    /// `127.0.0.1.8770` / `*.9119` / `::1.8770` / `fe80::1%lo0.8770` → (地址, 端口)
    private static func parseLocalAddress(_ field: String) -> (address: String, port: Int)? {
        guard let separator = field.lastIndex(of: ".") else { return nil }
        guard let port = Int(field[field.index(after: separator)...]) else { return nil }
        let address = String(field[..<separator])
        return (address.isEmpty ? "*" : address, port)
    }
}
