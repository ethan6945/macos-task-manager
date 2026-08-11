import Foundation

/// 一次采样的全部结果。全部是值类型，可以安全跨越 actor 边界。
struct Sample: Sendable {
    var cpu = CPUSnapshot()
    var memory = MemorySnapshot()
    var gpu = GPUSnapshot()
    var disks: [DiskSnapshot] = []
    var networks: [NetworkInterfaceSnapshot] = []
    var processes: [ProcessRow] = []
    /// 正在监听的 TCP 端口。不叫 `ports` —— `ProcessRow.ports` 是 Mach port 数。
    var listeningPorts: [ListeningPort] = []
    var topHealthy = false
    var topUnavailable = false
    var openFiles: Int = 0
    var timestamp = Date()
}

/// 所有采集器都关在这个 actor 里，采样在后台线程完成，只把不可变快照交回主线程。
actor SamplingEngine {

    private let cpuSampler = CPUSampler()
    private let memorySampler = MemorySampler()
    private let gpuSampler = GPUSampler()
    private let diskSampler = DiskSampler()
    private let networkSampler = NetworkSampler()
    private let processSampler = ProcessSampler()
    private let portSampler = PortSampler()
    private let topStream = TopStream()

    private var topInterval: TimeInterval = 0

    var gpuInfo: GPUInfo { gpuSampler.info }

    /// 按刷新速率启动/重启 top 子进程。
    func configureTop(interval: TimeInterval) {
        guard interval > 0 else {
            topStream.stop()
            topInterval = 0
            return
        }
        let rounded = max(1, interval.rounded())
        guard rounded != topInterval else { return }
        topInterval = rounded
        topStream.restart(interval: rounded)
    }

    func stopTop() {
        topStream.stop()
        topInterval = 0
    }

    /// 让下一拍绕过 PortSampler 的节流缓存（「网络端口」页的刷新按钮用）。
    func invalidatePorts() {
        portSampler.invalidate()
    }

    func tick(appIdentities: [pid_t: AppIdentity]) -> Sample {
        // top 子进程可能被外部杀掉（它自己也会出现在进程列表里）。发现挂了就重启，
        // 否则其他用户的进程会永久失去指标。
        if topInterval > 0 && topStream.isUnavailable {
            topStream.restart(interval: topInterval)
        }

        var sample = Sample()
        sample.cpu = cpuSampler.sample()
        sample.memory = memorySampler.sample()
        sample.gpu = gpuSampler.sample()
        sample.disks = diskSampler.sample()
        sample.networks = networkSampler.sample()
        sample.openFiles = Int(Sysctl.openFileCount ?? 0)
        sample.listeningPorts = portSampler.sample()

        let metrics = topStream.metrics()
        sample.topHealthy = topStream.isHealthy
        sample.topUnavailable = topStream.isUnavailable
        sample.processes = processSampler.sample(appIdentities: appIdentities, topMetrics: metrics)
        return sample
    }
}
