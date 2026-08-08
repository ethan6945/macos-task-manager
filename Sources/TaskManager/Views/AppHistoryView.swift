import SwiftUI

/// 对应 Win11 的「应用历史记录」页。
///
/// macOS 没有系统级的长期资源记账，所以这里的数据是本程序自己累计的：
/// 每次采样时对每个进程的累计 CPU 时间做增量，按应用聚合后持久化。
struct AppHistoryView: View {
    @Environment(SystemMonitor.self) private var monitor

    @State private var search = ""
    @State private var sortOrder = [KeyPathComparator(\AppHistoryEntry.cpuSeconds, order: .reverse)]
    @State private var onlyApps = false
    @State private var confirmingReset = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Toggle(L("只看有界面的应用"), isOn: $onlyApps).toggleStyle(.checkbox)
                Spacer()
                Text(L("统计起始：%@", Fmt.time(monitor.history.since)))
                    .font(.caption).foregroundStyle(.secondary)
                Button(role: .destructive) {
                    confirmingReset = true
                } label: {
                    Label(L("删除使用历史记录"), systemImage: "trash")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            Table(of: AppHistoryEntry.self, sortOrder: $sortOrder) {
                TableColumn(L("名称"), value: \.name) { entry in
                    HStack(spacing: 6) {
                        ProcessIcon(bundlePath: entry.bundlePath, executablePath: entry.id)
                        Text(entry.name).lineLimit(1)
                    }
                }
                .width(min: 200, ideal: 300)

                TableColumn(L("CPU 时间"), value: \.cpuSeconds) { entry in
                    Text(Fmt.duration(entry.cpuSeconds))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 90, ideal: 110)

                TableColumn(L("峰值内存"), value: \.peakMemory) { entry in
                    Text(Fmt.bytes(entry.peakMemory))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 90, ideal: 110)

                TableColumn(L("磁盘读取"), value: \.diskRead) { entry in
                    Text(entry.diskRead == 0 ? "—" : Fmt.bytes(entry.diskRead))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .foregroundStyle(entry.diskRead == 0 ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                }
                .width(min: 90, ideal: 110)

                TableColumn(L("磁盘写入"), value: \.diskWrite) { entry in
                    Text(entry.diskWrite == 0 ? "—" : Fmt.bytes(entry.diskWrite))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .foregroundStyle(entry.diskWrite == 0 ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                }
                .width(min: 90, ideal: 110)

                TableColumn(L("最近出现"), value: \.lastSeen) { entry in
                    Text(Fmt.time(entry.lastSeen)).foregroundStyle(.secondary)
                }
                .width(min: 140, ideal: 160)
            } rows: {
                ForEach(filtered) { TableRow($0) }
            }
            .tableStyle(.inset)
            .monospacedDigit()

            Divider()
            Text(L("统计自本程序首次运行开始累计，保存在 ~/Library/Application Support/TaskManager/。磁盘读写只能读到与你同用户的进程；按进程的网络流量 macOS 未公开接口，故不提供。"))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        .searchable(text: $search, placement: .toolbar, prompt: L("搜索应用"))
        .confirmationDialog(L("删除所有使用历史记录？"), isPresented: $confirmingReset) {
            Button(L("删除"), role: .destructive) { monitor.history.reset() }
            Button(L("取消"), role: .cancel) { }
        } message: {
            Text(L("累计的 CPU 时间、峰值内存与磁盘读写都会清零，统计将从现在重新开始。"))
        }
    }

    private var filtered: [AppHistoryEntry] {
        let keyword = search.trimmingCharacters(in: .whitespaces).lowercased()
        var list = monitor.history.entries
        if onlyApps { list = list.filter(\.isApp) }
        if !keyword.isEmpty {
            list = list.filter { $0.name.lowercased().contains(keyword) || $0.id.lowercased().contains(keyword) }
        }
        return list.sorted(using: sortOrder)
    }
}
