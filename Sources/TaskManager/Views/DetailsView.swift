import AppKit
import SwiftUI

/// 对应 Win11 的「详细信息」页：更硬核的进程表 + 优先级设置 + 命令行。
struct DetailsView: View {
    @Environment(SystemMonitor.self) private var monitor
    private var localizer: Localizer { .shared }
    @Binding var focusedPID: pid_t?

    @State private var search = ""
    @State private var selection: Set<pid_t> = []
    @State private var sort = ProcessSort(key: .pid, ascending: true)
    @State private var commandLine: String = ""
    @State private var failure: String?
    @State private var groups = GroupedProcesses()

    /// Windows 的优先级档位映射到 macOS 的 nice 值。
    private static let priorities: [(String, Int32)] = [
        (L("实时"), -20), (L("高"), -10), (L("高于正常"), -5),
        (L("正常"), 0), (L("低于正常"), 5), (L("低"), 10), (L("最低"), 19)
    ]

    private static var columns: [ProcessColumn] { [
        ProcessColumn(key: .pid, title: "PID", width: 58, minWidth: 48, alignment: .right, text: \.pidText),
        ProcessColumn(key: .name, title: L("名称"), width: 200, minWidth: 120,
                      showsIcon: true, text: \.name, dimmed: { _ in false }),
        ProcessColumn(key: .status, title: L("状态"), width: 62, minWidth: 50, text: { $0.status.displayName }),
        ProcessColumn(key: .user, title: L("用户"), width: 90, minWidth: 60, text: \.user),
        ProcessColumn(key: .cpu, title: "CPU", width: 62, minWidth: 50, alignment: .right,
                      text: \.cpuText, dimmed: { $0.cpuPercent < 20 }),
        ProcessColumn(key: .memory, title: L("内存"), width: 80, minWidth: 64, alignment: .right, text: \.memoryText),
        ProcessColumn(key: .cpuTime, title: L("CPU 时间"), width: 84, minWidth: 64, alignment: .right,
                      text: { Fmt.duration($0.cpuTime) }),
        ProcessColumn(key: .threads, title: L("线程"), width: 52, minWidth: 42, alignment: .right, text: \.threadsText),
        ProcessColumn(key: .ports, title: L("端口"), width: 58, minWidth: 44, alignment: .right, text: \.portsText),
        ProcessColumn(key: .architecture, title: L("架构"), width: 64, minWidth: 52, text: \.architecture),
        ProcessColumn(key: .ppid, title: L("父进程"), width: 62, minWidth: 50, alignment: .right,
                      text: { String($0.ppid) }),
        ProcessColumn(key: .nice, title: L("优先级"), width: 58, minWidth: 46, alignment: .right,
                      text: { String($0.nice) }),
        ProcessColumn(key: .pageIns, title: L("页面调入"), width: 74, minWidth: 56, alignment: .right,
                      text: { $0.hasMetrics ? String($0.pageIns) : "—" }),
        ProcessColumn(key: .contextSwitches, title: L("上下文切换"), width: 90, minWidth: 66, alignment: .right,
                      text: { $0.hasMetrics ? String($0.contextSwitches) : "—" }),
        ProcessColumn(key: .startTime, title: L("启动时间"), width: 150, minWidth: 120,
                      text: { Fmt.time($0.startTime) }),
        ProcessColumn(key: .path, title: L("路径"), width: 340, minWidth: 140,
                      text: { $0.path ?? "—" })
    ] }

    var body: some View {
        // 不用 VSplitView：它不认 idealHeight，默认会把一半高度让给检查器。
        // 没选中进程时干脆不显示检查器，表格吃满整页。
        VStack(spacing: 0) {
            ProcessTable(
                groups: groups,
                key: tableKey,
                columns: Self.columns,
                grouped: false,
                selection: $selection,
                sort: $sort,
                menuBuilder: { buildMenu(menuActions(for: $0)) }
            )

            if selectedRow != nil {
                Divider()
                inspector.frame(height: 180)
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: L("搜索进程"))
        .alert(L("操作未完成"), isPresented: .init(
            get: { failure != nil }, set: { if !$0 { failure = nil } }
        )) {
            Button(L("好")) { failure = nil }
        } message: {
            Text(failure ?? "")
        }
        .onAppear {
            if let pid = focusedPID { selection = [pid] }
            refreshCommandLine()
        }
        .onChange(of: focusedPID) { _, pid in
            if let pid { selection = [pid] }
        }
        .onChange(of: selection) { _, _ in refreshCommandLine() }
        .onChange(of: tableKey, initial: true) { _, _ in
            groups = ProcessRows.build(from: monitor.processes, search: search,
                                       sort: sort, grouped: false)
        }
    }

    private var tableKey: ProcessTableKey {
        ProcessTableKey(stamp: monitor.lastUpdate, sort: sort, search: search,
                        grouped: false, language: localizer.language)
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let row = selectedRow {
                    Text(row.name).font(.headline)
                    SpecList(specs: [
                        Metric(L("完整路径"), row.path ?? "—"),
                        Metric("Bundle ID", row.bundleIdentifier ?? "—"),
                        Metric(L("父进程"), "\(row.ppid)"),
                        Metric(L("用户"), L("%@（uid %d）", row.user, Int(row.uid))),
                        Metric(L("启动于"), Fmt.time(row.startTime)),
                        Metric(L("累计 CPU 时间"), Fmt.duration(row.cpuTime)),
                        Metric(L("磁盘读/写"),
                               row.diskRead == nil
                               ? L("—（只能读取与你同用户的进程）")
                               : "\(Fmt.bytes(row.diskRead ?? 0)) / \(Fmt.bytes(row.diskWrite ?? 0))")
                    ])
                    Text(L("命令行")).font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                    Text(commandLine.isEmpty ? L("—（只能读取与你同用户的进程的命令行）") : commandLine)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(L("选择一个进程查看详细信息"))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                }
            }
            .padding(12)
        }
    }

    private func menuActions(for pids: Set<pid_t>) -> [MenuAction] {
        guard let pid = pids.first,
              let row = monitor.processes.first(where: { $0.pid == pid }) else { return [] }

        var actions: [MenuAction] = [
            MenuAction(title: L("结束进程")) { terminate(row, force: false) },
            MenuAction(title: L("强制结束")) { terminate(row, force: true) },
            .separator
        ]
        for (name, nice) in Self.priorities {
            actions.append(MenuAction(title: L("优先级：%@（nice %d）", L(name), nice)) { setPriority(row, nice) })
        }
        actions.append(.separator)
        if let path = row.path {
            actions.append(MenuAction(title: L("在访达中显示")) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            })
        }
        actions.append(MenuAction(title: L("拷贝命令行")) {
            let text = Sysctl.commandLine(row.pid)?.joined(separator: " ") ?? row.path ?? row.name
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        })
        return actions
    }

    private var selectedRow: ProcessRow? {
        guard let pid = selection.first else { return nil }
        return monitor.processes.first { $0.pid == pid }
    }

    private func refreshCommandLine() {
        guard let pid = selection.first else { commandLine = ""; return }
        commandLine = Sysctl.commandLine(pid)?.joined(separator: " ") ?? ""
    }

    private func terminate(_ row: ProcessRow, force: Bool) {
        do {
            try ProcessControl.terminate(row.pid, force: force)
            monitor.refreshNow()
        } catch {
            failure = L("%@（%d）：%@", row.name, row.pid, error.localizedDescription)
        }
    }

    private func setPriority(_ row: ProcessRow, _ nice: Int32) {
        do {
            try ProcessControl.setNice(row.pid, to: nice)
            monitor.refreshNow()
        } catch {
            failure = L("%@（%d）：%@", row.name, row.pid, error.localizedDescription)
        }
    }
}
