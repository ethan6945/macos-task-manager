import Darwin
import Foundation
import IOKit

struct DiskSnapshot: Sendable, Identifiable {
    var id: String { name }
    var name: String
    var bsdName: String?
    var size: UInt64

    var readRate: Double = 0        // 字节/秒
    var writeRate: Double = 0
    var readOPS: Double = 0         // 次/秒
    var writeOPS: Double = 0
    /// 活动时间 0...100，对应 Win11 磁盘页的「活动时间」
    var activeTime: Double = 0
    /// 平均响应时间（毫秒）
    var averageLatency: Double = 0

    var totalBytesRead: UInt64 = 0
    var totalBytesWritten: UInt64 = 0
}

struct VolumeInfo: Sendable, Identifiable {
    var id: String { mountPoint }
    var name: String
    var mountPoint: String
    var fileSystem: String
    var device: String
    var capacity: UInt64
    var available: UInt64
    var isBoot: Bool
    var isReadOnly: Bool

    var used: UInt64 { capacity > available ? capacity - available : 0 }
    var usedPercent: Double { capacity > 0 ? Double(used) / Double(capacity) * 100 : 0 }
}

/// 磁盘吞吐来自 `IOBlockStorageDriver` 的 `Statistics` 字典差分。
final class DiskSampler {

    private struct Counters {
        var bytesRead: UInt64 = 0, bytesWritten: UInt64 = 0
        var opsRead: UInt64 = 0, opsWritten: UInt64 = 0
        var timeRead: UInt64 = 0, timeWritten: UInt64 = 0
    }

    private var previous: [String: Counters] = [:]
    private var lastSampleTime = Date()

    func sample() -> [DiskSnapshot] {
        let now = Date()
        let elapsed = max(0.001, now.timeIntervalSince(lastSampleTime))
        lastSampleTime = now

        var results: [DiskSnapshot] = []
        var current: [String: Counters] = [:]

        IORegistry.forEachService(matching: "IOBlockStorageDriver") { entry, props in
            guard let stats = props["Statistics"] as? [String: Any] else { return }

            let (name, bsdName, size) = Self.identify(entry)
            var counters = Counters()
            counters.bytesRead = stats.integer("Bytes (Read)") ?? 0
            counters.bytesWritten = stats.integer("Bytes (Write)") ?? 0
            counters.opsRead = stats.integer("Operations (Read)") ?? 0
            counters.opsWritten = stats.integer("Operations (Write)") ?? 0
            counters.timeRead = stats.integer("Total Time (Read)") ?? 0
            counters.timeWritten = stats.integer("Total Time (Write)") ?? 0
            current[name] = counters

            var snapshot = DiskSnapshot(name: name, bsdName: bsdName, size: size)
            snapshot.totalBytesRead = counters.bytesRead
            snapshot.totalBytesWritten = counters.bytesWritten

            if let old = self.previous[name] {
                func delta(_ new: UInt64, _ old: UInt64) -> Double { new >= old ? Double(new - old) : 0 }
                snapshot.readRate = delta(counters.bytesRead, old.bytesRead) / elapsed
                snapshot.writeRate = delta(counters.bytesWritten, old.bytesWritten) / elapsed
                let dOpsR = delta(counters.opsRead, old.opsRead)
                let dOpsW = delta(counters.opsWritten, old.opsWritten)
                snapshot.readOPS = dOpsR / elapsed
                snapshot.writeOPS = dOpsW / elapsed

                // Total Time 是纳秒累计的 I/O 服务时间
                let busyNanos = delta(counters.timeRead, old.timeRead) + delta(counters.timeWritten, old.timeWritten)
                snapshot.activeTime = min(100, busyNanos / (elapsed * 1_000_000_000) * 100)
                let ops = dOpsR + dOpsW
                snapshot.averageLatency = ops > 0 ? busyNanos / ops / 1_000_000 : 0
            }
            results.append(snapshot)
        }

        previous = current
        return results.sorted { $0.name < $1.name }
    }

    /// 由 IOBlockStorageDriver 的 IOMedia 子节点取盘名、BSD 名与容量。
    private static func identify(_ entry: io_registry_entry_t) -> (String, String?, UInt64) {
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(entry, kIOServicePlane, &iterator) == KERN_SUCCESS else {
            return (IORegistry.name(entry) ?? "Disk", nil, 0)
        }
        defer { IOObjectRelease(iterator) }

        while case let child = IOIteratorNext(iterator), child != 0 {
            defer { IOObjectRelease(child) }
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(child, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any] else { continue }

            var name = IORegistry.name(child) ?? "Disk"
            if name.hasSuffix(" Media") { name.removeLast(" Media".count) }
            return (name, dict["BSD Name"] as? String, dict.integer("Size") ?? 0)
        }
        return (IORegistry.name(entry) ?? "Disk", nil, 0)
    }

    /// 已挂载的卷。对应 Win11 磁盘页底部的容量/格式信息。
    static func volumes() -> [VolumeInfo] {
        var mounts: UnsafeMutablePointer<statfs>?
        let count = getmntinfo(&mounts, MNT_NOWAIT)
        guard count > 0, let mounts else { return [] }

        var results: [VolumeInfo] = []
        for i in 0..<Int(count) {
            let fs = mounts[i]
            let mountPoint = String(cTuple: fs.f_mntonname)
            let device = String(cTuple: fs.f_mntfromname)
            let type = String(cTuple: fs.f_fstypename)

            // 只保留真实的本地卷，过滤掉 devfs / autofs 之类的伪文件系统
            guard device.hasPrefix("/dev/") else { continue }

            let blockSize = UInt64(fs.f_bsize)
            results.append(VolumeInfo(
                name: (mountPoint as NSString).lastPathComponent.isEmpty ? mountPoint : (mountPoint as NSString).lastPathComponent,
                mountPoint: mountPoint,
                fileSystem: type.uppercased(),
                device: device,
                capacity: UInt64(fs.f_blocks) * blockSize,
                available: UInt64(fs.f_bavail) * blockSize,
                isBoot: mountPoint == "/",
                isReadOnly: (fs.f_flags & UInt32(MNT_RDONLY)) != 0
            ))
        }
        return results
    }
}
