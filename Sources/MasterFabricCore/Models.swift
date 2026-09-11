import Foundation

public struct SystemInfo: Sendable, Codable, Equatable {
    public var model: String
    public var modelIdentifier: String
    public var chip: String
    public var macOSVersion: String
    public var ramGB: Double
    public var uptimeSeconds: TimeInterval
    public var cpuCount: Int
    /// Performance (P) logical cores. 0 when unknown.
    public var performanceCoreCount: Int
    /// Efficiency (E) logical cores. 0 on Intel or when unknown.
    public var efficiencyCoreCount: Int

    public init(
        model: String,
        modelIdentifier: String,
        chip: String,
        macOSVersion: String,
        ramGB: Double,
        uptimeSeconds: TimeInterval,
        cpuCount: Int,
        performanceCoreCount: Int = 0,
        efficiencyCoreCount: Int = 0
    ) {
        self.model = model
        self.modelIdentifier = modelIdentifier
        self.chip = chip
        self.macOSVersion = macOSVersion
        self.ramGB = ramGB
        self.uptimeSeconds = uptimeSeconds
        self.cpuCount = cpuCount
        self.performanceCoreCount = performanceCoreCount
        self.efficiencyCoreCount = efficiencyCoreCount
    }

    public var uptimeFormatted: String {
        let total = Int(uptimeSeconds)
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

public struct FanReading: Sendable, Codable, Equatable {
    public var index: Int
    public var name: String
    public var role: String
    public var rpm: Double?
    public var minRPM: Double?
    public var maxRPM: Double?
    /// SMC mode when readable: 0 auto, 1 manual, 3 system (thermalmonitord).
    public var modeRaw: UInt8?
    public var mode: String
    public var targetRPM: Double?

    public init(
        index: Int = 0,
        name: String,
        role: String = "",
        rpm: Double?,
        minRPM: Double? = nil,
        maxRPM: Double? = nil,
        modeRaw: UInt8? = nil,
        mode: String = "unknown",
        targetRPM: Double? = nil
    ) {
        self.index = index
        self.name = name
        self.role = role
        self.rpm = rpm
        self.minRPM = minRPM
        self.maxRPM = maxRPM
        self.modeRaw = modeRaw
        self.mode = mode
        self.targetRPM = targetRPM
    }
}

public enum FanControlMode: String, Sendable, Codable, CaseIterable {
    case auto
    case full

    public var label: String {
        switch self {
        case .auto: return "Auto"
        case .full: return "Full"
        }
    }
}

public struct FanControlResult: Sendable, Codable, Equatable {
    public var ok: Bool
    public var mode: FanControlMode
    public var detail: String
    public var fans: [FanReading]
    public var unlockedWithFtst: Bool
    /// True when macOS blocked SMC writes without administrator privileges.
    public var needsPrivilege: Bool

    public init(
        ok: Bool,
        mode: FanControlMode,
        detail: String,
        fans: [FanReading],
        unlockedWithFtst: Bool = false,
        needsPrivilege: Bool = false
    ) {
        self.ok = ok
        self.mode = mode
        self.detail = detail
        self.fans = fans
        self.unlockedWithFtst = unlockedWithFtst
        self.needsPrivilege = needsPrivilege
    }
}

public struct TemperatureReading: Sendable, Codable, Equatable {
    public var cpuCelsius: Double?
    public var gpuCelsius: Double?
    public var sensors: [String: Double]

    public init(cpuCelsius: Double?, gpuCelsius: Double?, sensors: [String: Double] = [:]) {
        self.cpuCelsius = cpuCelsius
        self.gpuCelsius = gpuCelsius
        self.sensors = sensors
    }
}

public struct SystemStatus: Sendable, Codable, Equatable {
    public var temperature: TemperatureReading
    public var fans: [FanReading]
    public var timestamp: Date

    public init(temperature: TemperatureReading, fans: [FanReading], timestamp: Date = Date()) {
        self.temperature = temperature
        self.fans = fans
        self.timestamp = timestamp
    }
}
