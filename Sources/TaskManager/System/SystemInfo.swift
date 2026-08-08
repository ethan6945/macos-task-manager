import Darwin
import Foundation

/// 开机后不变的硬件信息 —— 对应 Win11 性能页底部那一排规格。
struct SystemInfo: Sendable {
    var cpuBrand: String = "—"
    var machineModel: String = ""          // hw.model，如 Mac14,3
    var modelName: String = ""             // 如 Mac mini
    var physicalCores: Int = 0
    var logicalCores: Int = 0
    var performanceCores: Int = 0
    var efficiencyCores: Int = 0
    var pCoreL1D: UInt64 = 0
    var pCoreL2: UInt64 = 0
    var eCoreL1D: UInt64 = 0
    var eCoreL2: UInt64 = 0
    var l3Cache: UInt64 = 0
    var cacheLineSize: UInt64 = 0
    /// Apple Silicon 不暴露基准频率，取到才显示
    var cpuFrequency: UInt64 = 0
    var isAppleSilicon: Bool = false

    var memoryTotal: UInt64 = 0
    var memoryType: String = ""            // 如 LPDDR5
    var memoryVendor: String = ""
    var memorySlots: String = ""

    var osVersion: String = ""
    var hostName: String = ""

    static func load() -> SystemInfo {
        var info = SystemInfo()
        info.cpuBrand = Sysctl.string("machdep.cpu.brand_string") ?? "—"
        info.machineModel = Sysctl.string("hw.model") ?? ""
        info.physicalCores = Int(Sysctl.value("hw.physicalcpu", as: Int32.self) ?? 0)
        info.logicalCores = Int(Sysctl.value("hw.logicalcpu", as: Int32.self) ?? 0)
        info.performanceCores = Int(Sysctl.value("hw.perflevel0.physicalcpu", as: Int32.self) ?? 0)
        info.efficiencyCores = Int(Sysctl.value("hw.perflevel1.physicalcpu", as: Int32.self) ?? 0)
        info.pCoreL1D = Sysctl.value("hw.perflevel0.l1dcachesize", as: UInt64.self) ?? 0
        info.pCoreL2 = Sysctl.value("hw.perflevel0.l2cachesize", as: UInt64.self) ?? 0
        info.eCoreL1D = Sysctl.value("hw.perflevel1.l1dcachesize", as: UInt64.self) ?? 0
        info.eCoreL2 = Sysctl.value("hw.perflevel1.l2cachesize", as: UInt64.self) ?? 0
        info.l3Cache = Sysctl.value("hw.l3cachesize", as: UInt64.self) ?? 0
        info.cacheLineSize = Sysctl.value("hw.cachelinesize", as: UInt64.self) ?? 0
        info.cpuFrequency = Sysctl.value("hw.cpufrequency", as: UInt64.self) ?? 0
        info.memoryTotal = Sysctl.value("hw.memsize", as: UInt64.self) ?? 0
        info.isAppleSilicon = info.performanceCores > 0 && info.cpuFrequency == 0

        // 没有 perflevel 的机器（Intel）退化成全部当作性能核
        if info.performanceCores == 0 { info.performanceCores = info.physicalCores }

        let os = ProcessInfo.processInfo.operatingSystemVersion
        info.osVersion = "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        // 不能用 ProcessInfo.hostName：它走 NSHost 的阻塞式反向 DNS，网络不通时会把主线程挂死。
        info.hostName = Redaction.hostName(Sysctl.string("kern.hostname") ?? "")

        return info
    }

    /// Apple Silicon 的统一内存没有插槽，这里存一个 key，展示时再本地化。
    static let solderedMemoryKey = "板载（统一内存，无插槽）"

    /// 机型名与内存规格来自 system_profiler，比较慢，启动后异步补齐。
    mutating func enrichFromSystemProfiler() {
        if let hardware = Self.runSystemProfiler("SPHardwareDataType") {
            modelName = hardware["Model Name"] ?? modelName
        }
        if let memory = Self.runSystemProfiler("SPMemoryDataType") {
            memoryType = memory["Type"] ?? ""
            memoryVendor = memory["Manufacturer"] ?? ""
        }
        if memorySlots.isEmpty {
            memorySlots = isAppleSilicon ? SystemInfo.solderedMemoryKey : "—"
        }
    }

    private static func runSystemProfiler(_ dataType: String) -> [String: String]? {
        guard let output = Shell.run("/usr/sbin/system_profiler", [dataType], timeout: 8) else { return nil }
        var result: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            result[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1].trimmingCharacters(in: .whitespaces)
        }
        return result.isEmpty ? nil : result
    }
}

/// 同步执行一个命令并取回 stdout。只用于取静态信息与 launchctl 列表。
enum Shell {
    static func run(_ path: String, _ arguments: [String], timeout: TimeInterval = 10) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do { try process.run() } catch { return nil }

        // 先读完管道再 wait，避免大输出把管道写满导致子进程阻塞
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            usleep(20_000)
        }
        if process.isRunning { process.terminate() }
        return String(decoding: data, as: UTF8.self)
    }
}
