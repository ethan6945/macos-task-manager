import AppKit
import SwiftUI

/// 对应 Win11 的「服务」页。macOS 上的服务就是 launchd 作业。
struct ServicesView: View {
    @Environment(SystemMonitor.self) private var monitor
    var onReveal: (pid_t) -> Void

    @State private var search = ""
    @State private var selection: Set<String> = []
    @State private var sortOrder = [KeyPathComparator(\ServiceEntry.label, order: .forward)]
    @State private var hideApple = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Toggle(L("隐藏 com.apple.* 系统作业"), isOn: $hideApple).toggleStyle(.checkbox)
                Spacer()
                Text(L("运行中 %d / 共 %d", running, monitor.services.count))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Button {
                    monitor.refreshSlowData()
                } label: {
                    Label(L("刷新"), systemImage: "arrow.clockwise")
                }
                .disabled(monitor.isLoadingSlowData)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            Table(of: ServiceEntry.self, selection: $selection, sortOrder: $sortOrder) {
                TableColumn(L("名称"), value: \.label) { entry in
                    Text(entry.label).lineLimit(1)
                }
                .width(min: 260, ideal: 420)

                TableColumn("PID", value: \.label) { entry in
                    Text(verbatim: entry.pid.map(String.init) ?? "—")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .foregroundStyle(entry.pid == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                }
                .width(min: 60, ideal: 70)

                TableColumn(L("状态"), value: \.lastExitStatus) { entry in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(entry.pid != nil ? Color.green : (entry.lastExitStatus == 0 ? Color.secondary : Color.orange))
                            .frame(width: 7, height: 7)
                        Text(entry.statusText)
                    }
                }
                .width(min: 110, ideal: 140)

                TableColumn(L("归属")) { entry in
                    Text(entry.isApple ? L("系统") : L("第三方"))
                        .foregroundStyle(.secondary)
                }
                .width(min: 60, ideal: 76)
            } rows: {
                ForEach(filtered) { TableRow($0) }
            }
            .contextMenu(forSelectionType: ServiceEntry.ID.self) { labels in
                if let label = labels.first, let entry = monitor.services.first(where: { $0.label == label }) {
                    if let pid = entry.pid {
                        Button(L("转到详细信息")) { onReveal(pid) }
                    }
                    Button(L("拷贝标识符")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.label, forType: .string)
                    }
                }
            }
            .tableStyle(.inset)

            Divider()
            Text(L("只列出当前用户域（gui/%d）的 launchd 作业。系统域（system/）需要管理员权限才能枚举，本程序不提权，也不提供启停按钮。", Int(getuid())))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        .searchable(text: $search, placement: .toolbar, prompt: L("搜索服务"))
        .onAppear {
            if monitor.services.isEmpty { monitor.refreshSlowData() }
        }
    }

    private var running: Int { monitor.services.count { $0.pid != nil } }

    private var filtered: [ServiceEntry] {
        let keyword = search.trimmingCharacters(in: .whitespaces).lowercased()
        var list = monitor.services
        if hideApple { list = list.filter { !$0.isApple } }
        if !keyword.isEmpty {
            list = list.filter { $0.label.lowercased().contains(keyword) }
        }
        return list.sorted(using: sortOrder)
    }
}
