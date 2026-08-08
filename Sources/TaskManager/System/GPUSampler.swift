import Foundation
import IOKit
import Metal

struct GPUSnapshot: Sendable {
    /// 总利用率 0...100（对应 Win11 GPU 页的「GPU 利用率」）
    var utilization: Double = 0
    /// 渲染器 / 分块器 —— 对应 Win11 的「GPU 引擎」分图
    var rendererUtilization: Double = 0
    var tilerUtilization: Double = 0
    /// 已分配 / 使用中的显存（统一内存架构下取自系统内存）
    var allocatedMemory: UInt64 = 0
    var inUseMemory: UInt64 = 0
    var driverMemory: UInt64 = 0
    var available: Bool = false
}

struct GPUInfo: Sendable {
    var name: String = "—"
    var coreCount: Int?
    var unifiedMemory: Bool = false
    var recommendedWorkingSet: UInt64 = 0
    var maxBufferLength: UInt64 = 0
    var registryName: String?
}

/// GPU 数据来自 IORegistry 里 `IOAccelerator` 节点的 `PerformanceStatistics` 字典，
/// 无需特殊权限；设备规格来自 Metal。
final class GPUSampler {

    let info: GPUInfo

    init() {
        var info = GPUInfo()
        if let device = MTLCreateSystemDefaultDevice() {
            info.name = device.name
            info.unifiedMemory = device.hasUnifiedMemory
            info.recommendedWorkingSet = device.recommendedMaxWorkingSetSize
            info.maxBufferLength = UInt64(device.maxBufferLength)
        }
        IORegistry.forEachService(matching: "IOAccelerator") { entry, props in
            if info.registryName == nil {
                info.registryName = IORegistry.name(entry)
                // 核心数挂在 GPU 的父节点（AGXAccelerator → 设备节点）上
                if let cores = IORegistry.property(entry, "gpu-core-count", searchParents: true) as? NSNumber {
                    info.coreCount = cores.intValue
                }
                if info.coreCount == nil, let cores = props.number("gpu-core-count") {
                    info.coreCount = Int(cores)
                }
            }
        }
        self.info = info
    }

    func sample() -> GPUSnapshot {
        var snapshot = GPUSnapshot()
        IORegistry.forEachService(matching: "IOAccelerator") { _, props in
            guard let stats = props["PerformanceStatistics"] as? [String: Any] else { return }
            // 多 GPU 时取利用率最高的那块（Apple Silicon 上只有一块）
            let utilization = stats.number("Device Utilization %") ?? 0
            guard !snapshot.available || utilization > snapshot.utilization else { return }
            snapshot.available = true
            snapshot.utilization = utilization
            snapshot.rendererUtilization = stats.number("Renderer Utilization %") ?? 0
            snapshot.tilerUtilization = stats.number("Tiler Utilization %") ?? 0
            snapshot.allocatedMemory = stats.integer("Alloc system memory") ?? 0
            snapshot.inUseMemory = stats.integer("In use system memory") ?? 0
            snapshot.driverMemory = stats.integer("In use system memory (driver)") ?? 0
        }
        return snapshot
    }
}
