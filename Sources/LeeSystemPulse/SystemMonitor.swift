import Foundation
import Observation
import ServiceManagement
import SwiftUI

enum UsageLevel: Equatable {
    case normal
    case warning
    case critical
    case severe

    init(_ value: Double) {
        if value >= 0.95 {
            self = .severe
        } else if value >= 0.90 {
            self = .critical
        } else if value >= 0.80 {
            self = .warning
        } else {
            self = .normal
        }
    }

    var color: Color {
        switch self {
        case .normal: Color(red: 0.20, green: 0.78, blue: 0.35)
        case .warning: .orange
        case .critical: .red
        case .severe: Color(red: 0.55, green: 0.02, blue: 0.04)
        }
    }
}

enum MemoryPressure: Equatable {
    case normal
    case light
    case moderate
    case heavy

    var label: String {
        switch self {
        case .normal: "正常"
        case .light: "轻度压力"
        case .moderate: "中度压力"
        case .heavy: "严重压力"
        }
    }

    var color: Color {
        switch self {
        case .normal: Color(red: 0.20, green: 0.78, blue: 0.35)
        case .light: .orange
        case .moderate: .red
        case .heavy: Color(red: 0.55, green: 0.02, blue: 0.04)
        }
    }

    var systemImage: String {
        switch self {
        case .normal: "checkmark.circle.fill"
        case .light: "exclamationmark.triangle.fill"
        case .moderate: "exclamationmark.octagon.fill"
        case .heavy: "xmark.octagon.fill"
        }
    }
}

@MainActor
@Observable
final class SystemMonitor {
    var cpu = 0.0
    var cpuSystem = 0.0
    var cpuUser = 0.0
    var cpuIdle = 1.0
    var memory = 0.0
    var usedBytes: UInt64 = 0
    var cachedBytes: UInt64 = 0
    var availableBytes: UInt64 = 0
    var totalBytes: UInt64 = 0
    var activeBytes: UInt64 = 0
    var wiredBytes: UInt64 = 0
    var compressedBytes: UInt64 = 0
    var purgeableBytes: UInt64 = 0
    var swapUsedBytes: UInt64 = 0
    var swapTotalBytes: UInt64 = 0
    var pageinsPerSec: Double = 0
    var swapinsPerSec: Double = 0
    var topProcesses: [ProcessMemoryInfo] = []
    var cpuHistory = Array(repeating: 0.0, count: 60)
    var memoryHistory = Array(repeating: 0.0, count: 60)
    var refreshInterval = 2.0 {
        didSet {
            UserDefaults.standard.set(refreshInterval, forKey: "refreshInterval")
            restartTimer()
        }
    }
    var launchAtLogin = false
    var launchAtLoginError: String?

    private let reader = SystemMetricsReader()
    private var timer: Timer?
    private var processTimer: Timer?
    private var sampleCount = 0

    init() {
        let savedInterval = UserDefaults.standard.double(forKey: "refreshInterval")
        if savedInterval > 0 {
            refreshInterval = savedInterval
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
        sample()
        restartTimer()
        restartProcessTimer()
    }

    var overallLevel: UsageLevel {
        let cpuLevel = UsageLevel(cpu)
        let memoryLevel = UsageLevel(memory)
        if cpuLevel == .severe || memoryLevel == .severe { return .severe }
        if cpuLevel == .critical || memoryLevel == .critical { return .critical }
        if cpuLevel == .warning || memoryLevel == .warning { return .warning }
        return .normal
    }

    var statusText: String {
        switch overallLevel {
        case .normal: "运行正常"
        case .warning: "负载较高"
        case .critical: "红色警告"
        case .severe: "严重拥塞"
        }
    }

    var memoryPressure: MemoryPressure {
        let usedRatio = totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0
        let compressedRatio = usedBytes > 0 ? Double(compressedBytes) / Double(usedBytes) : 0
        let swapRatio = swapTotalBytes > 0 ? Double(swapUsedBytes) / Double(swapTotalBytes) : 0
        let wiredRatio = totalBytes > 0 ? Double(wiredBytes) / Double(totalBytes) : 0

        // Scoring: each factor contributes to a 0...1 pressure score
        var score = 0.0
        score += min(usedRatio * 0.4, 0.4)            // memory usage: 0...0.4
        score += min(compressedRatio * 0.2, 0.2)       // compression ratio: 0...0.2
        score += min(swapRatio * 0.25, 0.25)           // swap usage: 0...0.25
        score += min(wiredRatio * 0.15, 0.15)          // wired ratio: 0...0.15

        if score >= 0.75 { return .heavy }
        if score >= 0.55 { return .moderate }
        if score >= 0.35 { return .light }
        return .normal
    }

    var optimizationTips: [String] {
        var tips: [String] = []

        if swapUsedBytes > 1024 * 1024 * 512 {
            let swapStr = bytes(swapUsedBytes)
            tips.append("Swap 使用较高 (\(swapStr))，建议关闭不常用的应用以释放内存")
        }

        if compressedBytes > totalBytes / 4 {
            tips.append("内存压缩占用较大，系统正在积极压缩内存，建议减少同时运行的应用")
        }

        if wiredBytes > totalBytes / 2 {
            tips.append("常驻内存（Wired）超过总内存一半，可能由内核扩展或驱动引起")
        }

        if pageinsPerSec > 100 {
            let rate = Int(pageinsPerSec)
            tips.append("Page-ins 速率较高 (\(rate)/秒)，磁盘读取频繁")
        }

        if swapinsPerSec > 10 {
            let rate = Int(swapinsPerSec)
            tips.append("Swap-ins 活跃 (\(rate)/秒)，物理内存不足导致频繁使用 Swap")
        }

        let heavyProcesses = topProcesses.filter { $0.residentBytes > 1024 * 1024 * 1024 }
        if !heavyProcesses.isEmpty {
            let names = heavyProcesses.prefix(3).map { $0.name }.joined(separator: "、")
            tips.append("以下进程内存占用超过 1GB：\(names)")
        }

        if tips.isEmpty && memoryPressure != .normal {
            tips.append("内存使用偏高，建议定期检查并关闭不需要的应用")
        }

        return tips
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            launchAtLoginError = nil
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            launchAtLoginError = "无法更新开机启动设置：\(error.localizedDescription)"
        }
    }

    func sample() {
        if let cpuSample = reader.readCPU() {
            cpu = cpuSample.total
            cpuSystem = cpuSample.system
            cpuUser = cpuSample.user
            cpuIdle = cpuSample.idle
            append(cpu, to: &cpuHistory)
        }

        if let memorySample = reader.readMemory() {
            memory = memorySample.usage
            usedBytes = memorySample.usedBytes
            cachedBytes = memorySample.cachedBytes
            availableBytes = memorySample.availableBytes
            totalBytes = memorySample.totalBytes
            activeBytes = memorySample.activeBytes
            wiredBytes = memorySample.wiredBytes
            compressedBytes = memorySample.compressedBytes
            purgeableBytes = memorySample.purgeableBytes
            append(memory, to: &memoryHistory)
        }

        if let swap = reader.readSwap() {
            swapUsedBytes = swap.usedBytes
            swapTotalBytes = swap.totalBytes
        }

        if let ioRates = reader.readMemoryIORates() {
            pageinsPerSec = ioRates.pageinsPerSec
            swapinsPerSec = ioRates.swapinsPerSec
        }

        sampleCount += 1
    }

    private func refreshProcesses() {
        let processes = reader.readTopProcesses(count: 8)
        self.topProcesses = processes
    }

    private func restartTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sample()
            }
        }
        timer?.tolerance = refreshInterval * 0.1
    }

    private func restartProcessTimer() {
        processTimer?.invalidate()
        processTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshProcesses()
            }
        }
        processTimer?.tolerance = 0.5
        // Initial load
        refreshProcesses()
    }

    private func append(_ value: Double, to history: inout [Double]) {
        history.append(value)
        if history.count > 60 {
            history.removeFirst(history.count - 60)
        }
    }
}
