import AppKit
import SwiftUI

struct ProcessesView: View {
    @Environment(SystemMonitor.self) private var monitor
    private var localizer: Localizer { .shared }
    @Binding var focusedPID: pid_t?

    @State private var search = ""
    @State private var selection: Set<pid_t> = []
    @State private var sort = ProcessSort(key: .cpu, ascending: false)
    @AppStorage("groupProcessesByType") private var groupByType = true
    @State private var pendingTermination: TerminationRequest?
    @State private var failure: String?
    /// 每个采样周期只重算一次过滤/排序结果
    @State private var groups = GroupedProcesses()

    private struct TerminationRequest: Identifiable {
        var id: String { "\(pids.map(String.init).joined(separator: ","))-\(force)" }
        var pids: [pid_t]
        var names: [String]
        var force: Bool
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ProcessTable(
                groups: groups,
                key: tableKey,
                columns: Self.columns,
                grouped: groupByType,
                selection: $selection,
                sort: $sort,
                menuBuilder: { buildMenu(menuActions(for: $0)) }
            )
        }
        .searchable(text: $search, placement: .toolbar, prompt: L("搜索进程名或 PID"))
        .confirmationDialog(confirmTitle, isPresented: .init(
            get: { pendingTermination != nil },
            set: { if !$0 { pendingTermination = nil } }
        ), presenting: pendingTermination) { request in
            Button(request.force ? L("强制结束") : L("结束进程"), role: .destructive) {
                terminate(request)
            }
            Button(L("取消"), role: .cancel) { pendingTermination = nil }
        } message: { request in
            let names = request.names.joined(separator: L("、"))
            Text(request.force
                 ? L("将向 %@ 发送 SIGKILL。进程不会有机会保存数据。", names)
                 : L("将向 %@ 发送 SIGTERM。", names))
        }
        .alert(L("操作未完成"), isPresented: .init(
            get: { failure != nil }, set: { if !$0 { failure = nil } }
        )) {
            Button(L("好")) { failure = nil }
        } message: {
            Text(failure ?? "")
        }
        .onChange(of: focusedPID) { _, pid in
            if let pid { selection = [pid] }
        }
        .onChange(of: tableKey, initial: true) { _, _ in
            groups = ProcessRows.build(from: monitor.processes, search: search,
                                       sort: sort, grouped: groupByType)
        }
    }

    private var tableKey: ProcessTableKey {
        ProcessTableKey(stamp: monitor.lastUpdate, sort: sort, search: search,
                        grouped: groupByType, language: localizer.language)
    }

    // MARK: - 列定义

    static var columns: [ProcessColumn] { [
        ProcessColumn(key: .name, title: L("名称"), width: 260, minWidth: 140,
                      showsIcon: true, text: \.name, dimmed: { _ in false }),
        ProcessColumn(key: .cpu, title: "CPU", width: 66, minWidth: 52, alignment: .right,
                      text: \.cpuText, dimmed: { $0.cpuPercent < 20 }),
        ProcessColumn(key: .memory, title: L("内存"), width: 82, minWidth: 64, alignment: .right,
                      text: \.memoryText, dimmed: { $0.memory <= 1_073_741_824 }),
        ProcessColumn(key: .disk, title: L("磁盘"), width: 82, minWidth: 64, alignment: .right,
                      text: \.diskText, dimmed: { $0.diskReadRate + $0.diskWriteRate <= 1_048_576 }),
        ProcessColumn(key: .threads, title: L("线程"), width: 54, minWidth: 44, alignment: .right,
                      text: \.threadsText),
        ProcessColumn(key: .energy, title: L("能耗"), width: 58, minWidth: 46, alignment: .right,
                      text: \.energyText, dimmed: { $0.energy < 20 }),
        ProcessColumn(key: .pid, title: "PID", width: 60, minWidth: 48, alignment: .right,
                      text: \.pidText),
        ProcessColumn(key: .user, title: L("用户"), width: 96, minWidth: 60, text: \.user)
    ] }

    // MARK: - 顶部工具条

    private var toolbar: some View {
        HStack(spacing: 10) {
            Toggle(L("按类型分组"), isOn: $groupByType)
                .toggleStyle(.checkbox)

            Spacer()

            if monitor.metricsDegraded {
                Label(L("部分进程的指标暂不可用"), systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help(L("未提权的应用读不到其他用户进程的 CPU 与内存，本程序靠常驻的 top 子进程补齐；它尚未就绪。"))
            }

            Button {
                request(force: false)
            } label: {
                Label(L("结束进程"), systemImage: "xmark.octagon")
            }
            .disabled(selection.isEmpty)

            Button {
                request(force: true)
            } label: {
                Label(L("强制结束"), systemImage: "bolt.horizontal")
            }
            .disabled(selection.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - 右键菜单

    private func menuActions(for pids: Set<pid_t>) -> [MenuAction] {
        let rows = monitor.processes.filter { pids.contains($0.pid) }
        guard let first = rows.first else { return [] }

        var actions: [MenuAction] = []
        if rows.count > 1 {
            actions.append(MenuAction(title: L("结束选中的 %d 个进程", rows.count)) { request(force: false) })
            actions.append(MenuAction(title: L("强制结束选中的 %d 个进程", rows.count)) { request(force: true) })
        } else {
            actions.append(MenuAction(title: L("结束进程")) {
                pendingTermination = .init(pids: [first.pid], names: [first.name], force: false)
            })
            actions.append(MenuAction(title: L("强制结束")) {
                pendingTermination = .init(pids: [first.pid], names: [first.name], force: true)
            })
        }
        actions.append(.separator)
        if let path = first.path {
            actions.append(MenuAction(title: L("在访达中显示")) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            })
            actions.append(MenuAction(title: L("拷贝路径")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(path, forType: .string)
            })
        }
        actions.append(MenuAction(title: L("拷贝 PID")) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(rows.map { "\($0.pid)" }.joined(separator: " "), forType: .string)
        })
        return actions
    }

    private var confirmTitle: String {
        guard let pending = pendingTermination else { return "" }
        return pending.force ? L("强制结束这些进程？") : L("结束这些进程？")
    }

    // MARK: - 操作

    private func request(force: Bool) {
        let rows = monitor.processes.filter { selection.contains($0.pid) }
        guard !rows.isEmpty else { return }
        pendingTermination = .init(pids: rows.map(\.pid), names: rows.map(\.name), force: force)
    }

    private func terminate(_ request: TerminationRequest) {
        pendingTermination = nil
        var errors: [String] = []
        for (index, pid) in request.pids.enumerated() {
            do {
                try ProcessControl.terminate(pid, force: request.force)
            } catch {
                let name = index < request.names.count ? request.names[index] : "\(pid)"
                errors.append(L("%@（%d）：%@", name, pid, error.localizedDescription))
            }
        }
        if !errors.isEmpty { failure = errors.joined(separator: "\n") }
        selection.removeAll()
        monitor.refreshNow()
    }
}
