import SwiftUI

struct DiskView: View {
    @Environment(SystemMonitor.self) private var monitor
    var disk: DiskSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text(disk.name).font(.title2.weight(.semibold))
                Text(disk.bsdName.map { "/dev/\($0)  ·  \(Fmt.bytes(disk.size))" } ?? Fmt.bytes(disk.size))
                    .font(.callout).foregroundStyle(.secondary)
            }

            GraphCard(
                title: L("活动时间"),
                currentValue: Fmt.percent(disk.activeTime, decimals: 0),
                series: [GraphSeries(values: monitor.diskHistory[disk.id]?.values ?? [], color: .orange)],
                maxValue: 100,
                maxLabel: "100%",
                height: 130
            )

            GraphCard(
                title: L("传输速率"),
                currentValue: "↓\(Fmt.rate(disk.readRate))   ↑\(Fmt.rate(disk.writeRate))",
                series: [
                    GraphSeries(values: monitor.diskReadHistory[disk.id]?.values ?? [], color: .blue),
                    GraphSeries(values: monitor.diskWriteHistory[disk.id]?.values ?? [], color: .orange)
                ],
                maxValue: nil,
                maxLabel: Fmt.rate(peakRate),
                height: 130
            )
            HStack(spacing: 16) {
                legend(.blue, L("读取"))
                legend(.orange, L("写入"))
            }

            MetricGrid(metrics: [
                Metric(L("活动时间"), Fmt.percent(disk.activeTime, decimals: 0), emphasized: true),
                Metric(L("读取速度"), Fmt.rate(disk.readRate), emphasized: true),
                Metric(L("写入速度"), Fmt.rate(disk.writeRate), emphasized: true),
                Metric(L("平均响应时间"), String(format: "%.2f ms", disk.averageLatency), emphasized: true),
                Metric(L("读取 IOPS"), String(format: "%.0f/s", disk.readOPS)),
                Metric(L("写入 IOPS"), String(format: "%.0f/s", disk.writeOPS)),
                Metric(L("累计读取"), Fmt.bytes(disk.totalBytesRead)),
                Metric(L("累计写入"), Fmt.bytes(disk.totalBytesWritten))
            ], columns: 4)

            Divider()
            Text(L("卷")).font(.headline)
            ForEach(volumes) { volume in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(volume.mountPoint).font(.callout)
                        if volume.isBoot {
                            Text(L("系统盘"))
                                .font(.caption2)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 3).fill(Color.accentColor.opacity(0.18)))
                        }
                        if volume.isReadOnly {
                            Text(L("只读")).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Fmt.bytes(volume.used)) / \(Fmt.bytes(volume.capacity))")
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                    ProgressView(value: min(1, volume.usedPercent / 100))
                        .progressViewStyle(.linear)
                    Text("\(volume.fileSystem)  ·  \(volume.device)")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(.vertical, 3)
            }
        }
    }

    /// 卷列表按 BSD 名与当前磁盘对应（disk3s1 属于 disk3）。取不到就全都列出来。
    private var volumes: [VolumeInfo] {
        guard let bsd = disk.bsdName else { return monitor.volumes }
        let matched = monitor.volumes.filter { $0.device.contains(bsd) }
        return matched.isEmpty ? monitor.volumes : matched
    }

    private var peakRate: Double {
        let reads = monitor.diskReadHistory[disk.id]?.peak ?? 0
        let writes = monitor.diskWriteHistory[disk.id]?.peak ?? 0
        return max(reads, writes)
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 3)
            Text(text).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
