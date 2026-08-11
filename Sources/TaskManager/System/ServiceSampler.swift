import Foundation

struct ServiceEntry: Sendable, Identifiable {
    var id: String { label }
    var label: String
    var pid: pid_t?
    /// launchctl 报告的上次退出码（0 表示正常退出）
    var lastExitStatus: Int32
    var isApple: Bool { label.hasPrefix("com.apple.") }

    @MainActor
    var statusText: String {
        if pid != nil { return L("运行中") }
        if lastExitStatus == 0 { return L("已加载") }
        return L("上次退出码 %d", lastExitStatus)
    }
}

/// 服务页的数据源。macOS 上「服务」的对应物就是 launchd 作业。
///
/// 非 root 只能看到当前用户域（gui/<uid>）里的作业；系统域（system/）需要 root，
/// 所以这里只列用户域，并在界面上说明。
enum ServiceSampler {

    static func load() -> [ServiceEntry] {
        guard let output = Shell.run("/bin/launchctl", ["list"], timeout: 10) else { return [] }
        var result: [ServiceEntry] = []
        for line in output.split(separator: "\n").dropFirst() {   // 首行是表头 PID Status Label
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 3 else { continue }
            let label = fields[2].trimmingCharacters(in: .whitespaces)
            guard !label.isEmpty else { continue }
            result.append(ServiceEntry(
                label: label,
                pid: pid_t(fields[0]),
                lastExitStatus: Int32(fields[1]) ?? 0
            ))
        }
        return result.sorted { $0.label < $1.label }
    }
}
