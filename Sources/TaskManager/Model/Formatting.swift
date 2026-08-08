import Foundation

enum Fmt {

    /// 字节数 → "1.23 GB"。任务管理器风格：GB/MB 保留一位小数，KB 取整。
    static func bytes(_ value: UInt64) -> String {
        bytes(Double(value))
    }

    static func bytes(_ value: Double) -> String {
        let v = max(0, value)
        switch v {
        case 0..<1024:
            return "\(Int(v)) B"
        case 1024..<(1024 * 1024):
            return String(format: "%.0f KB", v / 1024)
        case (1024 * 1024)..<(1024 * 1024 * 1024):
            return String(format: "%.1f MB", v / (1024 * 1024))
        case (1024 * 1024 * 1024)..<(1024 * 1024 * 1024 * 1024):
            return String(format: "%.2f GB", v / (1024 * 1024 * 1024))
        default:
            return String(format: "%.2f TB", v / (1024 * 1024 * 1024 * 1024))
        }
    }

    /// 速率（字节/秒）。网络与磁盘页用。
    static func rate(_ bytesPerSecond: Double) -> String {
        bytes(bytesPerSecond) + "/s"
    }

    /// 网络页习惯用 Mbps。
    static func mbps(_ bytesPerSecond: Double) -> String {
        String(format: "%.1f Mbps", bytesPerSecond * 8 / 1_000_000)
    }

    static func percent(_ value: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f%%", value)
    }

    /// CPU 累计时间 "12:34:56"。
    static func duration(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        let (h, m, sec) = (s / 3600, (s % 3600) / 60, s % 60)
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%02d:%02d", m, sec)
    }

    /// 开机时长 "3 天 04:15:22"（对应 Win11 CPU 页的「正常运行时间」）。
    static func uptime(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        let days = s / 86400
        let rest = s % 86400
        let text = String(format: "%02d:%02d:%02d", rest / 3600, (rest % 3600) / 60, rest % 60)
        return days > 0 ? MainActor.assumeIsolated { L("%d 天 %@", days, text) } : text
    }

    static let dateTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static func time(_ date: Date) -> String { dateTime.string(from: date) }
}
