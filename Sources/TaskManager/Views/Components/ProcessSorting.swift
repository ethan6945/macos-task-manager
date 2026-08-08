import SwiftUI

/// 表格重算的缓存键：只有这些输入变了才需要重新过滤和排序。
struct ProcessTableKey: Equatable {
    var stamp: Date
    var sort: ProcessSort
    var search: String
    var grouped: Bool
    /// 切换语言后列标题与分组标题要重建
    var language: AppLanguage = .system
}

struct GroupedProcesses {
    var all: [ProcessRow] = []
    var apps: [ProcessRow] = []
    var background: [ProcessRow] = []
}

enum ProcessRows {

    /// 过滤 + 排序 + 分组，一个采样周期只做一次。
    static func build(from processes: [ProcessRow],
                      search: String,
                      sort: ProcessSort,
                      grouped: Bool) -> GroupedProcesses {
        var rows = processes
        let keyword = search.trimmingCharacters(in: .whitespaces).lowercased()
        if !keyword.isEmpty {
            rows = rows.filter {
                $0.name.lowercased().contains(keyword)
                || "\($0.pid)" == keyword
                || $0.user.lowercased().contains(keyword)
                || ($0.path?.lowercased().contains(keyword) ?? false)
            }
        }
        Self.sort(&rows, by: sort)

        var result = GroupedProcesses(all: rows)
        guard grouped else { return result }
        result.apps.reserveCapacity(64)
        result.background.reserveCapacity(rows.count)
        for row in rows {
            if row.isApp { result.apps.append(row) } else { result.background.append(row) }
        }
        return result
    }

    static func sort(_ rows: inout [ProcessRow], by sort: ProcessSort) {
        let ascending = sort.ascending

        func by<T: Comparable>(_ value: (ProcessRow) -> T) {
            rows.sort { ascending ? value($0) < value($1) : value($0) > value($1) }
        }
        func byText(_ value: (ProcessRow) -> String) {
            rows.sort {
                let result = value($0).caseInsensitiveCompare(value($1))
                return ascending ? result == .orderedAscending : result == .orderedDescending
            }
        }

        switch sort.key {
        case .name:            byText(\.name)
        case .user:            byText(\.user)
        case .path:            byText(\.pathText)
        case .architecture:    byText(\.architecture)
        case .cpu:             by(\.cpuPercent)
        case .cpuTime:         by(\.cpuTime)
        case .memory:          by(\.memory)
        case .disk:            by { $0.diskReadRate + $0.diskWriteRate }
        case .threads:         by(\.threads)
        case .ports:           by(\.ports)
        case .energy:          by(\.energy)
        case .pid:             by(\.pid)
        case .ppid:            by(\.ppid)
        case .nice:            by(\.nice)
        case .pageIns:         by(\.pageIns)
        case .contextSwitches: by(\.contextSwitches)
        case .startTime:       by(\.startTime)
        case .status:          by(\.status.rawValue)
        }
    }
}
