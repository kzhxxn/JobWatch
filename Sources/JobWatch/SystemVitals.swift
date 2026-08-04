import Foundation
import Darwin

/// 시스템 자원 스냅샷 (0~1 비율). 잡 관측 보조용 — CPU/메모리/디스크만.
struct SystemVitals: Sendable {
    var cpu: Double = 0
    var mem: Double = 0
    var diskUsed: Int64 = 0
    var diskTotal: Int64 = 0
    var diskFraction: Double { diskTotal > 0 ? Double(diskUsed) / Double(diskTotal) : 0 }
}

/// CPU는 델타 샘플링이 필요해 이전 tick을 보관. 1초마다 sample() 호출.
final class SystemSampler: @unchecked Sendable {
    private var prevUsed: Double = 0
    private var prevTotal: Double = 0

    func sample() -> SystemVitals {
        var v = SystemVitals()
        v.cpu = cpuUsage()
        v.mem = memUsage()
        let d = DiskInfo.current()
        v.diskUsed = d.usedBytes
        v.diskTotal = d.totalBytes
        return v
    }

    private func cpuUsage() -> Double {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let res = withUnsafeMutablePointer(to: &load) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard res == KERN_SUCCESS else { return 0 }
        let user = Double(load.cpu_ticks.0)
        let system = Double(load.cpu_ticks.1)
        let idle = Double(load.cpu_ticks.2)
        let nice = Double(load.cpu_ticks.3)
        let used = user + system + nice
        let total = used + idle
        defer { prevUsed = used; prevTotal = total }
        let dUsed = used - prevUsed
        let dTotal = total - prevTotal
        return dTotal > 0 ? max(0, min(1, dUsed / dTotal)) : 0
    }

    private func memUsage() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let res = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard res == KERN_SUCCESS else { return 0 }
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let page = Double(pageSize)
        let usedBytes = (Double(stats.active_count) + Double(stats.wire_count)
                         + Double(stats.compressor_page_count)) * page
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        return total > 0 ? min(1, usedBytes / total) : 0
    }
}
