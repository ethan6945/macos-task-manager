import SwiftUI

enum PerformanceTab: Hashable {
    case cpu, memory, gpu
    case disk(String)
    case network(String)
}

/// 性能页容器。左边一列缩略图（Win11 的做法），右边是选中项的大图与规格。
struct PerformanceView: View {
    @Environment(SystemMonitor.self) private var monitor
    @Binding var tab: PerformanceTab

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 200)
            Divider()
            ScrollView {
                detail
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - 左侧缩略列表

    private var sidebar: some View {
        ScrollView {
            VStack(spacing: 6) {
                item(.cpu, title: "CPU",
                     subtitle: "\(Fmt.percent(monitor.cpu.total, decimals: 0))",
                     values: monitor.cpuHistory.values, color: .blue, maxValue: 100)

                item(.memory, title: L("内存"),
                     subtitle: "\(Fmt.bytes(monitor.memory.used))/\(Fmt.bytes(monitor.memory.total))",
                     values: monitor.memoryHistory.values, color: .purple, maxValue: 100)

                if monitor.gpu.available {
                    item(.gpu, title: "GPU",
                         subtitle: Fmt.percent(monitor.gpu.utilization, decimals: 0),
                         values: monitor.gpuHistory.values, color: .green, maxValue: 100)
                }

                ForEach(monitor.disks) { disk in
                    item(.disk(disk.id), title: disk.name,
                         subtitle: Fmt.percent(disk.activeTime, decimals: 0),
                         values: monitor.diskHistory[disk.id]?.values ?? [],
                         color: .orange, maxValue: 100)
                }

                ForEach(visibleInterfaces) { interface in
                    item(.network(interface.id), title: interface.displayName,
                         subtitle: "↓\(Fmt.rate(interface.receiveRate))",
                         values: monitor.networkReceiveHistory[interface.id]?.values ?? [],
                         color: .teal, maxValue: nil)
                }
            }
            .padding(8)
        }
    }

    private func item(_ target: PerformanceTab, title: String, subtitle: String,
                      values: [Double], color: Color, maxValue: Double?) -> some View {
        Button {
            tab = target
        } label: {
            HStack(spacing: 8) {
                Graph(series: [GraphSeries(values: values, color: color)],
                      maxValue: maxValue, gridColumns: 6, gridRows: 3, pointCapacity: 60)
                    .frame(width: 56, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.callout).lineLimit(1)
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(tab == target ? Color.accentColor.opacity(0.18) : .clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var visibleInterfaces: [NetworkInterfaceSnapshot] {
        monitor.networks.filter { !$0.isLoopback && !$0.isVirtual && $0.hasTraffic }
    }

    // MARK: - 右侧详情

    @ViewBuilder
    private var detail: some View {
        switch tab {
        case .cpu:
            CPUView()
        case .memory:
            MemoryView()
        case .gpu:
            GPUView()
        case .disk(let id):
            if let disk = monitor.disks.first(where: { $0.id == id }) {
                DiskView(disk: disk)
            } else {
                ContentUnavailableView(L("磁盘已移除"), systemImage: "externaldrive.badge.xmark")
            }
        case .network(let id):
            if let interface = monitor.networks.first(where: { $0.id == id }) {
                NetworkView(interface: interface)
            } else {
                ContentUnavailableView(L("接口已移除"), systemImage: "network.slash")
            }
        }
    }
}
