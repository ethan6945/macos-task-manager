import Darwin
import Foundation

/// 内存快照。字段口径对齐「活动监视器」，同时补齐 Win11 内存页需要的分解项。
struct MemorySnapshot: Sendable {
    var total: UInt64 = 0
    /// 使用中 = App 内存 + 联动内存 + 已压缩
    var used: UInt64 = 0
    var free: UInt64 = 0
    /// App 内存（匿名页，不含可清除页）
    var app: UInt64 = 0
    /// 联动内存（内核不可换出）
    var wired: UInt64 = 0
    var compressed: UInt64 = 0
    /// 已缓存文件（文件映射页 + 可清除页 + 预读页）
    var cachedFiles: UInt64 = 0

    var swapTotal: UInt64 = 0
    var swapUsed: UInt64 = 0

    var pageIns: UInt64 = 0
    var pageOuts: UInt64 = 0
    var swapIns: UInt64 = 0
    var swapOuts: UInt64 = 0

    /// 内存压力 0...100，以及内核给出的压力等级。
    var pressure: Double = 0
    var pressureLevel: PressureLevel = .normal

    var usedPercent: Double { total > 0 ? Double(used) / Double(total) * 100 : 0 }

    enum PressureLevel: Int, Sendable {
        case normal = 1, warning = 2, critical = 4

        @MainActor
        var displayName: String {
            switch self {
            case .normal: L("正常")
            case .warning: L("警告")
            case .critical: L("紧张")
            }
        }
    }
}

final class MemorySampler {
    private let pageSize = Sysctl.value("hw.pagesize", as: UInt64.self) ?? 16384
    private let totalMemory = Sysctl.value("hw.memsize", as: UInt64.self) ?? 0

    func sample() -> MemorySnapshot {
        var snapshot = MemorySnapshot()
        snapshot.total = totalMemory

        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return snapshot }

        func toBytes(_ pages: some BinaryInteger) -> UInt64 { UInt64(pages) * pageSize }

        let purgeable = toBytes(stats.purgeable_count)
        let external = toBytes(stats.external_page_count)
        let internalPages = toBytes(stats.internal_page_count)
        let speculative = toBytes(stats.speculative_count)

        snapshot.wired = toBytes(stats.wire_count)
        snapshot.compressed = toBytes(stats.compressor_page_count)
        snapshot.app = internalPages > purgeable ? internalPages - purgeable : 0
        snapshot.cachedFiles = external + purgeable + speculative
        snapshot.free = toBytes(stats.free_count) > speculative ? toBytes(stats.free_count) - speculative : 0
        snapshot.used = snapshot.app + snapshot.wired + snapshot.compressed

        snapshot.pageIns = UInt64(stats.pageins)
        snapshot.pageOuts = UInt64(stats.pageouts)
        snapshot.swapIns = UInt64(stats.swapins)
        snapshot.swapOuts = UInt64(stats.swapouts)

        if let swap = Sysctl.swapUsage {
            snapshot.swapTotal = swap.total
            snapshot.swapUsed = swap.used
        }

        // 压力百分比取「联动 + 已压缩」占比（与 Stats/htop 的近似口径一致），
        // 等级则直接用内核的 memorystatus 判定，两者互为印证。
        if snapshot.total > 0 {
            snapshot.pressure = Double(snapshot.wired + snapshot.compressed) / Double(snapshot.total) * 100
        }
        if let level = Sysctl.value("kern.memorystatus_vm_pressure_level", as: Int32.self) {
            snapshot.pressureLevel = MemorySnapshot.PressureLevel(rawValue: Int(level)) ?? .normal
        }
        return snapshot
    }
}
