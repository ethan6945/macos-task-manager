import AppKit
import SwiftUI

/// 把窗口内容渲染成 PNG。
///
/// 渲染的是自己进程里的 CALayer 树，不经过屏幕捕获，**不需要「屏幕录制」权限**。
/// 用于导出界面快照、提 bug 时附图，也让自动化验证能真正看到界面。
enum WindowSnapshot {

    @MainActor
    @discardableResult
    static func capture(to url: URL) async -> Bool {
        guard let window = NSApplication.shared.windows.first(where: { $0.isVisible && $0.contentView != nil }),
              let view = window.contentView else { return false }

        // 已知限制：左侧导航栏用的是毛玻璃材质，由窗口服务器合成，离屏渲染只能得到
        // 一块不透明的白。试过改 blendingMode、给 List 铺实色，都没用 —— 那一列
        // 压根不在这棵图层树里。要连侧栏一起截，只能走系统录屏（需要屏幕录制权限）。


        guard let image = renderLayerTree(of: view, scale: window.backingScaleFactor,
                                          appearance: window.effectiveAppearance)
                ?? renderWithCacheDisplay(view) else { return false }
        do {
            try image.write(to: url)
            return true
        } catch {
            return false
        }
    }

    /// SwiftUI 的内容是图层承载的，`cacheDisplay` 只走 `drawRect`，画出来是空白。
    /// 直接渲染 CALayer 树才能拿到完整画面，而且同样不需要屏幕录制权限。
    @MainActor
    private static func renderLayerTree(of view: NSView, scale: CGFloat,
                                        appearance: NSAppearance) -> Data? {
        guard let layer = view.layer else { return nil }
        let size = view.bounds.size
        let pixelWidth = Int(size.width * scale)
        let pixelHeight = Int(size.height * scale)
        guard pixelWidth > 0, pixelHeight > 0,
              let context = CGContext(
                data: nil, width: pixelWidth, height: pixelHeight,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)
        else { return nil }

        // CGContext 原点在左下、AppKit 图层原点在左上，不翻转的话画面是上下颠倒的
        context.saveGState()
        context.translateBy(x: 0, y: CGFloat(pixelHeight))
        context.scaleBy(x: scale, y: -scale)
        layer.render(in: context)
        context.restoreGState()

        // 窗口的毛玻璃背板由窗口服务器合成，离屏渲染拿不到，图层没画到的地方是全透明的
        // （看图工具会显示成白色）。所以渲染**之后**用 destinationOver 补一层窗口背景色，
        // 只填空白处，已经画好的内容不受影响。渲染之前铺会被图层直接覆盖掉。
        appearance.performAsCurrentDrawingAppearance {
            context.setBlendMode(.destinationOver)
            context.setFillColor(NSColor.windowBackgroundColor.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        }

        guard let cgImage = context.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = size
        return rep.representation(using: .png, properties: [:])
    }

    @MainActor
    private static func renderWithCacheDisplay(_ view: NSView) -> Data? {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        rep.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    /// 弹存储面板，让用户自己选位置。
    @MainActor
    static func saveWithPanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "TaskManager.png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await capture(to: url) }
    }
}

/// 自动化验证用：设了 `TM_CAPTURE_DIR` 就逐页截图然后退出。
@MainActor
enum SnapshotRunner {

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["TM_CAPTURE_DIR"] != nil
    }

    static func runIfRequested(setPage: @escaping (Page) -> Void,
                               setPerformanceTab: @escaping (PerformanceTab) -> Void,
                               performanceTabs: @escaping () -> [(String, PerformanceTab)]) {
        guard let directory = ProcessInfo.processInfo.environment["TM_CAPTURE_DIR"] else { return }
        let base = URL(fileURLWithPath: directory)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        Task { @MainActor in
            // 可指定窗口尺寸，例如 TM_CAPTURE_SIZE=760x1000（竖版素材用）
            if let spec = ProcessInfo.processInfo.environment["TM_CAPTURE_SIZE"] {
                let parts = spec.split(separator: "x").compactMap { Double($0) }
                if parts.count == 2, let window = NSApplication.shared.windows.first {
                    var frame = window.frame
                    frame.size = NSSize(width: parts[0], height: parts[1])
                    window.setFrame(frame, display: true)
                }
            }
            // 先等数据填充几轮，图表和表格才有内容
            try? await Task.sleep(for: .seconds(8))

            for (index, page) in Page.allCases.enumerated() {
                setPage(page)
                if page == .performance {
                    try? await Task.sleep(for: .seconds(1))
                    for (name, tab) in performanceTabs() {
                        setPerformanceTab(tab)
                        try? await Task.sleep(for: .seconds(1.5))
                        await WindowSnapshot.capture(to: base.appendingPathComponent(
                            String(format: "%02d-performance-%@.png", index, name)))
                    }
                    continue
                }
                try? await Task.sleep(for: .seconds(2))
                await WindowSnapshot.capture(to: base.appendingPathComponent(
                    String(format: "%02d-%@.png", index, page.rawValue)))
            }
            NSApplication.shared.terminate(nil)
        }
    }
}
