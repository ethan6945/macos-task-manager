import SwiftUI

struct SettingsView: View {
    private var theme: ThemeSettings { .shared }
    private var localizer: Localizer { .shared }
    private var sidebar: SidebarSettings { .shared }
    @Environment(SystemMonitor.self) private var monitor

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

            Section(L("侧栏")) {
                ForEach(Page.allCases) { item in
                    Toggle(isOn: Binding(
                        get: { sidebar.isVisible(item) },
                        set: { sidebar.setVisible(item, $0) }
                    )) {
                        Label(item.title, systemImage: item.symbol)
                    }
                    .disabled(!sidebar.canToggle(item))
                }
                Text(L("取消勾选的页面不会出现在侧栏里。至少要留下一页。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
