import AppKit
import SwiftUI

/// 「网络端口」页：本机所有正在监听的 TCP 端口，以及占用它们的进程。
///
/// 主要用途是找到后台跑着的本地服务（`http://127.0.0.1:8770` 这种）并一键打开。
/// 只读 —— 不提供「杀掉占用端口的进程」，和「服务」「启动项」两页的取向一致。
struct PortsView: View {
    @Environment(SystemMonitor.self) private var monitor
    var onReveal: (pid_t) -> Void

    @State private var search = ""
    @State private var selection: Set<ListeningPort.ID> = []
    @State private var sortOrder = [KeyPathComparator(\PortRow.port, order: .forward)]
    /// 默认只看能用浏览器打开的，也就是本页的主要用途
    @State private var localOnly = true
    /// 探测结果按行 id 存。只在用户点「检测」时才有值。
    @State private var probes: [ListeningPort.ID: WebProbeResult] = [:]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Toggle(L("只看本机可访问的服务"), isOn: $localOnly).toggleStyle(.checkbox)
                Spacer()
                Text(L("监听中 %d 个端口", rows.count))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Button {
                    monitor.refreshPorts()
                } label: {
                    Label(L("刷新"), systemImage: "arrow.clockwise")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            table

            Divider()
            Text(L("端口列表来自 netstat，只列出正在监听的 TCP 端口（不含 UDP，也不含向外建立的连接）。「检测」会向 127.0.0.1 发一次 HTTP 请求，只在你点击时才发。本页不提供结束进程的操作。"))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        .searchable(text: $search, placement: .toolbar, prompt: L("搜索端口或进程"))
    }

    private var table: some View {
        Table(of: PortRow.self, selection: $selection, sortOrder: $sortOrder) {
            TableColumn(L("名称"), value: \.name) { row in
                HStack(spacing: 6) {
                    ProcessIcon(bundlePath: row.bundlePath, executablePath: row.path)
                    Text(row.name).lineLimit(1)
                }
            }
            .width(min: 140, ideal: 180)

            TableColumn(L("端口号"), value: \.port) { row in
                Text(verbatim: "\(row.port)")
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 56, ideal: 70)

            TableColumn(L("地址"), value: \.entry.address) { row in
                Text(row.entry.endpoint).lineLimit(1).foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 140)

            TableColumn(L("范围"), value: \.scopeSortKey) { row in
                Text(row.entry.scopeText).foregroundStyle(.secondary)
            }
            .width(min: 88, ideal: 105)

            TableColumn(L("打开")) { row in
                if let url = row.entry.url {
                    Button(L("打开")) { NSWorkspace.shared.open(url) }
                        .buttonStyle(.link)
                        .help(url.absoluteString)
                } else {
                    Text(verbatim: "—").foregroundStyle(.tertiary)
                }
            }
            .width(min: 50, ideal: 56)

            TableColumn(L("Web 检测")) { row in
                probeCell(row)
            }
            .width(min: 120, ideal: 150)

            TableColumn("PID", value: \.entry.pid) { row in
                Text(verbatim: "\(row.entry.pid)")
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 56, ideal: 65)

            TableColumn(L("用户"), value: \.user) { row in
                Text(row.user).foregroundStyle(.secondary).lineLimit(1)
            }
            .width(min: 68, ideal: 85)
        } rows: {
            ForEach(rows) { TableRow($0) }
        }
        .contextMenu(forSelectionType: PortRow.ID.self) { ids in
            if let id = ids.first, let row = rows.first(where: { $0.id == id }) {
                menu(for: row)
            }
        }
        .tableStyle(.inset)
    }

    @ViewBuilder
    private func probeCell(_ row: PortRow) -> some View {
        switch probes[row.id] {
        case .none:
            Button(L("检测")) { probe(row) }
                .buttonStyle(.link)
                .disabled(row.entry.url == nil)
        case .probing:
            Text(WebProbeResult.probing.text).foregroundStyle(.secondary)
        case let .some(result):
            HStack(spacing: 5) {
                Circle()
                    .fill(result.isWeb ? Color.green : Color.secondary)
                    .frame(width: 7, height: 7)
                Text(result.text).lineLimit(1).help(result.text)
            }
        }
    }

    @ViewBuilder
    private func menu(for row: PortRow) -> some View {
        if let url = row.entry.url {
            Button(L("在浏览器中打开")) { NSWorkspace.shared.open(url) }
            Button(L("检测是否为 Web 服务")) { probe(row) }
            Button(L("拷贝地址")) { copy(url.absoluteString) }
        }
        Button(L("拷贝端口")) { copy("\(row.port)") }
        Divider()
        Button(L("转到详细信息")) { onReveal(row.entry.pid) }
        if let path = row.path {
            Button(L("在访达中显示")) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
        }
    }

    // MARK: - 行数据

    /// 把 netstat 的端口和进程表 join 起来：netstat 的进程名会被截断，
    /// 而且没有图标、路径和用户，这些都得从 `ProcessRow` 拿。
    private var rows: [PortRow] {
        let processes = Dictionary(monitor.processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        let keyword = search.trimmingCharacters(in: .whitespaces).lowercased()

        var list = monitor.listeningPorts.compactMap { entry -> PortRow? in
            if localOnly && !entry.isLocallyReachable { return nil }
            let process = processes[entry.pid]
            let row = PortRow(
                entry: entry,
                name: process?.name ?? entry.processName,
                path: process?.path,
                bundlePath: process?.bundlePath,
                user: process?.user ?? "—"
            )
            guard !keyword.isEmpty else { return row }
            return row.matches(keyword) ? row : nil
        }
        list.sort(using: sortOrder)
        return list
    }

    // MARK: - 操作

    private func probe(_ row: PortRow) {
        guard row.entry.url != nil, probes[row.id] != .probing else { return }
        probes[row.id] = .probing
        Task {
            let result = await WebProbe.probe(port: row.port)
            probes[row.id] = result
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// 表格一行：端口 + 从进程表补齐的展示信息。
struct PortRow: Identifiable {
    var id: ListeningPort.ID { entry.id }

    var entry: ListeningPort
    var name: String
    var path: String?
    var bundlePath: String?
    var user: String

    var port: Int { entry.port }
    /// 排序用：让「仅本机」排在「所有网络接口」前面
    var scopeSortKey: Int { entry.isLoopback ? 0 : (entry.isAnyAddress ? 1 : 2) }

    func matches(_ keyword: String) -> Bool {
        "\(entry.port)".contains(keyword)
            || name.lowercased().contains(keyword)
            || entry.address.contains(keyword)
            || "\(entry.pid)".contains(keyword)
    }
}
