import SwiftUI

struct NetworkView: View {
    @Environment(SystemMonitor.self) private var monitor
    var interface: NetworkInterfaceSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text(interface.displayName).font(.title2.weight(.semibold))
                Text("\(interface.name)  ·  \(interface.kind)").font(.callout).foregroundStyle(.secondary)
            }

            GraphCard(
                title: L("吞吐量"),
                currentValue: "↓\(Fmt.rate(interface.receiveRate))   ↑\(Fmt.rate(interface.sendRate))",
                series: [
                    GraphSeries(values: monitor.networkReceiveHistory[interface.id]?.values ?? [], color: .teal),
                    GraphSeries(values: monitor.networkSendHistory[interface.id]?.values ?? [], color: .indigo)
                ],
                maxValue: nil,
                maxLabel: Fmt.rate(peakRate)
            )
            HStack(spacing: 16) {
                legend(.teal, L("接收"))
                legend(.indigo, L("发送"))
            }

            MetricGrid(metrics: [
                Metric(L("接收"), Fmt.rate(interface.receiveRate), emphasized: true),
                Metric(L("发送"), Fmt.rate(interface.sendRate), emphasized: true),
                Metric(L("接收（Mbps）"), Fmt.mbps(interface.receiveRate)),
                Metric(L("发送（Mbps）"), Fmt.mbps(interface.sendRate)),
                Metric(L("累计接收"), Fmt.bytes(interface.bytesIn)),
                Metric(L("累计发送"), Fmt.bytes(interface.bytesOut)),
                Metric(L("接收包数"), "\(interface.packetsIn)"),
                Metric(L("发送包数"), "\(interface.packetsOut)")
            ], columns: 4)

            Divider()
            SpecList(specs: [
                Metric(L("接口"), "\(interface.displayName)  ·  \(interface.name)"),
                Metric(L("类型"), interface.kind),
                Metric(L("状态"), interface.isUp ? L("已连接") : L("未连接")),
                Metric(L("链路速度"), interface.linkSpeed > 0
                       ? String(format: "%.0f Mbps", Double(interface.linkSpeed) / 1_000_000)
                       : "—"),
                Metric(L("MAC 地址"), interface.macAddress ?? "—"),
                Metric("IPv4", interface.ipv4.isEmpty ? "—" : interface.ipv4.joined(separator: ", ")),
                Metric("IPv6", interface.ipv6.isEmpty ? "—" : interface.ipv6.joined(separator: ", ")),
                Metric(L("错误（收/发）"), "\(interface.errorsIn) / \(interface.errorsOut)")
            ])

            Text(L("说明：macOS 未公开按进程的网络流量接口（系统自带的 nettop 走的是私有框架且需 root），因此进程页不提供「网络」列。"))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var peakRate: Double {
        let rx = monitor.networkReceiveHistory[interface.id]?.peak ?? 0
        let tx = monitor.networkSendHistory[interface.id]?.peak ?? 0
        return max(max(rx, tx), 1024)
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 3)
            Text(text).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
