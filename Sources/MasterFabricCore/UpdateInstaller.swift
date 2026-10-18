import Foundation

/// Installs a published GitHub release tag, then reopens the menu bar.
///
/// The menu bar must not codesign its own running binary. `spawnDetached` starts
/// this script outside the app and the app quits. The script waits for that process
/// to exit, installs the tag, and opens the app again.
public enum UpdateInstaller {
    public static let supportDirectory: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/masterfabric", isDirectory: true)
    }()

    public static var logFilePath: String {
        supportDirectory.appendingPathComponent("update.log").path
    }

    public static var statusFilePath: String {
        supportDirectory.appendingPathComponent("update-status.txt").path
    }

    public struct Status: Equatable, Sendable {
        public var ok: Bool
        public var ref: String
        public var detail: String
    }

    /// Read the last install result once, then delete it so the next launch stays quiet.
    public static func consumeStatus() -> Status? {
        let url = URL(fileURLWithPath: statusFilePath)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        try? FileManager.default.removeItem(at: url)
        return parseStatus(text)
    }

    public static func failureTail() -> String {
        guard let text = try? String(contentsOfFile: logFilePath, encoding: .utf8) else { return "" }
        return tail(text, lines: 20)
    }

    /// Build and install `ref` (for example `v0.4.16`) in this process. Reopens the menu bar when it was running.
    public static func runSynchronously(ref: String, prefix: String) throws -> String {
        let wasRunning = menuBarIsRunning()
        let script = try writeScript(ref: ref, prefix: prefix, waitForPID: 0, reopen: wasRunning)
        let output = try runScript(at: script)
        if let status = readStatusWithoutDeleting(), !status.ok {
            throw UpdateInstallerError.installFailed(status.detail)
        }
        return output
    }

    /// Start the installer outside this process. Caller should then quit the menu bar.
    public static func spawnDetached(ref: String, prefix: String, waitForPID: Int32) throws {
        let script = try writeScript(ref: ref, prefix: prefix, waitForPID: waitForPID, reopen: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "nohup /bin/bash \(shellQuote(script.path)) >/dev/null 2>&1 &"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw UpdateInstallerError.spawnFailed
        }
    }

    public static func releaseRef(_ remote: String) -> String {
        "v" + VersionService.normalize(remote)
    }

    // MARK: - Script

    private static func writeScript(ref: String, prefix: String, waitForPID: Int32, reopen: Bool) throws -> URL {
        let safeRef = try validatedRef(ref)
        let safePrefix = try validatedPrefix(prefix)
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        let url = supportDirectory.appendingPathComponent("update.sh")
        let body = script(
            ref: safeRef,
            prefix: safePrefix,
            repo: AppVersion.gitCloneURL,
            support: supportDirectory.path,
            log: logFilePath,
            status: statusFilePath,
            waitForPID: waitForPID,
            reopen: reopen
        )
        try body.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    private static func script(
        ref: String,
        prefix: String,
        repo: String,
        support: String,
        log: String,
        status: String,
        waitForPID: Int32,
        reopen: Bool
    ) -> String {
        let reopenFlag = reopen ? "1" : "0"
        return """
        #!/bin/bash
        set -u
        REF=\(shellQuote(ref))
        PREFIX=\(shellQuote(prefix))
        REPO=\(shellQuote(repo))
        SUPPORT=\(shellQuote(support))
        LOG=\(shellQuote(log))
        STATUS=\(shellQuote(status))
        REOPEN=\(reopenFlag)
        WAIT_PID=\(waitForPID)
        export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin:${PATH:-}"
        export GIT_TERMINAL_PROMPT=0
        mkdir -p "$SUPPORT"
        : > "$LOG"
        exec >>"$LOG" 2>&1
        echo "==> MasterFabric update $REF"
        echo "==> $(date)"
        TMP=""
        cleanup() {
          local code=$?
          if [[ -n "$TMP" ]]; then
            rm -rf "$TMP"
          fi
          if [[ $code -eq 0 ]]; then
            {
              echo ok
              echo "$REF"
              echo "Installed GitHub release $REF."
            } > "$STATUS"
          else
            {
              echo failed
              echo "$REF"
              echo "GitHub release install failed (exit $code)."
              echo "Log: $LOG"
              tail -n 12 "$LOG" || true
            } > "$STATUS"
          fi
          if [[ "$REOPEN" == "1" ]]; then
            /usr/bin/open "$PREFIX/MasterFabricMenuBar.app" || true
          fi
          exit "$code"
        }
        trap cleanup EXIT
        set -euo pipefail
        if [[ "$WAIT_PID" != "0" ]]; then
          for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40; do
            kill -0 "$WAIT_PID" 2>/dev/null || break
            sleep 0.25
          done
        fi
        if /usr/bin/pgrep -x MasterFabricMenuBar >/dev/null 2>&1; then
          /usr/bin/killall MasterFabricMenuBar || true
          sleep 0.4
        fi
        command -v git >/dev/null 2>&1 || { echo "error: git is required."; exit 1; }
        command -v swift >/dev/null 2>&1 || { echo "error: Swift toolchain required (Xcode or Command Line Tools)."; exit 1; }
        command -v make >/dev/null 2>&1 || { echo "error: make is required."; exit 1; }
        TMP="$(mktemp -d)"
        echo "==> Cloning $REF from $REPO"
        git clone --depth 1 --branch "$REF" "$REPO" "$TMP/src"
        echo "==> Building and installing into $PREFIX"
        make -C "$TMP/src" install "PREFIX=$PREFIX"
        echo "==> Installed $($PREFIX/bin/mf version 2>/dev/null || echo unknown)"
        """
    }

    private static func runScript(at url: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        let output = failureTail()
        if process.terminationStatus != 0 {
            let detail = readStatusWithoutDeleting()?.detail ?? output
            throw UpdateInstallerError.installFailed(detail.isEmpty ? "install failed" : detail)
        }
        return output
    }

    private static func readStatusWithoutDeleting() -> Status? {
        guard let text = try? String(contentsOfFile: statusFilePath, encoding: .utf8) else { return nil }
        return parseStatus(text)
    }

    private static func parseStatus(_ text: String) -> Status? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count >= 2 else { return nil }
        let ok = lines[0].trimmingCharacters(in: .whitespacesAndNewlines) == "ok"
        let ref = lines[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = lines.dropFirst(2).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return Status(ok: ok, ref: ref, detail: detail.isEmpty ? (ok ? "Installed \(ref)." : "Update failed.") : detail)
    }

    private static func menuBarIsRunning() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", "MasterFabricMenuBar"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func validatedRef(_ ref: String) throws -> String {
        let pattern = #"^v[0-9]+(\.[0-9]+){1,3}$"#
        guard ref.range(of: pattern, options: .regularExpression) != nil else {
            throw UpdateInstallerError.invalidRef(ref)
        }
        return ref
    }

    private static func validatedPrefix(_ prefix: String) throws -> String {
        if prefix.isEmpty || prefix.contains("\n") || prefix.contains("'") || !prefix.hasPrefix("/") {
            throw UpdateInstallerError.invalidPrefix(prefix)
        }
        return prefix
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func tail(_ text: String, lines: Int) -> String {
        let rows = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return rows.suffix(lines).joined(separator: "\n")
    }
}

public enum UpdateInstallerError: LocalizedError {
    case invalidRef(String)
    case invalidPrefix(String)
    case spawnFailed
    case installFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRef(let ref):
            return "Refusing to install unexpected release ref \(ref)."
        case .invalidPrefix(let prefix):
            return "Refusing to install into \(prefix)."
        case .spawnFailed:
            return "Could not start the update. See \(UpdateInstaller.logFilePath)"
        case .installFailed(let detail):
            return detail
        }
    }
}
