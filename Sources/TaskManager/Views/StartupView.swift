import AppKit
import SwiftUI

/// 对应 Win11 的「启动应用」页。macOS 的等价物是 launchd 的 Agents / Daemons。
struct StartupView: View {
    @Environment(SystemMonitor.self) private var monitor

    @State private var search = ""
    @State private var selection: Set<String> = []
    @State private var sortOrder = [KeyPathComparator(\StartupItem.label, order: .forward)]
    @State private var failure: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L("开机/登录时由 launchd 拉起的项目"))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(L("共 %d 项，其中 %d 项已加载", monitor.startupItems.count, loaded))
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

            Table(of: StartupItem.self, selection: $selection, sortOrder: $sortOrder) {
                TableColumn(L("名称"), value: \.label) { item in
                    HStack(spacing: 6) {
                        ProcessIcon(bundlePath: nil, executablePath: item.program)
                        Text(item.label).lineLimit(1)
                    }
                }
                .width(min: 230, ideal: 340)

                TableColumn(L("类型"), value: \.domain.rawValue) { item in
                    Text(item.domain.displayName).foregroundStyle(.secondary)
                }
                .width(min: 96, ideal: 116)

                TableColumn(L("状态")) { item in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(item.pid != nil ? Color.green : (item.isLoaded ? Color.secondary : Color.orange))
                            .frame(width: 7, height: 7)
                        Text(item.statusText)
                    }
                }
                .width(min: 80, ideal: 96)

                TableColumn(L("登录时启动")) { item in
                    Text(item.runAtLoad ? L("是") : L("否"))
                        .foregroundStyle(item.runAtLoad ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                }
                .width(min: 80, ideal: 92)

                TableColumn(L("保持运行")) { item in
                    Text(item.keepAlive ? L("是") : L("否"))
                        .foregroundStyle(item.keepAlive ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                }
                .width(min: 76, ideal: 88)

                TableColumn(L("程序")) { item in
                    Text(item.program ?? "—").lineLimit(1).foregroundStyle(.secondary)
                }
                .width(min: 180, ideal: 320)
            } rows: {
                ForEach(filtered) { TableRow($0) }
            }
            .contextMenu(forSelectionType: StartupItem.ID.self) { paths in
                if let path = paths.first, let item = monitor.startupItems.first(where: { $0.plistPath == path }) {
                    menu(for: item)
                }
            }
            .tableStyle(.inset)

            Divider()
            Text(L("停用仅对 ~/Library/LaunchAgents 下的条目开放（launchctl bootout）。系统域的代理与守护进程需要管理员权限，本程序不提权。"))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        .searchable(text: $search, placement: .toolbar, prompt: L("搜索启动项"))
        .alert(L("操作未完成"), isPresented: .init(
            get: { failure != nil }, set: { if !$0 { failure = nil } }
        )) {
            Button(L("好")) { failure = nil }
        } message: {
            Text(failure ?? "")
        }
        .onAppear {
            if monitor.startupItems.isEmpty { monitor.refreshSlowData() }
        }
    }

    @ViewBuilder
    private func menu(for item: StartupItem) -> some View {
        if item.domain.isUserWritable {
            Button(item.isLoaded ? L("停用（bootout）") : L("启用（bootstrap）")) {
                setEnabled(item, !item.isLoaded)
            }
            Divider()
        }
        Button(L("在访达中显示配置")) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.plistPath)])
        }
        if let program = item.program {
            Button(L("在访达中显示程序")) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: program)])
            }
        }
        Button(L("拷贝配置路径")) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.plistPath, forType: .string)
        }
    }

    private func setEnabled(_ item: StartupItem, _ enabled: Bool) {
        do {
            try StartupSampler.setEnabled(item, enabled: enabled)
            monitor.refreshSlowData()
        } catch {
            failure = error.localizedDescription
        }
    }

    private var loaded: Int { monitor.startupItems.count(where: \.isLoaded) }

    private var filtered: [StartupItem] {
        let keyword = search.trimmingCharacters(in: .whitespaces).lowercased()
        var list = monitor.startupItems
        if !keyword.isEmpty {
            list = list.filter {
                $0.label.lowercased().contains(keyword)
                || ($0.program?.lowercased().contains(keyword) ?? false)
            }
        }
        return list.sorted(using: sortOrder)
    }
}
