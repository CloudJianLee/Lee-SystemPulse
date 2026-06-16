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

    init() {
        let savedInterval = UserDefaults.standard.double(forKey: "refreshInterval")
        if savedInterval > 0 {
            refreshInterval = savedInterval
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
        sample()
        restartTimer()
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
            append(memory, to: &memoryHistory)
        }
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

    private func append(_ value: Double, to history: inout [Double]) {
        history.append(value)
        if history.count > 60 {
            history.removeFirst(history.count - 60)
        }
    }
}
