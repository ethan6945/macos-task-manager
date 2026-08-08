import Darwin
import Foundation

/// 从 `top` 拿到的每进程指标。
///
/// 为什么要靠 `top`：`/bin/ps` 和 `/usr/bin/top` 都是 setuid root 且带
/// `com.apple.system-task-ports.read` 权限，而未签名的普通 App 调用
/// `proc_pidinfo(PROC_PIDTASKALLINFO)` 只能读到**同用户**的进程
/// （本机实测 691 个进程里有 291 个读不到）。常驻一个 `top -l 0` 子进程解析它的
/// 输出，是无需提权就能覆盖全部进程的唯一稳妥办法。
struct TopMetrics: Sendable {
    var pid: pid_t
    var cpuPercent: Double = 0
    var cpuTime: TimeInterval = 0
    var threads: Int = 0
    var ports: Int = 0
    var memory: UInt64 = 0
    var energy: Double = 0
    var pageIns: UInt64 = 0
    var contextSwitches: UInt64 = 0
    var state: String = ""
}

/// 常驻的 `top` 子进程，按块解析输出。
final class TopStream: @unchecked Sendable {

    private let lock = NSLock()
    private var process: Process?
    private var buffer = Data()
    private var pending: [pid_t: TopMetrics] = [:]
    private var latest: [pid_t: TopMetrics] = [:]
    private var blockCount = 0
    private var inBlock = false
    private var columns: [String] = []
    private var lastUpdate = Date.distantPast
    private var startFailed = false

    /// top 是否正在提供数据。首个采样块的 %CPU 是进程生命周期均值，会被丢弃。
    var isHealthy: Bool {
        lock.lock(); defer { lock.unlock() }
        return !startFailed && blockCount > 1 && Date().timeIntervalSince(lastUpdate) < 15
    }

    var isUnavailable: Bool {
        lock.lock(); defer { lock.unlock() }
        return startFailed
    }

    func metrics() -> [pid_t: TopMetrics] {
        lock.lock(); defer { lock.unlock() }
        return latest
    }

    /// 以给定采样间隔启动（或重启）top。
    func restart(interval: TimeInterval) {
        stop()
        lock.lock()
        buffer.removeAll(keepingCapacity: true)
        pending.removeAll(keepingCapacity: true)
        blockCount = 0
        inBlock = false
        startFailed = false
        lock.unlock()

        let stats = "pid,cpu,time,threads,ports,mem,power,pageins,csw,pstate,command"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/top")
        process.arguments = [
            "-l", "0",                                   // 无限采样
            "-s", String(max(1, Int(interval.rounded()))),
            "-n", "8192",                                // 不限制进程数
            "-o", "pid",                                 // 固定顺序，减少 top 自身排序开销
            "-stats", stats
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.consume(data)
        }
        process.terminationHandler = { [weak self] _ in
            guard let self else { return }
            self.lock.lock()
            self.startFailed = true
            self.lock.unlock()
        }

        do {
            try process.run()
            self.process = process
        } catch {
            lock.lock(); startFailed = true; lock.unlock()
        }
    }

    func stop() {
        if let process, process.isRunning {
            (process.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
            process.terminationHandler = nil
            process.terminate()
        }
        process = nil
    }

    deinit { stop() }

    // MARK: - 解析

    private func consume(_ data: Data) {
        lock.lock()
        buffer.append(data)
        // 按行切分，最后一段可能不完整，留到下次
        while let newline = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            let line = String(decoding: lineData, as: UTF8.self)
            parse(line)
        }
        lock.unlock()
    }

    /// 调用方必须持有 lock。
    private func parse(_ rawLine: String) {
        let line = rawLine.trimmingCharacters(in: .whitespaces)

        if line.hasPrefix("PID") {
            // 新的一块开始：把上一块的结果提交
            if inBlock {
                commitBlock()
            }
            columns = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            inBlock = true
            pending.removeAll(keepingCapacity: true)
            return
        }

        guard inBlock else { return }
        if line.isEmpty { return }
        // 下一块的表头前会出现 "Processes:" 这样的汇总行，说明当前块结束
        if line.hasPrefix("Processes:") || line.hasPrefix("Load Avg") {
            commitBlock()
            inBlock = false
            return
        }

        guard let metrics = parseRow(line) else { return }
        pending[metrics.pid] = metrics
    }

    private func commitBlock() {
        blockCount += 1
        lastUpdate = Date()
        // 首块的 %CPU 是生命周期均值而非瞬时值，丢弃
        if blockCount > 1 {
            latest = pending
        }
        pending.removeAll(keepingCapacity: true)
    }

    private func parseRow(_ line: String) -> TopMetrics? {
        // 列顺序与启动时的 -stats 一致，COMMAND 放在最后，所以前面的列可以直接按空白切
        var fields = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard fields.count >= 10, let pid = pid_t(fields[0]) else { return nil }

        var m = TopMetrics(pid: pid)
        m.cpuPercent = Double(fields[1]) ?? 0
        m.cpuTime = Self.parseTime(fields[2])
        m.threads = Self.parseCount(fields[3])
        m.ports = Self.parseCount(fields[4])
        m.memory = Self.parseSize(fields[5])
        m.energy = Double(fields[6]) ?? 0
        m.pageIns = UInt64(Self.parseCount(fields[7]))
        m.contextSwitches = UInt64(Self.parseCount(fields[8]))
        m.state = fields[9]
        fields.removeAll(keepingCapacity: false)
        return m
    }

    /// top 会在数值后面加 `+` / `-` 表示相对上一次采样的增减，解析前要去掉。
    static func trimDelta(_ text: String) -> String {
        var s = text
        while let last = s.last, last == "+" || last == "-" { s.removeLast() }
        return s
    }

    /// "16:27.61" / "1:02:03.45" / "00:00.00" → 秒
    static func parseTime(_ text: String) -> TimeInterval {
        let parts = text.split(separator: ":").map(String.init)
        guard !parts.isEmpty else { return 0 }
        var seconds: TimeInterval = 0
        for part in parts {
            seconds = seconds * 60 + (Double(part) ?? 0)
        }
        return seconds
    }

    /// "17" / "2803-" / "5/1"（总数/运行中）/ "5974+" → 总数
    static func parseCount(_ text: String) -> Int {
        let cleaned = trimDelta(text)
        if let slash = cleaned.firstIndex(of: "/") {
            return Int(cleaned[cleaned.startIndex..<slash]) ?? 0
        }
        return Int(cleaned) ?? 0
    }

    /// "531M+" / "4960K" / "1.2G-" / "0B" → 字节
    static func parseSize(_ text: String) -> UInt64 {
        var s = trimDelta(text)
        guard let unit = s.last else { return 0 }
        let multiplier: Double
        switch unit {
        case "B": multiplier = 1
        case "K": multiplier = 1024
        case "M": multiplier = 1024 * 1024
        case "G": multiplier = 1024 * 1024 * 1024
        case "T": multiplier = 1024 * 1024 * 1024 * 1024
        default:  multiplier = 1     // 没有单位后缀时按字节
        }
        if multiplier > 1 { s.removeLast() }
        return UInt64(max(0, (Double(s) ?? 0) * multiplier))
    }
}
