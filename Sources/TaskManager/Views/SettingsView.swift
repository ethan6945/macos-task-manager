import SwiftUI

struct SettingsView: View {
    private var theme: ThemeSettings { .shared }
    private var localizer: Localizer { .shared }
    @Environment(SystemMonitor.self) private var monitor
    @AppStorage("privacyMode") private var privacyMode = false

    var body: some View {
        @Bindable var theme = theme
        @Bindable var localizer = localizer
        @Bindable var monitor = monitor

        Form {
            Section(L("外观")) {
                Picker(L("外观"), selection: $theme.theme) {
                    ForEach(AppTheme.allCases) { option in
                        Label(option.displayName, systemImage: option.symbol).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                Picker(L("强调色"), selection: $theme.accent) {
                    ForEach(AppAccent.allCases) { option in
                        HStack {
                            Circle()
                                .fill(option.color ?? Color.accentColor)
                                .frame(width: 10, height: 10)
                            Text(option.displayName)
                        }
                        .tag(option)
                    }
                }
            }

            Section(L("语言")) {
                Picker(L("语言"), selection: $localizer.language) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            Section(L("刷新速率")) {
                Picker(L("刷新速率"), selection: $monitor.refreshRate) {
                    ForEach(RefreshRate.allCases) { rate in
                        Text(rate.displayName).tag(rate)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section(L("隐私")) {
                Toggle(L("隐私模式"), isOn: $privacyMode)
                Text(L("分享截图时用：用户名显示成 user、主机名显示成 mac，服务页与启动项页只列 com.apple.* 的系统作业。进程名不受影响。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(L("界面语言与外观会立即生效，无需重启。"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onChange(of: privacyMode) { _, _ in monitor.refreshSlowData() }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// 工具栏上的快捷开关，不用打开设置窗口也能换主题/语言。
struct AppearanceMenu: View {
    private var theme: ThemeSettings { .shared }
    private var localizer: Localizer { .shared }

    var body: some View {
        @Bindable var theme = theme
        @Bindable var localizer = localizer

        Menu {
            Picker(L("外观"), selection: $theme.theme) {
                ForEach(AppTheme.allCases) { option in
                    Label(option.displayName, systemImage: option.symbol).tag(option)
                }
            }
            .pickerStyle(.inline)

            Divider()

            Picker(L("强调色"), selection: $theme.accent) {
                ForEach(AppAccent.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.inline)

            Divider()

            Picker(L("语言"), selection: $localizer.language) {
                ForEach(AppLanguage.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(L("外观"), systemImage: theme.theme.symbol)
        }
    }
}
