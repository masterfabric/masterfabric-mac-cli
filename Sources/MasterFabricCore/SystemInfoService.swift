import Foundation

public enum SystemInfoService {
    public static func current() -> SystemInfo {
        let modelIdentifier = sysctlString("hw.model") ?? "Unknown"
        let brand = sysctlString("machdep.cpu.brand_string")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let pCores = sysctlInt("hw.perflevel0.logicalcpu") ?? 0
        let eCores = sysctlInt("hw.perflevel1.logicalcpu") ?? 0
        let cpuCount = ProcessInfo.processInfo.processorCount
        let chip = resolveChip(brand: brand, identifier: modelIdentifier, pCores: pCores, eCores: eCores)
        let model = refineMarketingName(marketingName(for: modelIdentifier) ?? modelIdentifier, chip: chip)
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let macOSVersion = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        let ramBytes = ProcessInfo.processInfo.physicalMemory
        let ramGB = Double(ramBytes) / 1_073_741_824.0
        let uptime = ProcessInfo.processInfo.systemUptime

        return SystemInfo(
            model: model,
            modelIdentifier: modelIdentifier,
            chip: chip,
            macOSVersion: macOSVersion,
            ramGB: (ramGB * 10).rounded() / 10,
            uptimeSeconds: uptime,
            cpuCount: cpuCount,
            performanceCoreCount: pCores,
            efficiencyCoreCount: eCores
        )
    }

    private static func resolveChip(brand: String?, identifier: String, pCores: Int, eCores: Int) -> String {
        let base: String
        if let brand, !brand.isEmpty, brand.lowercased() != "unknown", Int(brand) == nil {
            base = brand
        } else if let inferred = chipFromIdentifier(identifier) {
            base = inferred
        } else {
            base = "Apple Silicon"
        }
        if pCores > 0, eCores > 0 {
            return "\(base) (\(pCores)P+\(eCores)E)"
        }
        return base
    }

    private static func chipFromIdentifier(_ identifier: String) -> String? {
        if identifier.hasPrefix("Mac17") {
            if identifier == "Mac17,2" { return "Apple M5" }
            return "Apple M5 Pro"
        }
        if identifier.hasPrefix("Mac16") {
            switch identifier {
            case "Mac16,1", "Mac16,12", "Mac16,13": return "Apple M4"
            case "Mac16,7", "Mac16,8": return "Apple M4 Max"
            default: return "Apple M4 Pro"
            }
        }
        return nil
    }

    private static func refineMarketingName(_ name: String, chip: String) -> String {
        guard name.contains("Pro/Max") else { return name }
        let lower = chip.lowercased()
        if lower.contains("max") {
            return name.replacingOccurrences(of: "Pro/Max", with: "Max")
        }
        if lower.contains("pro") {
            return name.replacingOccurrences(of: "Pro/Max", with: "Pro")
        }
        return name
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }

    private static func marketingName(for identifier: String) -> String? {
        // Identifiers from Apple Support (MacBook Pro) + Air/M-series notebooks.
        let map: [String: String] = [
            "Mac14,2": "MacBook Air (M2)",
            "Mac14,7": "MacBook Pro 13-inch (M2)",
            "Mac14,5": "MacBook Pro 14-inch (M2 Max)",
            "Mac14,6": "MacBook Pro 16-inch (M2 Max)",
            "Mac14,9": "MacBook Pro 14-inch (M2 Pro)",
            "Mac14,10": "MacBook Pro 16-inch (M2 Pro)",
            "Mac15,3": "MacBook Pro 14-inch (M3)",
            "Mac15,6": "MacBook Pro 14-inch (M3 Pro)",
            "Mac15,7": "MacBook Pro 16-inch (M3 Pro)",
            "Mac15,8": "MacBook Pro 14-inch (M3 Max)",
            "Mac15,9": "MacBook Pro 16-inch (M3 Max)",
            "Mac15,10": "MacBook Pro 14-inch (M3 Max)",
            "Mac15,11": "MacBook Pro 16-inch (M3 Max)",
            "Mac15,12": "MacBook Air 13-inch (M3)",
            "Mac15,13": "MacBook Air 15-inch (M3)",
            "Mac16,1": "MacBook Pro 14-inch (M4)",
            "Mac16,5": "MacBook Pro 16-inch (M4 Pro/Max)",
            "Mac16,6": "MacBook Pro 14-inch (M4 Pro/Max)",
            "Mac16,7": "MacBook Pro 16-inch (M4 Pro/Max)",
            "Mac16,8": "MacBook Pro 14-inch (M4 Pro/Max)",
            "Mac16,12": "MacBook Air 13-inch (M4)",
            "Mac16,13": "MacBook Air 15-inch (M4)",
            "Mac17,2": "MacBook Pro 14-inch (M5)",
            "Mac17,6": "MacBook Pro 16-inch (M5 Pro/Max)",
            "Mac17,7": "MacBook Pro 14-inch (M5 Pro/Max)",
            "Mac17,8": "MacBook Pro 16-inch (M5 Pro/Max)",
            "Mac17,9": "MacBook Pro 14-inch (M5 Pro/Max)",
            "MacBookAir10,1": "MacBook Air (M1)",
            "MacBookPro17,1": "MacBook Pro 13-inch (M1)",
            "MacBookPro18,1": "MacBook Pro 16-inch (M1 Pro)",
            "MacBookPro18,2": "MacBook Pro 16-inch (M1 Max)",
            "MacBookPro18,3": "MacBook Pro 14-inch (M1 Pro)",
            "MacBookPro18,4": "MacBook Pro 14-inch (M1 Max)",
        ]
        return map[identifier]
    }
}
