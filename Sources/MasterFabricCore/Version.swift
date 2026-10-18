import Foundation

/// Single source of truth for the product version (keep in sync with root `VERSION`).
public enum AppVersion {
    public static let current = "0.4.17"
    /// Canonical GitHub owner. The previous owner name redirects here.
    public static let repoOwner = "masterfabric"
    public static let legacyRepoOwner = "gurkanfikretgunak"
    public static let repoName = "masterfabric-mac-cli"
    public static var repoURL: String { "https://github.com/\(repoOwner)/\(repoName)" }
    public static var gitCloneURL: String { "\(repoURL).git" }
    public static var releasesURL: String { "\(repoURL)/releases" }
    public static var apiReleasesLatest: String {
        "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
    }
    public static var apiTags: String {
        "https://api.github.com/repos/\(repoOwner)/\(repoName)/tags?per_page=5"
    }

    public static func releasesLatestURL(owner: String) -> String {
        "https://api.github.com/repos/\(owner)/\(repoName)/releases/latest"
    }

    public static func tagsURL(owner: String) -> String {
        "https://api.github.com/repos/\(owner)/\(repoName)/tags?per_page=5"
    }

    public static func repoURL(owner: String) -> String {
        "https://github.com/\(owner)/\(repoName)"
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
        let owners = [AppVersion.repoOwner, AppVersion.legacyRepoOwner]
        var lastError: Error?
        for owner in owners {
            do {
                if let found = try lookup(owner: owner, local: local) {
                    return found
                }
            } catch {
                lastError = error
            }
        }
        if let lastError {
            return VersionCheckResult(
                local: local,
                remote: nil,
                updateAvailable: false,
                source: "error",
                detail: "Could not reach GitHub: \(lastError.localizedDescription)"
            )
        }
        return VersionCheckResult(
            local: local,
            remote: nil,
            updateAvailable: false,
            source: "github",
            detail: "No releases or tags found yet on \(AppVersion.repoURL)"
        )
    }

    private static func lookup(owner: String, local: String) throws -> VersionCheckResult? {
        let repoURL = AppVersion.repoURL(owner: owner)
        let releasesURL = "\(repoURL)/releases"
        if let release = try fetchLatestRelease(owner: owner) {
            return compared(
                remoteRaw: release,
                local: local,
                source: "github-release",
                repoURL: repoURL,
                releasesURL: releasesURL,
                newer: "Update available: v\(local) → v",
                same: "Up to date with GitHub release v",
                older: "Local v\(local) is newer than GitHub release v"
            )
        }
        if let tag = try fetchLatestTag(owner: owner) {
            return compared(
                remoteRaw: tag,
                local: local,
                source: "github-tag",
                repoURL: repoURL,
                releasesURL: releasesURL,
                newer: "Newer tag on GitHub: v\(local) → v",
                same: "Up to date with GitHub tag v",
                older: "Local v\(local) is newer than GitHub tag v"
            )
        }
        return nil
    }

    private static func compared(
        remoteRaw: String,
        local: String,
        source: String,
        repoURL: String,
        releasesURL: String,
        newer: String,
        same: String,
        older: String
    ) -> VersionCheckResult {
        let remote = normalize(remoteRaw)
        let cmp = compare(remote, normalize(local))
        let detail: String
        switch cmp {
        case .orderedDescending:
            detail = "\(newer)\(remote)"
        case .orderedSame:
            detail = "\(same)\(remote)"
        case .orderedAscending:
            detail = "\(older)\(remote) (unreleased / ahead)"
        }
        return VersionCheckResult(
            local: local,
            remote: remote,
            updateAvailable: cmp == .orderedDescending,
            source: source,
            detail: detail,
            repoURL: repoURL,
            releasesURL: releasesURL
        )
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

    private static func fetchLatestRelease(owner: String) throws -> String? {
        guard let url = URL(string: AppVersion.releasesLatestURL(owner: owner)) else { return nil }
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

    private static func fetchLatestTag(owner: String) throws -> String? {
        guard let url = URL(string: AppVersion.tagsURL(owner: owner)) else { return nil }
        let (data, response) = try httpGET(url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return nil }
        guard (200...299).contains(status) else {
            throw VersionError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = arr.first,
              let name = first["name"] as? String
        else { return nil }
        return name
    }

    /// Follow GitHub's repo-move redirects. A 301 body is not a release.
    private static func httpGET(_ url: URL, hops: Int = 0) throws -> (Data, URLResponse) {
        let (data, response) = try httpGETOnce(url)
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        if hops < 5,
           (300...399).contains(status),
           let location = http?.value(forHTTPHeaderField: "Location"),
           let next = URL(string: location, relativeTo: url)?.absoluteURL {
            return try httpGET(next, hops: hops + 1)
        }
        return (data, response)
    }

    private static func httpGETOnce(_ url: URL) throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MasterFabricCLI/\(AppVersion.current)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let box = VersionSyncBox()
        let sem = DispatchSemaphore(value: 0)
        let task = VersionHTTP.session.dataTask(with: request) { data, response, error in
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

/// Install / upgrade from the published GitHub release tag.
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

    /// Check GitHub; if newer (or `force`), install that release tag and reopen the menu bar when it was running.
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
        guard let remote = check.remote else {
            return Result(
                performed: false,
                localBefore: before,
                localAfter: nil,
                check: check,
                output: "",
                detail: check.detail,
                steps: steps
            )
        }

        let envPrefix = prefix
            ?? (ProcessInfo.processInfo.environment["MASTERFABRIC_PREFIX"] ?? "\(NSHomeDirectory())/.local")
        let ref = UpdateInstaller.releaseRef(remote)
        step("installing:\(envPrefix)")
        step("log:\(UpdateInstaller.logFilePath)")

        do {
            let output = try UpdateInstaller.runSynchronously(ref: ref, prefix: envPrefix)
            step("install_finished")
            let after = readInstalledVersion(prefix: envPrefix) ?? VersionService.normalize(remote)
            step("verify:\(after)")
            let expected = VersionService.normalize(remote)
            let verified = after == expected || !VersionService.isRemoteNewer(remote: expected, local: after)
            return Result(
                performed: true,
                localBefore: before,
                localAfter: after,
                check: check,
                output: output,
                detail: verified
                    ? "Update OK: v\(before) → v\(after)"
                    : "Install finished but version verify unclear (before v\(before), after v\(after)). Run: \(envPrefix)/bin/mf version",
                steps: steps
            )
        } catch {
            step("install_failed")
            let tail = UpdateInstaller.failureTail()
            return Result(
                performed: false,
                localBefore: before,
                localAfter: nil,
                check: check,
                output: tail,
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
        if result.steps.contains(where: { $0.hasPrefix("log:") || $0 == "install_failed" }) {
            lines.append("Log: \(UpdateInstaller.logFilePath)")
        }
        if !result.steps.isEmpty {
            lines.append("Steps: \(result.steps.joined(separator: " → "))")
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
        process.standardError = FileHandle.nullDevice
        let group = DispatchGroup()
        group.enter()
        let box = VersionSyncBox()
        DispatchQueue.global(qos: .userInitiated).async {
            box.data = out.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        do {
            try process.run()
            process.waitUntilExit()
            group.wait()
            guard process.terminationStatus == 0, let data = box.data else { return nil }
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let version = obj["version"] as? String
            else { return nil }
            return VersionService.normalize(version)
        } catch {
            try? out.fileHandleForWriting.close()
            group.wait()
            return nil
        }
    }
}

private final class VersionSyncBox: @unchecked Sendable {
    var data: Data?
    var response: URLResponse?
    var error: Error?
}

/// Surface GitHub 301/302 to `httpGET` instead of treating the redirect body as a failed release lookup.
private final class VersionHTTP: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.httpShouldSetCookies = false
        config.urlCache = nil
        return URLSession(configuration: config, delegate: VersionHTTP(), delegateQueue: nil)
    }()

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
