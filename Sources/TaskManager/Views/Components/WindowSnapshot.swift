import AppKit
import SwiftUI

/// 把窗口内容渲染成 PNG。
///
/// 走的是 `bitmapImageRepForCachingDisplay` —— 在**自己的进程里画自己的视图**，
/// 不经过屏幕捕获，所以不需要「屏幕录制」权限。用于导出界面快照、提 bug 时附图，
/// 也让自动化验证能真正看到界面。
enum WindowSnapshot {

    @MainActor
    @discardableResult
    static func capture(to url: URL) -> Bool {
        guard let window = NSApplication.shared.windows.first(where: { $0.isVisible && $0.contentView != nil }),
              let view = window.contentView else { return false }

        // 毛玻璃默认是 behind-window 混合，由窗口服务器合成，离屏渲染只会得到一块白。
        // 截图期间临时切成 within-window，画完再还原。
        let restore = makeVisualEffectsRenderable(in: view)
        defer { restore() }

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

        // 窗口的毛玻璃背板是窗口服务器合成的，离屏渲染拿不到，
        // 不先铺一层窗口背景色的话深色模式会变成「白底浅灰字」。
        appearance.performAsCurrentDrawingAppearance {
            context.setFillColor(NSColor.windowBackgroundColor.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        }

        // CGContext 原点在左下、AppKit 图层原点在左上，不翻转的话画面是上下颠倒的
        context.translateBy(x: 0, y: CGFloat(pixelHeight))
        context.scaleBy(x: scale, y: -scale)
        layer.render(in: context)

        guard let cgImage = context.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = size
        return rep.representation(using: .png, properties: [:])
    }

    /// 把视图树里所有 `NSVisualEffectView` 切成可离屏渲染的混合模式，返回还原闭包。
    @MainActor
    private static func makeVisualEffectsRenderable(in root: NSView) -> () -> Void {
        var saved: [(view: NSVisualEffectView, blending: NSVisualEffectView.BlendingMode, state: NSVisualEffectView.State)] = []

        func walk(_ view: NSView) {
            if let effect = view as? NSVisualEffectView, effect.blendingMode == .behindWindow {
                saved.append((effect, effect.blendingMode, effect.state))
                effect.blendingMode = .withinWindow
                effect.state = .active
            }
            view.subviews.forEach(walk)
        }
        walk(root)
        root.displayIfNeeded()

        return {
            for entry in saved {
                entry.view.blendingMode = entry.blending
                entry.view.state = entry.state
            }
        }
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
        capture(to: url)
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
                        WindowSnapshot.capture(to: base.appendingPathComponent(
                            String(format: "%02d-performance-%@.png", index, name)))
                    }
                    continue
                }
                try? await Task.sleep(for: .seconds(2))
                WindowSnapshot.capture(to: base.appendingPathComponent(
                    String(format: "%02d-%@.png", index, page.rawValue)))
            }
            NSApplication.shared.terminate(nil)
        }
    }
}
