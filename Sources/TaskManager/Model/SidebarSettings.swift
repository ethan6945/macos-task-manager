import Observation
import SwiftUI

/// 侧栏里显示哪些页面。用不上的页可以在「设置」里关掉。
///
/// 存的是**隐藏**的页面而不是显示的：以后再加新页时，老用户的设置里没有它，
/// 默认就会显示出来，不会因为存量配置把新功能藏起来。
@MainActor
@Observable
final class SidebarSettings {
    static let shared = SidebarSettings()

    private static let key = "hiddenPages"

    private var hidden: Set<String>

    private init() {
        hidden = Set(UserDefaults.standard.stringArray(forKey: Self.key) ?? [])
    }

    /// 侧栏实际显示的页面，顺序仍按 `Page.allCases`。
    var visiblePages: [Page] {
        let pages = Page.allCases.filter { !hidden.contains($0.rawValue) }
        // 兜底：真要是全被藏了（比如手改了 UserDefaults），就全部显示，别给一个空侧栏
        return pages.isEmpty ? Page.allCases : pages
    }

    func isVisible(_ page: Page) -> Bool { !hidden.contains(page.rawValue) }

    /// 最后一页不许再关 —— 侧栏空掉就没法再打开任何页面了。
    func canToggle(_ page: Page) -> Bool {
        !isVisible(page) || visiblePages.count > 1
    }

    func setVisible(_ page: Page, _ visible: Bool) {
        if visible {
            hidden.remove(page.rawValue)
        } else {
            guard canToggle(page) else { return }
            hidden.insert(page.rawValue)
        }
        UserDefaults.standard.set(Array(hidden), forKey: Self.key)
    }
}
