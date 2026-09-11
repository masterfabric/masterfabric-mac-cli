import AppKit
import Foundation
import MasterFabricCore
import SwiftUI

/// Renders README screenshots without Accessibility permission.
@main
@MainActor
struct GenerateScreenshot {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let status = StatusService.current()
        let info = SystemInfoService.current()
        let battery = BatteryService.current()
        let memory = MemoryService.current()
        _ = CPULoadService.current()
        Thread.sleep(forTimeInterval: 0.35)
        let load = CPULoadService.current()
        let power = PowerService.current()
        HistoryStore.record()
        let history = HistoryStore.snapshot()
        var config = ConfigStore.load()
        config.language = "en"
        config.integrations.telegram.enabled = true
        config.integrations.telegram.botToken = "demo"
        config.integrations.telegram.chatID = "123456789"
        let alerts = AlertService.evaluate(
            status: status,
            memory: memory,
            disk: DiskService.current(),
            battery: battery,
            power: power,
            config: config
        )

        let outDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/screenshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let display = MenuBarDisplayConfig.default
        let title = TextFormat.compactStatusBar(status, load: load, battery: battery, display: display)
        let fanFull = FanService.isFullMode(status.fans)

        writePNG(
            content: MenuBarShot(
                title: title,
                fanIsFull: fanFull,
                showFanBadge: !status.fans.isEmpty,
                info: info,
                status: status,
                load: load,
                power: power,
                battery: battery,
                memory: memory,
                history: history,
                alerts: alerts,
                alertConfig: config.alerts,
                integrations: config.integrations
            )
            .padding(20)
            .frame(width: 380)
            .background(Color(nsColor: .windowBackgroundColor)),
            to: outDir.appendingPathComponent("menubar.png")
        )

        writePNG(
            content: MenuBarSettingsShot(draft: display)
                .padding(20)
                .frame(width: 380)
                .background(Color(nsColor: .windowBackgroundColor)),
            to: outDir.appendingPathComponent("menubar-settings.png")
        )

        writePNG(
            content: StatusStylesShot(status: status, load: load, battery: battery, fanIsFull: fanFull)
                .padding(20)
                .frame(width: 720)
                .background(Color(nsColor: .windowBackgroundColor)),
            to: outDir.appendingPathComponent("menubar-styles.png")
        )

        let cliBody = buildCLITranscript(status: status, info: info, load: load, memory: memory)
        writePNG(
            content: TerminalShot(transcript: cliBody)
                .padding(24)
                .frame(width: 720)
                .background(Color(red: 0.12, green: 0.13, blue: 0.15)),
            to: outDir.appendingPathComponent("cli.png")
        )
    }

    private static func buildCLITranscript(
        status: SystemStatus,
        info: SystemInfo,
        load: CPULoadInfo,
        memory: MemoryInfo
    ) -> String {
        let cpu = status.temperature.cpuCelsius.map { String(format: "%.1f°C", $0) } ?? "N/A"
        let gpu = status.temperature.gpuCelsius.map { String(format: "%.1f°C", $0) } ?? "N/A"
        let fansLine: String = {
            if status.fans.isEmpty { return "Fan: N/A" }
            return status.fans.map { fan in
                let rpm = fan.rpm.map { String(format: "%.0f", $0) } ?? "—"
                return "\(fan.name) [\(fan.role)]: \(rpm) RPM · \(fan.mode)"
            }.joined(separator: "\n")
        }()
        return """
        $ mf status
        CPU \(cpu)  ·  GPU \(gpu)  ·  Fan \(status.fans.first?.rpm.map { String(format: "%.0f", $0) } ?? "N/A")

        $ mf fan
        \(fansLine)

        $ mf fan helper status
        Fan helper: running (no password needed for Auto/Full).

        $ mf fan full --elevate
        ✓ Fans set to Full (max RPM)

        $ mf fan auto --elevate
        ✓ Fans set to Auto (system thermal)

        $ mf about
        \(AboutInfo.product) v\(AboutInfo.version)
        \(info.model) · \(info.chip)
        Privacy-first · no telemetry · MIT
        """
    }

    @MainActor
    private static func writePNG<V: View>(content: V, to url: URL) {
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2.0
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else {
            fputs("Failed to render \(url.lastPathComponent)\n", stderr)
            exit(1)
        }
        do {
            try png.write(to: url)
            print("Wrote \(url.path)")
        } catch {
            fputs("Write failed: \(error)\n", stderr)
            exit(1)
        }
    }
}

// MARK: - Shared chrome

private struct StatusStrip: View {
    let title: String
    let showBadge: Bool
    let fanIsFull: Bool
    var capsule: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Text("MF")
                .font(.caption.weight(.bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 4))

            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(capsule ? .white : .primary)
                if showBadge {
                    Text(fanIsFull ? "F" : "A")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            fanIsFull
                                ? Color(red: 0.20, green: 0.48, blue: 0.96)
                                : Color(red: 0.18, green: 0.72, blue: 0.36),
                            in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                        )
                }
            }
            .padding(.horizontal, capsule ? 8 : 0)
            .padding(.vertical, capsule ? 3 : 0)
            .background(
                capsule
                    ? Capsule().fill(Color(white: 0.22).opacity(0.92))
                    : nil
            )
            Spacer()
        }
    }
}

private func shotRow(_ label: String, _ value: String) -> some View {
    HStack {
        Text(label).foregroundStyle(.secondary)
        Spacer()
        Text(value).font(.body.monospacedDigit())
    }
}

// MARK: - Main panel

private struct MenuBarShot: View {
    let title: String
    let fanIsFull: Bool
    let showFanBadge: Bool
    let info: SystemInfo
    let status: SystemStatus
    let load: CPULoadInfo
    let power: PowerInfo
    let battery: BatteryInfo
    let memory: MemoryInfo
    let history: HistorySnapshot
    let alerts: [String]
    let alertConfig: AlertConfig
    let integrations: IntegrationsConfig

    private let alertKinds: [(String, String)] = [
        ("thermometer.medium", "CPU"),
        ("cpu", "GPU"),
        ("fanblades", "Fan"),
        ("memorychip", "Mem"),
        ("internaldrive", "Disk"),
        ("battery.100", "Batt"),
        ("bolt.fill", "Power"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StatusStrip(title: title, showBadge: showFanBadge, fanIsFull: fanIsFull)
                .padding(.bottom, 2)

            Text("MasterFabric")
                .font(.headline)
            Text("MacBook system monitor · CLI · Menu Bar · MCP")
                .font(.caption2)
                .foregroundStyle(.secondary)

            shotRow("Model", info.model)
            shotRow("Chip", info.chip)

            Divider()

            shotRow("CPU", status.temperature.cpuCelsius.map { String(format: "%.1f °C", $0) } ?? "N/A")
            shotRow("GPU", status.temperature.gpuCelsius.map { String(format: "%.1f °C", $0) } ?? "N/A")
            shotRow("Load", String(format: "%.1f%%", load.overallPercent))
            shotRow("Thermal", power.thermalState)

            if status.fans.isEmpty {
                shotRow("Fan", "N/A")
            } else {
                ForEach(Array(status.fans.enumerated()), id: \.offset) { _, fan in
                    let rpm = fan.rpm.map { String(format: "%.0f", $0) } ?? "—"
                    let max = fan.maxRPM.map { String(format: "%.0f", $0) } ?? "?"
                    shotRow(fan.name, "\(rpm)/\(max) · \(fan.mode)")
                }
                HStack {
                    Text("Fan control")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Auto")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                    Text("Full")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                }
            }

            Divider()

            if battery.isPresent {
                shotRow("Battery", battery.percent.map { String(format: "%.0f%%", $0) } ?? "N/A")
            }
            shotRow("Memory", String(format: "%.0f%% · %@", memory.usedPercent, memory.pressure))
            shotRow("CPU hist", history.cpuSparkline)

            Divider()

            HStack {
                Text("Alerts")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(alertConfig.enabled ? "On" : "Off")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                ForEach(Array(alertKinds.enumerated()), id: \.offset) { _, item in
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.22))
                            .frame(width: 28, height: 28)
                        Image(systemName: item.0)
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
            }

            if !alerts.isEmpty {
                ForEach(alerts.prefix(2), id: \.self) { alert in
                    Text(alert)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Divider()

            HStack {
                Text("Integrations")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                ShotBrandBadge.telegram
                Text("Telegram").font(.callout)
                Spacer()
                Text("On").font(.caption2).foregroundStyle(.secondary)
            }

            Divider()

            Text("About")
                .font(.subheadline.weight(.semibold))
            Text("\(AboutInfo.product) v\(AboutInfo.version)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            HStack {
                Text("Quit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        )
    }
}

// MARK: - Settings shot

private struct MenuBarSettingsShot: View {
    let draft: MenuBarDisplayConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Menu Bar Settings")
                    .font(.headline)
                Spacer()
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }

            Text("Status item style")
                .font(.subheadline.weight(.semibold))

            ForEach(MenuBarStatusStyle.allCases) { style in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: draft.style == style ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(draft.style == style ? Color.accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(style.title)
                            .font(.callout.weight(.medium))
                        Text(style.subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }

            Divider()

            Text("Show in menu bar")
                .font(.subheadline.weight(.semibold))
            toggleRow("CPU temperature", draft.showCPUTemp)
            toggleRow("CPU load %", draft.showLoad)
            toggleRow("Fan RPM", draft.showFanRPM)
            toggleRow("Fan A/F badge", draft.showFanBadge)

            Divider()

            Text("Show in panel")
                .font(.subheadline.weight(.semibold))
            toggleRow("Fans", draft.panelFans)
            toggleRow("Fan control", draft.panelFanControl)
            toggleRow("Alerts", draft.panelAlerts)
            toggleRow("Integrations", draft.panelIntegrations)

            HStack {
                Text("Reset").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("Done")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        )
    }

    private func toggleRow(_ title: String, _ on: Bool) -> some View {
        HStack {
            Text(title).font(.caption)
            Spacer()
            Image(systemName: on ? "switch.2" : "switch.2")
                .foregroundStyle(on ? Color.green : Color.secondary)
                .font(.caption)
            Text(on ? "On" : "Off")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
        }
    }
}

// MARK: - Four styles strip

private struct StatusStylesShot: View {
    let status: SystemStatus
    let load: CPULoadInfo
    let battery: BatteryInfo
    let fanIsFull: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Menu bar status styles")
                .font(.headline)

            ForEach(MenuBarStatusStyle.allCases) { style in
                styleRow(style)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
        )
    }

    private func styleRow(_ style: MenuBarStatusStyle) -> some View {
        var display = MenuBarDisplayConfig.default
        display.style = style
        let image = StatusItemRenderer.make(
            status: status,
            load: load,
            battery: battery,
            memory: nil,
            display: display,
            isFull: fanIsFull
        )

        return VStack(alignment: .leading, spacing: 6) {
            Text(style.title)
                .font(.subheadline.weight(.semibold))
            Text(style.subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text("MF")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.5))
                Image(nsImage: image)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.82))
            )
        }
    }
}

private enum ShotBrandBadge {
    static var telegram: some View {
        logo("brand-telegram")
    }

    private static func logo(_ name: String) -> some View {
        Group {
            if let url = Bundle.module.url(forResource: name, withExtension: "png"),
               let ns = NSImage(contentsOf: url)
            {
                Image(nsImage: ns)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 22, height: 22)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color(red: 34 / 255, green: 158 / 255, blue: 217 / 255))
                    .frame(width: 22, height: 22)
            }
        }
    }
}

// MARK: - CLI terminal shot

private struct TerminalShot: View {
    let transcript: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(Color(red: 1, green: 0.38, blue: 0.35)).frame(width: 10, height: 10)
                Circle().fill(Color(red: 1, green: 0.74, blue: 0.25)).frame(width: 10, height: 10)
                Circle().fill(Color(red: 0.19, green: 0.8, blue: 0.35)).frame(width: 10, height: 10)
                Spacer()
                Text("mf — MasterFabric CLI")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.55))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.35))

            Text(transcript)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(Color(red: 0.86, green: 0.9, blue: 0.88))
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 0.09, green: 0.1, blue: 0.12))
                .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
