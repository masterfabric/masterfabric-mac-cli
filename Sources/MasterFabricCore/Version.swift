import Foundation

/// Single source of truth for the product version (keep in sync with root `VERSION`).
public enum AppVersion {
    public static let current = "0.4.14"
    public static let repoOwner = "gurkanfikretgunak"
    public static let repoName = "masterfabric-mac-cli"
    public static var repoURL: String { "https://github.com/\(repoOwner)/\(repoName)" }
    public static var releasesURL: String { "\(repoURL)/releases" }
    public static var apiReleasesLatest: String {
        "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
    }
    public static var apiTags: String {
        "https://api.github.com/repos/\(repoOwner)/\(repoName)/tags?per_page=5"
    }
}

public struct VersionCheckResult: Sendable, Codable, Equatable {
    public var local: String
    public var remote: String?
    public var updateAvailable: Bool
    public var source: String
    public var detail: String
    public var repoURL: String
    public var releasesURL: String

    public init(
        local: String,
        remote: String?,
        updateAvailable: Bool,
        source: String,
        detail: String,
        repoURL: String = AppVersion.repoURL,
        releasesURL: String = AppVersion.releasesURL
    ) {
        self.local = local
        self.remote = remote
        self.updateAvailable = updateAvailable
        self.source = source
        self.detail = detail
        self.repoURL = repoURL
        self.releasesURL = releasesURL
    }
}

public enum VersionService {
    /// Compare local version to the open-source GitHub repo (latest release, else newest tag).
    public static func check(local: String = AppVersion.current) -> VersionCheckResult {
        do {
            if let release = try fetchLatestRelease() {
                let remote = normalize(release)
                let cmp = compare(remote, normalize(local))
                let available = cmp == .orderedDescending
                let detail: String
                switch cmp {
                case .orderedDescending:
                    detail = "Update available: v\(local) → v\(remote)"
                case .orderedSame:
                    detail = "Up to date with GitHub release v\(remote)"
                case .orderedAscending:
                    detail = "Local v\(local) is newer than GitHub release v\(remote) (unreleased / ahead)"
                }
                return VersionCheckResult(
                    local: local,
                    remote: remote,
                    updateAvailable: available,
                    source: "github-release",
                    detail: detail
                )
            }
            if let tag = try fetchLatestTag() {
                let remote = normalize(tag)
                let cmp = compare(remote, normalize(local))
                let available = cmp == .orderedDescending
                let detail: String
                switch cmp {
                case .orderedDescending:
                    detail = "Newer tag on GitHub: v\(local) → v\(remote)"
                case .orderedSame:
                    detail = "Up to date with GitHub tag v\(remote)"
                case .orderedAscending:
                    detail = "Local v\(local) is newer than GitHub tag v\(remote) (unreleased / ahead)"
                }
                return VersionCheckResult(
                    local: local,
                    remote: remote,
                    updateAvailable: available,
                    source: "github-tag",
                    detail: detail
                )
            }
            return VersionCheckResult(
                local: local,
                remote: nil,
                updateAvailable: false,
                source: "github",
                detail: "No releases or tags found yet on \(AppVersion.repoURL)"
            )
        } catch {
            return VersionCheckResult(
                local: local,
                remote: nil,
                updateAvailable: false,
                source: "error",
                detail: "Could not reach GitHub: \(error.localizedDescription)"
            )
        }
    }

    public static func format(_ result: VersionCheckResult) -> String {
        var lines = [
            "\(AboutInfo.product) v\(result.local)",
            "Repo: \(result.repoURL)",
        ]
        if let remote = result.remote {
            lines.append("GitHub (\(result.source)): v\(remote)")
        } else {
            lines.append("GitHub (\(result.source)): —")
        }
        lines.append(result.detail)
        if result.updateAvailable {
            lines.append("Update: \(result.releasesURL)")
            lines.append("Run:    mf update")
            lines.append("Or:     curl -fsSL \(AppVersion.repoURL)/raw/main/scripts/install.sh | bash")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - GitHub

    private static func fetchLatestRelease() throws -> String? {
        guard let url = URL(string: AppVersion.apiReleasesLatest) else { return nil }
        let (data, response) = try httpGET(url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return nil }
        guard (200...299).contains(status) else {
            throw VersionError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let tag = obj["tag_name"] as? String { return tag }
        return nil
    }

    private static func fetchLatestTag() throws -> String? {
        guard let url = URL(string: AppVersion.apiTags) else { return nil }
        let (data, response) = try httpGET(url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            throw VersionError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = arr.first,
              let name = first["name"] as? String
        else { return nil }
        return name
    }

    private static func httpGET(_ url: URL) throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MasterFabricCLI/\(AppVersion.current)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let box = VersionSyncBox()
        let sem = DispatchSemaphore(value: 0)
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            box.data = data
            box.response = response
            box.error = error
            sem.signal()
        }
        task.resume()
        if sem.wait(timeout: .now() + 20) == .timedOut {
            task.cancel()
            throw URLError(.timedOut)
        }
        if let error = box.error { throw error }
        guard let data = box.data, let response = box.response else {
            throw URLError(.badServerResponse)
        }
        return (data, response)
    }

    public static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("v") {
            s = String(s.dropFirst())
        }
        return s
    }

    /// Semver-ish compare: returns true if `remote` is strictly newer than `local`.
    public static func isRemoteNewer(remote: String, local: String) -> Bool {
        compare(normalize(remote), normalize(local)) == .orderedDescending
    }

    private static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let ap = a.split(separator: ".").map { Int($0) ?? 0 }
        let bp = b.split(separator: ".").map { Int($0) ?? 0 }
        let n = max(ap.count, bp.count)
        for i in 0..<n {
            let x = i < ap.count ? ap[i] : 0
            let y = i < bp.count ? bp[i] : 0
            if x < y { return .orderedAscending }
            if x > y { return .orderedDescending }
        }
        return .orderedSame
    }

    public enum VersionError: Error, LocalizedError {
        case http(Int, String)
        public var errorDescription: String? {
            switch self {
            case .http(let code, let body):
                return "HTTP \(code): \(body.prefix(200))"
            }
        }
    }
}

/// Install / upgrade from the open-source GitHub repo via `scripts/install.sh`.
public enum UpdateService {
    public static var installScriptURL: String {
        "\(AppVersion.repoURL)/raw/main/scripts/install.sh"
    }

    public struct Result: Sendable, Codable, Equatable {
        public var performed: Bool
        public var localBefore: String
        public var localAfter: String?
        public var check: VersionCheckResult
        public var output: String
        public var detail: String
        public var steps: [String]

        public init(
            performed: Bool,
            localBefore: String,
            localAfter: String? = nil,
            check: VersionCheckResult,
            output: String,
            detail: String,
            steps: [String] = []
        ) {
            self.performed = performed
            self.localBefore = localBefore
            self.localAfter = localAfter
            self.check = check
            self.output = output
            self.detail = detail
            self.steps = steps
        }
    }

    /// Check GitHub; if newer (or `force`), run the official install script.
    public static func update(
        force: Bool = false,
        prefix: String? = nil,
        onStep: ((String) -> Void)? = nil
    ) -> Result {
        var steps: [String] = []
        func step(_ message: String) {
            steps.append(message)
            onStep?(message)
        }

        let before = AppVersion.current
        step("checking_github")
        let check = VersionService.check(local: before)
        if let remote = check.remote {
            step("github_ok:\(remote)")
        } else {
            step("github_done:\(check.source)")
        }

        if !force, !check.updateAvailable {
            return Result(
                performed: false,
                localBefore: before,
                localAfter: before,
                check: check,
                output: "",
                detail: check.remote == nil
                    ? check.detail
                    : "Already on latest (local v\(before), GitHub v\(check.remote ?? "?")). Use --force to reinstall.",
                steps: steps
            )
        }

        let envPrefix = prefix
            ?? (ProcessInfo.processInfo.environment["MASTERFABRIC_PREFIX"] ?? "\(NSHomeDirectory())/.local")
        step("installing:\(envPrefix)")
        let script = """
        set -euo pipefail
        export MASTERFABRIC_PREFIX="\(envPrefix)"
        curl -fsSL "\(installScriptURL)" | bash
        """

        do {
            let output = try runShell(script)
            step("install_finished")
            let after = readInstalledVersion(prefix: envPrefix) ?? check.remote
            step("verify:\(after ?? "unknown")")
            let ok = after.map { VersionService.normalize($0) } ?? ""
            let expected = check.remote.map { VersionService.normalize($0) } ?? ""
            let verified = !ok.isEmpty && (expected.isEmpty || ok == expected || !VersionService.isRemoteNewer(remote: expected, local: ok))
            return Result(
                performed: true,
                localBefore: before,
                localAfter: after,
                check: check,
                output: output,
                detail: verified
                    ? "Update OK: v\(before) → v\(after ?? "?")"
                    : "Install finished but version verify unclear (before v\(before), after \(after ?? "unknown")). Run: \(envPrefix)/bin/mf version",
                steps: steps
            )
        } catch {
            step("install_failed")
            return Result(
                performed: false,
                localBefore: before,
                localAfter: nil,
                check: check,
                output: "",
                detail: "Update failed: \(error.localizedDescription)",
                steps: steps
            )
        }
    }

    public static func format(_ result: Result) -> String {
        var lines = [VersionService.format(result.check), "", result.detail]
        if let after = result.localAfter, result.performed {
            lines.append("Installed binary: v\(after)")
        }
        if !result.steps.isEmpty {
            lines.append("Steps: \(result.steps.joined(separator: " → "))")
        }
        if !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("")
            lines.append(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return lines.joined(separator: "\n")
    }

    private static func readInstalledVersion(prefix: String) -> String? {
        let mf = "\(prefix)/bin/mf"
        guard FileManager.default.isExecutableFile(atPath: mf) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: mf)
        process.arguments = ["version", "--json"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let version = obj["version"] as? String
            else { return nil }
            return VersionService.normalize(version)
        } catch {
            return nil
        }
    }

    private static func runShell(_ script: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-lc", script]
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let combined = (stdout + stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        if process.terminationStatus != 0 {
            throw NSError(
                domain: "MasterFabricUpdate",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: combined.isEmpty ? "install.sh failed" : combined]
            )
        }
        return combined
    }
}

private final class VersionSyncBox: @unchecked Sendable {
    var data: Data?
    var response: URLResponse?
    var error: Error?
}
