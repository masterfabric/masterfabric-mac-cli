import Foundation

public enum ThermalService {
    /// Fallback SMC keys when discovery finds nothing (Apple Silicon + Intel).
    private static let cpuKeys = [
        "Te05", "Te0S", "Te09", "Te0H", "Te0L", "Te0P",
        "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e",
        "Tp0G", "Tp0T", "Tp0H", "Tp0L", "Tp0P", "Tp0X",
        "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E",
        "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E",
        "TC0P", "TC0E", "TC0F", "TCAD", "TC0H", "TC0c", "TC0C",
    ]
    private static let gpuKeys = [
        "Tg0D", "Tg0L", "Tg0P", "Tg05", "Tg0H", "Tg1H",
        "Tg0G", "Tg0K", "Tg0d", "Tg0e", "Tg0j", "Tg0k",
        "Tg1U", "Tg1k",
        "TG0P", "TGDD", "TG0D", "TCGC", "Tg0F",
    ]

    private static let cacheLock = NSLock()
    private static var cachedCPUKeys: [String]?
    private static var cachedGPUKeys: [String]?

    public static func read() -> TemperatureReading {
        var sensors: [String: Double] = [:]

        let hid = HIDThermalReader.readSensors()
        for (name, value) in hid where isPlausibleDieTemp(value) {
            sensors[name] = round1(value)
        }

        if let smc = try? SMCClient() {
            let keys = resolvedKeys(smc)
            for key in keys.cpu {
                if let v = smc.readNumber(key), isPlausibleDieTemp(v) {
                    sensors["SMC:\(key)"] = round1(v)
                }
            }
            for key in keys.gpu {
                if let v = smc.readNumber(key), isPlausibleDieTemp(v) {
                    sensors["SMC:\(key)"] = round1(v)
                }
            }
        }

        var cpu = pickSMC(from: sensors, prefixes: ["SMC:Tp", "SMC:Te", "SMC:Tf"])
            ?? pick(from: sensors, matching: ["cpu", "soc", "p-core", "e-core", "ane", "mtr", "die", "package"])
        let gpu = pickSMC(from: sensors, prefixes: ["SMC:Tg", "SMC:TG"])
            ?? pick(from: sensors, matching: ["gpu", "graphics"])

        if let gpuVal = gpu, let cpuVal = cpu, cpuVal + 15 < gpuVal {
            cpu = pickSMC(from: sensors, prefixes: ["SMC:Tp", "SMC:Te", "SMC:Tf"]) ?? gpu
        }

        return TemperatureReading(cpuCelsius: cpu, gpuCelsius: gpu, sensors: sensors)
    }

    /// Idle SoC is typically mid-30s+. 2–10°C on M-series is an unused/delta SMC channel.
    private static func isPlausibleDieTemp(_ v: Double) -> Bool {
        v.isFinite && v >= 25 && v < 115
    }

    private static func resolvedKeys(_ smc: SMCClient) -> (cpu: [String], gpu: [String]) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cpu = cachedCPUKeys, let gpu = cachedGPUKeys {
            return (cpu, gpu)
        }

        var cpu: [String] = []
        var gpu: [String] = []
        for key in smc.allKeys() {
            if key.hasPrefix("Te") || key.hasPrefix("Tp") || key.hasPrefix("Tf") {
                if let v = smc.readNumber(key), isPlausibleDieTemp(v) {
                    cpu.append(key)
                }
            } else if key.hasPrefix("Tg") {
                if let v = smc.readNumber(key), isPlausibleDieTemp(v) {
                    gpu.append(key)
                }
            }
        }
        if cpu.isEmpty { cpu = cpuKeys }
        if gpu.isEmpty { gpu = gpuKeys }
        cachedCPUKeys = cpu
        cachedGPUKeys = gpu
        return (cpu, gpu)
    }

    private static func pickSMC(from sensors: [String: Double], prefixes: [String]) -> Double? {
        let matches = sensors.filter { key, value in
            guard isPlausibleDieTemp(value) else { return false }
            return prefixes.contains { key.hasPrefix($0) }
        }
        return matches.values.max().map(round1)
    }

    private static func pick(from sensors: [String: Double], matching needles: [String]) -> Double? {
        let matches = sensors.filter { key, value in
            guard isPlausibleDieTemp(value) else { return false }
            let lower = key.lowercased()
            return needles.contains { lower.contains($0) }
        }
        return matches.values.max().map(round1)
    }

    private static func round1(_ v: Double) -> Double {
        (v * 10).rounded() / 10
    }
}

public enum FanService {
    public static func roleName(for index: Int) -> String {
        switch index {
        case 0: return "CPU"
        case 1: return "GPU"
        default: return "Fan \(index)"
        }
    }

    public static func displayName(for index: Int) -> String {
        "\(roleName(for: index)) fan"
    }

    public static func read() -> [FanReading] {
        guard let smc = try? SMCClient() else { return [] }

        let count: Int
        if let n = smc.readUInt8("FNum") {
            count = Int(n)
        } else if let n = smc.readNumber("FNum") {
            count = Int(n)
        } else {
            count = 0
        }
        guard count > 0 else { return [] }

        var fans: [FanReading] = []
        for i in 0..<min(count, 10) {
            let rpm = smc.readNumber("F\(i)Ac")
            let minRPM = smc.readNumber("F\(i)Mn")
            let maxRPM = smc.readNumber("F\(i)Mx")
            let modeKey = resolveModeKey(smc, index: i)
            let modeRaw = modeKey.flatMap { smc.readUInt8($0) }
            let target = smc.readNumber("F\(i)Tg")
            fans.append(
                FanReading(
                    index: i,
                    name: displayName(for: i),
                    role: roleName(for: i),
                    rpm: rpm.map { $0.rounded() },
                    minRPM: minRPM,
                    maxRPM: maxRPM,
                    modeRaw: modeRaw,
                    mode: describeMode(modeRaw),
                    targetRPM: target.map { $0.rounded() }
                )
            )
        }
        return fans
    }

    /// Set both fans (typically CPU + GPU) to automatic system control or forced max RPM.
    /// On modern macOS, SMC writes often require administrator privileges (`sudo mf fan …`).
    public static func setMode(_ mode: FanControlMode) -> FanControlResult {
        do {
            let smc = try SMCClient()
            let count = fanCount(smc)
            guard count > 0 else {
                return FanControlResult(ok: false, mode: mode, detail: "No fans reported by SMC (FNum=0)", fans: [])
            }

            var unlocked = false
            var notes: [String] = []
            var needsPrivilege = false
            var writeOK = true

            switch mode {
            case .auto:
                for i in 0..<count {
                    do {
                        try setFanAuto(smc, index: i, notes: &notes)
                    } catch let error as SMCClient.SMCError {
                        writeOK = false
                        if case .notPrivileged = error { needsPrivilege = true }
                    } catch {
                        writeOK = false
                    }
                }
                if !needsPrivilege, smc.readUInt8("Ftst") != nil || smc.keyType("Ftst") != nil {
                    try? smc.writeUInt8("Ftst", 0)
                    notes.append("Ftst=0")
                }
            case .full:
                do {
                    unlocked = try unlockIfNeeded(smc, notes: &notes)
                } catch let error as SMCClient.SMCError {
                    writeOK = false
                    if case .notPrivileged = error { needsPrivilege = true }
                } catch {
                    writeOK = false
                }
                for i in 0..<count {
                    do {
                        try setFanFull(smc, index: i, notes: &notes)
                    } catch let error as SMCClient.SMCError {
                        writeOK = false
                        if case .notPrivileged = error { needsPrivilege = true }
                    } catch {
                        writeOK = false
                    }
                }
            }

            if notes.contains(where: { $0.localizedCaseInsensitiveContains("privileges required") || $0.contains("not privileged") }) {
                needsPrivilege = true
                writeOK = false
            }
            if notes.contains(where: { $0.contains("write failed") }) {
                writeOK = false
            }

            // Brief settle so RPM/mode reads reflect the write.
            Thread.sleep(forTimeInterval: 0.35)
            let fans = read()
            let observedOK = fans.contains { fan in
                switch mode {
                case .auto:
                    return fan.modeRaw == 0 || fan.mode == "auto"
                case .full:
                    if let rpm = fan.rpm, let max = fan.maxRPM, max > 0 {
                        return rpm >= max * 0.85 || fan.modeRaw == 1
                    }
                    return fan.modeRaw == 1
                }
            }

            let ok = writeOK && (mode == .auto ? observedOK || fans.allSatisfy({ $0.modeRaw == 0 }) : observedOK)

            let detail: String
            if needsPrivilege {
                detail = "Administrator privileges required for SMC fan writes. CLI: sudo mf fan \(mode.rawValue) — Menu Bar will prompt. \(notes.joined(separator: "; "))"
            } else if !ok {
                detail = "Fan control incomplete. \(notes.joined(separator: "; "))"
            } else {
                switch mode {
                case .auto:
                    detail = "Fans set to Auto (system thermal). \(notes.joined(separator: "; "))"
                case .full:
                    detail = "Fans set to Full (max RPM). Loud — use Auto when done. \(notes.joined(separator: "; "))"
                }
            }
            return FanControlResult(
                ok: ok,
                mode: mode,
                detail: detail,
                fans: fans,
                unlockedWithFtst: unlocked,
                needsPrivilege: needsPrivilege
            )
        } catch {
            let needsPrivilege: Bool
            if let smcError = error as? SMCClient.SMCError, case .notPrivileged = smcError {
                needsPrivilege = true
            } else {
                needsPrivilege = false
            }
            return FanControlResult(
                ok: false,
                mode: mode,
                detail: "Fan control failed: \(error.localizedDescription)",
                fans: read(),
                needsPrivilege: needsPrivilege
            )
        }
    }

    /// True when any fan is in manual/full (modeRaw == 1) or spinning near max after a full request.
    public static func isFullMode(_ fans: [FanReading] = read()) -> Bool {
        guard !fans.isEmpty else { return false }
        if fans.contains(where: { $0.modeRaw == 1 || $0.mode == "manual" }) {
            return true
        }
        // Fallback: all fans near max RPM (elevated write may stick target before mode reads back).
        let nearMax = fans.filter { fan in
            guard let rpm = fan.rpm, let max = fan.maxRPM, max > 0 else { return false }
            return rpm >= max * 0.85
        }
        return nearMax.count == fans.count && !nearMax.isEmpty
    }

    /// Resolve installed `mf` binary (menu bar elevation / helpers).
    public static func resolveMFExecutable() -> String {
        let args = ProcessInfo.processInfo.arguments
        if let first = args.first {
            let name = (first as NSString).lastPathComponent
            if name == "mf", FileManager.default.isExecutableFile(atPath: first) {
                return first
            }
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var candidates = [
            "\(home)/.local/bin/mf",
            "/usr/local/bin/mf",
            "/opt/homebrew/bin/mf",
            FanDaemon.helperBinary,
        ]
        // Sibling of menu bar binary / .app Contents/MacOS
        if let first = args.first {
            let dir = (first as NSString).deletingLastPathComponent
            candidates.insert((dir as NSString).appendingPathComponent("mf"), at: 0)
            let parent = (dir as NSString).deletingLastPathComponent // Contents
            let appParent = (parent as NSString).deletingLastPathComponent // .app
            let localBin = ((appParent as NSString).deletingLastPathComponent as NSString)
                .appendingPathComponent("bin/mf")
            candidates.insert(localBin, at: 0)
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? candidates[0]
    }

    // MARK: - Internals

    private static func fanCount(_ smc: SMCClient) -> Int {
        if let n = smc.readUInt8("FNum") { return Int(n) }
        if let n = smc.readNumber("FNum") { return Int(n) }
        return 0
    }

    private static func resolveModeKey(_ smc: SMCClient, index: Int) -> String? {
        let upper = "F\(index)Md"
        let lower = "F\(index)md"
        // Prefer keys that already return a mode byte (more reliable than getKeyInfo alone).
        if smc.readUInt8(upper) != nil { return upper }
        if smc.readUInt8(lower) != nil { return lower }
        if smc.keyType(upper) != nil { return upper }
        if smc.keyType(lower) != nil { return lower }
        return nil
    }

    private static func describeMode(_ raw: UInt8?) -> String {
        guard let raw else { return "unknown" }
        switch raw {
        case 0: return "auto"
        case 1: return "manual"
        case 3: return "system"
        default: return "mode-\(raw)"
        }
    }

    private static func unlockIfNeeded(_ smc: SMCClient, notes: inout [String]) throws -> Bool {
        guard let modeKey = resolveModeKey(smc, index: 0) else { return false }
        let current = smc.readUInt8(modeKey) ?? 0
        if current == 1 { return false }

        // Always try Ftst on Apple Silicon when leaving auto/system for manual/full.
        if smc.readUInt8("Ftst") != nil || smc.keyType("Ftst") != nil {
            do {
                try smc.writeUInt8("Ftst", 1)
                notes.append("Ftst=1")
            } catch let error as SMCClient.SMCError {
                if case .notPrivileged = error { throw error }
                notes.append("Ftst write failed: \(error.localizedDescription)")
            } catch {
                notes.append("Ftst write failed: \(error.localizedDescription)")
            }
        } else {
            notes.append("Ftst unavailable")
        }

        for _ in 0..<50 {
            do {
                try smc.writeUInt8(modeKey, 1)
            } catch let error as SMCClient.SMCError {
                if case .notPrivileged = error { throw error }
                // Keep retrying — thermalmonitord often rejects the first attempts.
            } catch {
                // Keep retrying.
            }
            Thread.sleep(forTimeInterval: 0.1)
            if smc.readUInt8(modeKey) == 1 {
                notes.append("\(modeKey)=1")
                return true
            }
        }
        notes.append("manual mode not sticky yet (will still try targets)")
        return true
    }

    private static func setFanAuto(_ smc: SMCClient, index: Int, notes: inout [String]) throws {
        guard let modeKey = resolveModeKey(smc, index: index) else {
            notes.append("F\(index): mode key missing")
            return
        }
        do {
            try smc.writeUInt8(modeKey, 0)
            notes.append("F\(index):\(modeKey)=0")
        } catch {
            notes.append("F\(index): auto write failed: \(error.localizedDescription)")
            throw error
        }
    }

    private static func setFanFull(_ smc: SMCClient, index: Int, notes: inout [String]) throws {
        guard let modeKey = resolveModeKey(smc, index: index) else {
            notes.append("F\(index): mode key missing — cannot force full")
            return
        }
        do {
            try smc.writeUInt8(modeKey, 1)
        } catch {
            notes.append("F\(index): mode write failed: \(error.localizedDescription)")
            // Continue — some firmware accepts target writes after Ftst alone.
        }
        guard let maxRPM = smc.readNumber("F\(index)Mx"), maxRPM > 0 else {
            notes.append("F\(index): max RPM missing")
            return
        }
        let minRPM = smc.readNumber("F\(index)Mn") ?? 0
        let target = Swift.max(minRPM, maxRPM)
        let tg = "F\(index)Tg"
        if smc.readNumber(tg) != nil || smc.keyType(tg) != nil {
            do {
                try smc.writeNumber(tg, target)
                notes.append("F\(index): \(tg)=\(Int(target))")
            } catch {
                notes.append("F\(index): target write failed: \(error.localizedDescription)")
                throw error
            }
        } else {
            notes.append("F\(index): no \(tg) key")
        }
    }
}

public enum StatusService {
    public static func current() -> SystemStatus {
        SystemStatus(
            temperature: ThermalService.read(),
            fans: FanService.read()
        )
    }
}
