import AppKit
import Foundation

// 生成 App 图标。每个尺寸都按矢量重画，小图标才不会糊。
//
// 用法：
//   MakeIcon <输出目录> [方案]        写出 AppIcon.iconset
//   MakeIcon <输出目录> --previews    把所有方案各出一张 256px 预览图
//
// 方案见 IconStyle。

@main
enum MakeIcon {

    static func main() {
        var arguments = Array(CommandLine.arguments.dropFirst())
        let output = arguments.first.map { $0 } ?? FileManager.default.currentDirectoryPath + "/Resources"
        if !arguments.isEmpty { arguments.removeFirst() }

        let directory = URL(fileURLWithPath: output)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if arguments.contains("--previews") {
            for style in IconStyle.allCases {
                for pixels in [256, 32] {
                    guard let data = render(style: style, pixels: pixels) else { continue }
                    let name = pixels == 256 ? "preview-\(style.rawValue).png" : "preview-\(style.rawValue)-small.png"
                    try? data.write(to: directory.appendingPathComponent(name))
                }
            }
            print("预览已写出到 \(directory.path)")
            return
        }

        let style = arguments.first.flatMap(IconStyle.init(rawValue:)) ?? .chip
        let iconset = directory.appendingPathComponent("AppIcon.iconset")
        try? FileManager.default.removeItem(at: iconset)
        try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

        // macOS 要求的 10 张图
        let variants: [(name: String, pixels: Int)] = [
            ("icon_16x16", 16), ("icon_16x16@2x", 32),
            ("icon_32x32", 32), ("icon_32x32@2x", 64),
            ("icon_128x128", 128), ("icon_128x128@2x", 256),
            ("icon_256x256", 256), ("icon_256x256@2x", 512),
            ("icon_512x512", 512), ("icon_512x512@2x", 1024)
        ]
        for variant in variants {
            guard let data = render(style: style, pixels: variant.pixels) else {
                FileHandle.standardError.write("渲染 \(variant.name) 失败\n".data(using: .utf8)!)
                exit(1)
            }
            try? data.write(to: iconset.appendingPathComponent("\(variant.name).png"))
        }
        print("写出 \(iconset.path)（方案：\(style.rawValue)）")
    }

    // MARK: - 画布

    static func render(style: IconStyle, pixels: Int) -> Data? {
        guard let context = CGContext(
            data: nil, width: pixels, height: pixels,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let size = CGFloat(pixels)
        // macOS 图标习惯留一圈边距，图形本体约占 82%
        let inset = size * 0.09
        let body = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
        let radius = body.width * 0.2237          // 接近系统的连续圆角

        context.saveGState()
        addRoundedRect(context, rect: body, radius: radius)
        context.clip()

        let palette = style.palette
        drawGradient(context, in: body, from: palette.backgroundTop, to: palette.backgroundBottom)

        // 顶部高光，让图标有一点体积感。必须是渐变淡出，直接填矩形会留一道硬边。
        drawGradient(context,
                     in: CGRect(x: body.minX, y: body.minY + body.height * 0.42,
                                width: body.width, height: body.height * 0.58),
                     from: CGColor(gray: 1, alpha: 0.10),
                     to: CGColor(gray: 1, alpha: 0))

        style.draw(context, in: body, scale: size)
        context.restoreGState()

        // 极细的一圈描边，浅色背景下不至于糊成一团
        addRoundedRect(context, rect: body, radius: radius)
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.12))
        context.setLineWidth(max(0.5, size * 0.004))
        context.strokePath()

        guard let image = context.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = NSSize(width: pixels, height: pixels)
        return rep.representation(using: .png, properties: [:])
    }

    static func addRoundedRect(_ context: CGContext, rect: CGRect, radius: CGFloat) {
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    }

    static func drawGradient(_ context: CGContext, in rect: CGRect, from: CGColor, to: CGColor) {
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [from, to] as CFArray, locations: [0, 1]
        ) else { return }
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: rect.maxY),
            end: CGPoint(x: rect.minX, y: rect.minY),
            options: []
        )
    }
}

// MARK: - 方案

enum IconStyle: String, CaseIterable {
    /// 处理器芯片：圆角晶粒 + 四边引脚 + 中间活动脉冲
    case chip
    /// 均衡器式活动柱：一排高低不同的圆角柱，不带趋势方向
    case bars
    /// 仪表盘：圆弧刻度 + 指针
    case gauge
    /// 示波器波形：居中对称脉冲，不上不下
    case pulse

    var palette: (backgroundTop: CGColor, backgroundBottom: CGColor, accent: CGColor, accent2: CGColor) {
        switch self {
        case .chip:
            (CGColor(red: 0.216, green: 0.243, blue: 0.294, alpha: 1),
             CGColor(red: 0.086, green: 0.098, blue: 0.129, alpha: 1),
             CGColor(red: 0.212, green: 0.639, blue: 1.000, alpha: 1),     // systemBlue
             CGColor(red: 0.188, green: 0.820, blue: 0.345, alpha: 1))     // systemGreen
        case .bars:
            (CGColor(red: 0.200, green: 0.227, blue: 0.286, alpha: 1),
             CGColor(red: 0.075, green: 0.086, blue: 0.118, alpha: 1),
             CGColor(red: 0.212, green: 0.639, blue: 1.000, alpha: 1),
             CGColor(red: 0.749, green: 0.353, blue: 0.949, alpha: 1))     // systemPurple
        case .gauge:
            (CGColor(red: 0.231, green: 0.247, blue: 0.290, alpha: 1),
             CGColor(red: 0.078, green: 0.086, blue: 0.106, alpha: 1),
             CGColor(red: 0.188, green: 0.820, blue: 0.345, alpha: 1),
             CGColor(red: 1.000, green: 0.271, blue: 0.227, alpha: 1))     // systemRed
        case .pulse:
            (CGColor(red: 0.153, green: 0.216, blue: 0.271, alpha: 1),
             CGColor(red: 0.055, green: 0.086, blue: 0.118, alpha: 1),
             CGColor(red: 0.251, green: 0.847, blue: 0.847, alpha: 1),     // 青
             CGColor(red: 0.212, green: 0.639, blue: 1.000, alpha: 1))
    }
    }

    func draw(_ context: CGContext, in body: CGRect, scale: CGFloat) {
        switch self {
        case .chip: drawChip(context, in: body, scale: scale)
        case .bars: drawBars(context, in: body, scale: scale)
        case .gauge: drawGauge(context, in: body, scale: scale)
        case .pulse: drawPulse(context, in: body, scale: scale)
        }
    }

    // MARK: 芯片

    private func drawChip(_ context: CGContext, in body: CGRect, scale: CGFloat) {
        let colors = palette
        let isTiny = scale <= 32
        let die = body.insetBy(dx: body.width * (isTiny ? 0.22 : 0.26),
                               dy: body.height * (isTiny ? 0.22 : 0.26))
        let pinLength = body.width * (isTiny ? 0.07 : 0.075)
        let pinWidth = max(1, body.width * (isTiny ? 0.055 : 0.045))

        // 引脚：每边 3 根（小尺寸 2 根）
        context.setFillColor(CGColor(gray: 1, alpha: 0.42))
        let pinCount = isTiny ? 2 : 3
        for index in 0..<pinCount {
            let t = (CGFloat(index) + 1) / CGFloat(pinCount + 1)
            let x = die.minX + die.width * t
            let y = die.minY + die.height * t
            context.fill(CGRect(x: x - pinWidth / 2, y: die.maxY, width: pinWidth, height: pinLength))
            context.fill(CGRect(x: x - pinWidth / 2, y: die.minY - pinLength, width: pinWidth, height: pinLength))
            context.fill(CGRect(x: die.maxX, y: y - pinWidth / 2, width: pinLength, height: pinWidth))
            context.fill(CGRect(x: die.minX - pinLength, y: y - pinWidth / 2, width: pinLength, height: pinWidth))
        }

        // 晶粒
        let dieRadius = die.width * 0.16
        context.saveGState()
        MakeIcon.addRoundedRect(context, rect: die, radius: dieRadius)
        context.clip()
        MakeIcon.drawGradient(context, in: die,
                              from: CGColor(gray: 1, alpha: 0.16),
                              to: CGColor(gray: 1, alpha: 0.05))
        context.restoreGState()

        MakeIcon.addRoundedRect(context, rect: die, radius: dieRadius)
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.55))
        context.setLineWidth(max(1, scale * 0.022))
        context.strokePath()

        // 晶粒里的活动脉冲：起落对称，不做上升趋势
        let plot = die.insetBy(dx: die.width * 0.16, dy: die.height * 0.3)
        let samples: [CGFloat] = isTiny
            ? [0.5, 0.5, 0.05, 0.95, 0.35, 0.5]
            : [0.5, 0.5, 0.42, 0.62, 0.5, 0.05, 0.95, 0.30, 0.55, 0.5, 0.5]
        var points: [CGPoint] = []
        for (index, value) in samples.enumerated() {
            let x = plot.minX + plot.width * CGFloat(index) / CGFloat(samples.count - 1)
            points.append(CGPoint(x: x, y: plot.minY + plot.height * value))
        }
        let line = CGMutablePath()
        line.addLines(between: points)
        context.addPath(line)
        context.setStrokeColor(colors.accent2)
        context.setLineWidth(max(1, scale * 0.030))
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.strokePath()
    }

    // MARK: 活动柱

    private func drawBars(_ context: CGContext, in body: CGRect, scale: CGFloat) {
        let colors = palette
        let isTiny = scale <= 32
        let plot = body.insetBy(dx: body.width * 0.20, dy: body.height * 0.24)
        let heights: [CGFloat] = isTiny ? [0.45, 1.0, 0.62] : [0.38, 0.72, 1.0, 0.55, 0.84]
        let gap = plot.width * (isTiny ? 0.16 : 0.09)
        let barWidth = (plot.width - gap * CGFloat(heights.count - 1)) / CGFloat(heights.count)
        let radius = min(barWidth / 2, plot.height * 0.06)

        for (index, height) in heights.enumerated() {
            let x = plot.minX + (barWidth + gap) * CGFloat(index)
            // 底部留一截「未填充」的槽，读起来像仪表而不是柱状图
            let track = CGRect(x: x, y: plot.minY, width: barWidth, height: plot.height)
            MakeIcon.addRoundedRect(context, rect: track, radius: radius)
            context.setFillColor(CGColor(gray: 1, alpha: 0.10))
            context.fillPath()

            let bar = CGRect(x: x, y: plot.minY, width: barWidth, height: plot.height * height)
            context.saveGState()
            MakeIcon.addRoundedRect(context, rect: bar, radius: radius)
            context.clip()
            MakeIcon.drawGradient(context, in: bar, from: colors.accent2, to: colors.accent)
            context.restoreGState()
        }
    }

    // MARK: 仪表盘

    private func drawGauge(_ context: CGContext, in body: CGRect, scale: CGFloat) {
        let colors = palette
        let isTiny = scale <= 32
        let center = CGPoint(x: body.midX, y: body.minY + body.height * 0.40)
        let radius = body.width * 0.30
        let width = max(2, body.width * (isTiny ? 0.13 : 0.11))
        let start = CGFloat.pi * 0.86            // 左下
        let end = CGFloat.pi * 0.14              // 右下

        // 底槽
        context.setLineCap(.round)
        context.setLineWidth(width)
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.14))
        context.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
        context.strokePath()

        // 已用刻度，绿 → 红
        context.saveGState()
        context.setLineWidth(width)
        context.addArc(center: center, radius: radius,
                       startAngle: start, endAngle: start - (start - end) * 0.68, clockwise: true)
        context.replacePathWithStrokedPath()
        context.clip()
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [colors.accent, colors.accent2] as CFArray, locations: [0, 1]
        ) else { context.restoreGState(); return }
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: center.x - radius, y: center.y),
            end: CGPoint(x: center.x + radius, y: center.y),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
        context.restoreGState()

        // 指针
        let angle = start - (start - end) * 0.68
        let tip = CGPoint(x: center.x + cos(angle) * radius * 0.78,
                          y: center.y + sin(angle) * radius * 0.78)
        context.setLineCap(.round)
        context.setLineWidth(max(1.5, scale * 0.032))
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.95))
        context.move(to: center)
        context.addLine(to: tip)
        context.strokePath()

        context.setFillColor(CGColor(gray: 1, alpha: 0.95))
        let hub = max(1.5, scale * 0.035)
        context.fillEllipse(in: CGRect(x: center.x - hub, y: center.y - hub, width: hub * 2, height: hub * 2))
    }

    // MARK: 示波波形

    private func drawPulse(_ context: CGContext, in body: CGRect, scale: CGFloat) {
        let colors = palette
        let isTiny = scale <= 32
        let plot = body.insetBy(dx: body.width * 0.14, dy: body.height * 0.28)

        if !isTiny {
            // 中线，强调「基线」而不是「趋势」
            context.setStrokeColor(CGColor(gray: 1, alpha: 0.16))
            context.setLineWidth(max(0.5, scale * 0.005))
            context.move(to: CGPoint(x: plot.minX, y: plot.midY))
            context.addLine(to: CGPoint(x: plot.maxX, y: plot.midY))
            context.strokePath()
        }

        let samples: [CGFloat] = isTiny
            ? [0.5, 0.5, 0.12, 0.92, 0.35, 0.5, 0.5]
            : [0.5, 0.5, 0.5, 0.40, 0.60, 0.5, 0.08, 0.96, 0.22, 0.58, 0.5, 0.5, 0.46, 0.5]
        var points: [CGPoint] = []
        for (index, value) in samples.enumerated() {
            let x = plot.minX + plot.width * CGFloat(index) / CGFloat(samples.count - 1)
            points.append(CGPoint(x: x, y: plot.minY + plot.height * value))
        }

        // 辉光
        let line = CGMutablePath()
        line.addLines(between: points)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.addPath(line)
        context.setStrokeColor(colors.accent.copy(alpha: 0.28) ?? colors.accent)
        context.setLineWidth(max(2, scale * 0.075))
        context.strokePath()

        context.addPath(line)
        context.setStrokeColor(colors.accent)
        context.setLineWidth(max(1, scale * 0.032))
        context.strokePath()
    }
}
