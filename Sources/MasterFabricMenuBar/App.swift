import AppKit
import SwiftUI
import UserNotifications
import MasterFabricCore

// Command Line Tools (no Xcode.app) often lack SwiftUIMacros.StateMacro for `@State`.
// Local editable form state uses `@StateObject` + `ObservableObject` instead so
// `swift build --product MasterFabricMenuBar` succeeds on CLT-only machines.
@MainActor
final class DisplaySettingsFormState: ObservableObject {
    @Published var draft: MenuBarDisplayConfig = .default
    @Published var notifyLocal: Bool = false
}

@MainActor
final class RemoteLabelFormState: ObservableObject {
    @Published var remoteLabel: String = ""
}

@MainActor
final class EditAlertFormState: ObservableObject {
    @Published var enabled = true
    @Published var threshold = ""
    @Published var feedback = ""
}

@MainActor
final class AddIntegrationFormState: ObservableObject {
    @Published var kind: IntegrationKind = .slack
    @Published var enabled = true
    @Published var webhookURL = ""
    @Published var botToken = ""
    @Published var chatID = ""
    @Published var provider = "resend"
    @Published var from = ""
    @Published var to = ""
    @Published var subjectPrefix = "[MasterFabric]"
    @Published var smtpHost = ""
    @Published var smtpPort = "587"
    @Published var smtpUsername = ""
    @Published var smtpPassword = ""
    @Published var smtpUseTLS = true
    @Published var apiKey = ""
    @Published var mailgunDomain = ""
    @Published var feedback = ""
}


/// Needed so Notification Center sheets/banners work for an LSUIElement menu bar app.
final class MenuBarAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        LocalNotificationPermissionUX.ensureAccessoryPolicy()
        let center = UNUserNotificationCenter.current()
        center.delegate = self
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Recover if a permission flow left us on `.regular` (breaks menu bar clicks).
        LocalNotificationPermissionUX.ensureAccessoryPolicy()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}

/// Ask for notification permission without breaking MenuBarExtra.
enum LocalNotificationPermissionUX {
    static func ensureAccessoryPolicy() {
        if NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// Request permission while staying an accessory app. No policy flips, no NSApp.hide
    /// (those leave MenuBarExtra unable to open again).
    static func requestWithVisiblePrompt(completion: @escaping (Bool) -> Void) {
        ensureAccessoryPolicy()
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.async {
            AlertService.promptLocalNotificationPermission { granted in
                ensureAccessoryPolicy()
                completion(granted)
            }
        }
    }

    static func openSystemNotificationSettings() {
        ensureAccessoryPolicy()
        let candidates = [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=com.masterfabric.menubar",
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.notifications",
        ]
        for raw in candidates {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}

@main
struct MasterFabricMenuBarApp: App {
    @NSApplicationDelegateAdaptor(MenuBarAppDelegate.self) private var appDelegate
    @StateObject private var model = MenuBarModel()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel(model: model)
        } label: {
            // MenuBarExtra only reliably shows Text / Image — colored badge is pre-rendered.
            if let image = model.statusItemImage {
                Image(nsImage: image)
            } else {
                Text(model.title)
                    .font(.system(size: 12).monospacedDigit())
            }
        }
        .menuBarExtraStyle(.window)
    }
}

/// Renders title + A/F pill as a bitmap. SwiftUI backgrounds are stripped from MenuBarExtra labels.
enum MenuBarStatusIcon {
    static func make(
        title: String,
        showBadge: Bool,
        isFull: Bool,
        style: MenuBarStatusStyle = .standard
    ) -> NSImage {
        let titleFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: style == .capsule ? NSColor.white : NSColor.labelColor,
        ]
        let titleSize = (title as NSString).size(withAttributes: titleAttrs)

        let badgeLetter = isFull ? "F" : "A"
        let badgeFont = NSFont.systemFont(ofSize: 9, weight: .bold)
        let badgeAttrs: [NSAttributedString.Key: Any] = [
            .font: badgeFont,
            .foregroundColor: NSColor.white,
        ]
        let badgeTextSize = (badgeLetter as NSString).size(withAttributes: badgeAttrs)
        let badgeH: CGFloat = 13
        let badgeW: CGFloat = max(14, badgeTextSize.width + 8)
        let gap: CGFloat = showBadge ? 5 : 0
        let padX: CGFloat = style == .capsule ? 7 : 1
        let padY: CGFloat = style == .capsule ? 2 : 0
        let contentW = titleSize.width + (showBadge ? gap + badgeW : 0)
        let height: CGFloat = style == .capsule ? 18 : 18
        let width = ceil(contentW + padX * 2)

        let size = NSSize(width: max(width, 12), height: height + padY * 2)
        let image = NSImage(size: size, flipped: false) { _ in
            if style == .capsule {
                let capsule = NSBezierPath(
                    roundedRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
                    xRadius: size.height / 2,
                    yRadius: size.height / 2
                )
                NSColor(calibratedWhite: 0.22, alpha: 0.92).setFill()
                capsule.fill()
            }

            let titleY = (size.height - titleSize.height) / 2
            (title as NSString).draw(at: NSPoint(x: padX, y: titleY), withAttributes: titleAttrs)

            guard showBadge else { return true }

            let bx = padX + titleSize.width + gap
            let by = (size.height - badgeH) / 2
            let fill = isFull
                ? NSColor(calibratedRed: 0.20, green: 0.48, blue: 0.96, alpha: 1)
                : NSColor(calibratedRed: 0.18, green: 0.72, blue: 0.36, alpha: 1)
            let path = NSBezierPath(
                roundedRect: NSRect(x: bx, y: by, width: badgeW, height: badgeH),
                xRadius: 4,
                yRadius: 4
            )
            fill.setFill()
            path.fill()

            let tx = bx + (badgeW - badgeTextSize.width) / 2
            let ty = by + (badgeH - badgeTextSize.height) / 2 - 0.5
            (badgeLetter as NSString).draw(at: NSPoint(x: tx, y: ty), withAttributes: badgeAttrs)
            return true
        }
        image.isTemplate = false
        return image
    }
}

enum IntegrationKind: String, CaseIterable, Identifiable {
    case slack = "Slack"
    case telegram = "Telegram"
    case mail = "Mail"

    var id: String { rawValue }

    /// Asset name for official logos (Slack / Telegram). Mail stays vector-drawn.
    var brandImageName: String? {
        switch self {
        case .slack: return "brand-slack"
        case .telegram: return "brand-telegram"
        case .mail: return nil
        }
    }

    var brandCircleColor: Color {
        switch self {
        case .slack: return Color(red: 74 / 255, green: 21 / 255, blue: 75 / 255) // #4A154B
        case .telegram: return Color(red: 34 / 255, green: 158 / 255, blue: 217 / 255) // #229ED9
        case .mail: return Color(red: 0 / 255, green: 122 / 255, blue: 255 / 255)
        }
    }
}

/// Circle badge using official Slack / Telegram logo assets (Mail stays drawn).
struct IntegrationBrandBadge: View {
    let kind: IntegrationKind
    var size: CGFloat = 22
    var dimmed: Bool = false

    var body: some View {
        Group {
            if let name = kind.brandImageName, let nsImage = BrandAssets.nsImage(named: name) {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                ZStack {
                    Circle()
                        .fill(kind.brandCircleColor)
                    MailEnvelopeMark()
                        .frame(width: size * 0.58, height: size * 0.58)
                }
                .frame(width: size, height: size)
            }
        }
        .opacity(dimmed ? 0.45 : 1)
        .accessibilityLabel(kind.rawValue)
    }
}

enum BrandAssets {
    /// Resolve brand PNGs without touching SPM `Bundle.module` (that accessor
    /// fatally asserts when the .app is installed without the SPM `.bundle`).
    static func nsImage(named name: String) -> NSImage? {
        // 1) Installed .app: Contents/Resources (copied by `make install`)
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let image = NSImage(contentsOf: url)
        {
            return image
        }

        // 2) SPM resource bundle next to the binary / inside Resources (dev installs)
        if let bundle = adjacentResourceBundle(),
           let url = bundle.url(forResource: name, withExtension: "png"),
           let image = NSImage(contentsOf: url)
        {
            return image
        }

        // 3) Explicit filesystem fallbacks
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            exe.deletingLastPathComponent()
                .appendingPathComponent("../Resources/\(name).png"),
            exe.deletingLastPathComponent()
                .appendingPathComponent("\(name).png"),
            Bundle.main.bundleURL
                .appendingPathComponent("Contents/Resources/\(name).png"),
            home.appendingPathComponent(".local/MasterFabricMenuBar.app/Contents/Resources/\(name).png"),
            home.appendingPathComponent(".local/bin/\(name).png"),
        ]
        for url in candidates {
            let resolved = url.standardizedFileURL
            if FileManager.default.fileExists(atPath: resolved.path),
               let image = NSImage(contentsOf: resolved)
            {
                return image
            }
        }
        return nil
    }

    private static func adjacentResourceBundle() -> Bundle? {
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let bundleNames = [
            "MasterFabric_MasterFabricMenuBar.bundle",
            "MasterFabricMenuBar_MasterFabricMenuBar.bundle",
        ]
        let dirs = [
            exe.deletingLastPathComponent(),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources"),
            Bundle.main.bundleURL,
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin"),
        ]
        for dir in dirs {
            for name in bundleNames {
                let url = dir.appendingPathComponent(name)
                if let bundle = Bundle(url: url) { return bundle }
            }
        }
        return nil
    }
}

private struct MailEnvelopeMark: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                RoundedRectangle(cornerRadius: w * 0.12, style: .continuous)
                    .strokeBorder(Color.white, lineWidth: max(1.2, w * 0.1))
                    .frame(width: w * 0.92, height: h * 0.68)
                Path { p in
                    p.move(to: CGPoint(x: w * 0.08, y: h * 0.28))
                    p.addLine(to: CGPoint(x: w * 0.5, y: h * 0.58))
                    p.addLine(to: CGPoint(x: w * 0.92, y: h * 0.28))
                }
                .stroke(Color.white, style: StrokeStyle(lineWidth: max(1.2, w * 0.1), lineCap: .round, lineJoin: .round))
            }
            .frame(width: w, height: h)
        }
    }
}


enum AlertKind: String, CaseIterable, Identifiable {
    case cpu
    case gpu
    case fan
    case memory
    case disk
    case battery
    case power

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: return "CPU temp"
        case .gpu: return "GPU temp"
        case .fan: return "Fan speed"
        case .memory: return "Memory"
        case .disk: return "Disk"
        case .battery: return "Battery"
        case .power: return "Low power"
        }
    }

    var symbol: String {
        switch self {
        case .cpu: return "thermometer.medium"
        case .gpu: return "cpu"
        case .fan: return "fanblades"
        case .memory: return "memorychip"
        case .disk: return "internaldrive"
        case .battery: return "battery.100"
        case .power: return "bolt.fill"
        }
    }

    var help: String {
        switch self {
        case .cpu: return "High CPU temperature"
        case .gpu: return "High GPU temperature"
        case .fan: return "Fan near max RPM"
        case .memory: return "High memory pressure"
        case .disk: return "Disk nearly full"
        case .battery: return "Low battery"
        case .power: return "Low Power Mode"
        }
    }
}

@MainActor
final class MenuBarModel: ObservableObject {
    @Published var title: String = "mf…"
    @Published var statusItemImage: NSImage?
    @Published var status: SystemStatus = StatusService.current()
    @Published var fanIsFull: Bool = false
    @Published var showFanBadge: Bool = false
    @Published var isChangingFanMode: Bool = false
    @Published var info: SystemInfo = SystemInfoService.current()
    @Published var battery: BatteryInfo = BatteryService.current()
    @Published var memory: MemoryInfo = MemoryService.current()
    @Published var disk: DiskInfo = DiskService.current()
    @Published var load: CPULoadInfo = CPULoadService.current()
    @Published var power: PowerInfo = PowerService.current()
    @Published var history: HistorySnapshot = HistoryStore.snapshot()
    @Published var alerts: [String] = []
    @Published var alertConfig: AlertConfig = ConfigStore.load().alerts
    @Published var integrations: IntegrationsConfig = ConfigStore.load().integrations
    @Published var displayConfig: MenuBarDisplayConfig = ConfigStore.load().menuBar
    @Published var lastNotifyMessage: String = ""

    /// Inline editor (not a sheet — MenuBarExtra sheets need two clicks to dismiss).
    @Published var showAddIntegration = false
    @Published var editingKind: IntegrationKind = .slack
    @Published var editorSession: Int = 0

    @Published var showEditAlert = false
    @Published var editingAlertKind: AlertKind = .cpu
    @Published var alertEditorSession: Int = 0

    @Published var showSettings = false

    /// Measured intrinsic height of the active panel (for MenuBarExtra window sync).
    @Published var panelContentHeight: CGFloat = 0

    /// Inline update prompt (avoid MenuBarExtra `.sheet` dismiss bugs).
    @Published var showUpdateDialog = false
    @Published var pendingUpdate: VersionCheckResult?
    @Published var declinedRemoteVersion: String?
    @Published var isCheckingUpdate = false
    @Published var isUpdating = false

    private var timer: Timer?
    private var updateCheckTimer: Timer?
    private var notifiedRemoteVersion: String?

    init() {
        refreshMetrics()
        // Do not request notification permission on launch — only when user enables the setting.
        let interval = ConfigStore.load().pollIntervalSeconds
        timer = Timer.scheduledTimer(withTimeInterval: max(1.0, interval), repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshMetrics()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.checkForUpdates(promptIfAvailable: true)
        }
        updateCheckTimer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForUpdates(promptIfAvailable: true)
            }
        }
    }

    /// Public refresh used by the Refresh button.
    func refresh() {
        refreshMetrics()
    }

    func openSettings() {
        showSettings = true
        showAddIntegration = false
        showEditAlert = false
        showUpdateDialog = false
    }

    func closeSettings() {
        showSettings = false
    }

    func saveDisplayConfig(_ config: MenuBarDisplayConfig) {
        displayConfig = config
        var full = ConfigStore.load()
        full.menuBar = config
        do {
            try ConfigStore.save(full)
            lastNotifyMessage = "Menu bar settings saved"
        } catch {
            lastNotifyMessage = "Save failed: \(error.localizedDescription)"
        }
        applyStatusItem(from: full)
    }

    func saveNotifyLocal(_ enabled: Bool) {
        var full = ConfigStore.load()
        full.alerts.notifyLocal = enabled
        alertConfig = full.alerts
        do {
            try ConfigStore.save(full)
        } catch {
            lastNotifyMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    /// Turn local notifications on and ask macOS for permission (panel stays usable).
    func enableLocalNotifications(completion: @escaping (Bool) -> Void) {
        LocalNotificationPermissionUX.ensureAccessoryPolicy()
        lastNotifyMessage = "Requesting notification permission…"

        LocalNotificationPermissionUX.requestWithVisiblePrompt { granted in
            LocalNotificationPermissionUX.ensureAccessoryPolicy()
            if granted {
                self.saveNotifyLocal(true)
                self.lastNotifyMessage = "Local notifications enabled"
                completion(true)
            } else {
                self.saveNotifyLocal(false)
                self.lastNotifyMessage = "Notifications not allowed. System Settings → Notifications → MasterFabric"
                completion(false)
            }
        }
    }

    func disableLocalNotifications() {
        saveNotifyLocal(false)
        lastNotifyMessage = "Local notifications off"
    }

    /// Send a one-off Notification Center banner (for Settings → Test).
    func sendTestLocalNotification() {
        LocalNotificationPermissionUX.ensureAccessoryPolicy()
        AlertService.currentLocalNotificationAuthorized { authorized in
            if !authorized {
                self.enableLocalNotifications { granted in
                    guard granted else {
                        self.lastNotifyMessage = "Allow notifications first, then tap Test again"
                        return
                    }
                    AlertService.postLocalNotifications([
                        "Test notification — MasterFabric local alerts are working.",
                    ])
                    self.lastNotifyMessage = "Test notification sent"
                }
                return
            }
            AlertService.postLocalNotifications([
                "Test notification — MasterFabric local alerts are working.",
            ])
            self.lastNotifyMessage = "Test notification sent"
        }
    }

    private var isEditingInline: Bool {
        showAddIntegration || showEditAlert || showUpdateDialog || showSettings
    }

    private func refreshMetrics() {
        // Don't stomp the inline editor while the user is configuring.
        guard !isEditingInline else { return }

        HistoryStore.record()
        status = StatusService.current()
        info = SystemInfoService.current()
        battery = BatteryService.current()
        memory = MemoryService.current()
        disk = DiskService.current()
        load = CPULoadService.current()
        power = PowerService.current()
        history = HistoryStore.snapshot()
        var config = ConfigStore.load()
        config.language = "en"
        alertConfig = config.alerts
        alerts = AlertService.evaluate(
            status: status,
            memory: memory,
            disk: disk,
            battery: battery,
            power: power,
            config: config
        )
        integrations = config.integrations
        displayConfig = config.menuBar
        applyStatusItem(from: config)

        if config.alerts.notifyIntegrations || config.alerts.notifyLocal, !alerts.isEmpty {
            let results = AlertService.notifyIfNeeded(
                status: status,
                memory: memory,
                disk: disk,
                battery: battery,
                power: power,
                config: config
            )
            if !results.isEmpty {
                lastNotifyMessage = TextFormat.notifyResults(results)
            }
        }
    }

    func applyStatusItem(from config: AppConfig? = nil) {
        let mb = config?.menuBar ?? displayConfig
        title = TextFormat.compactStatusBar(
            status,
            load: load,
            battery: battery,
            display: mb
        )
        let fansPresent = !status.fans.isEmpty
        fanIsFull = FanService.isFullMode(status.fans)
        let badge: Bool = {
            switch mb.style {
            case .tempOnly, .fanOnly:
                return false
            case .standard, .capsule:
                return mb.showFanBadge && fansPresent
            }
        }()
        showFanBadge = badge
        statusItemImage = MenuBarStatusIcon.make(
            title: title,
            showBadge: badge,
            isFull: fanIsFull,
            style: mb.style
        )
    }

    func openAdd(kind: IntegrationKind? = nil) {
        showEditAlert = false
        if let kind {
            editingKind = kind
        } else if let firstMissing = IntegrationKind.allCases.first(where: { !isConfigured($0) }) {
            editingKind = firstMissing
        } else {
            editingKind = .slack
        }
        editorSession &+= 1
        showAddIntegration = true
    }

    func openEditAlert(kind: AlertKind) {
        showAddIntegration = false
        editingAlertKind = kind
        alertEditorSession &+= 1
        showEditAlert = true
    }

    func closeEditor() {
        showAddIntegration = false
        showEditAlert = false
        var config = ConfigStore.load()
        config.language = "en"
        alertConfig = config.alerts
        integrations = config.integrations
        alerts = AlertService.evaluate(
            status: status,
            memory: memory,
            disk: disk,
            battery: battery,
            power: power,
            config: config
        )
    }

    func isAlertRuleEnabled(_ kind: AlertKind) -> Bool {
        let a = alertConfig
        switch kind {
        case .cpu: return a.cpuTempEnabled
        case .gpu: return a.gpuTempEnabled
        case .fan: return a.fanEnabled
        case .memory: return a.memoryPressureNotify
        case .disk: return a.diskEnabled
        case .battery: return a.batteryEnabled
        case .power: return a.lowPowerModeNotify
        }
    }

    func isAlertActive(_ kind: AlertKind) -> Bool {
        let joined = alerts.joined(separator: " ").lowercased()
        switch kind {
        case .cpu: return joined.contains("cpu")
        case .gpu: return joined.contains("gpu")
        case .fan: return joined.contains("fan") || joined.contains("maximum")
        case .memory: return joined.contains("memory")
        case .disk: return joined.contains("disk")
        case .battery: return joined.contains("battery")
        case .power: return joined.contains("low power")
        }
    }

    func saveAlerts(_ alerts: AlertConfig) {
        var config = ConfigStore.load()
        config.alerts = alerts
        try? ConfigStore.save(config)
        alertConfig = alerts
    }

    func isConfigured(_ kind: IntegrationKind) -> Bool {
        switch kind {
        case .slack: return integrations.slack.isConfigured
        case .telegram: return integrations.telegram.isConfigured
        case .mail: return integrations.mail.isConfigured
        }
    }

    var listedIntegrations: [IntegrationKind] {
        IntegrationKind.allCases.filter { isConfigured($0) }
    }

    var availableToAdd: [IntegrationKind] {
        IntegrationKind.allCases.filter { !isConfigured($0) }
    }

    func isEnabled(_ kind: IntegrationKind) -> Bool {
        switch kind {
        case .slack: return integrations.slack.enabled
        case .telegram: return integrations.telegram.enabled
        case .mail: return integrations.mail.enabled
        }
    }

    func saveIntegrations(_ updated: IntegrationsConfig) {
        var config = ConfigStore.load()
        config.integrations = updated
        do {
            try ConfigStore.save(config)
            integrations = updated
            lastNotifyMessage = "Saved"
        } catch {
            lastNotifyMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    func toggle(_ kind: IntegrationKind, enabled: Bool) {
        var updated = integrations
        switch kind {
        case .slack: updated.slack.enabled = enabled
        case .telegram: updated.telegram.enabled = enabled
        case .mail: updated.mail.enabled = enabled
        }
        saveIntegrations(updated)
    }

    func remove(_ kind: IntegrationKind) {
        var updated = integrations
        switch kind {
        case .slack: updated.slack = .default
        case .telegram: updated.telegram = .default
        case .mail: updated.mail = .default
        }
        saveIntegrations(updated)
        lastNotifyMessage = "\(kind.rawValue) removed"
    }

    func test(_ kind: IntegrationKind) {
        let channel: NotifyChannel
        switch kind {
        case .slack: channel = .slack
        case .telegram: channel = .telegram
        case .mail: channel = .mail
        }
        let msg = "MasterFabric menu bar test · \(info.model)"
        let results = IntegrationNotifier.send(msg, channel: channel)
        lastNotifyMessage = TextFormat.notifyResults(results)
    }

    func checkForUpdates(promptIfAvailable: Bool, forcePrompt: Bool = false) {
        guard !isCheckingUpdate else { return }
        isCheckingUpdate = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = VersionService.check()
            DispatchQueue.main.async {
                guard let self else { return }
                self.isCheckingUpdate = false
                self.pendingUpdate = result
                if result.updateAvailable {
                    let remote = result.remote ?? ""
                    let alreadyDeclined = self.declinedRemoteVersion == remote
                    self.lastNotifyMessage = result.detail
                    if forcePrompt || (promptIfAvailable && !alreadyDeclined) {
                        self.showAddIntegration = false
                        self.showEditAlert = false
                        self.showSettings = false
                        self.showUpdateDialog = true
                    }
                    if !alreadyDeclined, self.notifiedRemoteVersion != remote {
                        self.notifiedRemoteVersion = remote
                        AlertService.postLocalNotifications(
                            ["v\(result.local) → v\(remote). Open the menu bar to update CLI and the app (mf update)."],
                            title: "MasterFabric update available"
                        )
                    }
                } else if forcePrompt {
                    self.lastNotifyMessage = VersionService.format(result)
                }
            }
        }
    }

    func declineUpdate() {
        if let remote = pendingUpdate?.remote {
            declinedRemoteVersion = remote
        }
        showUpdateDialog = false
        lastNotifyMessage = "Update declined"
    }

    func acceptUpdate() {
        guard !isUpdating else { return }
        isUpdating = true
        lastNotifyMessage = "Updating from GitHub…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = UpdateService.update(force: false)
            DispatchQueue.main.async {
                guard let self else { return }
                self.isUpdating = false
                self.showUpdateDialog = false
                self.lastNotifyMessage = UpdateService.format(result)
                if result.performed {
                    self.declinedRemoteVersion = nil
                }
            }
        }
    }
}

/// Bubbles the intrinsic content height out of MenuBarExtra panels.
private struct MenuBarContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// MenuBarExtra(.window) keeps a stale NSWindow / hosting-view clip region when
/// content grows (settings, add integration). Drive `setContentSize` from the
/// measured SwiftUI height so the popover chrome matches the real layout.
private struct MenuBarExtraWindowSizer: NSViewRepresentable {
    var width: CGFloat
    var height: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let width = width
        let height = height
        guard width > 1, height > 1 else { return }
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            if let contentView = window.contentView {
                contentView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
                contentView.setContentHuggingPriority(.defaultLow, for: .vertical)
            }
            let current = window.contentView?.bounds.size ?? .zero
            if abs(current.width - width) < 0.5, abs(current.height - height) < 0.5 {
                return
            }
            window.setContentSize(NSSize(width: width, height: height))
        }
    }
}

struct MenuBarPanel: View {
    @ObservedObject var model: MenuBarModel

    var body: some View {
        let width = panelWidth
        let maxHeight = panelMaxHeight
        let windowHeight = resolvedWindowHeight(maxHeight: maxHeight)

        Group {
            if needsScroll {
                ScrollView {
                    panelContent
                        .padding(14)
                        .frame(width: width, alignment: .topLeading)
                        .background(heightReader)
                }
                .frame(width: width, height: windowHeight, alignment: .topLeading)
            } else {
                panelContent
                    .padding(14)
                    .frame(width: width, alignment: .topLeading)
                    .background(heightReader)
                    .frame(width: width, height: windowHeight > 1 ? windowHeight : nil, alignment: .topLeading)
            }
        }
        .id(panelModeID)
        .onChange(of: panelModeID) { _ in
            model.panelContentHeight = 0
        }
        .onPreferenceChange(MenuBarContentHeightKey.self) { model.panelContentHeight = $0 }
        .background(
            Group {
                if windowHeight > 1 {
                    MenuBarExtraWindowSizer(width: width, height: windowHeight)
                }
            }
        )
    }

    @ViewBuilder
    private var panelContent: some View {
        if model.showUpdateDialog {
            UpdatePromptView(model: model)
        } else if model.showSettings {
            MenuBarSettingsView(model: model)
        } else if model.showEditAlert {
            EditAlertForm(model: model)
                .id(model.alertEditorSession)
        } else if model.showAddIntegration {
            AddIntegrationForm(model: model)
                .id(model.editorSession)
        } else {
            StatusHomeView(model: model)
        }
    }

    private var heightReader: some View {
        GeometryReader { geo in
            Color.clear.preference(key: MenuBarContentHeightKey.self, value: geo.size.height)
        }
    }

    private var needsScroll: Bool {
        model.showSettings || model.showAddIntegration || model.showEditAlert
    }

    private var panelWidth: CGFloat {
        model.showSettings ? 340 : 320
    }

    private var panelMaxHeight: CGFloat {
        let screen = NSScreen.main?.visibleFrame.height ?? 900
        return min(560, max(360, screen * 0.62))
    }

    private var panelModeID: String {
        if model.showUpdateDialog { return "update" }
        if model.showSettings { return "settings" }
        if model.showEditAlert { return "alert-\(model.alertEditorSession)" }
        if model.showAddIntegration { return "add-\(model.editorSession)" }
        return "home"
    }

    private func resolvedWindowHeight(maxHeight: CGFloat) -> CGFloat {
        // Include padding that wraps panelContent in the scroll/home branches.
        let padded = model.panelContentHeight > 1 ? model.panelContentHeight : 0
        if needsScroll {
            if padded > 1 {
                return min(padded, maxHeight)
            }
            return maxHeight
        }
        return padded > 1 ? padded : 0
    }
}

struct UpdatePromptView: View {
    @ObservedObject var model: MenuBarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.orange)
                Text("Update available")
                    .font(.headline)
                Spacer()
                Button {
                    model.declineUpdate()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .disabled(model.isUpdating)
            }

            let local = model.pendingUpdate?.local ?? AboutInfo.version
            let remote = model.pendingUpdate?.remote ?? "?"
            Text("A newer open-source release is on GitHub.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Installed: v\(local)")
                .font(.callout.monospacedDigit())
            Text("Latest:    v\(remote)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.orange)

            if model.isUpdating {
                Text("Updating from GitHub…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Decline") {
                    model.declineUpdate()
                }
                .disabled(model.isUpdating)
                Spacer()
                Button(model.isUpdating ? "Updating…" : "Update") {
                    model.acceptUpdate()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.isUpdating)
            }
        }
    }
}

struct StatusHomeView: View {
    @ObservedObject var model: MenuBarModel
    private var d: MenuBarDisplayConfig { model.displayConfig }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MasterFabric")
                        .font(.headline)
                    Text("MacBook system monitor · CLI · Menu Bar · MCP")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button {
                    model.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .help("Refresh metrics")
            }

            if d.panelModel || d.panelChip {
                Group {
                    if d.panelModel { row("Model", model.info.model) }
                    if d.panelChip { row("Chip", model.info.chip) }
                }
                Divider()
            }

            if model.pendingUpdate?.updateAvailable == true,
               model.pendingUpdate?.remote != model.declinedRemoteVersion {
                Button {
                    model.checkForUpdates(promptIfAvailable: true, forcePrompt: true)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(.orange)
                        Text(model.pendingUpdate.map { "Update v\($0.remote ?? "?") available" } ?? "Update available")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Text("Install")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
                .buttonStyle(.plain)
                Divider()
            }

            if d.panelCPU {
                row("CPU", model.status.temperature.cpuCelsius.map { String(format: "%.1f °C", $0) } ?? "N/A")
            }
            if d.panelGPU {
                row("GPU", model.status.temperature.gpuCelsius.map { String(format: "%.1f °C", $0) } ?? "N/A")
            }
            if d.panelLoad {
                let loadText: String = {
                    if let p = model.load.performancePercent, let e = model.load.efficiencyPercent {
                        return String(format: "%.1f%%  (P %.0f%% · E %.0f%%)", model.load.overallPercent, p, e)
                    }
                    return String(format: "%.1f%%", model.load.overallPercent)
                }()
                row("Load", loadText)
            }
            if d.panelThermal {
                row("Thermal", model.power.thermalState)
            }

            if d.panelFans || d.panelFanControl {
                if model.status.fans.isEmpty {
                    if d.panelFans { row("Fan", "N/A") }
                } else {
                    if d.panelFans {
                        ForEach(Array(model.status.fans.enumerated()), id: \.offset) { _, fan in
                            let rpm = fan.rpm.map { String(format: "%.0f", $0) } ?? "—"
                            let max = fan.maxRPM.map { String(format: "%.0f", $0) } ?? "?"
                            row(fan.name, "\(rpm)/\(max) · \(fan.mode)")
                        }
                    }
                    if d.panelFanControl, !model.status.fans.isEmpty {
                        HStack(spacing: 8) {
                            Text("Fan control")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if model.isChangingFanMode {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Button("Auto") { applyFanMode(.auto) }
                                .buttonStyle(.borderless)
                                .font(.caption)
                                .disabled(model.isChangingFanMode)
                                .help("Automatic control — password only on first helper install")

                            Button("Full") { applyFanMode(.full) }
                                .buttonStyle(.borderless)
                                .font(.caption)
                                .disabled(model.isChangingFanMode)
                                .help("Max RPM — password only on first helper install")
                        }
                    }
                }
            }

            if d.panelBattery || d.panelMemory || d.panelCPUHist {
                Divider()
                if d.panelBattery, model.battery.isPresent {
                    row("Battery", model.battery.percent.map { String(format: "%.0f%%", $0) } ?? "N/A")
                }
                if d.panelMemory {
                    row("Memory", String(format: "%.0f%% · %@", model.memory.usedPercent, model.memory.pressure))
                }
                if d.panelCPUHist {
                    row("CPU hist", model.history.cpuSparkline)
                }
            }

            if d.panelAlerts {
                Divider()
                AlertsSection(model: model)
                if !model.alerts.isEmpty {
                    ForEach(model.alerts, id: \.self) { alert in
                        Text(alert)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            if d.panelIntegrations {
                Divider()
                IntegrationsSection(model: model)
            }

            if !model.lastNotifyMessage.isEmpty {
                Text(model.lastNotifyMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if d.panelAbout {
                Divider()
                AboutSection(model: model)
            }

            Divider()

            HStack(spacing: 10) {
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
                Spacer()
                Button {
                    model.openSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .help("Menu bar display settings")
            }
        }
    }

    private func applyFanMode(_ mode: FanControlMode) {
        model.isChangingFanMode = true
        model.lastNotifyMessage = mode == .full
            ? "Fan Full… (password only if helper not installed yet)"
            : "Fan Auto… (password only if helper not installed yet)"
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = FanService.setModePrivileged(mode)
            DispatchQueue.main.async {
                model.isChangingFanMode = false
                model.lastNotifyMessage = TextFormat.fanControl(result)
                model.fanIsFull = FanService.isFullMode(result.fans)
                model.applyStatusItem()
                model.refresh()
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.body.monospacedDigit())
        }
    }
}

struct MenuBarSettingsView: View {
    @ObservedObject var model: MenuBarModel
    @StateObject private var form = DisplaySettingsFormState()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Menu Bar Settings")
                        .font(.headline)
                    Spacer()
                    Button {
                        model.closeSettings()
                        model.refresh()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }

                // MARK: Notifications (top)
                Text("Notifications")
                    .font(.subheadline.weight(.semibold))
                Toggle("Local notifications on alert", isOn: Binding(
                    get: { form.notifyLocal },
                    set: { on in
                        if on {
                            model.enableLocalNotifications { granted in
                                form.notifyLocal = granted
                            }
                        } else {
                            form.notifyLocal = false
                            model.disableLocalNotifications()
                        }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.caption)
                Text("Off by default. Turning On asks for macOS notification permission.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Button("Test notification") {
                        model.sendTestLocalNotification()
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                    .disabled(!form.notifyLocal)
                    .help(form.notifyLocal ? "Send a sample Notification Center banner" : "Enable local notifications first")

                    if !form.notifyLocal {
                        Button("Open Notification Settings…") {
                            LocalNotificationPermissionUX.openSystemNotificationSettings()
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                    }
                }

                Divider()

                Text("Status item style")
                    .font(.subheadline.weight(.semibold))

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(MenuBarStatusStyle.allCases) { style in
                        Button {
                            form.draft.style = style
                            preview(form.draft)
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: form.draft.style == style ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(form.draft.style == style ? Color.accentColor : .secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(style.title)
                                        .font(.callout.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text(style.subtitle)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider()

                Text("Show in menu bar")
                    .font(.subheadline.weight(.semibold))
                toggle("CPU temperature", form.draft.showCPUTemp) { form.draft.showCPUTemp = $0; preview(form.draft) }
                toggle("GPU temperature", form.draft.showGPUTemp) { form.draft.showGPUTemp = $0; preview(form.draft) }
                toggle("CPU load %", form.draft.showLoad) { form.draft.showLoad = $0; preview(form.draft) }
                toggle("Fan RPM", form.draft.showFanRPM) { form.draft.showFanRPM = $0; preview(form.draft) }
                toggle("Fan A/F badge", form.draft.showFanBadge) { form.draft.showFanBadge = $0; preview(form.draft) }
                toggle("Battery %", form.draft.showBattery) { form.draft.showBattery = $0; preview(form.draft) }

                Text("Temp only / Fan only styles ignore most toggles above.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Divider()

                Text("Show in panel")
                    .font(.subheadline.weight(.semibold))

                Group {
                    toggle("Model", form.draft.panelModel) { form.draft.panelModel = $0 }
                    toggle("Chip", form.draft.panelChip) { form.draft.panelChip = $0 }
                    toggle("CPU", form.draft.panelCPU) { form.draft.panelCPU = $0 }
                    toggle("GPU", form.draft.panelGPU) { form.draft.panelGPU = $0 }
                    toggle("Load", form.draft.panelLoad) { form.draft.panelLoad = $0 }
                    toggle("Thermal", form.draft.panelThermal) { form.draft.panelThermal = $0 }
                    toggle("Fans", form.draft.panelFans) { form.draft.panelFans = $0 }
                    toggle("Fan control", form.draft.panelFanControl) { form.draft.panelFanControl = $0 }
                    toggle("Battery", form.draft.panelBattery) { form.draft.panelBattery = $0 }
                    toggle("Memory", form.draft.panelMemory) { form.draft.panelMemory = $0 }
                    toggle("CPU history", form.draft.panelCPUHist) { form.draft.panelCPUHist = $0 }
                    toggle("Alerts", form.draft.panelAlerts) { form.draft.panelAlerts = $0 }
                    toggle("Integrations", form.draft.panelIntegrations) { form.draft.panelIntegrations = $0 }
                    toggle("About", form.draft.panelAbout) { form.draft.panelAbout = $0 }
                }

                HStack {
                    Button("Reset") {
                        form.draft = .default
                        form.notifyLocal = false
                        preview(form.draft)
                    }
                    Spacer()
                    Button("Done") {
                        model.saveDisplayConfig(form.draft)
                        model.saveNotifyLocal(form.notifyLocal)
                        model.closeSettings()
                        model.refresh()
                    }
                    .keyboardShortcut(.defaultAction)
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            form.draft = model.displayConfig
            form.notifyLocal = model.alertConfig.notifyLocal
        }
    }

    private func preview(_ config: MenuBarDisplayConfig) {
        model.displayConfig = config
        model.applyStatusItem()
    }

    private func toggle(_ title: String, _ value: Bool, onChange: @escaping (Bool) -> Void) -> some View {
        Toggle(title, isOn: Binding(
            get: { value },
            set: { onChange($0) }
        ))
        .toggleStyle(.switch)
        .controlSize(.small)
        .font(.caption)
    }
}

struct AboutSection: View {
    @ObservedObject var model: MenuBarModel
    @StateObject private var form = RemoteLabelFormState()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("About")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    model.checkForUpdates(promptIfAvailable: true, forcePrompt: true)
                } label: {
                    Group {
                        if model.isCheckingUpdate {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 13, weight: .semibold))
                        }
                    }
                }
                .buttonStyle(.borderless)
                .help("Check for updates")
                .disabled(model.isCheckingUpdate || model.isUpdating)
            }

            Text("\(AboutInfo.product) v\(AboutInfo.version)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !form.remoteLabel.isEmpty {
                Text(form.remoteLabel)
                    .font(.caption2)
                    .foregroundStyle(form.remoteLabel.contains("Update") ? .orange : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 4) {
                Text("Author")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Link(AboutInfo.author, destination: URL(string: AboutInfo.authorURL)!)
                    .font(.caption)
            }

            HStack(spacing: 4) {
                Text("Company")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Link("MasterFabric · masterfabric.co", destination: URL(string: AboutInfo.companyURL)!)
                    .font(.caption)
            }

            Text("Open-source company · MIT")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Link("GitHub repo", destination: URL(string: AboutInfo.repoURL)!)
                .font(.caption2)
        }
        .onAppear {
            model.checkForUpdates(promptIfAvailable: true, forcePrompt: false)
            syncLabelFromPending()
        }
        .onChange(of: model.pendingUpdate) { _ in
            syncLabelFromPending()
        }
    }

    private func syncLabelFromPending() {
        guard let result = model.pendingUpdate else { return }
        if let remote = result.remote {
            if result.updateAvailable {
                form.remoteLabel = "GitHub latest: v\(remote) — Update available"
            } else if VersionService.isRemoteNewer(remote: AboutInfo.version, local: remote) {
                form.remoteLabel = "GitHub latest: v\(remote) (local ahead)"
            } else {
                form.remoteLabel = "GitHub latest: v\(remote) — up to date"
            }
        } else {
            form.remoteLabel = result.detail
        }
    }
}

struct AlertsSection: View {
    @ObservedObject var model: MenuBarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Alerts")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { model.alertConfig.enabled },
                    set: { on in
                        var a = model.alertConfig
                        a.enabled = on
                        model.saveAlerts(a)
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .help("Master alerts on/off")
            }

            Text("Tap an icon to set thresholds · fires to Integrations")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(AlertKind.allCases) { kind in
                    Button {
                        model.openEditAlert(kind: kind)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(circleFill(for: kind))
                                .frame(width: 32, height: 32)
                            Image(systemName: kind.symbol)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(circleForeground(for: kind))
                        }
                    }
                    .buttonStyle(.plain)
                    .help(kind.help)
                }
            }

            Toggle("Send to Integrations", isOn: Binding(
                get: { model.alertConfig.notifyIntegrations },
                set: { on in
                    var a = model.alertConfig
                    a.notifyIntegrations = on
                    model.saveAlerts(a)
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .font(.caption)
            .help("When an alert triggers, notify enabled Slack / Telegram / Mail")
        }
    }

    private func circleFill(for kind: AlertKind) -> Color {
        if model.isAlertActive(kind) { return Color.orange.opacity(0.35) }
        if model.isAlertRuleEnabled(kind), model.alertConfig.enabled {
            return Color.accentColor.opacity(0.22)
        }
        return Color.secondary.opacity(0.15)
    }

    private func circleForeground(for kind: AlertKind) -> Color {
        if model.isAlertActive(kind) { return .orange }
        if model.isAlertRuleEnabled(kind), model.alertConfig.enabled { return .primary }
        return .secondary
    }
}

/// Inline alert threshold editor (replaces home view).
struct EditAlertForm: View {
    @ObservedObject var model: MenuBarModel

    @StateObject private var form = EditAlertFormState()

    private var kind: AlertKind { model.editingAlertKind }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    model.closeEditor()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: kind.symbol)
                    Text(kind.title)
                        .font(.headline)
                }

                Spacer()

                Button {
                    model.closeEditor()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Close")
            }

            Text(kind.help)
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Enabled", isOn: $form.enabled)

            if showsThreshold {
                VStack(alignment: .leading, spacing: 4) {
                    Text(thresholdLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(thresholdPlaceholder, text: $form.threshold)
                        .textFieldStyle(.roundedBorder)
                }
            } else {
                Text(boolOnlyHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("When this fires, enabled Integrations (Slack / Telegram / Mail) receive the alert.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !form.feedback.isEmpty {
                Text(form.feedback)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Cancel") { model.closeEditor() }
                Spacer()
                Button("Save") {
                    save()
                    model.closeEditor()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { load() }
    }

    private var showsThreshold: Bool {
        switch kind {
        case .memory, .power: return false
        default: return true
        }
    }

    private var thresholdLabel: String {
        switch kind {
        case .cpu, .gpu: return "Alert when ≥ °C"
        case .fan: return "Alert when fan ≥ % of max RPM"
        case .disk: return "Alert when disk used ≥ %"
        case .battery: return "Alert when battery ≤ %"
        default: return "Threshold"
        }
    }

    private var thresholdPlaceholder: String {
        switch kind {
        case .cpu, .gpu: return "90"
        case .fan: return "95"
        case .disk: return "90"
        case .battery: return "15"
        default: return ""
        }
    }

    private var boolOnlyHint: String {
        switch kind {
        case .memory: return "Triggers when memory pressure is high (system-reported)."
        case .power: return "Triggers when Low Power Mode is on."
        default: return ""
        }
    }

    private func load() {
        let a = model.alertConfig
        switch kind {
        case .cpu:
            form.enabled = a.cpuTempEnabled
            form.threshold = String(format: "%.0f", a.cpuTempCelsius)
        case .gpu:
            form.enabled = a.gpuTempEnabled
            form.threshold = String(format: "%.0f", a.gpuTempCelsius)
        case .fan:
            form.enabled = a.fanEnabled
            form.threshold = String(format: "%.0f", a.fanNearMaxPercent)
        case .memory:
            form.enabled = a.memoryPressureNotify
            form.threshold = ""
        case .disk:
            form.enabled = a.diskEnabled
            form.threshold = String(format: "%.0f", a.diskUsedPercentMax)
        case .battery:
            form.enabled = a.batteryEnabled
            form.threshold = String(format: "%.0f", a.batteryPercentMin)
        case .power:
            form.enabled = a.lowPowerModeNotify
            form.threshold = ""
        }
        form.feedback = ""
    }

    private func save() {
        var a = model.alertConfig
        let value = Double(form.threshold.trimmingCharacters(in: .whitespacesAndNewlines))
        switch kind {
        case .cpu:
            a.cpuTempEnabled = form.enabled
            if let value { a.cpuTempCelsius = value }
        case .gpu:
            a.gpuTempEnabled = form.enabled
            if let value { a.gpuTempCelsius = value }
        case .fan:
            a.fanEnabled = form.enabled
            if let value { a.fanNearMaxPercent = value }
        case .memory:
            a.memoryPressureNotify = form.enabled
        case .disk:
            a.diskEnabled = form.enabled
            if let value { a.diskUsedPercentMax = value }
        case .battery:
            a.batteryEnabled = form.enabled
            if let value { a.batteryPercentMin = value }
        case .power:
            a.lowPowerModeNotify = form.enabled
        }
        model.saveAlerts(a)
        form.feedback = "Saved — Integrations will get this alert when it fires"
    }
}

struct IntegrationsSection: View {
    @ObservedObject var model: MenuBarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Integrations")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if !model.availableToAdd.isEmpty {
                    Button {
                        model.openAdd()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .imageScale(.medium)
                    }
                    .buttonStyle(.borderless)
                    .help("Add Slack, Telegram, or Mail")
                }
            }

            if model.listedIntegrations.isEmpty {
                Text("No integrations yet — tap + to add")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.listedIntegrations) { kind in
                    HStack(spacing: 8) {
                        IntegrationBrandBadge(
                            kind: kind,
                            size: 24,
                            dimmed: !model.isEnabled(kind)
                        )

                        Toggle(kind.rawValue, isOn: Binding(
                            get: { model.isEnabled(kind) },
                            set: { model.toggle(kind, enabled: $0) }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.mini)

                        Spacer(minLength: 0)

                        Button("Edit") { model.openAdd(kind: kind) }
                            .buttonStyle(.borderless)
                            .font(.caption)

                        Button {
                            model.remove(kind)
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .help("Remove \(kind.rawValue)")
                    }
                }
            }
        }
    }
}

/// Inline form (replaces home view). Avoids MenuBarExtra `.sheet` double-click close bug.
struct AddIntegrationForm: View {
    @ObservedObject var model: MenuBarModel

    @StateObject private var form = AddIntegrationFormState()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    model.closeEditor()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)

                Spacer()

                HStack(spacing: 6) {
                    IntegrationBrandBadge(kind: form.kind, size: 20)
                    Text(model.isConfigured(model.editingKind) ? "Edit integration" : "Add integration")
                        .font(.headline)
                }

                Spacer()

                Button {
                    model.closeEditor()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Close")
            }

            Picker("Channel", selection: $form.kind) {
                ForEach(pickerKinds) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .disabled(pickerKinds.count <= 1)
            .onChange(of: form.kind) { newValue in
                load(from: newValue)
            }

            Toggle("Enabled", isOn: $form.enabled)

            Group {
                switch form.kind {
                case .slack:
                    field("Webhook URL", text: $form.webhookURL, secure: false)
                case .telegram:
                    field("Bot token", text: $form.botToken, secure: true)
                    field("Chat ID (numeric example: 123456789 — not @username)", text: $form.chatID, secure: false)
                case .mail:
                    Picker("Provider", selection: $form.provider) {
                        Text("Resend").tag("resend")
                        Text("Mailgun").tag("mailgun")
                        Text("SMTP").tag("smtp")
                    }
                    field("From", text: $form.from, secure: false)
                    field("To", text: $form.to, secure: false)
                    field("Subject prefix", text: $form.subjectPrefix, secure: false)
                    if form.provider == "smtp" {
                        field("SMTP host", text: $form.smtpHost, secure: false)
                        field("SMTP port", text: $form.smtpPort, secure: false)
                        field("Username", text: $form.smtpUsername, secure: false)
                        field("Password", text: $form.smtpPassword, secure: true)
                        Toggle("Use TLS", isOn: $form.smtpUseTLS)
                    } else {
                        field("API key", text: $form.apiKey, secure: true)
                        if form.provider == "mailgun" {
                            field("Mailgun domain", text: $form.mailgunDomain, secure: false)
                        }
                    }
                }
            }

            if !form.feedback.isEmpty {
                Text(form.feedback)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Test") { test() }
                Spacer()
                Button("Cancel") { model.closeEditor() }
                Button("Save") {
                    save()
                    model.closeEditor()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            form.kind = model.editingKind
            if !pickerKinds.contains(form.kind), let first = pickerKinds.first {
                form.kind = first
            }
            load(from: form.kind)
        }
    }

    private var pickerKinds: [IntegrationKind] {
        var kinds = model.availableToAdd
        if model.isConfigured(model.editingKind), !kinds.contains(model.editingKind) {
            kinds.insert(model.editingKind, at: 0)
        }
        return IntegrationKind.allCases.filter { kinds.contains($0) }
    }

    private func field(_ title: String, text: Binding<String>, secure: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            if secure {
                SecureField(title, text: text)
                    .textFieldStyle(.roundedBorder)
            } else {
                TextField(title, text: text)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private func load(from selectedKind: IntegrationKind) {
        let i = model.integrations
        switch selectedKind {
        case .slack:
            form.enabled = i.slack.enabled || i.slack.webhookURL.isEmpty
            form.webhookURL = i.slack.webhookURL
        case .telegram:
            form.enabled = i.telegram.enabled || i.telegram.botToken.isEmpty
            form.botToken = i.telegram.botToken
            form.chatID = i.telegram.chatID
        case .mail:
            form.enabled = i.mail.enabled || i.mail.from.isEmpty
            form.provider = i.mail.provider
            form.from = i.mail.from
            form.to = i.mail.to
            form.subjectPrefix = i.mail.subjectPrefix
            form.smtpHost = i.mail.smtpHost
            form.smtpPort = String(i.mail.smtpPort)
            form.smtpUsername = i.mail.smtpUsername
            form.smtpPassword = i.mail.smtpPassword
            form.smtpUseTLS = i.mail.smtpUseTLS
            form.apiKey = i.mail.apiKey
            form.mailgunDomain = i.mail.mailgunDomain
        }
        form.feedback = ""
    }

    private func save() {
        var updated = model.integrations
        switch form.kind {
        case .slack:
            updated.slack = SlackIntegrationConfig(
                enabled: form.enabled,
                webhookURL: form.webhookURL.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        case .telegram:
            updated.telegram = TelegramIntegrationConfig(
                enabled: form.enabled,
                botToken: form.botToken.trimmingCharacters(in: .whitespacesAndNewlines),
                chatID: form.chatID.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        case .mail:
            updated.mail = MailIntegrationConfig(
                enabled: form.enabled,
                provider: form.provider,
                from: form.from.trimmingCharacters(in: .whitespacesAndNewlines),
                to: form.to.trimmingCharacters(in: .whitespacesAndNewlines),
                subjectPrefix: form.subjectPrefix,
                smtpHost: form.smtpHost.trimmingCharacters(in: .whitespacesAndNewlines),
                smtpPort: Int(form.smtpPort) ?? 587,
                smtpUsername: form.smtpUsername,
                smtpPassword: form.smtpPassword,
                smtpUseTLS: form.smtpUseTLS,
                apiKey: form.apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                mailgunDomain: form.mailgunDomain.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        model.saveIntegrations(updated)
        form.feedback = "Saved to config.toml"
    }

    private func test() {
        save()
        model.test(form.kind)
        form.feedback = model.lastNotifyMessage
    }
}
