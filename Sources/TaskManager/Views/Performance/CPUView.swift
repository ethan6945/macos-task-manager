import SwiftUI

struct CPUView: View {
    @Environment(SystemMonitor.self) private var monitor
    @State private var showPerCore = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CPU").font(.title2.weight(.semibold))
                    Text(monitor.info.cpuBrand).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle(L("按逻辑处理器显示"), isOn: $showPerCore).toggleStyle(.switch)
            }

            if showPerCore {
                perCoreGrid
            } else {
                GraphCard(
                    title: L("利用率"),
                    currentValue: Fmt.percent(monitor.cpu.total),
                    series: [
                        GraphSeries(values: monitor.cpuHistory.values, color: .blue),
                        GraphSeries(values: monitor.cpuSystemHistory.values, color: .red,
                                    filled: false, lineWidth: 1)
                    ],
                    maxValue: 100,
                    maxLabel: "100%"
                )
                HStack(spacing: 16) {
                    legend(.blue, L("总利用率"))
                    legend(.red, L("系统（内核）"))
                }
            }

            MetricGrid(metrics: [
                Metric(L("利用率"), Fmt.percent(monitor.cpu.total), emphasized: true),
                Metric(L("进程"), "\(monitor.processCount)", emphasized: true),
                Metric(L("线程"), "\(monitor.threadCount)", emphasized: true),
                Metric(L("打开的文件"), "\(monitor.openFiles)", emphasized: true),
                Metric(L("用户态"), Fmt.percent(monitor.cpu.user + monitor.cpu.nice)),
                Metric(L("内核态"), Fmt.percent(monitor.cpu.system)),
                Metric(L("空闲"), Fmt.percent(monitor.cpu.idle)),
                Metric(L("正常运行时间"), Fmt.uptime(monitor.uptime))
            ], columns: 4)

            Divider()
            SpecList(specs: specs)
        }
    }

    private var perCoreGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 150, maximum: 260), spacing: 10)]
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Array(monitor.cpu.perCore.enumerated()), id: \.offset) { index, value in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(coreLabel(index)).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(Fmt.percent(value, decimals: 0)).font(.caption).monospacedDigit()
                    }
                    Graph(
                        series: [GraphSeries(values: monitor.perCoreHistory[safe: index]?.values ?? [],
                                             color: isPerformanceCore(index) ? .blue : .teal)],
                        maxValue: 100, gridColumns: 6, gridRows: 4, pointCapacity: 60
                    )
                    .frame(height: 66)
                }
            }
        }
    }

    /// Apple Silicon 上逻辑处理器 0..<P 为性能核，其余为能效核。
    private func isPerformanceCore(_ index: Int) -> Bool {
        guard monitor.info.efficiencyCores > 0 else { return true }
        return index < monitor.info.performanceCores
    }

    private func coreLabel(_ index: Int) -> String {
        guard monitor.info.efficiencyCores > 0 else { return "CPU \(index)" }
        return isPerformanceCore(index)
            ? L("性能核 %d", index)
            : L("能效核 %d", index - monitor.info.performanceCores)
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 3)
            Text(text).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var specs: [Metric] {
        let info = monitor.info
        var list: [Metric] = [
            Metric(L("型号"), info.cpuBrand),
            Metric(L("机型"), info.modelName.isEmpty ? info.machineModel : "\(info.modelName)（\(info.machineModel)）"),
            Metric(L("物理核心"), "\(info.physicalCores)"),
            Metric(L("逻辑处理器"), "\(info.logicalCores)")
        ]
        if info.efficiencyCores > 0 {
            list.append(Metric(L("核心构成"), L("%d 性能核 + %d 能效核", info.performanceCores, info.efficiencyCores)))
            list.append(Metric(L("性能核缓存"), "L1d \(Fmt.bytes(info.pCoreL1D))，L2 \(Fmt.bytes(info.pCoreL2))"))
            list.append(Metric(L("能效核缓存"), "L1d \(Fmt.bytes(info.eCoreL1D))，L2 \(Fmt.bytes(info.eCoreL2))"))
        } else {
            list.append(Metric(L("缓存"), "L1d \(Fmt.bytes(info.pCoreL1D))，L2 \(Fmt.bytes(info.pCoreL2))"))
        }
        if info.l3Cache > 0 {
            list.append(Metric(L("L3 缓存"), Fmt.bytes(info.l3Cache)))
        }
        list.append(Metric(L("缓存行"), L("%d 字节", Int(info.cacheLineSize))))
        list.append(Metric(
            L("基准速度"),
            info.cpuFrequency > 0
                ? String(format: "%.2f GHz", Double(info.cpuFrequency) / 1e9)
                : L("—（Apple Silicon 不暴露基准频率）")
        ))
        list.append(Metric(L("系统"), "\(info.osVersion)  ·  \(info.hostName)"))
        return list
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
