import SwiftUI

struct GPUView: View {
    @Environment(SystemMonitor.self) private var monitor

    var body: some View {
        let gpu = monitor.gpu
        let info = monitor.gpuInfo

        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text("GPU").font(.title2.weight(.semibold))
                Text(info.name).font(.callout).foregroundStyle(.secondary)
            }

            if !gpu.available {
                ContentUnavailableView(
                    L("读不到 GPU 统计"),
                    systemImage: "cpu",
                    description: Text(L("IORegistry 里没有找到带 PerformanceStatistics 的 IOAccelerator 节点。"))
                )
            } else {
                GraphCard(
                    title: L("GPU 利用率"),
                    currentValue: Fmt.percent(gpu.utilization, decimals: 0),
                    series: [GraphSeries(values: monitor.gpuHistory.values, color: .green)],
                    maxValue: 100,
                    maxLabel: "100%"
                )

                // 对应 Win11 GPU 页的「GPU 引擎」分图：Apple GPU 是 TBDR 架构，
                // 渲染器（Renderer）与分块器（Tiler）就是它的两个主要引擎。
                Text(L("GPU 引擎")).font(.headline)
                HStack(spacing: 12) {
                    engine(L("渲染器 Renderer"), gpu.rendererUtilization,
                           monitor.gpuRendererHistory.values, .green)
                    engine(L("分块器 Tiler"), gpu.tilerUtilization,
                           monitor.gpuTilerHistory.values, .mint)
                }

                MetricGrid(metrics: [
                    Metric(L("利用率"), Fmt.percent(gpu.utilization, decimals: 0), emphasized: true),
                    Metric(L("已分配显存"), Fmt.bytes(gpu.allocatedMemory), emphasized: true),
                    Metric(L("使用中显存"), Fmt.bytes(gpu.inUseMemory), emphasized: true),
                    Metric(L("驱动占用"), Fmt.bytes(gpu.driverMemory), emphasized: true)
                ], columns: 4)
            }

            Divider()
            SpecList(specs: [
                Metric(L("名称"), info.name),
                Metric(L("GPU 核心"), info.coreCount.map { "\($0)" } ?? "—"),
                Metric(L("内存架构"), info.unifiedMemory ? L("统一内存（与 CPU 共享）") : L("独立显存")),
                Metric(L("建议工作集上限"), info.recommendedWorkingSet > 0 ? Fmt.bytes(info.recommendedWorkingSet) : "—"),
                Metric(L("单缓冲上限"), info.maxBufferLength > 0 ? Fmt.bytes(info.maxBufferLength) : "—"),
                Metric(L("IORegistry 节点"), info.registryName ?? "—")
            ])

            Text(L("说明：macOS 没有公开的按进程 GPU 用量接口，因此进程页不提供「GPU」列。"))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func engine(_ title: String, _ value: Double, _ values: [Double], _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(Fmt.percent(value, decimals: 0)).font(.caption).monospacedDigit()
            }
            Graph(series: [GraphSeries(values: values, color: color)],
                  maxValue: 100, gridColumns: 8, gridRows: 4)
                .frame(height: 90)
        }
        .frame(maxWidth: .infinity)
    }
}
