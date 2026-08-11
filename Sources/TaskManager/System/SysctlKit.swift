import Darwin
import Foundation

/// uid → 用户名的缓存。`getpwuid` 会查目录服务，每秒对几百个进程调用一次太贵。
private let userNameCache = Locked<[uid_t: String]>([:])

/// `sysctl` / `sysctlbyname` 的轻量封装。
enum Sysctl {

    /// 读取一个定长标量，例如 `hw.memsize`、`hw.logicalcpu`。
    static func value<T: FixedWidthInteger>(_ name: String, as type: T.Type = T.self) -> T? {
        var size = MemoryLayout<T>.size
        var result = T.zero
        guard sysctlbyname(name, &result, &size, nil, 0) == 0 else { return nil }
        return result
    }

    /// 读取字符串，例如 `machdep.cpu.brand_string`、`hw.model`。
    static func string(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cBuffer: buffer)
    }

    /// 读取任意结构体，通过 MIB 数组。
    static func struct_<T>(_ mib: [Int32], as type: T.Type) -> T? {
        var mib = mib
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        var size = MemoryLayout<T>.size
        guard sysctl(&mib, UInt32(mib.count), value, &size, nil, 0) == 0 else { return nil }
        return value.pointee
    }

    /// 开机时刻。
    static var bootTime: Date? {
        guard let tv = struct_([CTL_KERN, KERN_BOOTTIME], as: timeval.self) else { return nil }
        return Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000)
    }

    /// 已开机时长（秒）。
    static var uptime: TimeInterval {
        guard let boot = bootTime else { return 0 }
        return Date().timeIntervalSince(boot)
    }

    /// 交换区使用情况（`vm.swapusage`）。
    static var swapUsage: (total: UInt64, used: UInt64, free: UInt64, encrypted: Bool)? {
        guard let x = struct_([CTL_VM, VM_SWAPUSAGE], as: xsw_usage.self) else { return nil }
        return (x.xsu_total, x.xsu_used, x.xsu_avail, x.xsu_encrypted != 0)
    }

    /// 全系统打开文件数（对应 Windows 的「句柄」）。
    static var openFileCount: Int32? { value("kern.num_files") }

    /// 系统级最大文件数上限。
    static var maxFileCount: Int32? { value("kern.maxfiles") }
}

/// 一次 `KERN_PROC_ALL` 快照能拿到的进程身份信息 —— 这些字段对**所有**进程都可读，
/// 不受 libproc 的同用户限制。
struct KernProcEntry: Sendable {
    var pid: pid_t
    var ppid: pid_t
    var uid: uid_t
    var gid: gid_t
    var comm: String          // 内核里的短名（最长 16 字节）
    var status: ProcessStatus
    var nice: Int32
    var startTime: Date
    var is64Bit: Bool
}

enum ProcessStatus: UInt8, Sendable {
    case idle = 1, running = 2, sleeping = 3, stopped = 4, zombie = 5, unknown = 0

    @MainActor
    var displayName: String {
        switch self {
        case .idle: L("空闲")
        case .running: L("运行中")
        case .sleeping: L("睡眠")
        case .stopped: L("已停止")
        case .zombie: L("僵尸")
        case .unknown: L("未知")
        }
    }
}

extension Sysctl {
    /// 全量进程列表。返回的字段对所有用户的进程都有效。
    static func allProcesses() -> [KernProcEntry] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }

        // 两次调用之间进程数可能增加，多留一些余量。
        let capacity = size / MemoryLayout<kinfo_proc>.stride + 64
        var buffer = [kinfo_proc](repeating: kinfo_proc(), count: capacity)
        size = capacity * MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &buffer, &size, nil, 0) == 0 else { return [] }

        let count = size / MemoryLayout<kinfo_proc>.stride
        var result: [KernProcEntry] = []
        result.reserveCapacity(count)

        for i in 0..<count {
            let kp = buffer[i]
            let pid = kp.kp_proc.p_pid
            guard pid >= 0 else { continue }

            let comm = String(cTuple: kp.kp_proc.p_comm)
            let start = kp.kp_proc.p_starttime
            result.append(KernProcEntry(
                pid: pid,
                ppid: kp.kp_eproc.e_ppid,
                uid: kp.kp_eproc.e_ucred.cr_uid,
                gid: kp.kp_eproc.e_pcred.p_rgid,
                comm: comm,
                status: ProcessStatus(rawValue: UInt8(clamping: kp.kp_proc.p_stat)) ?? .unknown,
                nice: Int32(kp.kp_proc.p_nice),
                startTime: Date(timeIntervalSince1970: Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000),
                is64Bit: (kp.kp_proc.p_flag & P_LP64) != 0
            ))
        }
        return result
    }

    /// 进程完整路径。对所有进程都可读。
    static func executablePath(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 2)
        let n = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard n > 0 else { return nil }
        return String(cBuffer: buffer)
    }

    /// 进程命令行参数（`KERN_PROCARGS2`）。仅对同用户进程可读。
    static func commandLine(_ pid: pid_t) -> [String]? {
        var argmax: Int32 = 0
        var sz = MemoryLayout<Int32>.size
        var mibMax: [Int32] = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&mibMax, 2, &argmax, &sz, nil, 0) == 0 else { return nil }

        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = Int(argmax)
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }

        // 布局：argc(int32) | 可执行文件路径\0 | 对齐填充\0* | argv[0]\0 argv[1]\0 ...
        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        var offset = MemoryLayout<Int32>.size

        func readCString() -> String? {
            guard offset < size else { return nil }
            let start = offset
            while offset < size && buffer[offset] != 0 { offset += 1 }
            guard offset <= size else { return nil }
            let bytes = buffer[start..<offset].map { UInt8(bitPattern: $0) }
            offset += 1
            return String(decoding: bytes, as: UTF8.self)
        }

        _ = readCString()                                   // 跳过可执行文件路径
        while offset < size && buffer[offset] == 0 { offset += 1 }  // 跳过对齐填充

        var args: [String] = []
        for _ in 0..<max(0, argc) {
            guard let s = readCString() else { break }
            args.append(s)
        }
        return args.isEmpty ? nil : args
    }

    /// 由 uid 取用户名。
    static func userName(_ uid: uid_t) -> String {
        if let cached = userNameCache.withLock({ $0[uid] }) {
            return cached
        }
        let name: String
        if let pw = getpwuid(uid), let raw = pw.pointee.pw_name {
            name = String(cString: raw)
        } else {
            name = String(uid)
        }
        userNameCache.withLock { $0[uid] = name }
        return name
    }
}
