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
        let outDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/screenshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let display = MenuBarDisplayConfig.default
        let disk = DiskService.current()
        let fanFull = FanService.isFullMode(status.fans)
        let statusImage = StatusItemRenderer.make(
            status: status,
            load: load,
            battery: battery,
            memory: memory,
            disk: disk,
            display: display,
            isFull: fanFull
        )

        writePNG(
            content: PurposeShot()
                .padding(24)
                .frame(width: 880)
                .background(Color(nsColor: .windowBackgroundColor)),
            to: outDir.appendingPathComponent("purpose.png")
        )

        writePNG(
            content: MenuBarShot(
                statusImage: statusImage,
                info: info,
                status: status,
                load: load,
                power: power,
                battery: battery,
                memory: memory,
                disk: disk,
                history: history
            )
            .padding(20)
            .frame(width: 400)
            .background(Color(nsColor: .windowBackgroundColor)),
            to: outDir.appendingPathComponent("menubar.png")
        )

        writePNG(
            content: MenuBarSettingsShot(
                draft: display,
                status: status,
                load: load,
                battery: battery,
                fanIsFull: fanFull
            )
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

        let cliBody = buildCLITranscript(status: status, info: info, load: load, memory: memory, disk: disk)
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
        memory: MemoryInfo,
        disk: DiskInfo
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

        $ mf disk
        \(disk.volumeName.isEmpty ? disk.path : disk.volumeName): \(String(format: "%.0f%%", disk.usedPercent)) used · \(TextFormat.bytes(disk.freeBytes)) free

        $ mf memory room
        Room: \(TextFormat.bytes(MemoryRoomService.headroom().availableBytes)) allocatable · \(String(format: "%.0f%%", memory.usedPercent)) used

        $ mf about
        \(AboutInfo.product) v\(AboutInfo.version)
        \(info.model) · \(info.chip)
        Privacy-first · no telemetry · AGPL-3.0
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

private func shotRow(_ label: String, _ value: String) -> some View {
    HStack {
        Text(label).foregroundStyle(.secondary)
        Spacer()
        Text(value).font(.body.monospacedDigit())
    }
}

private enum ShotMeterTint {
    case heat(Double)
    case load
    case capacity
    case battery
    case fan
}

private struct ShotMeter: View {
    var percent: Double
    var tint: ShotMeterTint

    var body: some View {
        Capsule()
            .fill(Color.primary.opacity(0.08))
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule()
                        .fill(fill)
                        .frame(width: max(4, geo.size.width * CGFloat(min(1, max(0, percent / 100)))))
                }
            }
            .frame(height: 5)
            .clipShape(Capsule())
    }

    private var fill: Color {
        switch tint {
        case .heat(let celsius):
            if celsius >= 88 { return Color(red: 0.92, green: 0.28, blue: 0.25) }
            if celsius >= 78 { return Color(red: 0.95, green: 0.55, blue: 0.15) }
            if celsius >= 65 { return Color(red: 0.92, green: 0.75, blue: 0.12) }
            return Color(red: 0.22, green: 0.78, blue: 0.42)
        case .load, .fan:
            if percent >= 85 { return Color(red: 0.92, green: 0.28, blue: 0.25) }
            if percent >= 60 { return Color(red: 0.95, green: 0.55, blue: 0.15) }
            return Color(red: 0.20, green: 0.62, blue: 0.95)
        case .capacity:
            if percent >= 90 { return Color(red: 0.92, green: 0.28, blue: 0.25) }
            if percent >= 75 { return Color(red: 0.95, green: 0.55, blue: 0.15) }
            return Color(red: 0.22, green: 0.72, blue: 0.42)
        case .battery:
            if percent <= 20 { return Color(red: 0.92, green: 0.28, blue: 0.25) }
            return Color(red: 0.22, green: 0.72, blue: 0.42)
        }
    }
}

private struct ShotSparkline: View {
    var samples: [HistorySample]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text("Last hour").foregroundStyle(.secondary)
                Spacer(minLength: 8)
                legend(Color(red: 0.95, green: 0.55, blue: 0.15), "CPU")
                legend(Color(red: 0.20, green: 0.62, blue: 0.95), "Load")
            }
            .font(.caption)
            Canvas { context, size in
                let plot = CGRect(x: 0, y: 3, width: size.width, height: max(1, size.height - 6))
                guard let start = samples.first?.timestamp, let end = samples.last?.timestamp else { return }
                stroke(samples.compactMap { sample in sample.cpuCelsius.map { (sample.timestamp, $0) } }, in: plot, from: start, to: end, low: 30, high: 100, color: Color(red: 0.95, green: 0.55, blue: 0.15), context: context)
                stroke(samples.compactMap { sample in sample.cpuLoadPercent.map { (sample.timestamp, $0) } }, in: plot, from: start, to: end, low: 0, high: 100, color: Color(red: 0.20, green: 0.62, blue: 0.95), context: context)
            }
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
        }
    }

    private func legend(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title).foregroundStyle(.secondary)
        }
    }

    private func stroke(
        _ points: [(Date, Double)],
        in plot: CGRect,
        from start: Date,
        to end: Date,
        low: Double,
        high: Double,
        color: Color,
        context: GraphicsContext
    ) {
        guard points.count >= 2 else { return }
        let span = max(end.timeIntervalSince(start), 1)
        let valueSpan = max(high - low, 1)
        var path = Path()
        for (index, point) in points.enumerated() {
            let x = plot.minX + CGFloat(point.0.timeIntervalSince(start) / span) * plot.width
            let fraction = min(1, max(0, (point.1 - low) / valueSpan))
            let y = plot.maxY - CGFloat(fraction) * plot.height
            let next = CGPoint(x: x, y: y)
            if index == 0 { path.move(to: next) } else { path.addLine(to: next) }
        }
        context.stroke(path, with: .color(color), lineWidth: 1.5)
    }
}

// MARK: - Main panel

private struct PurposeShot: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("On your Mac. For your agent.")
                    .font(.title2.weight(.semibold))
                Text("Temps, fans, storage, and allocatable RAM stay on this machine. The menu bar, the mf CLI, and a local MCP server all read the same sensors. No telemetry.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .top, spacing: 12) {
                purposeCard(
                    symbol: "rectangle.topthird.inset.filled",
                    title: "Menu bar",
                    lines: [
                        "Meters for heat, load, and fans",
                        "Storage fill, used, and free",
                        "RAM room asks before it quits apps",
                    ]
                )
                purposeCard(
                    symbol: "terminal",
                    title: "CLI",
                    lines: [
                        "mf status --json",
                        "mf disk",
                        "mf memory room",
                    ]
                )
                purposeCard(
                    symbol: "desktopcomputer",
                    title: "MCP",
                    lines: [
                        "get_status · get_disk",
                        "get_memory_room",
                        "Local stdio only",
                    ]
                )
            }
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.12), radius: 16, y: 4)
        )
    }

    private func purposeCard(symbol: String, title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
            Text(title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

private struct MenuBarShot: View {
    let statusImage: NSImage
    let info: SystemInfo
    let status: SystemStatus
    let load: CPULoadInfo
    let power: PowerInfo
    let battery: BatteryInfo
    let memory: MemoryInfo
    let disk: DiskInfo
    let history: HistorySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("MF")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
                Image(nsImage: statusImage)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.82)))

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MasterFabric")
                        .font(.headline)
                    Text("Mac system monitor · CLI · Menu Bar · MCP")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "memorychip")
                    .font(.system(size: 13, weight: .semibold))
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
            }

            shotRow("Model", info.model)
            shotRow("Chip", info.chip)
            Divider()

            if let cpu = status.temperature.cpuCelsius {
                meterRow("CPU", String(format: "%.1f °C", cpu), percent: heatMeter(cpu), tint: .heat(cpu))
            } else {
                shotRow("CPU", "N/A")
            }
            if let gpu = status.temperature.gpuCelsius {
                meterRow("GPU", String(format: "%.1f °C", gpu), percent: heatMeter(gpu), tint: .heat(gpu))
            }
            meterRow("Load", String(format: "%.1f%%", load.overallPercent), percent: load.overallPercent, tint: .load)
            shotRow("Thermal", power.thermalState)

            if status.fans.isEmpty {
                shotRow("Fan", "N/A")
            } else {
                ForEach(Array(status.fans.enumerated()), id: \.offset) { _, fan in
                    let rpm = fan.rpm.map { String(format: "%.0f", $0) } ?? "—"
                    let max = fan.maxRPM.map { String(format: "%.0f", $0) } ?? "?"
                    VStack(alignment: .leading, spacing: 3) {
                        shotRow(fan.name, "\(rpm)/\(max) · \(fan.mode)")
                        if let current = fan.rpm, let cap = fan.maxRPM, cap > 0 {
                            ShotMeter(percent: min(100, current / cap * 100), tint: .fan)
                        }
                    }
                }
                HStack {
                    Text("Fan control").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("Auto").font(.caption.weight(.semibold))
                    Text("Full").font(.caption.weight(.semibold)).foregroundStyle(.blue)
                }
            }

            Divider()
            if battery.isPresent, let percent = battery.percent {
                meterRow("Battery", String(format: "%.0f%%", percent), percent: percent, tint: .battery)
            }
            storageBlock
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Memory").foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.0f%% · %@", memory.usedPercent, memory.pressure))
                        .font(.body.monospacedDigit())
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                ShotMeter(percent: memory.usedPercent, tint: .capacity)
            }
            ShotSparkline(samples: history.samples)

            Divider()
            HStack {
                Text("Quit").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .semibold))
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

    private var storageBlock: some View {
        let name = disk.volumeName.isEmpty ? "Storage" : disk.volumeName
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name).foregroundStyle(.secondary)
                Spacer()
                Text(disk.totalBytes > 0 ? String(format: "%.0f%%", disk.usedPercent) : "N/A")
                    .font(.body.monospacedDigit())
            }
            ShotMeter(percent: disk.usedPercent, tint: .capacity)
            Text(disk.totalBytes > 0
                 ? "\(TextFormat.bytes(disk.usedBytes)) of \(TextFormat.bytes(disk.totalBytes)) · \(TextFormat.bytes(disk.freeBytes)) free"
                 : "Capacity unavailable")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func heatMeter(_ celsius: Double) -> Double {
        min(100, max(0, (celsius - 35) / 65 * 100))
    }

    private func meterRow(_ label: String, _ value: String, percent: Double, tint: ShotMeterTint) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            shotRow(label, value)
            ShotMeter(percent: percent, tint: tint)
        }
    }
}

// MARK: - Settings shot

private struct MenuBarSettingsShot: View {
    let draft: MenuBarDisplayConfig
    let status: SystemStatus
    let load: CPULoadInfo
    let battery: BatteryInfo
    let fanIsFull: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Settings")
                    .font(.headline)
                Spacer()
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }

            Text("Look")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.16), in: Capsule())

            Text("Status item")
                .font(.subheadline.weight(.semibold))
            Text(draft.style.subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text("MF")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
                Image(nsImage: StatusItemRenderer.make(
                    status: status,
                    load: load,
                    battery: battery,
                    memory: nil,
                    display: draft,
                    isFull: fanIsFull
                ))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.82)))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], spacing: 6) {
                ForEach(MenuBarStatusStyle.allCases) { style in
                    let selected = draft.style == style
                    Text(style.title)
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selected ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 1)
                        )
                }
            }

            Divider()

            Text("On the status item")
                .font(.subheadline.weight(.semibold))
            toggleRow("CPU °C", draft.showCPUTemp)
            toggleRow("Load %", draft.showLoad)
            toggleRow("Fan RPM", draft.showFanRPM)
            toggleRow("Storage", draft.showDisk)
            toggleRow("Memory", draft.showMemory)

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
