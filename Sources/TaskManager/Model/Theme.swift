import AppKit
import Observation
import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    var id: String { rawValue }

    @MainActor
    var displayName: String {
        switch self {
        case .system: L("跟随系统")
        case .light: L("浅色")
        case .dark: L("深色")
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    /// nil 表示跟随系统。
    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

enum AppAccent: String, CaseIterable, Identifiable, Sendable {
    case system, blue, purple, pink, red, orange, yellow, green, graphite

    var id: String { rawValue }

    @MainActor
    var displayName: String {
        switch self {
        case .system: L("默认")
        case .blue: L("蓝色")
        case .purple: L("紫色")
        case .pink: L("粉色")
        case .red: L("红色")
        case .orange: L("橙色")
        case .yellow: L("黄色")
        case .green: L("绿色")
        case .graphite: L("石墨色")
        }
    }

    /// nil 表示用系统强调色。
    var color: Color? {
        switch self {
        case .system: nil
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .graphite: Color(nsColor: .systemGray)
        }
    }

    /// 图表主色跟随强调色，没选时用蓝色（图表不能没有颜色）。
    var chartColor: Color { color ?? .blue }
}

/// 外观设置。改动直接作用到 `NSApp.appearance`，全窗口即时生效。
@MainActor
@Observable
final class ThemeSettings {
    static let shared = ThemeSettings()

    var theme: AppTheme {
        didSet {
            guard theme != oldValue else { return }
            UserDefaults.standard.set(theme.rawValue, forKey: "theme")
            apply()
        }
    }

    var accent: AppAccent {
        didSet {
            guard accent != oldValue else { return }
            UserDefaults.standard.set(accent.rawValue, forKey: "accent")
        }
    }

    private init() {
        let defaults = UserDefaults.standard
        theme = defaults.string(forKey: "theme").flatMap(AppTheme.init(rawValue:)) ?? .system
        accent = defaults.string(forKey: "accent").flatMap(AppAccent.init(rawValue:)) ?? .system
    }

    func apply() {
        NSApplication.shared.appearance = theme.appearance
    }
}

extension View {
    /// 把当前强调色套到视图树上。
    @MainActor
    func appAccent() -> some View {
        modifier(AccentModifier())
    }
}

private struct AccentModifier: ViewModifier {
    private var settings: ThemeSettings { .shared }

    func body(content: Content) -> some View {
        if let color = settings.accent.color {
            content.tint(color)
        } else {
            content
        }
    }
}
