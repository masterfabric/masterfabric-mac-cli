import Darwin
import Foundation

public enum NetworkService {
    private static var previous: [String: (inBytes: UInt64, outBytes: UInt64, at: Date)] = [:]
    private static let lock = NSLock()

    public static func current() -> NetworkInfo {
        var interfaces: [NetworkInterfaceStats] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else {
            return NetworkInfo(interfaces: [])
        }
        defer { freeifaddrs(ifaddr) }

        var seen = Set<String>()
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        let now = Date()

        while let current = ptr {
            defer { ptr = current.pointee.ifa_next }
            let name = String(cString: current.pointee.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("awdl") || name.hasPrefix("bridge") || name.hasPrefix("pdp_ip") || name.hasPrefix("utun") else {
                continue
            }
            guard current.pointee.ifa_addr.pointee.sa_family == UInt8(AF_LINK) else { continue }
            guard !seen.contains(name) else { continue }
            seen.insert(name)

            let data = unsafeBitCast(current.pointee.ifa_data, to: UnsafeMutablePointer<if_data>?.self)
            guard let data else { continue }
            let bytesIn = UInt64(data.pointee.ifi_ibytes)
            let bytesOut = UInt64(data.pointee.ifi_obytes)

            var inRate: Double?
            var outRate: Double?
            lock.lock()
            if let prev = previous[name] {
                let dt = now.timeIntervalSince(prev.at)
                if dt > 0.2 {
                    inRate = Double(bytesIn &- prev.inBytes) / dt
                    outRate = Double(bytesOut &- prev.outBytes) / dt
                }
            }
            previous[name] = (bytesIn, bytesOut, now)
            lock.unlock()

            interfaces.append(
                NetworkInterfaceStats(
                    name: name,
                    bytesIn: bytesIn,
                    bytesOut: bytesOut,
                    bytesInPerSec: inRate,
                    bytesOutPerSec: outRate
                )
            )
        }

        interfaces.sort { $0.name < $1.name }
        return NetworkInfo(interfaces: interfaces)
    }
}

public enum CPULoadService {
    private static var previousTicks: [UInt32] = []
    private static let lock = NSLock()
    /// One-shot baseline so CLI / first menu-bar tick is a real interval, not 0%.
    private static var didCalibrate = false

    public static func current() -> CPULoadInfo {
        lock.lock()
        let needsCalibrate = !didCalibrate || previousTicks.isEmpty
        lock.unlock()

        if needsCalibrate {
            _ = sampleOnce()
            Thread.sleep(forTimeInterval: 0.18)
            lock.lock()
            didCalibrate = true
            lock.unlock()
        }

        return sampleOnce()
    }

    private static func sampleOnce() -> CPULoadInfo {
        var cpuCount: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0

        let kr = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &cpuInfo,
            &cpuInfoCount
        )

        guard kr == KERN_SUCCESS, let info = cpuInfo, cpuCount > 0 else {
            return CPULoadInfo(
                overallPercent: 0,
                perCorePercent: [],
                userPercent: 0,
                systemPercent: 0,
                idlePercent: 100
            )
        }

        defer {
            let size = vm_size_t(cpuInfoCount) * vm_size_t(MemoryLayout<integer_t>.size)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)
        }

        let stride = Int(CPU_STATE_MAX)
        let coreCount = Int(cpuCount)
        var nowTicks = [UInt32](repeating: 0, count: coreCount * stride)
        for i in 0..<(coreCount * stride) {
            nowTicks[i] = UInt32(bitPattern: info[i])
        }

        lock.lock()
        defer { lock.unlock() }

        var perCore: [Double] = []
        var totalUser: Double = 0
        var totalSystem: Double = 0
        var totalIdle: Double = 0
        var totalNice: Double = 0
        let prev = previousTicks
        let hasPrev = prev.count == nowTicks.count && !prev.isEmpty

        for i in 0..<coreCount {
            let base = i * stride
            let user = nowTicks[base + Int(CPU_STATE_USER)]
            let system = nowTicks[base + Int(CPU_STATE_SYSTEM)]
            let idle = nowTicks[base + Int(CPU_STATE_IDLE)]
            let nice = nowTicks[base + Int(CPU_STATE_NICE)]

            if hasPrev {
                let dUser = tickDelta(user, prev[base + Int(CPU_STATE_USER)])
                let dSystem = tickDelta(system, prev[base + Int(CPU_STATE_SYSTEM)])
                let dIdle = tickDelta(idle, prev[base + Int(CPU_STATE_IDLE)])
                let dNice = tickDelta(nice, prev[base + Int(CPU_STATE_NICE)])
                let sum = dUser + dSystem + dIdle + dNice
                let busy = sum > 0 ? (dUser + dSystem + dNice) / sum * 100 : 0
                perCore.append(round1(busy))
                totalUser += dUser
                totalSystem += dSystem
                totalIdle += dIdle
                totalNice += dNice
            } else {
                perCore.append(0)
            }
        }

        previousTicks = nowTicks

        let total = totalUser + totalSystem + totalIdle + totalNice
        let overall = total > 0 ? (totalUser + totalSystem + totalNice) / total * 100 : 0
        let userPct = total > 0 ? totalUser / total * 100 : 0
        let sysPct = total > 0 ? totalSystem / total * 100 : 0
        let idlePct = total > 0 ? totalIdle / total * 100 : 100

        let pCount = sysctlInt("hw.perflevel0.logicalcpu") ?? 0
        let eCount = sysctlInt("hw.perflevel1.logicalcpu") ?? 0
        let clusters = clusterAverages(perCore: perCore, pCount: pCount, eCount: eCount)

        return CPULoadInfo(
            overallPercent: round1(overall),
            perCorePercent: perCore,
            userPercent: round1(userPct),
            systemPercent: round1(sysPct),
            idlePercent: round1(idlePct),
            performancePercent: clusters.p.map(round1),
            efficiencyPercent: clusters.e.map(round1),
            performanceCoreCount: pCount,
            efficiencyCoreCount: eCount
        )
    }

    /// Apple Silicon lists E-cores first, then P-cores, in `host_processor_info`.
    private static func clusterAverages(perCore: [Double], pCount: Int, eCount: Int) -> (p: Double?, e: Double?) {
        guard pCount > 0, eCount > 0, perCore.count == pCount + eCount else {
            return (nil, nil)
        }
        let eSlice = perCore.prefix(eCount)
        let pSlice = perCore.suffix(pCount)
        let eAvg = eSlice.reduce(0, +) / Double(eCount)
        let pAvg = pSlice.reduce(0, +) / Double(pCount)
        return (pAvg, eAvg)
    }

    /// 32-bit Mach tick counters wrap; wrapping subtract keeps long-uptime samples valid.
    private static func tickDelta(_ now: UInt32, _ prev: UInt32) -> Double {
        Double(now &- prev)
    }

    private static func round1(_ v: Double) -> Double {
        (v * 10).rounded() / 10
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }
}
