import SwiftUI

/// 一条曲线。
struct GraphSeries: Identifiable {
    let id = UUID()
    var values: [Double]
    var color: Color
    var filled: Bool = true
    var lineWidth: CGFloat = 1.5
    var dashed: Bool = false
}

/// 用 `Canvas` 自绘的滚动折线/面积图。
///
/// 之所以不用 Swift Charts：性能页同屏会有十几张图（每个逻辑处理器一张）且每秒重绘，
/// Charts 在这个密度下明显掉帧；自绘也更容易做出网格背景。
struct Graph: View {
    var series: [GraphSeries]
    /// 纵轴上限。传 nil 表示按数据自动缩放。
    var maxValue: Double?
    var gridColumns: Int = 12
    var gridRows: Int = 5
    var showGrid: Bool = true
    var pointCapacity: Int = 120

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            if showGrid { drawGrid(context: context, in: bounds) }

            let ceiling = resolvedMax
            guard ceiling > 0 else { return }

            for line in series {
                let points = pointsFor(line.values, in: bounds, ceiling: ceiling)
                guard points.count >= 2 else { continue }

                if line.filled {
                    var area = Path()
                    area.move(to: CGPoint(x: points[0].x, y: bounds.maxY))
                    for point in points { area.addLine(to: point) }
                    area.addLine(to: CGPoint(x: points[points.count - 1].x, y: bounds.maxY))
                    area.closeSubpath()
                    context.fill(area, with: .linearGradient(
                        Gradient(colors: [line.color.opacity(0.45), line.color.opacity(0.06)]),
                        startPoint: CGPoint(x: 0, y: bounds.minY),
                        endPoint: CGPoint(x: 0, y: bounds.maxY)
                    ))
                }

                var stroke = Path()
                stroke.addLines(points)
                context.stroke(
                    stroke,
                    with: .color(line.color),
                    style: StrokeStyle(
                        lineWidth: line.lineWidth,
                        lineJoin: .round,
                        dash: line.dashed ? [3, 3] : []
                    )
                )
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    private var resolvedMax: Double {
        if let maxValue { return maxValue }
        let peak = series.flatMap(\.values).max() ?? 0
        guard peak > 0 else { return 1 }
        // 取一个好看的整数刻度，避免曲线随每一帧的峰值抖动
        let magnitude = pow(10, floor(log10(peak)))
        return ceil(peak / magnitude * 2) / 2 * magnitude
    }

    private func pointsFor(_ values: [Double], in bounds: CGRect, ceiling: Double) -> [CGPoint] {
        let padded = values.count >= pointCapacity
            ? Array(values.suffix(pointCapacity))
            : Array(repeating: 0, count: pointCapacity - values.count) + values
        guard padded.count > 1 else { return [] }

        let stepX = bounds.width / CGFloat(padded.count - 1)
        return padded.enumerated().map { index, value in
            let ratio = min(1, max(0, value / ceiling))
            return CGPoint(x: bounds.minX + CGFloat(index) * stepX,
                           y: bounds.maxY - CGFloat(ratio) * bounds.height)
        }
    }

    private func drawGrid(context: GraphicsContext, in bounds: CGRect) {
        var grid = Path()
        for column in 1..<max(2, gridColumns) {
            let x = bounds.minX + bounds.width * CGFloat(column) / CGFloat(gridColumns)
            grid.move(to: CGPoint(x: x, y: bounds.minY))
            grid.addLine(to: CGPoint(x: x, y: bounds.maxY))
        }
        for row in 1..<max(2, gridRows) {
            let y = bounds.minY + bounds.height * CGFloat(row) / CGFloat(gridRows)
            grid.move(to: CGPoint(x: bounds.minX, y: y))
            grid.addLine(to: CGPoint(x: bounds.maxX, y: y))
        }
        context.stroke(grid, with: .color(.primary.opacity(0.07)), lineWidth: 0.5)
    }
}

/// 带标题、当前值和纵轴刻度的图表卡片。
struct GraphCard<Footer: View>: View {
    var title: String
    var currentValue: String
    var series: [GraphSeries]
    var maxValue: Double?
    var maxLabel: String
    var minLabel: String = "0"
    var height: CGFloat = 200
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                Text(currentValue)
                    .font(.system(.title3, design: .rounded).weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(series.first?.color ?? .accentColor)
            }
            HStack(alignment: .top, spacing: 6) {
                Graph(series: series, maxValue: maxValue)
                    .frame(height: height)
                VStack {
                    Text(maxLabel)
                    Spacer()
                    Text(minLabel)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(height: height)
            }
            HStack {
                Text(L("60 秒前")).font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Text(L("现在")).font(.caption2).foregroundStyle(.tertiary)
            }
            footer()
        }
    }
}

extension GraphCard where Footer == EmptyView {
    init(title: String, currentValue: String, series: [GraphSeries],
         maxValue: Double?, maxLabel: String, minLabel: String = "0", height: CGFloat = 200) {
        self.init(title: title, currentValue: currentValue, series: series,
                  maxValue: maxValue, maxLabel: maxLabel, minLabel: minLabel,
                  height: height, footer: { EmptyView() })
    }
}
