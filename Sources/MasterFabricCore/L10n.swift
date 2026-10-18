import Foundation

/// Lightweight EN/TR strings for CLI + alerts + about.
public enum L10n {
    public static func language(_ explicit: String? = nil) -> String {
        if let explicit, !explicit.isEmpty { return explicit }
        return ConfigStore.load().language
    }

    public static func t(_ key: String, _ lang: String? = nil, args: [String] = []) -> String {
        let l = (lang ?? language()).lowercased().hasPrefix("tr") ? "tr" : "en"
        var template = table[l]?[key] ?? table["en"]?[key] ?? key
        for (i, arg) in args.enumerated() {
            template = template.replacingOccurrences(of: "{\(i)}", with: arg)
        }
        return template
    }

    private static let table: [String: [String: String]] = [
        "en": [
            "app.name": "MasterFabric",
            "app.tagline": "MacBook system monitor — CLI, menu bar, MCP. No telemetry.",
            "alert.cpu_hot": "CPU temperature high: {0}°C",
            "alert.gpu_hot": "GPU temperature high: {0}°C",
            "alert.fan_max": "{0} near maximum ({1}%)",
            "alert.memory_high": "Memory pressure is high",
            "alert.disk_full": "Disk usage high: {0}%",
            "alert.battery_low": "Battery low: {0}%",
            "alert.low_power": "Low Power Mode is on",
            "about.privacy": "Privacy-first: all readings stay on this Mac. No telemetry.",
            "fan.na": "Fan: N/A (fanless or unavailable)",
            "battery.absent": "No battery present",
        ],
        "tr": [
            "app.name": "MasterFabric",
            "app.tagline": "MacBook sistem monitörü — CLI, menü çubuğu, MCP. Telemetri yok.",
            "alert.cpu_hot": "CPU sıcaklığı yüksek: {0}°C",
            "alert.gpu_hot": "GPU sıcaklığı yüksek: {0}°C",
            "alert.fan_max": "{0} maksimuma yakın (%{1})",
            "alert.memory_high": "Bellek baskısı yüksek",
            "alert.disk_full": "Disk kullanımı yüksek: %{0}",
            "alert.battery_low": "Pil düşük: %{0}",
            "alert.low_power": "Düşük Güç Modu açık",
            "about.privacy": "Gizlilik öncelikli: tüm ölçümler bu Mac'te kalır. Telemetri yok.",
            "fan.na": "Fan: N/A (fansız veya okunamadı)",
            "battery.absent": "Pil yok",
        ],
    ]
}

public enum AboutInfo {
    public static var version: String { AppVersion.current }
    public static let product = "MasterFabric Mac CLI"
    public static let author = "gurkanfikretgunak"
    public static let authorURL = "https://github.com/gurkanfikretgunak"
    public static let company = "MasterFabric"
    public static let companyURL = "https://masterfabric.co"
    public static var repoURL: String { AppVersion.repoURL }

    public static func text(language: String? = nil) -> String {
        let lang = L10n.language(language)
        return """
        \(product) v\(version)
        \(L10n.t("app.tagline", lang))
        \(L10n.t("about.privacy", lang))

        Author:  \(author)
                 \(authorURL)
        Company: \(company) — open-source
                 \(companyURL)
        License: GNU AGPL-3.0
        Repo:    \(repoURL)

        Surfaces: CLI (`mf`) · Menu Bar · MCP (`mf mcp`)
        Config:   ~/.config/masterfabric/config.toml
        Version:  mf version [--check]
        """
    }
}
