import AppKit
import Foundation

public enum StatusBarTokenKind: Sendable, Equatable {
    case cpuTemp
    case gpuTemp
    case load
    case fan
    case battery
    case memory
}

public struct StatusBarToken: Sendable, Equatable {
    public var text: String
    public var kind: StatusBarTokenKind
    public var value: Double?

    public init(text: String, kind: StatusBarTokenKind, value: Double? = nil) {
        self.text = text
        self.kind = kind
        self.value = value
    }
}

public enum StatusBarComposer {
    public static func tokens(
        status: SystemStatus,
        load: CPULoadInfo?,
        battery: BatteryInfo?,
        memory: MemoryInfo?,
        display: MenuBarDisplayConfig
    ) -> [StatusBarToken] {
        switch display.style {
        case .tempOnly:
            if let cpu = status.temperature.cpuCelsius {
                return [StatusBarToken(text: String(format: "%.0f°", cpu), kind: .cpuTemp, value: cpu)]
            }
            return [StatusBarToken(text: "—°", kind: .cpuTemp)]
        case .fanOnly:
            if let fan = status.fans.first, let rpm = fan.rpm {
                return [StatusBarToken(text: "\(Int(rpm))", kind: .fan, value: rpm)]
            }
            return [StatusBarToken(text: "Fan —", kind: .fan)]
        case .standard, .compact, .stacked, .meters, .capsule:
            break
        }

        let short = display.showShortLabels || display.style == .compact
            || display.style == .stacked || display.style == .meters
        var items: [StatusBarToken] = []

        if display.showCPUTemp {
            let cpu = status.temperature.cpuCelsius
            let value = cpu.map { String(format: "%.0f°", $0) } ?? "—"
            let text = short ? value : "CPU \(value)"
            items.append(StatusBarToken(text: text, kind: .cpuTemp, value: cpu))
        }
        if display.showGPUTemp, let gpu = status.temperature.gpuCelsius {
            let value = String(format: "%.0f°", gpu)
            items.append(StatusBarToken(text: short ? "G\(value)" : "GPU \(value)", kind: .gpuTemp, value: gpu))
        }
        if display.showLoad, let load {
            items.append(
                StatusBarToken(
                    text: String(format: "%.0f%%", load.overallPercent),
                    kind: .load,
                    value: load.overallPercent
                )
            )
        }
        if display.showFanRPM, let fan = status.fans.first, let rpm = fan.rpm {
            let value = "\(Int(rpm))"
            items.append(StatusBarToken(text: short ? value : "Fan \(value)", kind: .fan, value: rpm))
        }
        if display.showBattery, let battery, battery.isPresent, let pct = battery.percent {
            let value = String(format: "%.0f%%", pct)
            items.append(StatusBarToken(text: short ? "B\(value)" : "Bat \(value)", kind: .battery, value: pct))
        }
        if display.showMemory, let memory {
            let value = String(format: "%.0f%%", memory.usedPercent)
            items.append(StatusBarToken(text: short ? "M\(value)" : "Mem \(value)", kind: .memory, value: memory.usedPercent))
        }
        if items.isEmpty {
            return [StatusBarToken(text: "mf", kind: .cpuTemp)]
        }
        return items
    }
}

/// Bitmap status item. MenuBarExtra strips SwiftUI backgrounds, so we draw into an `NSImage`.
public enum StatusItemRenderer {
    public static func make(
        status: SystemStatus,
        load: CPULoadInfo,
        battery: BatteryInfo?,
        memory: MemoryInfo?,
        display: MenuBarDisplayConfig,
        isFull: Bool,
        updateAvailable: Bool = false
    ) -> NSImage {
        let tokens = StatusBarComposer.tokens(
            status: status,
            load: load,
            battery: battery,
            memory: memory,
            display: display
        )
        let fansPresent = !status.fans.isEmpty
        let showBadge = display.style.allowsFanBadge && display.showFanBadge && fansPresent
        let cpuTemp = status.temperature.cpuCelsius
        let loadPct = load.overallPercent

        switch display.style {
        case .stacked:
            return drawStacked(
                tokens: tokens,
                display: display,
                showBadge: showBadge,
                isFull: isFull,
                updateAvailable: updateAvailable
            )
        case .meters:
            return drawMeters(
                tokens: tokens,
                display: display,
                cpuTemp: cpuTemp,
                loadPct: loadPct,
                showBadge: showBadge,
                isFull: isFull,
                updateAvailable: updateAvailable
            )
        default:
            return drawLinear(
                tokens: tokens,
                display: display,
                cpuTemp: cpuTemp,
                showBadge: showBadge,
                isFull: isFull,
                updateAvailable: updateAvailable
            )
        }
    }

    public static func heatColor(celsius: Double?) -> NSColor {
        guard let c = celsius else {
            return NSColor.labelColor
        }
        if c >= 88 { return NSColor(calibratedRed: 0.92, green: 0.28, blue: 0.25, alpha: 1) }
        if c >= 78 { return NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.15, alpha: 1) }
        if c >= 65 { return NSColor(calibratedRed: 0.92, green: 0.75, blue: 0.12, alpha: 1) }
        return NSColor(calibratedRed: 0.22, green: 0.78, blue: 0.42, alpha: 1)
    }

    public static func loadColor(percent: Double) -> NSColor {
        if percent >= 85 { return NSColor(calibratedRed: 0.92, green: 0.28, blue: 0.25, alpha: 1) }
        if percent >= 60 { return NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.15, alpha: 1) }
        return NSColor(calibratedRed: 0.20, green: 0.62, blue: 0.95, alpha: 1)
    }

    private static func color(for token: StatusBarToken, display: MenuBarDisplayConfig, defaultColor: NSColor) -> NSColor {
        guard display.colorizeHeat else { return defaultColor }
        switch token.kind {
        case .cpuTemp, .gpuTemp:
            return heatColor(celsius: token.value)
        case .load, .memory:
            return loadColor(percent: token.value ?? 0)
        case .battery:
            if let v = token.value, v <= 20 {
                return NSColor(calibratedRed: 0.92, green: 0.28, blue: 0.25, alpha: 1)
            }
            return defaultColor
        case .fan:
            return defaultColor
        }
    }

    private static func drawLinear(
        tokens: [StatusBarToken],
        display: MenuBarDisplayConfig,
        cpuTemp: Double?,
        showBadge: Bool,
        isFull: Bool,
        updateAvailable: Bool
    ) -> NSImage {
        let isCapsule = display.style == .capsule
        let isTempHero = display.style == .tempOnly
        let fontSize: CGFloat = isTempHero ? 13 : (display.style == .compact ? 11 : 12)
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: isTempHero ? .semibold : .regular)
        let defaultColor: NSColor = isCapsule ? .white : .labelColor
        let sep = display.style == .compact ? " " : " · "
        let sepAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: defaultColor.withAlphaComponent(0.55),
        ]

        var pieces: [(String, [NSAttributedString.Key: Any])] = []
        for (i, token) in tokens.enumerated() {
            if i > 0 {
                pieces.append((sep, sepAttrs))
            }
            let color = color(for: token, display: display, defaultColor: defaultColor)
            pieces.append((token.text, [.font: font, .foregroundColor: color]))
        }

        let titleSize = pieces.reduce(NSSize.zero) { acc, part in
            let s = (part.0 as NSString).size(withAttributes: part.1)
            return NSSize(width: acc.width + s.width, height: max(acc.height, s.height))
        }

        let badgeLetter = isFull ? "F" : "A"
        let badgeFont = NSFont.systemFont(ofSize: 9, weight: .bold)
        let badgeAttrs: [NSAttributedString.Key: Any] = [.font: badgeFont, .foregroundColor: NSColor.white]
        let badgeTextSize = (badgeLetter as NSString).size(withAttributes: badgeAttrs)
        let badgeH: CGFloat = 13
        let badgeW: CGFloat = max(14, badgeTextSize.width + 8)
        let updateW: CGFloat = updateAvailable ? 10 : 0
        let gap: CGFloat = showBadge ? 5 : 0
        let padX: CGFloat = isCapsule ? 7 : 1
        let padY: CGFloat = isCapsule ? 2 : 0
        let height: CGFloat = 18
        let contentW = titleSize.width + (showBadge ? gap + badgeW : 0) + (updateAvailable ? 4 + updateW : 0)
        let width = ceil(contentW + padX * 2)
        let size = NSSize(width: max(width, 12), height: height + padY * 2)

        return image(size: size) { _ in
            if isCapsule {
                let capsule = NSBezierPath(
                    roundedRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
                    xRadius: size.height / 2,
                    yRadius: size.height / 2
                )
                capsuleFill(cpuTemp: cpuTemp, colorize: display.colorizeHeat).setFill()
                capsule.fill()
            }

            var x = padX
            let titleY = (size.height - titleSize.height) / 2
            for (text, attrs) in pieces {
                let s = (text as NSString).size(withAttributes: attrs)
                (text as NSString).draw(at: NSPoint(x: x, y: titleY), withAttributes: attrs)
                x += s.width
            }

            if updateAvailable {
                x += 4
                drawUpdateDot(at: NSPoint(x: x, y: (size.height - 7) / 2))
                x += 7
            }

            guard showBadge else { return true }
            x += gap
            let by = (size.height - badgeH) / 2
            let fill = isFull
                ? NSColor(calibratedRed: 0.20, green: 0.48, blue: 0.96, alpha: 1)
                : NSColor(calibratedRed: 0.18, green: 0.72, blue: 0.36, alpha: 1)
            let path = NSBezierPath(
                roundedRect: NSRect(x: x, y: by, width: badgeW, height: badgeH),
                xRadius: 4,
                yRadius: 4
            )
            fill.setFill()
            path.fill()
            let tx = x + (badgeW - badgeTextSize.width) / 2
            let ty = by + (badgeH - badgeTextSize.height) / 2 - 0.5
            (badgeLetter as NSString).draw(at: NSPoint(x: tx, y: ty), withAttributes: badgeAttrs)
            return true
        }
    }

    private static func drawStacked(
        tokens: [StatusBarToken],
        display: MenuBarDisplayConfig,
        showBadge: Bool,
        isFull: Bool,
        updateAvailable: Bool
    ) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
        let top = tokens.first
        let rest = Array(tokens.dropFirst())
        let topText = top?.text ?? "—"
        let bottomText = rest.map(\.text).joined(separator: " ")
        let defaultColor = NSColor.labelColor
        let topColor = top.map { color(for: $0, display: display, defaultColor: defaultColor) } ?? defaultColor
        let topAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: topColor]
        let botAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: defaultColor.withAlphaComponent(0.85),
        ]
        let topSize = (topText as NSString).size(withAttributes: topAttrs)
        let botSize = (bottomText as NSString).size(withAttributes: botAttrs)
        let textW = max(topSize.width, botSize.width)
        let badgeW: CGFloat = showBadge ? 14 : 0
        let width = ceil(textW + 4 + badgeW + (updateAvailable ? 10 : 0))
        let size = NSSize(width: max(width, 22), height: 20)

        return image(size: size) { _ in
            (topText as NSString).draw(at: NSPoint(x: 1, y: 9), withAttributes: topAttrs)
            if !bottomText.isEmpty {
                (bottomText as NSString).draw(at: NSPoint(x: 1, y: 0), withAttributes: botAttrs)
            }
            var x = 2 + textW
            if updateAvailable {
                drawUpdateDot(at: NSPoint(x: x + 2, y: 6.5))
                x += 10
            }
            if showBadge {
                let letter = isFull ? "F" : "A"
                let fill = isFull
                    ? NSColor(calibratedRed: 0.20, green: 0.48, blue: 0.96, alpha: 1)
                    : NSColor(calibratedRed: 0.18, green: 0.72, blue: 0.36, alpha: 1)
                let path = NSBezierPath(roundedRect: NSRect(x: x, y: 3.5, width: 12, height: 13), xRadius: 3, yRadius: 3)
                fill.setFill()
                path.fill()
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 8, weight: .bold),
                    .foregroundColor: NSColor.white,
                ]
                (letter as NSString).draw(at: NSPoint(x: x + 3, y: 5), withAttributes: attrs)
            }
            return true
        }
    }

    private static func drawMeters(
        tokens: [StatusBarToken],
        display: MenuBarDisplayConfig,
        cpuTemp: Double?,
        loadPct: Double,
        showBadge: Bool,
        isFull: Bool,
        updateAvailable: Bool
    ) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let defaultColor = NSColor.labelColor
        var textW: CGFloat = 0
        var drawn: [(String, [NSAttributedString.Key: Any])] = []
        for (i, token) in tokens.enumerated() {
            if i > 0 {
                let sep = " "
                let a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: defaultColor.withAlphaComponent(0.4)]
                drawn.append((sep, a))
                textW += (sep as NSString).size(withAttributes: a).width
            }
            let a: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color(for: token, display: display, defaultColor: defaultColor),
            ]
            drawn.append((token.text, a))
            textW += (token.text as NSString).size(withAttributes: a).width
        }

        let barW: CGFloat = 22
        let heatW: CGFloat = 8
        let gap: CGFloat = 4
        let badgeW: CGFloat = showBadge ? 16 : 0
        let width = ceil(heatW + gap + barW + gap + textW + badgeW + (updateAvailable ? 10 : 0) + 4)
        let size = NSSize(width: max(width, 48), height: 18)

        return image(size: size) { _ in
            let heat = NSBezierPath(roundedRect: NSRect(x: 1, y: 3, width: heatW, height: 12), xRadius: 2, yRadius: 2)
            heatColor(celsius: cpuTemp).setFill()
            heat.fill()

            let track = NSBezierPath(roundedRect: NSRect(x: 1 + heatW + gap, y: 5, width: barW, height: 8), xRadius: 2, yRadius: 2)
            NSColor.labelColor.withAlphaComponent(0.15).setFill()
            track.fill()
            let fillW = max(2, barW * CGFloat(min(1, max(0, loadPct / 100))))
            let fill = NSBezierPath(roundedRect: NSRect(x: 1 + heatW + gap, y: 5, width: fillW, height: 8), xRadius: 2, yRadius: 2)
            loadColor(percent: loadPct).setFill()
            fill.fill()

            var x = 1 + heatW + gap + barW + gap
            for (text, attrs) in drawn {
                let s = (text as NSString).size(withAttributes: attrs)
                (text as NSString).draw(at: NSPoint(x: x, y: (size.height - s.height) / 2), withAttributes: attrs)
                x += s.width
            }
            if updateAvailable {
                drawUpdateDot(at: NSPoint(x: x + 2, y: 5.5))
                x += 10
            }
            if showBadge {
                let letter = isFull ? "F" : "A"
                let badgeFill = isFull
                    ? NSColor(calibratedRed: 0.20, green: 0.48, blue: 0.96, alpha: 1)
                    : NSColor(calibratedRed: 0.18, green: 0.72, blue: 0.36, alpha: 1)
                let path = NSBezierPath(roundedRect: NSRect(x: x + 2, y: 2.5, width: 13, height: 13), xRadius: 3, yRadius: 3)
                badgeFill.setFill()
                path.fill()
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 8, weight: .bold),
                    .foregroundColor: NSColor.white,
                ]
                (letter as NSString).draw(at: NSPoint(x: x + 5, y: 4.5), withAttributes: attrs)
            }
            return true
        }
    }

    private static func capsuleFill(cpuTemp: Double?, colorize: Bool) -> NSColor {
        guard colorize, let cpuTemp else {
            return NSColor(calibratedWhite: 0.22, alpha: 0.92)
        }
        let heat = heatColor(celsius: cpuTemp)
        return heat.blended(withFraction: 0.45, of: NSColor.black) ?? NSColor(calibratedWhite: 0.22, alpha: 0.92)
    }

    private static func drawUpdateDot(at origin: NSPoint) {
        let path = NSBezierPath(ovalIn: NSRect(x: origin.x, y: origin.y, width: 7, height: 7))
        NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.12, alpha: 1).setFill()
        path.fill()
    }

    private static func image(size: NSSize, draw: @escaping (NSRect) -> Bool) -> NSImage {
        let image = NSImage(size: size, flipped: false, drawingHandler: draw)
        image.isTemplate = false
        return image
    }
}
