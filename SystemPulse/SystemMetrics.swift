import Foundation
import Darwin

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
}

final class SystemMetricsReader {
    private var previousTicks: [UInt64]?

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

        let total = ProcessInfo.processInfo.physicalMemory
        let cached = min(total, inactive + speculative)
        let available = min(total, free + cached)
        let used = total - available

        return MemorySample(
            usage: total > 0 ? Double(used) / Double(total) : 0,
            usedBytes: used,
            cachedBytes: cached,
            availableBytes: available,
            totalBytes: total
        )
    }
}
