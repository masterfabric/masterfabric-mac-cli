import Foundation

public enum ConfigStore {
    public static var configDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/masterfabric", isDirectory: true)
    }

    public static var configURL: URL {
        configDirectory.appendingPathComponent("config.toml")
    }

    public static var historyURL: URL {
        configDirectory.appendingPathComponent("history.json")
    }

    public static func load() -> AppConfig {
        ensureDirectory()
        guard let data = try? Data(contentsOf: configURL),
              let text = String(data: data, encoding: .utf8)
        else {
            return .default
        }
        return parseTOML(text)
    }

    public static func save(_ config: AppConfig) throws {
        ensureDirectory()
        let text = renderTOML(config)
        try text.write(to: configURL, atomically: true, encoding: .utf8)
    }

    private static func ensureDirectory() {
        try? FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
    }

    // Minimal TOML for our keys only
    private static func parseTOML(_ text: String) -> AppConfig {
        var config = AppConfig.default
        var section = ""
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("["), line.hasSuffix("]") {
                section = String(line.dropFirst().dropLast())
                continue
            }
            let parts = line.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2 else { continue }
            let key = parts[0]
            let value = stripQuotes(parts[1])

            if section.isEmpty || section == "general" {
                switch key {
                case "language": config.language = value
                case "launch_at_login": config.launchAtLogin = value == "true"
                case "poll_interval_seconds": config.pollIntervalSeconds = Double(value) ?? config.pollIntervalSeconds
                default: break
                }
            } else if section == "alerts" {
                switch key {
                case "enabled": config.alerts.enabled = value == "true"
                case "notify_integrations": config.alerts.notifyIntegrations = value == "true"
                case "notify_local": config.alerts.notifyLocal = value == "true"
                case "notify_cooldown_seconds":
                    config.alerts.notifyCooldownSeconds = Double(value) ?? config.alerts.notifyCooldownSeconds
                case "cpu_temp_enabled": config.alerts.cpuTempEnabled = value == "true"
                case "cpu_temp_celsius": config.alerts.cpuTempCelsius = Double(value) ?? config.alerts.cpuTempCelsius
                case "gpu_temp_enabled": config.alerts.gpuTempEnabled = value == "true"
                case "gpu_temp_celsius": config.alerts.gpuTempCelsius = Double(value) ?? config.alerts.gpuTempCelsius
                case "fan_enabled": config.alerts.fanEnabled = value == "true"
                case "fan_near_max_percent": config.alerts.fanNearMaxPercent = Double(value) ?? config.alerts.fanNearMaxPercent
                case "memory_pressure_notify": config.alerts.memoryPressureNotify = value == "true"
                case "disk_enabled": config.alerts.diskEnabled = value == "true"
                case "disk_used_percent_max":
                    config.alerts.diskUsedPercentMax = Double(value) ?? config.alerts.diskUsedPercentMax
                case "battery_enabled": config.alerts.batteryEnabled = value == "true"
                case "battery_percent_min":
                    config.alerts.batteryPercentMin = Double(value) ?? config.alerts.batteryPercentMin
                case "low_power_mode_notify": config.alerts.lowPowerModeNotify = value == "true"
                default: break
                }
            } else if section == "integrations.slack" {
                switch key {
                case "enabled": config.integrations.slack.enabled = value == "true"
                case "webhook_url": config.integrations.slack.webhookURL = value
                default: break
                }
            } else if section == "integrations.telegram" {
                switch key {
                case "enabled": config.integrations.telegram.enabled = value == "true"
                case "bot_token": config.integrations.telegram.botToken = value
                case "chat_id": config.integrations.telegram.chatID = value
                default: break
                }
            } else if section == "integrations.mail" {
                switch key {
                case "enabled": config.integrations.mail.enabled = value == "true"
                case "provider": config.integrations.mail.provider = value
                case "from": config.integrations.mail.from = value
                case "to": config.integrations.mail.to = value
                case "subject_prefix": config.integrations.mail.subjectPrefix = value
                case "smtp_host": config.integrations.mail.smtpHost = value
                case "smtp_port": config.integrations.mail.smtpPort = Int(value) ?? config.integrations.mail.smtpPort
                case "smtp_username": config.integrations.mail.smtpUsername = value
                case "smtp_password": config.integrations.mail.smtpPassword = value
                case "smtp_use_tls": config.integrations.mail.smtpUseTLS = value == "true"
                case "api_key": config.integrations.mail.apiKey = value
                case "mailgun_domain": config.integrations.mail.mailgunDomain = value
                default: break
                }
            } else if section == "menubar" {
                switch key {
                case "style":
                    config.menuBar.style = MenuBarStatusStyle(rawValue: value) ?? config.menuBar.style
                case "show_cpu_temp": config.menuBar.showCPUTemp = value == "true"
                case "show_gpu_temp": config.menuBar.showGPUTemp = value == "true"
                case "show_load": config.menuBar.showLoad = value == "true"
                case "show_fan_rpm": config.menuBar.showFanRPM = value == "true"
                case "show_fan_badge": config.menuBar.showFanBadge = value == "true"
                case "show_battery": config.menuBar.showBattery = value == "true"
                case "show_memory": config.menuBar.showMemory = value == "true"
                case "show_short_labels": config.menuBar.showShortLabels = value == "true"
                case "colorize_heat": config.menuBar.colorizeHeat = value == "true"
                case "panel_model": config.menuBar.panelModel = value == "true"
                case "panel_chip": config.menuBar.panelChip = value == "true"
                case "panel_cpu": config.menuBar.panelCPU = value == "true"
                case "panel_gpu": config.menuBar.panelGPU = value == "true"
                case "panel_load": config.menuBar.panelLoad = value == "true"
                case "panel_thermal": config.menuBar.panelThermal = value == "true"
                case "panel_fans": config.menuBar.panelFans = value == "true"
                case "panel_fan_control": config.menuBar.panelFanControl = value == "true"
                case "panel_battery": config.menuBar.panelBattery = value == "true"
                case "panel_memory": config.menuBar.panelMemory = value == "true"
                case "panel_cpu_hist": config.menuBar.panelCPUHist = value == "true"
                case "panel_alerts": config.menuBar.panelAlerts = value == "true"
                case "panel_integrations": config.menuBar.panelIntegrations = value == "true"
                case "panel_about": config.menuBar.panelAbout = value == "true"
                default: break
                }
            }
        }
        return config
    }

    private static func stripQuotes(_ raw: String) -> String {
        var v = raw.trimmingCharacters(in: .whitespaces)
        if v.hasPrefix("\""), v.hasSuffix("\""), v.count >= 2 {
            v.removeFirst()
            v.removeLast()
            v = v.replacingOccurrences(of: "\\\"", with: "\"")
        }
        return v
    }

    private static func escapeTOML(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func renderTOML(_ config: AppConfig) -> String {
        let s = config.integrations.slack
        let t = config.integrations.telegram
        let m = config.integrations.mail
        let mb = config.menuBar
        return """
        # MasterFabric configuration
        # https://github.com/gurkanfikretgunak/masterfabric-mac-cli

        [general]
        language = "\(escapeTOML(config.language))"
        launch_at_login = \(config.launchAtLogin)
        poll_interval_seconds = \(config.pollIntervalSeconds)

        [menubar]
        style = "\(mb.style.rawValue)"
        show_cpu_temp = \(mb.showCPUTemp)
        show_gpu_temp = \(mb.showGPUTemp)
        show_load = \(mb.showLoad)
        show_fan_rpm = \(mb.showFanRPM)
        show_fan_badge = \(mb.showFanBadge)
        show_battery = \(mb.showBattery)
        show_memory = \(mb.showMemory)
        show_short_labels = \(mb.showShortLabels)
        colorize_heat = \(mb.colorizeHeat)
        panel_model = \(mb.panelModel)
        panel_chip = \(mb.panelChip)
        panel_cpu = \(mb.panelCPU)
        panel_gpu = \(mb.panelGPU)
        panel_load = \(mb.panelLoad)
        panel_thermal = \(mb.panelThermal)
        panel_fans = \(mb.panelFans)
        panel_fan_control = \(mb.panelFanControl)
        panel_battery = \(mb.panelBattery)
        panel_memory = \(mb.panelMemory)
        panel_cpu_hist = \(mb.panelCPUHist)
        panel_alerts = \(mb.panelAlerts)
        panel_integrations = \(mb.panelIntegrations)
        panel_about = \(mb.panelAbout)

        [alerts]
        enabled = \(config.alerts.enabled)
        notify_integrations = \(config.alerts.notifyIntegrations)
        notify_local = \(config.alerts.notifyLocal)
        notify_cooldown_seconds = \(config.alerts.notifyCooldownSeconds)
        cpu_temp_enabled = \(config.alerts.cpuTempEnabled)
        cpu_temp_celsius = \(config.alerts.cpuTempCelsius)
        gpu_temp_enabled = \(config.alerts.gpuTempEnabled)
        gpu_temp_celsius = \(config.alerts.gpuTempCelsius)
        fan_enabled = \(config.alerts.fanEnabled)
        fan_near_max_percent = \(config.alerts.fanNearMaxPercent)
        memory_pressure_notify = \(config.alerts.memoryPressureNotify)
        disk_enabled = \(config.alerts.diskEnabled)
        disk_used_percent_max = \(config.alerts.diskUsedPercentMax)
        battery_enabled = \(config.alerts.batteryEnabled)
        battery_percent_min = \(config.alerts.batteryPercentMin)
        low_power_mode_notify = \(config.alerts.lowPowerModeNotify)

        [integrations.slack]
        enabled = \(s.enabled)
        webhook_url = "\(escapeTOML(s.webhookURL))"

        [integrations.telegram]
        enabled = \(t.enabled)
        bot_token = "\(escapeTOML(t.botToken))"
        chat_id = "\(escapeTOML(t.chatID))"

        [integrations.mail]
        enabled = \(m.enabled)
        provider = "\(escapeTOML(m.provider))"
        from = "\(escapeTOML(m.from))"
        to = "\(escapeTOML(m.to))"
        subject_prefix = "\(escapeTOML(m.subjectPrefix))"
        smtp_host = "\(escapeTOML(m.smtpHost))"
        smtp_port = \(m.smtpPort)
        smtp_username = "\(escapeTOML(m.smtpUsername))"
        smtp_password = "\(escapeTOML(m.smtpPassword))"
        smtp_use_tls = \(m.smtpUseTLS)
        api_key = "\(escapeTOML(m.apiKey))"
        mailgun_domain = "\(escapeTOML(m.mailgunDomain))"
        """
    }
}

public enum LaunchAtLogin {
    private static let label = "com.masterfabric.menubar"
    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    public static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    public static func setEnabled(_ enabled: Bool, executablePath: String) throws {
        if enabled {
            // Prefer launching the .app bundle when available
            let programArguments: String
            let appPath = NSHomeDirectory() + "/.local/MasterFabricMenuBar.app"
            if FileManager.default.fileExists(atPath: appPath) {
                programArguments = """
                      <string>/usr/bin/open</string>
                      <string>-a</string>
                      <string>\(appPath)</string>
                """
            } else {
                programArguments = """
                      <string>\(executablePath)</string>
                """
            }
            let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
              <key>Label</key>
              <string>\(label)</string>
              <key>ProgramArguments</key>
              <array>
            \(programArguments)
              </array>
              <key>RunAtLoad</key>
              <true/>
              <key>KeepAlive</key>
              <false/>
            </dict>
            </plist>
            """
            let dir = plistURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try plist.write(to: plistURL, atomically: true, encoding: .utf8)
            _ = try? shell(["launchctl", "unload", plistURL.path])
            _ = try? shell(["launchctl", "load", plistURL.path])
        } else {
            _ = try? shell(["launchctl", "unload", plistURL.path])
            try? FileManager.default.removeItem(at: plistURL)
        }
    }

    private static func shell(_ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        try p.run()
        p.waitUntilExit()
        return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
