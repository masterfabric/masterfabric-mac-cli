import Foundation

// MARK: - Phase 2 metrics

public struct BatteryInfo: Sendable, Codable, Equatable {
    public var percent: Double?
    public var isCharging: Bool?
    public var isACPowered: Bool?
    public var cycleCount: Int?
    public var healthPercent: Double?
    public var watts: Double?
    public var timeRemainingMinutes: Int?
    public var isPresent: Bool

    public init(
        percent: Double? = nil,
        isCharging: Bool? = nil,
        isACPowered: Bool? = nil,
        cycleCount: Int? = nil,
        healthPercent: Double? = nil,
        watts: Double? = nil,
        timeRemainingMinutes: Int? = nil,
        isPresent: Bool = true
    ) {
        self.percent = percent
        self.isCharging = isCharging
        self.isACPowered = isACPowered
        self.cycleCount = cycleCount
        self.healthPercent = healthPercent
        self.watts = watts
        self.timeRemainingMinutes = timeRemainingMinutes
        self.isPresent = isPresent
    }
}

public struct MemoryInfo: Sendable, Codable, Equatable {
    public var totalBytes: UInt64
    public var usedBytes: UInt64
    public var freeBytes: UInt64
    public var wiredBytes: UInt64
    public var compressedBytes: UInt64
    public var swapUsedBytes: UInt64
    public var pressure: String

    public var usedPercent: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes) * 100
    }

    public init(
        totalBytes: UInt64,
        usedBytes: UInt64,
        freeBytes: UInt64,
        wiredBytes: UInt64,
        compressedBytes: UInt64,
        swapUsedBytes: UInt64,
        pressure: String
    ) {
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.freeBytes = freeBytes
        self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes
        self.swapUsedBytes = swapUsedBytes
        self.pressure = pressure
    }
}

public struct DiskInfo: Sendable, Codable, Equatable {
    public var path: String
    public var totalBytes: UInt64
    public var freeBytes: UInt64
    public var usedBytes: UInt64

    public var usedPercent: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes) * 100
    }

    public init(path: String, totalBytes: UInt64, freeBytes: UInt64, usedBytes: UInt64) {
        self.path = path
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
        self.usedBytes = usedBytes
    }
}

public struct NetworkInterfaceStats: Sendable, Codable, Equatable {
    public var name: String
    public var bytesIn: UInt64
    public var bytesOut: UInt64
    public var bytesInPerSec: Double?
    public var bytesOutPerSec: Double?

    public init(
        name: String,
        bytesIn: UInt64,
        bytesOut: UInt64,
        bytesInPerSec: Double? = nil,
        bytesOutPerSec: Double? = nil
    ) {
        self.name = name
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
        self.bytesInPerSec = bytesInPerSec
        self.bytesOutPerSec = bytesOutPerSec
    }
}

public struct NetworkInfo: Sendable, Codable, Equatable {
    public var interfaces: [NetworkInterfaceStats]

    public init(interfaces: [NetworkInterfaceStats]) {
        self.interfaces = interfaces
    }
}

public struct CPULoadInfo: Sendable, Codable, Equatable {
    public var overallPercent: Double
    public var perCorePercent: [Double]
    public var userPercent: Double
    public var systemPercent: Double
    public var idlePercent: Double
    /// Average load across performance cores (Apple Silicon).
    public var performancePercent: Double?
    /// Average load across efficiency cores (Apple Silicon).
    public var efficiencyPercent: Double?
    public var performanceCoreCount: Int
    public var efficiencyCoreCount: Int

    public init(
        overallPercent: Double,
        perCorePercent: [Double],
        userPercent: Double,
        systemPercent: Double,
        idlePercent: Double,
        performancePercent: Double? = nil,
        efficiencyPercent: Double? = nil,
        performanceCoreCount: Int = 0,
        efficiencyCoreCount: Int = 0
    ) {
        self.overallPercent = overallPercent
        self.perCorePercent = perCorePercent
        self.userPercent = userPercent
        self.systemPercent = systemPercent
        self.idlePercent = idlePercent
        self.performancePercent = performancePercent
        self.efficiencyPercent = efficiencyPercent
        self.performanceCoreCount = performanceCoreCount
        self.efficiencyCoreCount = efficiencyCoreCount
    }
}

// MARK: - Phase 4

public struct PowerInfo: Sendable, Codable, Equatable {
    public var thermalState: String
    public var lowPowerMode: Bool

    public init(thermalState: String, lowPowerMode: Bool) {
        self.thermalState = thermalState
        self.lowPowerMode = lowPowerMode
    }
}

public struct ProcessCPUInfo: Sendable, Codable, Equatable {
    public var pid: Int32
    public var name: String
    public var cpuPercent: Double
    public var memoryBytes: UInt64

    public init(pid: Int32, name: String, cpuPercent: Double, memoryBytes: UInt64) {
        self.pid = pid
        self.name = name
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
    }
}

public struct HistorySample: Sendable, Codable, Equatable {
    public var timestamp: Date
    public var cpuCelsius: Double?
    public var gpuCelsius: Double?
    public var fanRPM: Double?
    public var cpuLoadPercent: Double?
    public var batteryPercent: Double?

    public init(
        timestamp: Date = Date(),
        cpuCelsius: Double? = nil,
        gpuCelsius: Double? = nil,
        fanRPM: Double? = nil,
        cpuLoadPercent: Double? = nil,
        batteryPercent: Double? = nil
    ) {
        self.timestamp = timestamp
        self.cpuCelsius = cpuCelsius
        self.gpuCelsius = gpuCelsius
        self.fanRPM = fanRPM
        self.cpuLoadPercent = cpuLoadPercent
        self.batteryPercent = batteryPercent
    }
}

public struct HistorySnapshot: Sendable, Codable, Equatable {
    public var samples: [HistorySample]
    public var cpuSparkline: String
    public var loadSparkline: String

    public init(samples: [HistorySample], cpuSparkline: String, loadSparkline: String) {
        self.samples = samples
        self.cpuSparkline = cpuSparkline
        self.loadSparkline = loadSparkline
    }
}

// MARK: - Phase 3 config

public struct AlertConfig: Sendable, Codable, Equatable {
    public var enabled: Bool
    /// Push triggered alerts to Slack / Telegram / mail (with cooldown).
    public var notifyIntegrations: Bool
    /// Show macOS Notification Center banners when alerts fire (menu bar app).
    public var notifyLocal: Bool
    public var notifyCooldownSeconds: Double

    public var cpuTempEnabled: Bool
    public var cpuTempCelsius: Double

    public var gpuTempEnabled: Bool
    public var gpuTempCelsius: Double

    public var fanEnabled: Bool
    public var fanNearMaxPercent: Double

    public var memoryPressureNotify: Bool

    public var diskEnabled: Bool
    public var diskUsedPercentMax: Double

    public var batteryEnabled: Bool
    public var batteryPercentMin: Double

    public var lowPowerModeNotify: Bool

    public static let `default` = AlertConfig(
        enabled: true,
        notifyIntegrations: true,
        notifyLocal: false,
        notifyCooldownSeconds: 300,
        cpuTempEnabled: true,
        cpuTempCelsius: 90,
        gpuTempEnabled: true,
        gpuTempCelsius: 90,
        fanEnabled: true,
        fanNearMaxPercent: 95,
        memoryPressureNotify: true,
        diskEnabled: true,
        diskUsedPercentMax: 90,
        batteryEnabled: true,
        batteryPercentMin: 15,
        lowPowerModeNotify: true
    )

    public init(
        enabled: Bool,
        notifyIntegrations: Bool,
        notifyLocal: Bool = false,
        notifyCooldownSeconds: Double,
        cpuTempEnabled: Bool,
        cpuTempCelsius: Double,
        gpuTempEnabled: Bool,
        gpuTempCelsius: Double,
        fanEnabled: Bool,
        fanNearMaxPercent: Double,
        memoryPressureNotify: Bool,
        diskEnabled: Bool,
        diskUsedPercentMax: Double,
        batteryEnabled: Bool,
        batteryPercentMin: Double,
        lowPowerModeNotify: Bool
    ) {
        self.enabled = enabled
        self.notifyIntegrations = notifyIntegrations
        self.notifyLocal = notifyLocal
        self.notifyCooldownSeconds = notifyCooldownSeconds
        self.cpuTempEnabled = cpuTempEnabled
        self.cpuTempCelsius = cpuTempCelsius
        self.gpuTempEnabled = gpuTempEnabled
        self.gpuTempCelsius = gpuTempCelsius
        self.fanEnabled = fanEnabled
        self.fanNearMaxPercent = fanNearMaxPercent
        self.memoryPressureNotify = memoryPressureNotify
        self.diskEnabled = diskEnabled
        self.diskUsedPercentMax = diskUsedPercentMax
        self.batteryEnabled = batteryEnabled
        self.batteryPercentMin = batteryPercentMin
        self.lowPowerModeNotify = lowPowerModeNotify
    }
}

public struct AppConfig: Sendable, Codable, Equatable {
    public var language: String
    public var launchAtLogin: Bool
    public var pollIntervalSeconds: Double
    public var alerts: AlertConfig
    public var integrations: IntegrationsConfig
    public var menuBar: MenuBarDisplayConfig

    public static let `default` = AppConfig(
        language: "en",
        launchAtLogin: false,
        pollIntervalSeconds: 2.0,
        alerts: .default,
        integrations: .default,
        menuBar: .default
    )

    public init(
        language: String,
        launchAtLogin: Bool,
        pollIntervalSeconds: Double,
        alerts: AlertConfig,
        integrations: IntegrationsConfig = .default,
        menuBar: MenuBarDisplayConfig = .default
    ) {
        self.language = language
        self.launchAtLogin = launchAtLogin
        self.pollIntervalSeconds = pollIntervalSeconds
        self.alerts = alerts
        self.integrations = integrations
        self.menuBar = menuBar
    }
}

/// How the menu bar status item text is composed / drawn.
public enum MenuBarStatusStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    case standard = "standard"
    case tempOnly = "temp"
    case fanOnly = "fan"
    case capsule = "capsule"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .standard: return "Standard"
        case .tempOnly: return "Temp only"
        case .fanOnly: return "Fan only"
        case .capsule: return "Capsule"
        }
    }

    public var subtitle: String {
        switch self {
        case .standard: return "CPU · load · fan + A/F badge"
        case .tempOnly: return "Just temperature, e.g. 52°"
        case .fanOnly: return "Just fan RPM, e.g. 2400"
        case .capsule: return "Pill background + metrics + badge"
        }
    }
}

/// Menu bar status-item + dropdown panel visibility.
public struct MenuBarDisplayConfig: Sendable, Codable, Equatable {
    public var style: MenuBarStatusStyle

    // Status item (menu bar strip)
    public var showCPUTemp: Bool
    public var showGPUTemp: Bool
    public var showLoad: Bool
    public var showFanRPM: Bool
    public var showFanBadge: Bool
    public var showBattery: Bool

    // Dropdown panel sections
    public var panelModel: Bool
    public var panelChip: Bool
    public var panelCPU: Bool
    public var panelGPU: Bool
    public var panelLoad: Bool
    public var panelThermal: Bool
    public var panelFans: Bool
    public var panelFanControl: Bool
    public var panelBattery: Bool
    public var panelMemory: Bool
    public var panelCPUHist: Bool
    public var panelAlerts: Bool
    public var panelIntegrations: Bool
    public var panelAbout: Bool

    public static let `default` = MenuBarDisplayConfig(
        style: .standard,
        showCPUTemp: true,
        showGPUTemp: false,
        showLoad: true,
        showFanRPM: true,
        showFanBadge: true,
        showBattery: false,
        panelModel: true,
        panelChip: true,
        panelCPU: true,
        panelGPU: true,
        panelLoad: true,
        panelThermal: true,
        panelFans: true,
        panelFanControl: true,
        panelBattery: true,
        panelMemory: true,
        panelCPUHist: true,
        panelAlerts: true,
        panelIntegrations: true,
        panelAbout: true
    )

    public init(
        style: MenuBarStatusStyle,
        showCPUTemp: Bool,
        showGPUTemp: Bool,
        showLoad: Bool,
        showFanRPM: Bool,
        showFanBadge: Bool,
        showBattery: Bool,
        panelModel: Bool,
        panelChip: Bool,
        panelCPU: Bool,
        panelGPU: Bool,
        panelLoad: Bool,
        panelThermal: Bool,
        panelFans: Bool,
        panelFanControl: Bool,
        panelBattery: Bool,
        panelMemory: Bool,
        panelCPUHist: Bool,
        panelAlerts: Bool,
        panelIntegrations: Bool,
        panelAbout: Bool
    ) {
        self.style = style
        self.showCPUTemp = showCPUTemp
        self.showGPUTemp = showGPUTemp
        self.showLoad = showLoad
        self.showFanRPM = showFanRPM
        self.showFanBadge = showFanBadge
        self.showBattery = showBattery
        self.panelModel = panelModel
        self.panelChip = panelChip
        self.panelCPU = panelCPU
        self.panelGPU = panelGPU
        self.panelLoad = panelLoad
        self.panelThermal = panelThermal
        self.panelFans = panelFans
        self.panelFanControl = panelFanControl
        self.panelBattery = panelBattery
        self.panelMemory = panelMemory
        self.panelCPUHist = panelCPUHist
        self.panelAlerts = panelAlerts
        self.panelIntegrations = panelIntegrations
        self.panelAbout = panelAbout
    }
}
