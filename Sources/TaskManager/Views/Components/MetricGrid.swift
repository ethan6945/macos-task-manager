import SwiftUI

struct Metric: Identifiable {
    let id = UUID()
    var label: String
    var value: String
    var emphasized: Bool = false

    init(_ label: String, _ value: String, emphasized: Bool = false) {
        self.label = label
        self.value = value
        self.emphasized = emphasized
    }
}

/// Win11 性能页右侧那种「标签 + 数值」的成对排布。
struct MetricGrid: View {
    var metrics: [Metric]
    var columns: Int = 2

    var body: some View {
        let rows = stride(from: 0, to: metrics.count, by: columns).map { start in
            Array(metrics[start..<min(start + columns, metrics.count)])
        }
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows.indices, id: \.self) { index in
                HStack(alignment: .top, spacing: 24) {
                    ForEach(rows[index]) { metric in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(metric.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(metric.value)
                                .font(metric.emphasized
                                      ? .system(.title3, design: .rounded).weight(.medium)
                                      : .system(.body, design: .rounded))
                                .monospacedDigit()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if rows[index].count < columns {
                        ForEach(0..<(columns - rows[index].count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }
}

/// 页面底部那一排静态规格（型号、核心数、缓存……）。
struct SpecList: View {
    var specs: [Metric]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(specs) { spec in
                HStack(alignment: .top) {
                    Text(spec.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 130, alignment: .leading)
                    Text(spec.value)
                        .font(.caption)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

/// 内存构成条：把总内存按用途分段着色（对应 Win11 内存页的 composition bar）。
struct CompositionBar: View {
    struct Segment: Identifiable {
        let id = UUID()
        var label: String
        var bytes: UInt64
        var color: Color
    }

    var segments: [Segment]
    var total: UInt64

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                HStack(spacing: 1) {
                    ForEach(segments) { segment in
                        Rectangle()
                            .fill(segment.color)
                            .frame(width: width(for: segment, in: geometry.size.width))
                    }
                    Rectangle().fill(Color.primary.opacity(0.06))
                }
            }
            .frame(height: 26)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.12)))

            HStack(spacing: 14) {
                ForEach(segments) { segment in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(segment.color)
                            .frame(width: 9, height: 9)
                        Text("\(segment.label) \(Fmt.bytes(segment.bytes))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func width(for segment: Segment, in totalWidth: CGFloat) -> CGFloat {
        guard total > 0 else { return 0 }
        return max(0, totalWidth * CGFloat(Double(segment.bytes) / Double(total)))
    }
}
