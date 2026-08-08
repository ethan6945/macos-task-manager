import Foundation
import Observation

struct AppHistoryEntry: Codable, Identifiable, Sendable {
    var id: String            // bundle id / 可执行文件路径 / 进程名
    var name: String
    var bundlePath: String?
    var isApp: Bool
    var cpuSeconds: Double = 0
    var peakMemory: UInt64 = 0
    var diskRead: UInt64 = 0
    var diskWrite: UInt64 = 0
    var lastSeen: Date = .now
}

/// 应用历史记录。
///
/// Win11 的这一页统计的是系统长期记账的数据，macOS 没有等价的系统记录，
/// 所以这里从本程序第一次运行开始自己累计，并持久化到「应用程序支持」目录。
@MainActor
@Observable
final class AppHistoryStore {

    private(set) var entries: [AppHistoryEntry] = []
    private(set) var since: Date = .now

    /// pid → 上次看到的累计 CPU 时间，用来算增量
    private var cpuBaseline: [pid_t: Double] = [:]
    private var diskBaseline: [pid_t: (read: UInt64, write: UInt64)] = [:]
    private var byID: [String: AppHistoryEntry] = [:]
    private var lastSaved = Date.distantPast

    private struct Payload: Codable {
        var since: Date
        var entries: [AppHistoryEntry]
    }

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TaskManager", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("app-history.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let payload = try? JSONDecoder().decode(Payload.self, from: data) {
            since = payload.since
            byID = Dictionary(payload.entries.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            entries = payload.entries
        }
    }

    func update(with processes: [ProcessRow]) {
        var seenPIDs = Set<pid_t>()

        for row in processes {
            seenPIDs.insert(row.pid)
            let key = row.bundleIdentifier ?? row.path ?? row.name

            // 首次见到一个进程时只记基线，不把它启动至今的历史算进来
            let previousCPU = cpuBaseline[row.pid]
            cpuBaseline[row.pid] = row.cpuTime
            let cpuDelta = previousCPU.map { max(0, row.cpuTime - $0) } ?? 0

            var diskDelta = (read: UInt64(0), write: UInt64(0))
            if let read = row.diskRead, let write = row.diskWrite {
                if let previous = diskBaseline[row.pid] {
                    diskDelta.read = read >= previous.read ? read - previous.read : 0
                    diskDelta.write = write >= previous.write ? write - previous.write : 0
                }
                diskBaseline[row.pid] = (read, write)
            }

            var entry = byID[key] ?? AppHistoryEntry(
                id: key, name: row.name, bundlePath: row.bundlePath, isApp: row.isApp
            )
            entry.name = row.name
            entry.isApp = entry.isApp || row.isApp
            entry.bundlePath = entry.bundlePath ?? row.bundlePath
            entry.cpuSeconds += cpuDelta
            entry.peakMemory = max(entry.peakMemory, row.memory)
            entry.diskRead += diskDelta.read
            entry.diskWrite += diskDelta.write
            entry.lastSeen = .now
            byID[key] = entry
        }

        cpuBaseline = cpuBaseline.filter { seenPIDs.contains($0.key) }
        diskBaseline = diskBaseline.filter { seenPIDs.contains($0.key) }
        entries = byID.values.sorted { $0.cpuSeconds > $1.cpuSeconds }

        if Date().timeIntervalSince(lastSaved) > 60 {
            save()
        }
    }

    func save() {
        lastSaved = Date()
        let payload = Payload(since: since, entries: entries)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    func reset() {
        byID.removeAll()
        entries.removeAll()
        cpuBaseline.removeAll()
        diskBaseline.removeAll()
        since = .now
        save()
    }
}
