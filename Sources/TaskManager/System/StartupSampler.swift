import Foundation

struct StartupItem: Sendable, Identifiable {
    var id: String { plistPath }
    var label: String
    var plistPath: String
    var program: String?
    var runAtLoad: Bool
    var keepAlive: Bool
    var domain: Domain
    /// 与 `launchctl list` 交叉得到的运行状态
    var pid: pid_t?
    var isLoaded: Bool

    enum Domain: String, Sendable, CaseIterable {
        case userAgent, globalAgent, globalDaemon

        @MainActor
        var displayName: String {
            switch self {
            case .userAgent: L("用户代理")
            case .globalAgent: L("全局代理")
            case .globalDaemon: L("系统守护进程")
            }
        }

        var directory: String {
            switch self {
            case .userAgent: NSHomeDirectory() + "/Library/LaunchAgents"
            case .globalAgent: "/Library/LaunchAgents"
            case .globalDaemon: "/Library/LaunchDaemons"
            }
        }

        /// 只有用户自己目录下的条目才允许开关。
        var isUserWritable: Bool { self == .userAgent }
    }

    @MainActor
    var statusText: String {
        if pid != nil { return L("运行中") }
        return isLoaded ? L("已加载") : L("未加载")
    }
}

/// 启动应用页的数据源 —— macOS 上对应 launchd 的 Agents / Daemons。
///
/// 只扫描三个用户可见目录，`/System/Library/Launch*` 属于系统只读卷，不去动它。
enum StartupSampler {

    static func load(services: [ServiceEntry]) -> [StartupItem] {
        let byLabel = Dictionary(services.map { ($0.label, $0) }, uniquingKeysWith: { a, _ in a })
        var items: [StartupItem] = []

        for domain in StartupItem.Domain.allCases {
            let directory = domain.directory
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else { continue }

            for name in names where name.hasSuffix(".plist") {
                let path = (directory as NSString).appendingPathComponent(name)
                guard let data = FileManager.default.contents(atPath: path),
                      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
                      let dict = plist as? [String: Any] else { continue }

                let label = dict["Label"] as? String ?? (name as NSString).deletingPathExtension
                guard !Redaction.hidesThirdPartyJob(label) else { continue }
                let program = dict["Program"] as? String
                    ?? (dict["ProgramArguments"] as? [String])?.first

                let service = byLabel[label]
                items.append(StartupItem(
                    label: label,
                    plistPath: path,
                    program: program,
                    runAtLoad: dict["RunAtLoad"] as? Bool ?? false,
                    keepAlive: Self.parseKeepAlive(dict["KeepAlive"]),
                    domain: domain,
                    pid: service?.pid,
                    isLoaded: service != nil
                ))
            }
        }
        return items.sorted { $0.label < $1.label }
    }

    private static func parseKeepAlive(_ value: Any?) -> Bool {
        if let flag = value as? Bool { return flag }
        if value is [String: Any] { return true }   // 条件式 KeepAlive 也算「会被拉起」
        return false
    }

    /// 加载 / 卸载用户域的 LaunchAgent。只对 `~/Library/LaunchAgents` 开放。
    @MainActor
    static func setEnabled(_ item: StartupItem, enabled: Bool) throws {
        guard item.domain.isUserWritable else {
            throw OperationError(L("只允许开关 ~/Library/LaunchAgents 下的条目。系统域的代理与守护进程需要管理员权限，请在「终端」里自行处理。"))
        }
        let domainTarget = "gui/\(getuid())"
        let arguments = enabled
            ? ["bootstrap", domainTarget, item.plistPath]
            : ["bootout", "\(domainTarget)/\(item.label)"]
        guard let output = Shell.run("/bin/launchctl", arguments, timeout: 10) else {
            throw OperationError(L("launchctl 报错：%@", "no output"))
        }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            throw OperationError(L("launchctl 报错：%@", trimmed))
        }
    }

}
