import SwiftUI

enum Page: String, CaseIterable, Identifiable, Hashable {
    // 侧栏顺序就是这里的顺序：性能第一，进程第二
    case performance, processes, appHistory, startup, users, details, services

    var id: String { rawValue }

    @MainActor
    var title: String {
        switch self {
        case .processes: L("进程")
        case .performance: L("性能")
        case .appHistory: L("应用历史记录")
        case .startup: L("启动应用")
        case .users: L("用户")
        case .details: L("详细信息")
        case .services: L("服务")
        }
    }

    var symbol: String {
        switch self {
        case .processes: "list.bullet.rectangle"
        case .performance: "waveform.path.ecg"
        case .appHistory: "clock.arrow.circlepath"
        case .startup: "power"
        case .users: "person.2"
        case .details: "tablecells"
        case .services: "gearshape.2"
        }
    }
}

struct RootView: View {
    @Environment(SystemMonitor.self) private var monitor
    /// 每次启动都从性能页开始（不记忆上次停留的页面）。
    /// `TM_PAGE` 可以指定启动页，截图脚本用。
    @State private var pageID: String = ProcessInfo.processInfo.environment["TM_PAGE"]
        .flatMap { Page(rawValue: $0)?.rawValue } ?? Page.performance.rawValue
    @State private var performanceTab: PerformanceTab = .cpu
    /// 从服务/详细信息页跳转过来时要定位的进程
    @State private var focusedPID: pid_t?

    private var page: Binding<Page> {
        Binding(
            get: { Page(rawValue: pageID) ?? .processes },
            set: { pageID = $0.rawValue }
        )
    }

    var body: some View {
        NavigationSplitView {
            List(Page.allCases, selection: page) { item in
                Label(item.title, systemImage: item.symbol).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 168, ideal: 190, max: 240)
        } detail: {
            VStack(spacing: 0) {
                content
                Divider()
                StatusBar()
            }
            .navigationTitle(page.wrappedValue.title)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                AppearanceMenu()
            }
            ToolbarItem(placement: .primaryAction) {
                RefreshRateMenu()
            }
        }
        .onAppear {
            // 截图脚本用：指定性能页的子页
            if let tab = ProcessInfo.processInfo.environment["TM_PERF_TAB"] {
                switch tab {
                case "memory": performanceTab = .memory
                case "gpu": performanceTab = .gpu
                case "disk": if let d = monitor.disks.first { performanceTab = .disk(d.id) }
                case "network":
                    if let n = monitor.networks.first(where: { !$0.isLoopback && !$0.isVirtual && $0.hasTraffic }) {
                        performanceTab = .network(n.id)
                    }
                default: performanceTab = .cpu
                }
            }
            SnapshotRunner.runIfRequested(
                setPage: { pageID = $0.rawValue },
                setPerformanceTab: { performanceTab = $0 },
                performanceTabs: {
                    var tabs: [(String, PerformanceTab)] = [("cpu", .cpu), ("memory", .memory)]
                    if monitor.gpu.available { tabs.append(("gpu", .gpu)) }
                    if let disk = monitor.disks.first { tabs.append(("disk", .disk(disk.id))) }
                    if let net = monitor.networks.first(where: { !$0.isLoopback && !$0.isVirtual && $0.hasTraffic }) {
                        tabs.append(("network", .network(net.id)))
                    }
                    return tabs
                }
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        switch page.wrappedValue {
        case .processes:
            ProcessesView(focusedPID: $focusedPID)
        case .performance:
            PerformanceView(tab: $performanceTab)
        case .appHistory:
            AppHistoryView()
        case .startup:
            StartupView()
        case .users:
            UsersView()
        case .details:
            DetailsView(focusedPID: $focusedPID)
        case .services:
            ServicesView(onReveal: { pid in
                focusedPID = pid
                pageID = Page.details.rawValue
            })
        }
    }
}

struct RefreshRateMenu: View {
    @Environment(SystemMonitor.self) private var monitor

    var body: some View {
        @Bindable var monitor = monitor
        Menu {
            Picker(L("刷新速率"), selection: $monitor.refreshRate) {
                ForEach(RefreshRate.allCases) { rate in
                    Text(rate.displayName).tag(rate)
                }
            }
            .pickerStyle(.inline)
            Divider()
            Button(L("立即刷新")) { monitor.refreshNow() }
        } label: {
            Label(L("刷新速率：%@", monitor.refreshRate.displayName), systemImage: "timer")
        }
    }
}
