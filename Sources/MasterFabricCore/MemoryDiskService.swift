import Darwin
import Foundation

public enum MemoryService {
    public static func current() -> MemoryInfo {
        let total = ProcessInfo.processInfo.physicalMemory
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var hostInfo = vm_statistics64_data_t()

        let result = withUnsafeMutablePointer(to: &hostInfo) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &size)
            }
        }

        guard result == KERN_SUCCESS else {
            return MemoryInfo(
                totalBytes: total,
                usedBytes: 0,
                freeBytes: total,
                wiredBytes: 0,
                compressedBytes: 0,
                swapUsedBytes: 0,
                pressure: "unknown"
            )
        }

        let pageSize = UInt64(vm_kernel_page_size)
        let free = UInt64(hostInfo.free_count) * pageSize
        let active = UInt64(hostInfo.active_count) * pageSize
        let inactive = UInt64(hostInfo.inactive_count) * pageSize
        let wired = UInt64(hostInfo.wire_count) * pageSize
        let compressed = UInt64(hostInfo.compressor_page_count) * pageSize
        let speculative = UInt64(hostInfo.speculative_count) * pageSize
        let used = active + inactive + wired + compressed + speculative
        let swap = swapUsed()

        let pressure: String
        let usedPct = Double(used) / Double(total) * 100
        if usedPct > 85 || compressed > total / 8 {
            pressure = "high"
        } else if usedPct > 70 {
            pressure = "medium"
        } else {
            pressure = "normal"
        }

        return MemoryInfo(
            totalBytes: total,
            usedBytes: min(used, total),
            freeBytes: free,
            wiredBytes: wired,
            compressedBytes: compressed,
            swapUsedBytes: swap,
            pressure: pressure
        )
    }

    private static func swapUsed() -> UInt64 {
        var xsw = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        let err = sysctlbyname("vm.swapusage", &xsw, &size, nil, 0)
        guard err == 0 else { return 0 }
        return UInt64(xsw.xsu_used)
    }
}

public enum DiskService {
    public static func current(path: String = "/") -> DiskInfo {
        do {
            let values = try URL(fileURLWithPath: path).resourceValues(forKeys: [
                .volumeNameKey,
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeAvailableCapacityKey,
            ])
            let total = UInt64(values.volumeTotalCapacity ?? 0)
            let free = UInt64(
                values.volumeAvailableCapacityForImportantUsage
                    ?? Int64(values.volumeAvailableCapacity ?? 0)
            )
            let used = total > free ? total - free : 0
            return DiskInfo(
                path: path,
                totalBytes: total,
                freeBytes: free,
                usedBytes: used,
                volumeName: values.volumeName ?? ""
            )
        } catch {
            return DiskInfo(path: path, totalBytes: 0, freeBytes: 0, usedBytes: 0)
        }
    }
}
