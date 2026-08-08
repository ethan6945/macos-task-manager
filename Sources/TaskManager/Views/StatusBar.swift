import SwiftUI

/// 常驻底部状态栏 —— 致敬原版 taskmgr 的 "Processes / CPU Usage / Physical Memory"。
struct StatusBar: View {
    @Environment(SystemMonitor.self) private var monitor

    var body: some View {
        HStack(spacing: 18) {
            item(L("进程"), "\(monitor.processCount)")
            item(L("线程"), "\(monitor.threadCount)")
            item("CPU", Fmt.percent(monitor.cpu.total, decimals: 1))
            item(L("内存"), Fmt.percent(monitor.memory.usedPercent, decimals: 1))
            if monitor.gpu.available {
                item("GPU", Fmt.percent(monitor.gpu.utilization, decimals: 0))
            }
            Spacer()
            if monitor.refreshRate == .paused {
                Label(L("已暂停"), systemImage: "pause.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if monitor.metricsDegraded {
                Label(L("指标受限"), systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help(L("top 子进程尚未就绪或不可用，其他用户的进程暂时读不到 CPU/内存。"))
            }
            Text(monitor.lastUpdate == .distantPast ? "—" : Fmt.dateTime.string(from: monitor.lastUpdate))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func item(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.caption).monospacedDigit()
        }
    }
}
