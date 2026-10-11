import ArgumentParser
import Foundation
import MasterFabricCore

@main
struct MF: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mf",
        abstract: "MasterFabric — MacBook system monitor (CLI, menu bar, MCP).",
        version: AboutInfo.version,
        subcommands: [
            Info.self,
            Status.self,
            Temp.self,
            Fan.self,
            FanDaemonCommand.self,
            Battery.self,
            Memory.self,
            Disk.self,
            Network.self,
            CPU.self,
            Power.self,
            Top.self,
            History.self,
            Watch.self,
            Config.self,
            Login.self,
            Check.self,
            Notify.self,
            Bot.self,
            Version.self,
            Update.self,
            About.self,
            MenuBar.self,
            MCP.self,
        ],
        defaultSubcommand: Status.self
    )
}

struct JSONFlagOptions: ParsableArguments {
    @Flag(name: .long, help: "Output JSON.")
    var json: Bool = false
}

extension MF {
    struct Info: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show Mac model, chip, macOS, RAM, and uptime.")
        @OptionGroup var format: JSONFlagOptions
        func run() throws {
            let info = SystemInfoService.current()
            print(format.json ? try JSONOutput.string(info) : TextFormat.info(info))
        }
    }

    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show CPU/GPU temperature and fan RPM.")
        @OptionGroup var format: JSONFlagOptions
        func run() throws {
            HistoryStore.record()
            let status = StatusService.current()
            print(format.json ? try JSONOutput.string(status) : TextFormat.status(status))
        }
    }

    struct Temp: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show CPU and GPU temperatures.")
        @OptionGroup var format: JSONFlagOptions
        func run() throws {
            let temp = ThermalService.read()
            print(format.json ? try JSONOutput.string(temp) : TextFormat.temp(temp))
        }
    }

    struct Fan: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Fan speeds and control (auto / full). Two fans: CPU + GPU on most MacBook Pros.",
            subcommands: [Status.self, Auto.self, Full.self, Helper.self],
            defaultSubcommand: Status.self
        )

        struct Status: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Show fan RPM, mode, and targets.")
            @OptionGroup var format: JSONFlagOptions
            func run() throws {
                let fans = FanService.read()
                print(format.json ? try JSONOutput.string(fans) : TextFormat.fans(fans))
            }
        }

        struct Auto: ParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Return fans to automatic system thermal control."
            )
            @OptionGroup var format: JSONFlagOptions
            @Flag(name: .long, help: "Use privileged helper (installs once with admin password if needed).")
            var elevate: Bool = false
            func run() throws {
                let result = elevate
                    ? FanService.setModePrivileged(.auto)
                    : FanService.setMode(.auto)
                print(format.json ? try JSONOutput.string(result) : TextFormat.fanControl(result))
                if !result.ok {
                    if result.needsPrivilege {
                        FileHandle.standardError.write(Data("Hint: mf fan auto --elevate   or   sudo mf fan auto\n".utf8))
                    }
                    throw ExitCode.failure
                }
            }
        }

        struct Full: ParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Force both fans (CPU + GPU) to hardware max RPM. Loud — switch back with `mf fan auto`."
            )
            @OptionGroup var format: JSONFlagOptions
            @Flag(name: .long, help: "Use privileged helper (installs once with admin password if needed).")
            var elevate: Bool = false
            func run() throws {
                let result = elevate
                    ? FanService.setModePrivileged(.full)
                    : FanService.setMode(.full)
                print(format.json ? try JSONOutput.string(result) : TextFormat.fanControl(result))
                if !result.ok {
                    if result.needsPrivilege {
                        FileHandle.standardError.write(Data("Hint: mf fan full --elevate   or   sudo mf fan full\n".utf8))
                    }
                    throw ExitCode.failure
                }
            }
        }

        struct Helper: ParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Privileged fan helper (one-time admin install for menu bar).",
                subcommands: [Status.self, Install.self],
                defaultSubcommand: Status.self
            )

            struct Status: ParsableCommand {
                static let configuration = CommandConfiguration(abstract: "Show whether the root fan helper is running.")
                func run() {
                    let ok = FanDaemonInstaller.isInstalledAndRunning()
                    print(ok
                        ? "Fan helper: running (no password needed for Auto/Full)."
                        : "Fan helper: not running — menu bar will ask for admin once to install.")
                }
            }

            struct Install: ParsableCommand {
                static let configuration = CommandConfiguration(
                    abstract: "Install/start the root fan helper (single admin password prompt)."
                )
                func run() throws {
                    if FanDaemonInstaller.isInstalledAndRunning() {
                        print("Fan helper already running.")
                        return
                    }
                    let result = FanDaemonInstaller.installWithAdminPrompt()
                    print(result.detail)
                    if !result.ok { throw ExitCode.failure }
                    for _ in 0..<50 {
                        if FanDaemonClient.isReachable() {
                            print("Fan helper is ready.")
                            return
                        }
                        Thread.sleep(forTimeInterval: 0.1)
                    }
                    print("Installed, but helper not reachable yet — try again in a moment.")
                }
            }
        }
    }

    /// Root-only LaunchDaemon entrypoint (not for interactive use).
    struct FanDaemonCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "fan-daemon",
            abstract: "Internal: root Unix-socket fan helper (LaunchDaemon)."
        )
        func run() {
            FanDaemonServer.run()
        }
    }

    struct Battery: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show battery percent, health, cycles, watts.")
        @OptionGroup var format: JSONFlagOptions
        func run() throws {
            let b = BatteryService.current()
            print(format.json ? try JSONOutput.string(b) : TextFormat.battery(b))
        }
    }

    struct Memory: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show memory usage, or free RAM one process at a time for a model.",
            subcommands: [Show.self, Room.self, Free.self, Make.self],
            defaultSubcommand: Show.self
        )

        struct Show: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Show memory usage and pressure.")
            @OptionGroup var format: JSONFlagOptions
            func run() throws {
                let m = MemoryService.current()
                print(format.json ? try JSONOutput.string(m) : TextFormat.memory(m))
            }
        }

        struct Room: ParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Show allocatable RAM and the processes you can quit for a model."
            )
            @OptionGroup var format: JSONFlagOptions
            @Option(name: .shortAndLong, help: "Number of processes.")
            var limit: Int = 20
            func run() throws {
                let room = MemoryRoomService.snapshot(limit: limit)
                print(format.json ? try JSONOutput.string(room) : TextFormat.memoryRoom(room))
            }
        }

        struct Make: ParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Quit eligible apps until allocatable RAM reaches the saved target."
            )
            func run() {
                let targetGB = ConfigStore.load().menuBar.modelRoomTargetGB
                let target = MemoryRoomService.targetBytes(gigabytes: targetGB)
                print("Making \(TextFormat.bytes(target)) allocatable…")
                fflush(stdout)
                MemoryRoomService.makeRoom(targetBytes: { target }) { step in
                    print(step.detail)
                    fflush(stdout)
                }
            }
        }

        struct Free: ParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Quit one process so its RAM can be reused by a model."
            )
            @OptionGroup var format: JSONFlagOptions
            @Option(name: .long, help: "Process ID to quit.")
            var pid: Int32
            @Flag(name: .long, help: "Send SIGKILL if the process ignores a normal quit.")
            var force: Bool = false
            func run() throws {
                let result = MemoryRoomService.release(pid: pid, force: force)
                print(format.json ? try JSONOutput.string(result) : result.detail)
                if !result.ok { throw ExitCode.failure }
            }
        }
    }

    struct Disk: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show disk capacity for a volume.")
        @OptionGroup var format: JSONFlagOptions
        @Option(name: .shortAndLong, help: "Volume path.")
        var path: String = "/"
        func run() throws {
            let d = DiskService.current(path: path)
            print(format.json ? try JSONOutput.string(d) : TextFormat.disk(d))
        }
    }

    struct Network: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show network interface throughput.")
        @OptionGroup var format: JSONFlagOptions
        func run() throws {
            _ = NetworkService.current()
            Thread.sleep(forTimeInterval: 0.4)
            let n = NetworkService.current()
            print(format.json ? try JSONOutput.string(n) : TextFormat.network(n))
        }
    }

    struct CPU: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "cpu",
            abstract: "Show overall and per-core CPU load."
        )
        @OptionGroup var format: JSONFlagOptions
        func run() throws {
            _ = CPULoadService.current()
            Thread.sleep(forTimeInterval: 0.35)
            let c = CPULoadService.current()
            print(format.json ? try JSONOutput.string(c) : TextFormat.cpuLoad(c))
        }
    }

    struct Power: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show thermal pressure and low-power mode.")
        @OptionGroup var format: JSONFlagOptions
        func run() throws {
            let p = PowerService.current()
            print(format.json ? try JSONOutput.string(p) : TextFormat.power(p))
        }
    }

    struct Top: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show top processes by CPU.")
        @OptionGroup var format: JSONFlagOptions
        @Option(name: .shortAndLong, help: "Number of processes.")
        var limit: Int = 10
        func run() throws {
            let list = ProcessService.top(limit: limit)
            print(format.json ? try JSONOutput.string(list) : TextFormat.top(list))
        }
    }

    struct History: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show ~1h CPU/load sparklines.")
        @OptionGroup var format: JSONFlagOptions
        func run() throws {
            HistoryStore.record()
            let h = HistoryStore.snapshot()
            print(format.json ? try JSONOutput.string(h) : TextFormat.history(h))
        }
    }

    struct Watch: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Live-refresh metrics in the terminal.")
        @Option(name: .shortAndLong, help: "Refresh interval in seconds.")
        var interval: Double = 1.5
        func run() throws {
            let seconds = max(0.5, interval)
            while true {
                print("\u{001B}[2J\u{001B}[H", terminator: "")
                print("MasterFabric watch (Ctrl+C)  \(String(format: "%.1fs", seconds))\n")
                HistoryStore.record()
                let status = StatusService.current()
                _ = CPULoadService.current()
                Thread.sleep(forTimeInterval: 0.2)
                let load = CPULoadService.current()
                let batt = BatteryService.current()
                print(TextFormat.status(status))
                print("")
                print(TextFormat.cpuLoad(load))
                if batt.isPresent, let p = batt.percent {
                    print(String(format: "\nBattery: %.0f%%", p))
                }
                let alerts = AlertService.evaluate(status: status, memory: MemoryService.current())
                if !alerts.isEmpty {
                    print("\nAlerts:")
                    alerts.forEach { print("  • \($0)") }
                }
                print("\nUpdated: \(ISO8601DateFormatter().string(from: Date()))")
                fflush(stdout)
                Thread.sleep(forTimeInterval: max(0.1, seconds - 0.2))
            }
        }
    }

    struct Config: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show or update ~/.config/masterfabric/config.toml",
            subcommands: [Show.self, Init.self, Set.self],
            defaultSubcommand: Show.self
        )

        struct Show: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Print current config.")
            @OptionGroup var format: JSONFlagOptions
            func run() throws {
                let c = ConfigStore.load()
                print(format.json ? try JSONOutput.string(c) : TextFormat.config(c))
            }
        }

        struct Init: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Write default config.toml.")
            func run() throws {
                try ConfigStore.save(.default)
                print("Wrote \(ConfigStore.configURL.path)")
            }
        }

        struct Set: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Set a config key.")
            @Argument(help: "Key (language|…|integrations.slack.enabled|integrations.slack.webhook_url|integrations.telegram.*|integrations.mail.*)")
            var key: String
            @Argument(help: "Value")
            var value: String
            func run() throws {
                var c = ConfigStore.load()
                switch key {
                case "language": c.language = value
                case "launch_at_login":
                    c.launchAtLogin = ["1", "true", "yes", "on"].contains(value.lowercased())
                case "poll_interval_seconds":
                    c.pollIntervalSeconds = Double(value) ?? c.pollIntervalSeconds
                case "alerts.enabled":
                    c.alerts.enabled = ["1", "true", "yes", "on"].contains(value.lowercased())
                case "alerts.notify_integrations":
                    c.alerts.notifyIntegrations = ["1", "true", "yes", "on"].contains(value.lowercased())
                case "alerts.notify_local":
                    c.alerts.notifyLocal = ["1", "true", "yes", "on"].contains(value.lowercased())
                case "alerts.notify_cooldown_seconds":
                    c.alerts.notifyCooldownSeconds = Double(value) ?? c.alerts.notifyCooldownSeconds
                case "alerts.cpu_temp_enabled":
                    c.alerts.cpuTempEnabled = ["1", "true", "yes", "on"].contains(value.lowercased())
                case "alerts.cpu_temp_celsius":
                    c.alerts.cpuTempCelsius = Double(value) ?? c.alerts.cpuTempCelsius
                case "alerts.gpu_temp_enabled":
                    c.alerts.gpuTempEnabled = ["1", "true", "yes", "on"].contains(value.lowercased())
                case "alerts.gpu_temp_celsius":
                    c.alerts.gpuTempCelsius = Double(value) ?? c.alerts.gpuTempCelsius
                case "alerts.fan_enabled":
                    c.alerts.fanEnabled = ["1", "true", "yes", "on"].contains(value.lowercased())
                case "alerts.fan_near_max_percent":
                    c.alerts.fanNearMaxPercent = Double(value) ?? c.alerts.fanNearMaxPercent
                case "alerts.memory_pressure_notify":
                    c.alerts.memoryPressureNotify = ["1", "true", "yes", "on"].contains(value.lowercased())
                case "menubar.model_room_target_gb":
                    let parsed = Double(value) ?? c.menuBar.modelRoomTargetGB
                    c.menuBar.modelRoomTargetGB = min(32, max(1, parsed))
                case "alerts.disk_enabled":
                    c.alerts.diskEnabled = ["1", "true", "yes", "on"].contains(value.lowercased())
                case "alerts.disk_used_percent_max":
                    c.alerts.diskUsedPercentMax = Double(value) ?? c.alerts.diskUsedPercentMax
                case "alerts.battery_enabled":
                    c.alerts.batteryEnabled = ["1", "true", "yes", "on"].contains(value.lowercased())
                case "alerts.battery_percent_min":
                    c.alerts.batteryPercentMin = Double(value) ?? c.alerts.batteryPercentMin
                case "alerts.low_power_mode_notify":
                    c.alerts.lowPowerModeNotify = ["1", "true", "yes", "on"].contains(value.lowercased())
                case "integrations.slack.enabled":
                    c.integrations.slack.enabled = ["1", "true", "yes", "on"].contains(value.lowercased())
                case "integrations.slack.webhook_url":
                    c.integrations.slack.webhookURL = value
                case "integrations.telegram.enabled":
                    c.integrations.telegram.enabled = ["1", "true", "yes", "on"].contains(value.lowercased())
                case "integrations.telegram.bot_token":
                    c.integrations.telegram.botToken = value
                case "integrations.telegram.chat_id":
                    c.integrations.telegram.chatID = value
                case "integrations.mail.enabled":
                    c.integrations.mail.enabled = ["1", "true", "yes", "on"].contains(value.lowercased())
                case "integrations.mail.provider":
                    c.integrations.mail.provider = value
                case "integrations.mail.from":
                    c.integrations.mail.from = value
                case "integrations.mail.to":
                    c.integrations.mail.to = value
                case "integrations.mail.subject_prefix":
                    c.integrations.mail.subjectPrefix = value
                case "integrations.mail.smtp_host":
                    c.integrations.mail.smtpHost = value
                case "integrations.mail.smtp_port":
                    c.integrations.mail.smtpPort = Int(value) ?? c.integrations.mail.smtpPort
                case "integrations.mail.smtp_username":
                    c.integrations.mail.smtpUsername = value
                case "integrations.mail.smtp_password":
                    c.integrations.mail.smtpPassword = value
                case "integrations.mail.smtp_use_tls":
                    c.integrations.mail.smtpUseTLS = ["1", "true", "yes", "on"].contains(value.lowercased())
                case "integrations.mail.api_key":
                    c.integrations.mail.apiKey = value
                case "integrations.mail.mailgun_domain":
                    c.integrations.mail.mailgunDomain = value
                default:
                    throw ValidationError("Unknown key: \(key)")
                }
                try ConfigStore.save(c)
                if key == "launch_at_login" {
                    let path = menuBarPath()
                    try LaunchAtLogin.setEnabled(c.launchAtLogin, executablePath: path)
                }
                print(TextFormat.config(c))
            }
        }
    }

    struct Login: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Enable/disable menu bar launch at login.",
            subcommands: [Enable.self, Disable.self, Status.self],
            defaultSubcommand: Status.self
        )
        struct Enable: ParsableCommand {
            func run() throws {
                var c = ConfigStore.load()
                c.launchAtLogin = true
                try ConfigStore.save(c)
                try LaunchAtLogin.setEnabled(true, executablePath: menuBarPath())
                print("Launch at login enabled → \(menuBarPath())")
            }
        }
        struct Disable: ParsableCommand {
            func run() throws {
                var c = ConfigStore.load()
                c.launchAtLogin = false
                try ConfigStore.save(c)
                try LaunchAtLogin.setEnabled(false, executablePath: menuBarPath())
                print("Launch at login disabled")
            }
        }
        struct Status: ParsableCommand {
            func run() throws {
                print(LaunchAtLogin.isEnabled ? "enabled" : "disabled")
            }
        }
    }

    struct Check: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Evaluate alert thresholds and print warnings.")
        @Flag(name: .long, help: "Deliver via Slack/Telegram/mail (and macOS banner when running as .app).")
        var notify: Bool = false
        @OptionGroup var format: JSONFlagOptions
        func run() throws {
            let status = StatusService.current()
            let memory = MemoryService.current()
            let alerts = AlertService.evaluate(status: status, memory: memory)
            var delivered: [NotifyDeliveryResult] = []
            if notify, !alerts.isEmpty {
                delivered = IntegrationNotifier.deliverAlerts(alerts)
            }
            if format.json {
                struct Payload: Encodable {
                    let alerts: [String]
                    let delivered: [NotifyDeliveryResult]
                }
                print(try JSONOutput.string(Payload(alerts: alerts, delivered: delivered)))
                return
            }
            if alerts.isEmpty {
                print("OK — no alerts")
            } else {
                alerts.forEach { print("• \($0)") }
            }
            if notify {
                print("")
                if alerts.isEmpty {
                    print("Nothing to deliver")
                } else {
                    print(TextFormat.notifyResults(delivered))
                }
            }
        }
    }

    struct Notify: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Send a message or test alerts via Slack, Telegram, or mail.",
            subcommands: [Send.self, Test.self, Status.self],
            defaultSubcommand: Status.self
        )

        struct Status: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Show integration configuration status.")
            @OptionGroup var format: JSONFlagOptions
            func run() throws {
                let c = ConfigStore.load().integrations
                if format.json {
                    print(try JSONOutput.string(c))
                } else {
                    let listed = c.listedKinds.isEmpty ? "none" : c.listedKinds.joined(separator: ", ")
                    print("""
                    Slack:    enabled=\(c.slack.enabled) configured=\(c.slack.isConfigured)
                    Telegram: enabled=\(c.telegram.enabled) configured=\(c.telegram.isConfigured)
                    Mail:     enabled=\(c.mail.enabled) provider=\(c.mail.provider) configured=\(c.mail.isConfigured)
                    Listed:   \(listed)
                    Config:   \(ConfigStore.configURL.path)
                    """)
                }
            }
        }

        struct Send: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Send a custom message to a channel.")
            @Option(name: .shortAndLong, help: "Channel: slack | telegram | mail | all")
            var channel: String = "all"
            @Argument(help: "Message text")
            var message: String
            @OptionGroup var format: JSONFlagOptions
            func run() throws {
                guard let ch = NotifyChannel(rawValue: channel.lowercased()) else {
                    throw ValidationError("channel must be slack, telegram, mail, or all")
                }
                let results = IntegrationNotifier.send(message, channel: ch)
                if format.json {
                    print(try JSONOutput.string(results))
                } else {
                    print(TextFormat.notifyResults(results))
                }
                if results.contains(where: { !$0.ok }) {
                    throw ExitCode.failure
                }
            }
        }

        struct Test: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Send a test message to configured channels.")
            @Option(name: .shortAndLong, help: "Channel: slack | telegram | mail | all")
            var channel: String = "all"
            @OptionGroup var format: JSONFlagOptions
            func run() throws {
                guard let ch = NotifyChannel(rawValue: channel.lowercased()) else {
                    throw ValidationError("channel must be slack, telegram, mail, or all")
                }
                let host = SystemInfoService.current().model
                let msg = "MasterFabric test notification from \(host) at \(ISO8601DateFormatter().string(from: Date()))"
                let results = IntegrationNotifier.send(msg, channel: ch)
                if format.json {
                    print(try JSONOutput.string(results))
                } else {
                    print(TextFormat.notifyResults(results))
                }
                if results.contains(where: { !$0.ok }) {
                    throw ExitCode.failure
                }
            }
        }
    }

    struct Bot: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Run interactive bots that answer with live Mac metrics.",
            subcommands: [Telegram.self],
            defaultSubcommand: Telegram.self
        )

        struct Telegram: ParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Long-poll Telegram: reply to /status, /temp, questions, etc. with machine data."
            )

            @Option(name: .long, help: "Extra allowed chat_id (numeric). Can repeat.")
            var allowChat: [Int] = []

            func run() throws {
                var options = try TelegramBotService.optionsFromConfig()
                for id in allowChat {
                    options.allowedChatIDs.insert(id)
                }
                guard !options.allowedChatIDs.isEmpty else {
                    throw ValidationError(
                        "Set a numeric chat_id first:\n  mf config set integrations.telegram.chat_id \"123456789\"\nThen: mf bot telegram"
                    )
                }
                print("Starting Telegram bot (Ctrl+C to stop)…")
                fflush(stdout)
                try TelegramBotService.run(options: options)
            }
        }
    }

    struct Version: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show local version; optionally check the open-source GitHub repo for updates."
        )

        @Flag(name: .long, help: "Query GitHub releases/tags for a newer version.")
        var check: Bool = false

        @OptionGroup var format: JSONFlagOptions

        func run() throws {
            if check {
                let result = VersionService.check()
                if format.json {
                    print(try JSONOutput.string(result))
                } else {
                    print(VersionService.format(result))
                }
                if result.updateAvailable {
                    throw ExitCode(2)
                }
            } else if format.json {
                print(try JSONOutput.string([
                    "version": AppVersion.current,
                    "product": AboutInfo.product,
                    "repo": AppVersion.repoURL,
                ] as [String: String]))
            } else {
                print("\(AboutInfo.product) v\(AppVersion.current)")
                print("Repo: \(AppVersion.repoURL)")
                print("Check updates: mf version --check")
                print("Install update: mf update")
            }
        }
    }

    struct Update: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Upgrade from the open-source GitHub repo (runs scripts/install.sh)."
        )

        @Flag(name: .long, help: "Reinstall even when already up to date.")
        var force: Bool = false

        @Option(name: .long, help: "Install prefix (default: ~/.local).")
        var prefix: String?

        @OptionGroup var format: JSONFlagOptions

        func run() throws {
            if !format.json {
                print("Checking GitHub…")
                fflush(stdout)
            }
            let result = UpdateService.update(force: force, prefix: prefix) { step in
                guard !format.json else { return }
                switch step {
                case "checking_github":
                    break
                case let s where s.hasPrefix("github_ok:"):
                    print("GitHub latest: v\(s.dropFirst("github_ok:".count))")
                    fflush(stdout)
                case let s where s.hasPrefix("installing:"):
                    print("Installing into \(s.dropFirst("installing:".count)) …")
                    fflush(stdout)
                case "install_finished":
                    print("Install finished — verifying…")
                    fflush(stdout)
                case let s where s.hasPrefix("verify:"):
                    print("Verified installed: v\(s.dropFirst("verify:".count))")
                    fflush(stdout)
                case "install_failed":
                    print("Install failed.")
                    fflush(stdout)
                default:
                    break
                }
            }
            if format.json {
                print(try JSONOutput.string(result))
            } else {
                print(UpdateService.format(result))
            }
            if result.performed == false, result.check.updateAvailable || force {
                throw ExitCode.failure
            }
            if result.performed == false, result.check.source == "error" {
                throw ExitCode.failure
            }
        }
    }

    struct About: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Product info, version, privacy.")
        @Option(name: .long, help: "Language override (en|tr).")
        var lang: String?
        func run() throws {
            print(AboutInfo.text(language: lang))
        }
    }

    struct MenuBar: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "menubar",
            abstract: "Launch the MasterFabric menu bar app."
        )
        func run() throws {
            // Prefer opening the .app bundle so Resources (brand logos) resolve via Bundle.main.
            if let app = resolveMenuBarApp() {
                // Replace any stale instance so we always run the installed binary.
                let kill = Process()
                kill.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
                kill.arguments = ["MasterFabricMenuBar"]
                try? kill.run()
                kill.waitUntilExit()
                Thread.sleep(forTimeInterval: 0.2)

                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                process.arguments = ["-n", "-a", app]
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus != 0 {
                    // Fallback: launch executable directly
                    let exe = "\(app)/Contents/MacOS/MasterFabricMenuBar"
                    guard FileManager.default.isExecutableFile(atPath: exe) else {
                        throw ValidationError("Menu bar app missing executable at \(exe). Run `make install`.")
                    }
                    let direct = Process()
                    direct.executableURL = URL(fileURLWithPath: exe)
                    try direct.run()
                    print("Launched MasterFabricMenuBar (direct) from \(exe)")
                    return
                }
                print("Launched \(app)")
                return
            }
            let path = try resolveMenuBarExecutable()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            try process.run()
            print("Launched MasterFabricMenuBar from \(path)")
        }
    }
}

func menuBarPath() -> String {
    (try? resolveMenuBarExecutable())
        ?? "\(NSHomeDirectory())/.local/MasterFabricMenuBar.app/Contents/MacOS/MasterFabricMenuBar"
}

func resolveMenuBarExecutable() throws -> String {
    let fm = FileManager.default
    let home = NSHomeDirectory()
    let candidates = [
        "\(home)/.local/MasterFabricMenuBar.app/Contents/MacOS/MasterFabricMenuBar",
        Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("MasterFabricMenuBar").path,
        ".build/release/MasterFabricMenuBar",
        ".build/debug/MasterFabricMenuBar",
        "/usr/local/bin/MasterFabricMenuBar",
        "\(home)/.local/bin/MasterFabricMenuBar",
    ].compactMap { $0 }

    for path in candidates where fm.isExecutableFile(atPath: path) {
        return path
    }
    throw ValidationError("MasterFabricMenuBar not found. Run `make install`.")
}

func resolveMenuBarApp() -> String? {
    let app = "\(NSHomeDirectory())/.local/MasterFabricMenuBar.app"
    if FileManager.default.fileExists(atPath: app) { return app }
    return nil
}
