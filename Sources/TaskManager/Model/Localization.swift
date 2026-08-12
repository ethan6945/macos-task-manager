import Foundation
import Observation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system, chinese, english

    var id: String { rawValue }

    /// 语言名一律用各自的语言写，切换时不会看不懂。
    @MainActor
    var displayName: String {
        switch self {
        case .system: L("跟随系统")
        case .chinese: "简体中文"
        case .english: "English"
        }
    }
}

/// 界面语言。
///
/// 用中文原文当 key、英文查表：这样既不用发明一套 key 名，也能在运行时即时切换
/// （`.lproj` 资源包换语言要重启进程）。`L()` 在 view body 里被调用，
/// 读到 `language` 就自动建立了 SwiftUI 的观察依赖，切换后界面会自己重画。
@MainActor
@Observable
final class Localizer {
    static let shared = Localizer()

    var language: AppLanguage {
        didSet {
            guard language != oldValue else { return }
            UserDefaults.standard.set(language.rawValue, forKey: "language")
        }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: "language")
        language = saved.flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    /// 实际生效的语言。`.system` 按系统首选语言判定。
    var resolved: AppLanguage {
        guard language == .system else { return language }
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("zh") ? .chinese : .english
    }

    func text(_ chinese: String) -> String {
        guard resolved == .english else { return chinese }
        return Self.english[chinese] ?? chinese
    }
}

/// 取一条界面文案。参数版走 `String(format:)`。
@MainActor
func L(_ chinese: String) -> String {
    Localizer.shared.text(chinese)
}

@MainActor
func L(_ chinese: String, _ arguments: any CVarArg...) -> String {
    String(format: Localizer.shared.text(chinese), arguments: arguments)
}

extension Localizer {
    /// 中文原文 → 英文。缺失的条目会原样显示中文，不会崩。
    nonisolated static let english: [String: String] = [
        // MARK: 通用
        "任务管理器": "Task Manager",
        "查看": "View",
        "立即刷新": "Refresh Now",
        "刷新速率": "Update Speed",
        "刷新速率：%@": "Update speed: %@",
        "窗口置顶": "Always on Top",
        "刷新": "Refresh",
        "取消": "Cancel",
        "删除": "Delete",
        "好": "OK",
        "是": "Yes",
        "否": "No",
        "未知": "Unknown",
        "名称": "Name",
        "类型": "Type",
        "状态": "Status",
        "用户": "User",
        "系统": "System",
        "第三方": "Third-party",
        "程序": "Program",
        "路径": "Path",
        "操作未完成": "Action Failed",
        "现在": "Now",
        "60 秒前": "60 seconds ago",
        "跟随系统": "Match System",

        // MARK: 标点与拼接
        "、": ", ",
        "%@（%d）：%@": "%@ (%d): %@",
        "%@（uid %d）": "%@ (uid %d)",

        // MARK: 页面名
        "进程": "Processes",
        "性能": "Performance",
        "应用历史记录": "App history",
        "启动应用": "Startup apps",
        "详细信息": "Details",
        "服务": "Services",
        "设置": "Settings",

        // MARK: 刷新速率 / 外观 / 语言
        "高": "High",
        "正常": "Normal",
        "低": "Low",
        "已暂停": "Paused",
        "外观": "Appearance",
        "浅色": "Light",
        "深色": "Dark",
        "强调色": "Accent Color",
        "语言": "Language",
        "默认": "Default",
        "蓝色": "Blue",
        "紫色": "Purple",
        "粉色": "Pink",
        "红色": "Red",
        "橙色": "Orange",
        "黄色": "Yellow",
        "绿色": "Green",
        "石墨色": "Graphite",

        // MARK: 进程状态 / 优先级
        "空闲": "Idle",
        "运行中": "Running",
        "睡眠": "Sleeping",
        "已停止": "Stopped",
        "僵尸": "Zombie",
        "实时": "Realtime",
        "高于正常": "Above normal",
        "低于正常": "Below normal",
        "最低": "Lowest",
        "32 位": "32-bit",

        // MARK: 进程页
        "按类型分组": "Group by type",
        "结束进程": "End task",
        "强制结束": "Force quit",
        "搜索进程名或 PID": "Search by name or PID",
        "搜索进程": "Search processes",
        "应用（%d）": "Apps (%d)",
        "后台进程（%d）": "Background processes (%d)",
        "内存": "Memory",
        "磁盘": "Disk",
        "线程": "Threads",
        "端口": "Ports",
        "能耗": "Energy",
        "架构": "Architecture",
        "父进程": "Parent",
        "优先级": "Priority",
        "页面调入": "Page-ins",
        "上下文切换": "Context switches",
        "启动时间": "Start time",
        "CPU 时间": "CPU time",
        "结束这些进程？": "End these processes?",
        "强制结束这些进程？": "Force quit these processes?",
        "将向 %@ 发送 SIGTERM。": "SIGTERM will be sent to %@.",
        "将向 %@ 发送 SIGKILL。进程不会有机会保存数据。":
            "SIGKILL will be sent to %@. They will not get a chance to save data.",
        "结束选中的 %d 个进程": "End the %d selected processes",
        "强制结束选中的 %d 个进程": "Force quit the %d selected processes",
        "在访达中显示": "Show in Finder",
        "拷贝路径": "Copy Path",
        "拷贝 PID": "Copy PID",
        "拷贝命令行": "Copy Command Line",
        "优先级：%@（nice %d）": "Priority: %@ (nice %d)",
        "部分进程的指标暂不可用": "Some process metrics unavailable",
        "未提权的应用读不到其他用户进程的 CPU 与内存，本程序靠常驻的 top 子进程补齐；它尚未就绪。":
            "An unprivileged app cannot read CPU or memory for other users' processes. This app fills that gap with a resident top subprocess, which is not ready yet.",
        "指标受限": "Limited metrics",
        "top 子进程尚未就绪或不可用，其他用户的进程暂时读不到 CPU/内存。":
            "The top subprocess is not ready or unavailable, so other users' processes have no CPU/memory readings right now.",

        // MARK: 详细信息页
        "完整路径": "Full path",
        "启动于": "Started",
        "累计 CPU 时间": "Total CPU time",
        "磁盘读/写": "Disk read/write",
        "命令行": "Command line",
        "选择一个进程查看详细信息": "Select a process to see its details",
        "—（只能读取与你同用户的进程）": "— (readable only for processes owned by you)",
        "—（只能读取与你同用户的进程的命令行）": "— (command line readable only for processes owned by you)",

        // MARK: 错误
        "权限不足。%@": "Permission denied. %@",
        "进程已经不存在了。": "That process no longer exists.",
        "操作失败（errno %d：%@）。": "Operation failed (errno %d: %@).",
        "该进程属于其他用户或系统，未提权的应用结束不了它。":
            "It belongs to another user or the system; an unprivileged app cannot end it.",
        "提高优先级（负 nice）需要 root；降低优先级则不需要，但目标进程必须与你同用户。":
            "Raising priority (negative nice) requires root. Lowering it does not, but the process must be owned by you.",

        // MARK: 性能页 · 通用
        "利用率": "Utilization",
        "总利用率": "Total utilization",
        "正常运行时间": "Up time",
        "活动时间": "Active time",
        "传输速率": "Transfer rate",

        // MARK: 性能页 · CPU
        "按逻辑处理器显示": "Show logical processors",
        "系统（内核）": "System (kernel)",
        "打开的文件": "Open files",
        "用户态": "User",
        "内核态": "Kernel",
        "性能核 %d": "P-core %d",
        "能效核 %d": "E-core %d",
        "CPU %d": "CPU %d",
        "型号": "Model",
        "机型": "Machine",
        "物理核心": "Physical cores",
        "逻辑处理器": "Logical processors",
        "核心构成": "Core layout",
        "%d 性能核 + %d 能效核": "%d performance + %d efficiency",
        "性能核缓存": "P-core cache",
        "能效核缓存": "E-core cache",
        "缓存": "Cache",
        "L3 缓存": "L3 cache",
        "缓存行": "Cache line",
        "%d 字节": "%d bytes",
        "基准速度": "Base speed",
        "—（Apple Silicon 不暴露基准频率）": "— (Apple Silicon does not report a base frequency)",

        // MARK: 性能页 · 内存
        "内存使用": "Memory usage",
        "内存构成": "Memory composition",
        "联动": "Wired",
        "已压缩": "Compressed",
        "已缓存文件": "Cached files",
        "使用中（含压缩）": "In use (incl. compressed)",
        "可用": "Available",
        "App 内存": "App memory",
        "联动内存": "Wired memory",
        "完全空闲": "Free",
        "内存压力": "Memory pressure",
        "内存压力：%@": "Memory pressure: %@",
        "交换区已用": "Swap used",
        "页面调出": "Page-outs",
        "交换入/出": "Swap in/out",
        "已安装内存": "Installed memory",
        "制造商": "Manufacturer",
        "插槽": "Slots",
        "交换区": "Swap",
        "未启用（系统按需创建）": "Not in use (created on demand)",
        "板载（统一内存，无插槽）": "Soldered (unified memory, no slots)",
        "统一内存": "unified memory",
        "警告": "Warning",
        "紧张": "Critical",

        // MARK: 性能页 · GPU
        "读不到 GPU 统计": "No GPU statistics",
        "IORegistry 里没有找到带 PerformanceStatistics 的 IOAccelerator 节点。":
            "No IOAccelerator node with PerformanceStatistics was found in the IORegistry.",
        "GPU 利用率": "GPU utilization",
        "GPU 引擎": "GPU engines",
        "渲染器 Renderer": "Renderer",
        "分块器 Tiler": "Tiler",
        "已分配显存": "Allocated VRAM",
        "使用中显存": "VRAM in use",
        "驱动占用": "Driver",
        "GPU 核心": "GPU cores",
        "内存架构": "Memory architecture",
        "统一内存（与 CPU 共享）": "Unified (shared with CPU)",
        "独立显存": "Discrete VRAM",
        "建议工作集上限": "Recommended working set",
        "单缓冲上限": "Max buffer length",
        "IORegistry 节点": "IORegistry node",
        "说明：macOS 没有公开的按进程 GPU 用量接口，因此进程页不提供「GPU」列。":
            "Note: macOS exposes no public per-process GPU usage API, so the Processes page has no GPU column.",

        // MARK: 性能页 · 磁盘
        "读取": "Read",
        "写入": "Write",
        "读取速度": "Read speed",
        "写入速度": "Write speed",
        "平均响应时间": "Average response time",
        "读取 IOPS": "Read IOPS",
        "写入 IOPS": "Write IOPS",
        "累计读取": "Total read",
        "累计写入": "Total written",
        "卷": "Volumes",
        "系统盘": "System disk",
        "只读": "Read-only",
        "磁盘已移除": "Disk removed",

        // MARK: 性能页 · 网络
        "吞吐量": "Throughput",
        "接收": "Receive",
        "发送": "Send",
        "接收（Mbps）": "Receive (Mbps)",
        "发送（Mbps）": "Send (Mbps)",
        "累计接收": "Total received",
        "累计发送": "Total sent",
        "接收包数": "Packets in",
        "发送包数": "Packets out",
        "接口": "Interface",
        "已连接": "Connected",
        "未连接": "Not connected",
        "链路速度": "Link speed",
        "MAC 地址": "MAC address",
        "错误（收/发）": "Errors (in/out)",
        "接口已移除": "Interface removed",
        "说明：macOS 未公开按进程的网络流量接口（系统自带的 nettop 走的是私有框架且需 root），因此进程页不提供「网络」列。":
            "Note: macOS exposes no public per-process network API (the bundled nettop uses a private framework and needs root), so the Processes page has no Network column.",

        // MARK: 应用历史记录
        "只看有界面的应用": "Apps with a UI only",
        "统计起始：%@": "Tracking since %@",
        "删除使用历史记录": "Delete usage history",
        "删除所有使用历史记录？": "Delete all usage history?",
        "累计的 CPU 时间、峰值内存与磁盘读写都会清零，统计将从现在重新开始。":
            "Accumulated CPU time, peak memory and disk I/O will be cleared, and tracking restarts now.",
        "峰值内存": "Peak memory",
        "磁盘读取": "Disk read",
        "磁盘写入": "Disk written",
        "最近出现": "Last seen",
        "搜索应用": "Search apps",
        "统计自本程序首次运行开始累计，保存在 ~/Library/Application Support/TaskManager/。磁盘读写只能读到与你同用户的进程；按进程的网络流量 macOS 未公开接口，故不提供。":
            "Tracked since this app first ran, stored in ~/Library/Application Support/TaskManager/. Disk I/O is readable only for processes owned by you; macOS exposes no per-process network API.",

        // MARK: 启动应用
        "开机/登录时由 launchd 拉起的项目": "Items launchd starts at boot or login",
        "共 %d 项，其中 %d 项已加载": "%d items, %d loaded",
        "登录时启动": "Run at load",
        "保持运行": "Keep alive",
        "搜索启动项": "Search startup items",
        "停用（bootout）": "Disable (bootout)",
        "启用（bootstrap）": "Enable (bootstrap)",
        "在访达中显示配置": "Show config in Finder",
        "在访达中显示程序": "Show program in Finder",
        "拷贝配置路径": "Copy config path",
        "用户代理": "User agent",
        "全局代理": "Global agent",
        "系统守护进程": "System daemon",
        "已加载": "Loaded",
        "未加载": "Not loaded",
        "停用仅对 ~/Library/LaunchAgents 下的条目开放（launchctl bootout）。系统域的代理与守护进程需要管理员权限，本程序不提权。":
            "Only items under ~/Library/LaunchAgents can be toggled (launchctl bootout). System-domain agents and daemons need administrator rights, which this app does not request.",
        "只允许开关 ~/Library/LaunchAgents 下的条目。系统域的代理与守护进程需要管理员权限，请在「终端」里自行处理。":
            "Only items under ~/Library/LaunchAgents can be toggled. System-domain agents and daemons need administrator rights — please handle those in Terminal.",
        "launchctl 没有返回结果": "launchctl returned nothing",
        "launchctl 报错：%@": "launchctl error: %@",

        // MARK: 服务
        "隐藏 com.apple.* 系统作业": "Hide com.apple.* system jobs",
        "运行中 %d / 共 %d": "%d running of %d",
        "归属": "Origin",
        "转到详细信息": "Go to details",
        "拷贝标识符": "Copy label",
        "搜索服务": "Search services",
        "上次退出码 %d": "Last exit code %d",
        "只列出当前用户域（gui/%d）的 launchd 作业。系统域（system/）需要管理员权限才能枚举，本程序不提权，也不提供启停按钮。":
            "Only launchd jobs in your user domain (gui/%d) are listed. Enumerating the system domain requires administrator rights, which this app does not request — so there are no start/stop buttons.",

        // MARK: 侧栏
        "侧栏": "Sidebar",
        "取消勾选的页面不会出现在侧栏里。至少要留下一页。":
            "Unchecked pages are hidden from the sidebar. At least one page must stay.",

        // MARK: 网络端口
        "网络端口": "Network Ports",
        "只看本机可访问的服务": "Only services reachable from this Mac",
        "显示所有网络接口": "Show all-interface binds",
        "监听中 %d 个端口": "%d listening ports",
        "搜索端口或进程": "Search ports or processes",
        "端口号": "Port",
        "地址": "Address",
        "范围": "Scope",
        "打开": "Open",
        "Web 检测": "Web check",
        "检测": "Check",
        "检测中…": "Checking…",
        "不是 Web 服务": "Not a web service",
        "超时": "Timed out",
        "无法连接": "Cannot connect",
        "URL 无效": "Invalid URL",
        "被 App Transport Security 拦截": "Blocked by App Transport Security",
        "%@ %d · %@": "%@ %d · %@",
        "%@ %d": "%@ %d",
        "仅本机": "Loopback only",
        "所有网络接口": "All interfaces",
        "指定地址": "Bound address",
        "在浏览器中打开": "Open in Browser",
        "检测是否为 Web 服务": "Check whether it serves HTTP",
        "拷贝地址": "Copy address",
        "拷贝端口": "Copy port",
        "端口列表来自 netstat，只列出正在监听的 TCP 端口（不含 UDP，也不含向外建立的连接）。「检测」会向 127.0.0.1 发一次 HTTP 请求，只在你点击时才发。本页不提供结束进程的操作。":
            "Ports come from netstat and cover listening TCP sockets only — no UDP, no outbound connections. \"Check\" sends one HTTP request to 127.0.0.1, and only when you click it. This page offers no way to end a process.",

        // MARK: 用户
        "本机登录": "Console",
        "终端": "Terminal",
        "远程（%@）": "Remote (%@)",
        "无交互式登录会话（后台/系统用户）": "No interactive login session (background/system user)",
        "%@ · 登录于 %@": "%@ · signed in %@",
        "……还有 %d 个进程": "… and %d more processes",
        "会话信息来自 utmpx；资源占用是把该 uid 名下的所有进程加总得到的。":
            "Sessions come from utmpx; resource usage is the sum over all processes owned by that uid.",

        // MARK: 时间
        "%d 天 %@": "%dd %@"
    ]
}
