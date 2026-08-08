import SwiftUI

struct MemoryView: View {
    @Environment(SystemMonitor.self) private var monitor

    var body: some View {
        let memory = monitor.memory

        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("内存")).font(.title2.weight(.semibold))
                    Text(memoryHeadline).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                pressureBadge
            }

            GraphCard(
                title: L("内存使用"),
                currentValue: "\(Fmt.bytes(memory.used)) / \(Fmt.bytes(memory.total))",
                series: [GraphSeries(values: monitor.memoryHistory.values, color: .purple)],
                maxValue: 100,
                maxLabel: Fmt.bytes(memory.total)
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(L("内存构成")).font(.headline)
                CompositionBar(segments: [
                    .init(label: "App", bytes: memory.app, color: .purple),
                    .init(label: L("联动"), bytes: memory.wired, color: .red),
                    .init(label: L("已压缩"), bytes: memory.compressed, color: .orange),
                    .init(label: L("已缓存文件"), bytes: memory.cachedFiles, color: .blue.opacity(0.55))
                ], total: memory.total)
            }

            MetricGrid(metrics: [
                Metric(L("使用中（含压缩）"), Fmt.bytes(memory.used), emphasized: true),
                Metric(L("可用"), Fmt.bytes(memory.free + memory.cachedFiles), emphasized: true),
                Metric(L("已缓存文件"), Fmt.bytes(memory.cachedFiles), emphasized: true),
                Metric(L("已压缩"), Fmt.bytes(memory.compressed), emphasized: true),
                Metric(L("App 内存"), Fmt.bytes(memory.app)),
                Metric(L("联动内存"), Fmt.bytes(memory.wired)),
                Metric(L("完全空闲"), Fmt.bytes(memory.free)),
                Metric(L("内存压力"), Fmt.percent(memory.pressure, decimals: 0))
            ], columns: 4)

            VStack(alignment: .leading, spacing: 6) {
                Text(L("内存压力")).font(.headline)
                Graph(
                    series: [GraphSeries(values: monitor.memoryPressureHistory.values, color: pressureColor)],
                    maxValue: 100, gridColumns: 12, gridRows: 4
                )
                .frame(height: 70)
            }

            MetricGrid(metrics: [
                Metric(L("交换区已用"), "\(Fmt.bytes(memory.swapUsed)) / \(Fmt.bytes(memory.swapTotal))"),
                Metric(L("页面调入"), "\(memory.pageIns)"),
                Metric(L("页面调出"), "\(memory.pageOuts)"),
                Metric(L("交换入/出"), "\(memory.swapIns) / \(memory.swapOuts)")
            ], columns: 4)

            Divider()
            SpecList(specs: [
                Metric(L("已安装内存"), Fmt.bytes(memory.total)),
                Metric(L("类型"), monitor.info.memoryType.isEmpty ? "—" : monitor.info.memoryType),
                Metric(L("制造商"), monitor.info.memoryVendor.isEmpty ? "—" : monitor.info.memoryVendor),
                Metric(L("插槽"), monitor.info.memorySlots.isEmpty ? "—" : L(monitor.info.memorySlots)),
                Metric(L("交换区"), memory.swapTotal == 0 ? L("未启用（系统按需创建）") : Fmt.bytes(memory.swapTotal))
            ])
        }
    }

    private var memoryHeadline: String {
        let info = monitor.info
        let type = info.memoryType.isEmpty ? "" : "\(info.memoryType) "
        return "\(Fmt.bytes(monitor.memory.total)) \(type)\(info.isAppleSilicon ? L("统一内存") : "")"
    }

    private var pressureColor: Color {
        switch monitor.memory.pressureLevel {
        case .normal: .green
        case .warning: .yellow
        case .critical: .red
        }
    }

    private var pressureBadge: some View {
        HStack(spacing: 6) {
            Circle().fill(pressureColor).frame(width: 9, height: 9)
            Text(L("内存压力：%@", monitor.memory.pressureLevel.displayName))
                .font(.callout)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(pressureColor.opacity(0.12)))
    }
}
