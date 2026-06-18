import Darwin
import Foundation

struct CPUSample {
    let total: Double
    let system: Double
    let user: Double
    let idle: Double
}

struct MemorySample {
    let usage: Double
    let usedBytes: UInt64
    let cachedBytes: UInt64
    let availableBytes: UInt64
    let totalBytes: UInt64
    let activeBytes: UInt64
    let wiredBytes: UInt64
    let compressedBytes: UInt64
    let purgeableBytes: UInt64
}

struct SwapInfo {
    let usedBytes: UInt64
    let totalBytes: UInt64
}

struct ProcessMemoryInfo: Identifiable {
    let id: pid_t
    var pid: pid_t { id }
    let name: String
    let residentBytes: UInt64
}

struct MemoryIORates {
    let pageinsPerSec: Double
    let swapinsPerSec: Double
}

final class SystemMetricsReader {
    private var previousTicks: [UInt64]?
    private var previousMemoryCounters: MemoryCounters?
    private var previousSampleTime: TimeInterval?

    private struct MemoryCounters {
        let pageins: UInt64
        let swapins: UInt64
    }

    func readCPU() -> CPUSample? {
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0
        var cpuCount: natural_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &cpuInfo,
            &cpuInfoCount
        )

        guard result == KERN_SUCCESS, let cpuInfo else { return nil }
        defer {
            let size = vm_size_t(cpuInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), size)
        }

        var totals = [UInt64](repeating: 0, count: Int(CPU_STATE_MAX))
        for cpu in 0..<Int(cpuCount) {
            let base = cpu * Int(CPU_STATE_MAX)
            for state in 0..<Int(CPU_STATE_MAX) {
                totals[state] += UInt64(cpuInfo[base + state])
            }
        }

        guard let previousTicks else {
            self.previousTicks = totals
            return nil
        }
        self.previousTicks = totals

        let deltas = zip(totals, previousTicks).map { current, previous in
            current >= previous ? current - previous : 0
        }
        let all = Double(deltas.reduce(0, +))
        guard all > 0 else { return nil }

        let user = Double(deltas[Int(CPU_STATE_USER)]) / all
        let system = Double(deltas[Int(CPU_STATE_SYSTEM)]) / all
        let nice = Double(deltas[Int(CPU_STATE_NICE)]) / all
        let idle = Double(deltas[Int(CPU_STATE_IDLE)]) / all

        return CPUSample(
            total: min(1, user + system + nice),
            system: system,
            user: user + nice,
            idle: idle
        )
    }

    func readMemory() -> MemorySample? {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )

        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        var systemPageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &systemPageSize) == KERN_SUCCESS else {
            return nil
        }
        let pageSize = UInt64(systemPageSize)
        let inactive = UInt64(statistics.inactive_count) * pageSize
        let speculative = UInt64(statistics.speculative_count) * pageSize
        let free = UInt64(statistics.free_count) * pageSize
        let active = UInt64(statistics.active_count) * pageSize
        let wired = UInt64(statistics.wire_count) * pageSize
        let compressed = UInt64(statistics.compressor_page_count) * pageSize
        let purgeable = UInt64(statistics.purgeable_count) * pageSize

        let total = ProcessInfo.processInfo.physicalMemory
        let cached = min(total, inactive + speculative)
        let available = min(total, free + cached)
        let used = total - available

        // Store counters for delta calculation
        let currentTime = ProcessInfo.processInfo.systemUptime
        let currentCounters = MemoryCounters(
            pageins: statistics.pageins,
            swapins: statistics.swapins
        )
        self.previousMemoryCounters = currentCounters
        self.previousSampleTime = currentTime

        return MemorySample(
            usage: total > 0 ? Double(used) / Double(total) : 0,
            usedBytes: used,
            cachedBytes: cached,
            availableBytes: available,
            totalBytes: total,
            activeBytes: active,
            wiredBytes: wired,
            compressedBytes: compressed,
            purgeableBytes: purgeable
        )
    }

    func readSwap() -> SwapInfo? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        let result = sysctlbyname("vm.swapusage", &usage, &size, nil, 0)
        guard result == 0 else { return nil }
        return SwapInfo(
            usedBytes: usage.xsu_used,
            totalBytes: usage.xsu_total
        )
    }

    func readMemoryIORates() -> MemoryIORates? {
        guard let prev = previousMemoryCounters, let prevTime = previousSampleTime else {
            return nil
        }

        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let currentTime = ProcessInfo.processInfo.systemUptime
        let elapsed = currentTime - prevTime
        guard elapsed > 0 else { return nil }

        let pageinsDelta = statistics.pageins >= prev.pageins
            ? Double(statistics.pageins - prev.pageins) / elapsed
            : 0
        let swapinsDelta = statistics.swapins >= prev.swapins
            ? Double(statistics.swapins - prev.swapins) / elapsed
            : 0

        return MemoryIORates(
            pageinsPerSec: pageinsDelta,
            swapinsPerSec: swapinsDelta
        )
    }

    func readTopProcesses(count: Int = 8) -> [ProcessMemoryInfo] {
        let pidCount = proc_listallpids(nil, 0)
        guard pidCount > 0 else { return [] }

        let bufferSize = Int(pidCount) * MemoryLayout<pid_t>.size
        var pids = [pid_t](repeating: 0, count: Int(pidCount))
        let actualCount = proc_listallpids(&pids, Int32(bufferSize))
        guard actualCount > 0 else { return [] }

        var results: [ProcessMemoryInfo] = []
        results.reserveCapacity(Int(actualCount))

        for i in 0..<Int(actualCount) {
            let pid = pids[i]
            guard pid > 0 else { continue }

            var info = proc_taskallinfo()
            let infoSize = Int32(MemoryLayout<proc_taskallinfo>.size)
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, pointer, infoSize)
            }
            guard result == infoSize else { continue }

            let resident = UInt64(info.ptinfo.pti_resident_size)
            guard resident > 0 else { continue }

            let name = withUnsafePointer(to: &info.pbsd.pbi_comm) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN)) { cPointer in
                    String(cString: cPointer)
                }
            }

            let displayName = name.isEmpty ? "PID \(pid)" : name
            results.append(ProcessMemoryInfo(
                id: pid,
                name: displayName,
                residentBytes: resident
            ))
        }

        return results
            .sorted { $0.residentBytes > $1.residentBytes }
            .prefix(count)
            .map { $0 }
    }
}
