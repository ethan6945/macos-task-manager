import Darwin
import Foundation

/// 一行进程记录。汇总了 sysctl（身份）、proc_pidpath（路径）、
/// top（指标）与 rusage（磁盘 I/O）四个来源。
struct ProcessRow: Sendable, Identifiable {
    var id: pid_t { pid }

    var pid: pid_t
    var ppid: pid_t
    var uid: uid_t
    var user: String
    /// 展示名：优先用 App 的本地化名称，其次是可执行文件名，最后是内核短名
    var name: String
    var path: String?
    var bundleIdentifier: String?
    var bundlePath: String?
    /// 有 Dock 图标的前台应用（对应 Win11 的「应用」分组）
    var isApp: Bool = false

    var cpuPercent: Double = 0
    var cpuTime: TimeInterval = 0
    var memory: UInt64 = 0
    var threads: Int = 0
    var ports: Int = 0
    var energy: Double = 0
    var pageIns: UInt64 = 0
    var contextSwitches: UInt64 = 0

    var status: ProcessStatus = .unknown
    var nice: Int32 = 0
    var startTime: Date = .distantPast
    var is64Bit: Bool = true
    /// arm64 / x86_64 / 32 位 —— 采样时就算好，表格列排序要用
    var architecture: String = ""

    /// 磁盘 I/O 只能读到同用户的进程（rusage 受权限限制）
    var diskRead: UInt64?
    var diskWrite: UInt64?
    var diskReadRate: Double = 0
    var diskWriteRate: Double = 0

    /// top 是否覆盖到这个进程（没覆盖到时指标列显示「—」）
    var hasMetrics: Bool = false

    var isOwnedByCurrentUser: Bool { uid == getuid() }
    /// 排序用：Optional 不是 Comparable，表格列需要一个非可选的字符串
    var pathText: String { path ?? "" }

    // 单元格直接用这些预格式化好的字符串。表格每次刷新都要重建可见单元格，
    // 在这里格式化一次比在 body 里反复 String(format:) 便宜。
    var cpuText: String { hasMetrics ? String(format: "%.1f%%", cpuPercent) : "—" }
    var memoryText: String { hasMetrics ? Fmt.bytes(memory) : "—" }
    var threadsText: String { hasMetrics ? String(threads) : "—" }
    var portsText: String { hasMetrics ? String(ports) : "—" }
    var energyText: String { hasMetrics ? String(format: "%.1f", energy) : "—" }
    var pidText: String { String(pid) }
    var diskText: String {
        guard diskRead != nil else { return "—" }
        let total = diskReadRate + diskWriteRate
        return total < 1024 ? "0" : Fmt.rate(total)
    }
}

/// 从主线程采集的应用身份信息（NSWorkspace 只能在主线程用）。
struct AppIdentity: Sendable {
    var localizedName: String
    var bundleIdentifier: String?
    var bundlePath: String?
    var isRegular: Bool
}

final class ProcessSampler {

    private struct DiskCounters {
        var read: UInt64
        var written: UInt64
    }

    private var pathCache: [pid_t: (path: String, startTime: Date)] = [:]
    private var diskPrevious: [pid_t: DiskCounters] = [:]
    private var cpuPrevious: [pid_t: (time: TimeInterval, at: Date)] = [:]
    private var lastSampleTime = Date()
    private let nativeArchitecture: String = {
        (Sysctl.string("machdep.cpu.brand_string") ?? "").hasPrefix("Apple") ? "arm64" : "x86_64"
    }()

    func sample(appIdentities: [pid_t: AppIdentity], topMetrics: [pid_t: TopMetrics]) -> [ProcessRow] {
        let now = Date()
        let elapsed = max(0.001, now.timeIntervalSince(lastSampleTime))
        lastSampleTime = now

        let entries = Sysctl.allProcesses()
        let currentUID = getuid()
        var rows: [ProcessRow] = []
        rows.reserveCapacity(entries.count)

        var livePIDs = Set<pid_t>()
        var newDisk: [pid_t: DiskCounters] = [:]
        var newCPU: [pid_t: (time: TimeInterval, at: Date)] = [:]

        for entry in entries {
            livePIDs.insert(entry.pid)

            let path = cachedPath(for: entry)
            let identity = appIdentities[entry.pid]
            let name = identity?.localizedName
                ?? path.map { ($0 as NSString).lastPathComponent }
                ?? entry.comm

            var row = ProcessRow(
                pid: entry.pid,
                ppid: entry.ppid,
                uid: entry.uid,
                user: Sysctl.userName(entry.uid),
                name: name,
                path: path,
                bundleIdentifier: identity?.bundleIdentifier,
                bundlePath: identity?.bundlePath,
                isApp: identity?.isRegular ?? false
            )
            row.status = entry.status
            row.nice = entry.nice
            row.startTime = entry.startTime
            row.is64Bit = entry.is64Bit
            row.architecture = entry.is64Bit ? nativeArchitecture : "32-bit"

            if let m = topMetrics[entry.pid] {
                row.cpuPercent = m.cpuPercent
                row.cpuTime = m.cpuTime
                row.memory = m.memory
                row.threads = m.threads
                row.ports = m.ports
                row.energy = m.energy
                row.pageIns = m.pageIns
                row.contextSwitches = m.contextSwitches
                row.hasMetrics = true
                newCPU[entry.pid] = (m.cpuTime, now)
            } else if entry.uid == currentUID, let fallback = Self.libprocMetrics(entry.pid) {
                // top 不可用时，同用户的进程仍可用 libproc 自行差分
                row.memory = fallback.memory
                row.threads = fallback.threads
                row.cpuTime = fallback.cpuTime
                if let previous = cpuPrevious[entry.pid] {
                    let dt = now.timeIntervalSince(previous.at)
                    if dt > 0 {
                        row.cpuPercent = max(0, (fallback.cpuTime - previous.time) / dt * 100)
                    }
                }
                row.hasMetrics = true
                newCPU[entry.pid] = (fallback.cpuTime, now)
            }

            if entry.uid == currentUID, let io = Self.diskIO(entry.pid) {
                row.diskRead = io.read
                row.diskWrite = io.written
                if let previous = diskPrevious[entry.pid] {
                    row.diskReadRate = io.read >= previous.read ? Double(io.read - previous.read) / elapsed : 0
                    row.diskWriteRate = io.written >= previous.written ? Double(io.written - previous.written) / elapsed : 0
                }
                newDisk[entry.pid] = DiskCounters(read: io.read, written: io.written)
            }

            rows.append(row)
        }

        diskPrevious = newDisk
        cpuPrevious = newCPU
        pathCache = pathCache.filter { livePIDs.contains($0.key) }
        return rows
    }

    /// 可执行文件路径按 pid + 启动时间缓存，避免每秒对几百个进程重复系统调用。
    private func cachedPath(for entry: KernProcEntry) -> String? {
        if let cached = pathCache[entry.pid], cached.startTime == entry.startTime {
            return cached.path
        }
        guard let path = Sysctl.executablePath(entry.pid) else { return nil }
        pathCache[entry.pid] = (path, entry.startTime)
        return path
    }

    // MARK: - libproc 兜底（仅同用户进程可读）

    private static func libprocMetrics(_ pid: pid_t) -> (memory: UInt64, threads: Int, cpuTime: TimeInterval)? {
        var info = proc_taskallinfo()
        let size = Int32(MemoryLayout<proc_taskallinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, &info, size) == size else { return nil }
        let nanos = Double(info.ptinfo.pti_total_user + info.ptinfo.pti_total_system)
        return (info.ptinfo.pti_resident_size, Int(info.ptinfo.pti_threadnum), nanos / 1_000_000_000)
    }

    private static func diskIO(_ pid: pid_t) -> (read: UInt64, written: UInt64)? {
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) { pointer -> Int32 in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        guard result == 0 else { return nil }
        return (usage.ri_diskio_bytesread, usage.ri_diskio_byteswritten)
    }
}

// MARK: - 进程操作

@MainActor
enum ProcessControl {

    /// 结束进程。`force` 为真时发 SIGKILL，否则 SIGTERM。
    static func terminate(_ pid: pid_t, force: Bool) throws {
        guard kill(pid, force ? SIGKILL : SIGTERM) == 0 else {
            throw mapErrno(L("该进程属于其他用户或系统，未提权的应用结束不了它。"))
        }
    }

    /// 设置优先级（对应 Windows 的「设置优先级」）。nice 越小优先级越高。
    static func setNice(_ pid: pid_t, to value: Int32) throws {
        errno = 0
        guard setpriority(PRIO_PROCESS, id_t(pid), value) == 0 else {
            throw mapErrno(L("提高优先级（负 nice）需要 root；降低优先级则不需要，但目标进程必须与你同用户。"))
        }
    }

    /// 文案在抛出时就本地化好 —— `LocalizedError.errorDescription` 是 nonisolated 的，
    /// 没法在里面调 `L()`。
    private static func mapErrno(_ hint: String) -> OperationError {
        switch errno {
        case EPERM, EACCES: OperationError(L("权限不足。%@", hint))
        case ESRCH: OperationError(L("进程已经不存在了。"))
        default: OperationError(L("操作失败（errno %d：%@）。", Int(errno), String(cString: strerror(errno))))
        }
    }
}

/// 已本地化的操作失败信息。
struct OperationError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
