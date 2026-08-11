import AppKit
import Foundation
import Observation

enum RefreshRate: String, CaseIterable, Identifiable, Sendable {
    case high, normal, low, paused

    var id: String { rawValue }

    /// 与 Windows 任务管理器一致的四档。下限是 1 秒 —— `top` 的 `-s` 只接受整秒。
    var interval: TimeInterval {
        switch self {
        case .high: 1
        case .normal: 2
        case .low: 4
        case .paused: 0
        }
    }

    @MainActor
    var displayName: String {
        switch self {
        case .high: L("高")
        case .normal: L("正常")
        case .low: L("低")
        case .paused: L("已暂停")
        }
    }
}

/// 全局状态。采样在 `SamplingEngine` 里跑，这里只负责保存最新快照与历史曲线。
@MainActor
@Observable
final class SystemMonitor {

    // MARK: 静态信息
    private(set) var info = SystemInfo.load()
    private(set) var gpuInfo = GPUInfo()

    // MARK: 最新快照
    private(set) var cpu = CPUSnapshot()
    private(set) var memory = MemorySnapshot()
    private(set) var gpu = GPUSnapshot()
    private(set) var disks: [DiskSnapshot] = []
    private(set) var volumes: [VolumeInfo] = []
    private(set) var networks: [NetworkInterfaceSnapshot] = []
    private(set) var processes: [ProcessRow] = []
    private(set) var listeningPorts: [ListeningPort] = []
    private(set) var openFiles = 0
    private(set) var lastUpdate = Date.distantPast

    // MARK: 低频数据（服务 / 启动项 / 登录会话）
    private(set) var services: [ServiceEntry] = []
    private(set) var startupItems: [StartupItem] = []
    private(set) var sessions: [LoginSession] = []
    private(set) var isLoadingSlowData = false
    let history = AppHistoryStore()

    // MARK: 历史曲线
    private(set) var cpuHistory = History()
    private(set) var cpuUserHistory = History()
    private(set) var cpuSystemHistory = History()
    private(set) var perCoreHistory: [History] = []
    private(set) var memoryHistory = History()
    private(set) var memoryPressureHistory = History()
    private(set) var gpuHistory = History()
    private(set) var gpuRendererHistory = History()
    private(set) var gpuTilerHistory = History()
    private(set) var diskHistory: [String: History] = [:]
    private(set) var diskReadHistory: [String: History] = [:]
    private(set) var diskWriteHistory: [String: History] = [:]
    private(set) var networkReceiveHistory: [String: History] = [:]
    private(set) var networkSendHistory: [String: History] = [:]

    // MARK: 派生状态
    /// top 子进程不可用时，其他用户的进程读不到指标，界面上要如实说明
    private(set) var metricsDegraded = false
    var threadCount: Int { processes.reduce(0) { $0 + $1.threads } }
    var processCount: Int { processes.count }
    var uptime: TimeInterval { Sysctl.uptime }

    // MARK: 设置
    var refreshRate: RefreshRate = .normal {
        didSet {
            guard refreshRate != oldValue else { return }
            UserDefaults.standard.set(refreshRate.rawValue, forKey: "refreshRate")
            Task { await engine.configureTop(interval: refreshRate.interval) }
        }
    }

    private let engine = SamplingEngine()
    private var loop: Task<Void, Never>?
    private var tickCount = 0

    init() {
        if let saved = UserDefaults.standard.string(forKey: "refreshRate"),
           let rate = RefreshRate(rawValue: saved) {
            refreshRate = rate
        }
        volumes = DiskSampler.volumes()
    }

    func start() {
        guard loop == nil else { return }

        // 退出时确保常驻的 top 子进程被收掉，不留孤儿。
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }

        Task { [engine] in
            let gpuInfo = await engine.gpuInfo
            await MainActor.run { self.gpuInfo = gpuInfo }
        }
        Task { [info] in
            var enriched = info
            enriched.enrichFromSystemProfiler()
            await MainActor.run { self.info = enriched }
        }

        loop = Task { [weak self] in
            guard let self else { return }
            await self.engine.configureTop(interval: self.refreshRate.interval)

            while !Task.isCancelled {
                let interval = self.refreshRate.interval
                if interval > 0 {
                    let identities = Self.collectAppIdentities()
                    let sample = await self.engine.tick(appIdentities: identities)
                    guard !Task.isCancelled else { return }
                    self.apply(sample)
                }
                try? await Task.sleep(for: .seconds(interval > 0 ? interval : 0.5))
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        Task { [engine] in await engine.stopTop() }
    }

    /// 立即采一次（用于「刷新」菜单项与暂停状态下的手动刷新）。
    func refreshNow() {
        Task { [weak self] in
            guard let self else { return }
            await self.engine.configureTop(interval: max(1, self.refreshRate.interval))
            let identities = Self.collectAppIdentities()
            let sample = await self.engine.tick(appIdentities: identities)
            self.apply(sample)
        }
    }

    /// 「网络端口」页的刷新按钮：绕过端口采样的节流缓存，立刻重采一次。
    func refreshPorts() {
        Task { [weak self] in
            guard let self else { return }
            await self.engine.invalidatePorts()
            let identities = Self.collectAppIdentities()
            let sample = await self.engine.tick(appIdentities: identities)
            self.apply(sample)
        }
    }

    // MARK: - 应用快照

    private func apply(_ sample: Sample) {
        cpu = sample.cpu
        memory = sample.memory
        gpu = sample.gpu
        disks = sample.disks
        networks = sample.networks
        processes = sample.processes
        listeningPorts = sample.listeningPorts
        openFiles = sample.openFiles
        metricsDegraded = sample.topUnavailable || !sample.topHealthy
        lastUpdate = sample.timestamp

        cpuHistory.append(sample.cpu.total)
        cpuUserHistory.append(sample.cpu.user + sample.cpu.nice)
        cpuSystemHistory.append(sample.cpu.system)

        if perCoreHistory.count != sample.cpu.perCore.count {
            perCoreHistory = sample.cpu.perCore.map { _ in History(capacity: 60) }
        }
        for (index, value) in sample.cpu.perCore.enumerated() {
            perCoreHistory[index].append(value)
        }

        memoryHistory.append(sample.memory.usedPercent)
        memoryPressureHistory.append(sample.memory.pressure)

        gpuHistory.append(sample.gpu.utilization)
        gpuRendererHistory.append(sample.gpu.rendererUtilization)
        gpuTilerHistory.append(sample.gpu.tilerUtilization)

        for disk in sample.disks {
            diskHistory[disk.id, default: History()].append(disk.activeTime)
            diskReadHistory[disk.id, default: History()].append(disk.readRate)
            diskWriteHistory[disk.id, default: History()].append(disk.writeRate)
        }
        for interface in sample.networks {
            networkReceiveHistory[interface.id, default: History()].append(interface.receiveRate)
            networkSendHistory[interface.id, default: History()].append(interface.sendRate)
        }

        history.update(with: sample.processes)

        tickCount += 1
        if tickCount % 15 == 1 {
            volumes = DiskSampler.volumes()
        }
        if tickCount == 1 || tickCount % 60 == 0 {
            refreshSlowData()
        }
    }

    /// 服务、启动项、登录会话变化很慢，而且要 fork `launchctl`，所以低频刷新。
    func refreshSlowData() {
        guard !isLoadingSlowData else { return }
        isLoadingSlowData = true
        Task {
            let loaded = await Task.detached(priority: .utility) { () -> ([ServiceEntry], [StartupItem], [LoginSession]) in
                let services = ServiceSampler.load()
                let startup = StartupSampler.load(services: services)
                let sessions = UserSampler.sessions()
                return (services, startup, sessions)
            }.value
            self.services = loaded.0
            self.startupItems = loaded.1
            self.sessions = loaded.2
            self.isLoadingSlowData = false
        }
    }

    /// NSWorkspace 只能在主线程访问，这里把结果打包成值类型送进采样 actor。
    private static func collectAppIdentities() -> [pid_t: AppIdentity] {
        var result: [pid_t: AppIdentity] = [:]
        for app in NSWorkspace.shared.runningApplications {
            guard app.processIdentifier > 0 else { continue }
            result[app.processIdentifier] = AppIdentity(
                localizedName: app.localizedName ?? "",
                bundleIdentifier: app.bundleIdentifier,
                bundlePath: app.bundleURL?.path,
                isRegular: app.activationPolicy == .regular
            )
        }
        return result
    }
}
