import Darwin
import Foundation

struct CPUSnapshot: Sendable {
    /// 总利用率 0...100
    var total: Double = 0
    var user: Double = 0
    var system: Double = 0
    var idle: Double = 0
    var nice: Double = 0
    /// 每个逻辑处理器的利用率 0...100
    var perCore: [Double] = []
}

/// 由 `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` 做 tick 差分。
final class CPUSampler {
    private var previous: [[UInt32]] = []   // [core][user,system,idle,nice]

    func sample() -> CPUSnapshot {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                  &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info else { return CPUSnapshot() }

        defer {
            vm_deallocate(mach_task_self_,
                          vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }

        let states = Int(CPU_STATE_MAX)
        var current: [[UInt32]] = []
        current.reserveCapacity(Int(cpuCount))
        for core in 0..<Int(cpuCount) {
            let base = core * states
            current.append([
                UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])
            ])
        }

        defer { previous = current }
        guard previous.count == current.count else { return CPUSnapshot(perCore: Array(repeating: 0, count: current.count)) }

        var snapshot = CPUSnapshot()
        var sumUser = 0.0, sumSystem = 0.0, sumIdle = 0.0, sumNice = 0.0, sumTotal = 0.0

        for core in 0..<current.count {
            // tick 计数器是 32 位，回绕时用 &- 得到正确的差值。
            let d = (0..<4).map { Double(current[core][$0] &- previous[core][$0]) }
            let total = d.reduce(0, +)
            snapshot.perCore.append(total > 0 ? (total - d[2]) / total * 100 : 0)
            sumUser += d[0]; sumSystem += d[1]; sumIdle += d[2]; sumNice += d[3]; sumTotal += total
        }

        if sumTotal > 0 {
            snapshot.user = sumUser / sumTotal * 100
            snapshot.system = sumSystem / sumTotal * 100
            snapshot.idle = sumIdle / sumTotal * 100
            snapshot.nice = sumNice / sumTotal * 100
            snapshot.total = 100 - snapshot.idle
        }
        return snapshot
    }
}
