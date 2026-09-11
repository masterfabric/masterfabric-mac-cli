import Darwin
import Foundation

public enum PowerService {
    public static func current() -> PowerInfo {
        let state: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: state = "nominal"
        case .fair: state = "fair"
        case .serious: state = "serious"
        case .critical: state = "critical"
        @unknown default: state = "unknown"
        }
        return PowerInfo(
            thermalState: state,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }
}

public enum ProcessService {
    public static func top(limit: Int = 10) -> [ProcessCPUInfo] {
        let samples = samplePS()
        let sorted = samples.values.sorted { $0.cpu > $1.cpu }
        return Array(sorted.prefix(max(1, limit))).map {
            ProcessCPUInfo(pid: $0.pid, name: $0.name, cpuPercent: $0.cpu, memoryBytes: $0.mem)
        }
    }

    private struct Sample {
        var pid: Int32
        var name: String
        var cpu: Double
        var mem: UInt64
    }

    private static func samplePS() -> [Int32: Sample] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-Aro", "pid,%cpu,rss,comm"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            return [:]
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return [:] }

        var map: [Int32: Sample] = [:]
        for (i, line) in text.split(separator: "\n").enumerated() {
            if i == 0 { continue }
            let parts = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard parts.count >= 4, let pid = Int32(parts[0]), let cpu = Double(parts[1]),
                  let rssKB = UInt64(parts[2]) else { continue }
            let name = (parts[3...].joined(separator: " ") as NSString).lastPathComponent
            map[pid] = Sample(pid: pid, name: name, cpu: cpu, mem: rssKB * 1024)
        }
        return map
    }
}

public enum HistoryStore {
    private static let maxAge: TimeInterval = 3600
    private static let lock = NSLock()

    public static func record(now: Date = Date()) {
        let status = StatusService.current()
        let load = CPULoadService.current()
        let battery = BatteryService.current()
        lock.lock()
        defer { lock.unlock() }
        var samples = loadUnlocked()
        samples.append(
            HistorySample(
                timestamp: now,
                cpuCelsius: status.temperature.cpuCelsius,
                gpuCelsius: status.temperature.gpuCelsius,
                fanRPM: status.fans.first?.rpm,
                cpuLoadPercent: load.overallPercent,
                batteryPercent: battery.percent
            )
        )
        let cutoff = now.addingTimeInterval(-maxAge)
        samples = samples.filter { $0.timestamp >= cutoff }
        saveUnlocked(samples)
    }

    public static func snapshot() -> HistorySnapshot {
        lock.lock()
        defer { lock.unlock() }
        let samples = loadUnlocked()
        let cpuValues = samples.compactMap(\.cpuCelsius)
        let loadValues = samples.compactMap(\.cpuLoadPercent)
        return HistorySnapshot(
            samples: samples,
            cpuSparkline: sparkline(cpuValues),
            loadSparkline: sparkline(loadValues)
        )
    }

    public static func sparkline(_ values: [Double]) -> String {
        guard !values.isEmpty else { return "—" }
        let blocks = Array("▁▂▃▄▅▆▇█")
        let minV = values.min() ?? 0
        let maxV = values.max() ?? 1
        let span = max(maxV - minV, 1)
        // Downsample to ~40 chars
        let step = max(1, values.count / 40)
        var out = ""
        var i = 0
        while i < values.count {
            let v = values[i]
            let idx = Int(((v - minV) / span) * Double(blocks.count - 1))
            out.append(blocks[min(max(idx, 0), blocks.count - 1)])
            i += step
        }
        return out
    }

    private static func loadUnlocked() -> [HistorySample] {
        ConfigStore.configDirectory.createIfNeeded()
        guard let data = try? Data(contentsOf: ConfigStore.historyURL) else { return [] }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode([HistorySample].self, from: data)) ?? []
    }

    private static func saveUnlocked(_ samples: [HistorySample]) {
        ConfigStore.configDirectory.createIfNeeded()
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(samples) else { return }
        try? data.write(to: ConfigStore.historyURL, options: .atomic)
    }
}

private extension URL {
    func createIfNeeded() {
        try? FileManager.default.createDirectory(at: self, withIntermediateDirectories: true)
    }
}
