import SwiftUI

@main
struct TaskManagerApp: App {
    @State private var monitor = SystemMonitor()
    @State private var theme = ThemeSettings.shared
    @State private var localizer = Localizer.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window(L("任务管理器"), id: "main") {
            RootView()
                .environment(monitor)
                .environment(theme)
                .environment(localizer)
                .appAccent()
                .frame(minWidth: 900, minHeight: 560)
                .onAppear {
                    theme.apply()
                    monitor.start()
                }
        }
        .defaultSize(width: 1080, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .saveItem) {
                Button(L("存储窗口快照…")) { WindowSnapshot.saveWithPanel() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }
            CommandMenu(L("查看")) {
                Button(L("立即刷新")) { monitor.refreshNow() }
                    .keyboardShortcut("r", modifiers: .command)
                Divider()
                Picker(L("刷新速率"), selection: $monitor.refreshRate) {
                    ForEach(RefreshRate.allCases) { rate in
                        Text(rate.displayName).tag(rate)
                    }
                }
                Divider()
                Picker(L("外观"), selection: $theme.theme) {
                    ForEach(AppTheme.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                Picker(L("语言"), selection: $localizer.language) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                Divider()
                Toggle(L("窗口置顶"), isOn: Binding(
                    get: { appDelegate.isFloating },
                    set: { appDelegate.setFloating($0) }
                ))
            }
        }

        Settings {
            SettingsView()
                .environment(monitor)
                .environment(theme)
                .environment(localizer)
                .appAccent()
        }
    }
}

/// 只做两件事：退出时收尾，以及「窗口置顶」。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published var isFloating = false

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func setFloating(_ floating: Bool) {
        isFloating = floating
        for window in NSApplication.shared.windows {
            window.level = floating ? .floating : .normal
        }
    }
}
