import Darwin
import Foundation

@_silgen_name("os_proc_available_memory")
private func osProcAvailableMemory() -> UInt64

/// RAM headroom for loading a model, and a one-at-a-time quit of a chosen process.
public enum MemoryRoomService {
    public static let panelLimit = 18

    public static let gib = 1024.0 * 1024.0 * 1024.0

    /// Cheap reading for the live graph. Does not list processes.
    public static func headroom() -> (memory: MemoryInfo, availableBytes: UInt64) {
        let memory = MemoryService.current()
        return (memory, availableBytes(fallback: memory.freeBytes))
    }

    public static func targetBytes(gigabytes: Double) -> UInt64 {
        UInt64(max(0, gigabytes) * gib)
    }

    /// Largest-first candidates for Make room. Leaves Cursor itself, this agent, model runtimes, and protected processes running.
    public static func isMakeRoomCandidate(_ consumer: MemoryConsumer) -> Bool {
        guard consumer.releasable, consumer.role != "model" else { return false }
        if consumer.name.compare("Cursor", options: .caseInsensitive) == .orderedSame { return false }
        return consumer.memoryBytes >= 64 * 1024 * 1024
    }

    /// Quit eligible apps until `targetBytes` is allocatable. One failed or stuck process is skipped; the run continues.
    public static func makeRoom(
        targetBytes: () -> UInt64,
        maxQuits: Int = 24,
        pause: TimeInterval = 1.2,
        shouldStop: () -> Bool = { false },
        onStep: (MemoryMakeStep) -> Void
    ) {
        var skipped = Set<Int32>()
        var quits = 0
        while quits < maxQuits {
            let target = targetBytes()
            if shouldStop() {
                onStep(makeStep(targetBytes: target, detail: "Stopped.", done: true))
                return
            }
            let head = headroom()
            if head.availableBytes >= target {
                onStep(makeStep(
                    targetBytes: target,
                    available: head.availableBytes,
                    detail: "Room reached \(TextFormat.bytes(head.availableBytes)).",
                    done: true
                ))
                return
            }
            let room = snapshot(limit: 40)
            guard let next = room.consumers.first(where: { isMakeRoomCandidate($0) && !skipped.contains($0.pid) }) else {
                let gap = target > head.availableBytes ? target - head.availableBytes : 0
                onStep(makeStep(
                    targetBytes: target,
                    available: head.availableBytes,
                    detail: "Room is \(TextFormat.bytes(head.availableBytes)). Target still needs \(TextFormat.bytes(gap)). Cursor and this agent stay running.",
                    done: true
                ))
                return
            }
            let result = release(pid: next.pid, force: false)
            if !result.ok {
                skipped.insert(next.pid)
                onStep(makeStep(targetBytes: target, available: head.availableBytes, detail: result.detail, done: false))
                continue
            }
            quits += 1
            onStep(makeStep(targetBytes: target, available: head.availableBytes, detail: result.detail, done: false))
            Thread.sleep(forTimeInterval: pause)
            if snapshot(limit: 40).consumers.contains(where: { $0.pid == next.pid }) {
                skipped.insert(next.pid)
            }
        }
        let target = targetBytes()
        let head = headroom()
        let gap = target > head.availableBytes ? target - head.availableBytes : 0
        let detail = head.availableBytes >= target
            ? "Room reached \(TextFormat.bytes(head.availableBytes))."
            : "Stopped after \(maxQuits) apps. Room is \(TextFormat.bytes(head.availableBytes)); still need \(TextFormat.bytes(gap))."
        onStep(makeStep(targetBytes: target, available: head.availableBytes, detail: detail, done: true))
    }

    private static func makeStep(
        targetBytes: UInt64,
        available: UInt64? = nil,
        detail: String,
        done: Bool
    ) -> MemoryMakeStep {
        let bytes = available ?? headroom().availableBytes
        return MemoryMakeStep(
            availableBytes: bytes,
            targetBytes: targetBytes,
            detail: detail,
            done: done
        )
    }

    public static func snapshot(limit: Int = 20) -> MemoryRoom {
        let memory = MemoryService.current()
        let ranked = ProcessService.byMemory(limit: 10_000).map(consumer(from:))
        let quittable = ranked.filter(\.releasable).reduce(UInt64(0)) { $0 + $1.memoryBytes }
        return MemoryRoom(
            memory: memory,
            availableBytes: availableBytes(fallback: memory.freeBytes),
            quittableBytes: quittable,
            consumers: Array(ranked.prefix(max(1, limit)))
        )
    }

    /// SIGTERM by default. `force` sends SIGKILL. Protected system processes are refused.
    public static func release(pid: Int32, force: Bool = false) -> MemoryReleaseResult {
        if pid <= 1 || pid == ProcessInfo.processInfo.processIdentifier {
            return refused(pid: pid, name: "pid \(pid)", memoryBytes: 0, detail: "That process is protected and was left running.")
        }
        guard let info = ProcessService.lookup(pid: pid) else {
            return MemoryReleaseResult(
                ok: false,
                pid: pid,
                name: "",
                memoryBytes: 0,
                signal: "",
                detail: "No process with pid \(pid)."
            )
        }
        guard canRelease(pid: info.pid, name: info.name) else {
            return refused(
                pid: info.pid,
                name: info.name,
                memoryBytes: info.memoryBytes,
                detail: "\(info.name) (\(info.pid)) is protected and was left running."
            )
        }

        let signal = force ? SIGKILL : SIGTERM
        let signalName = force ? "SIGKILL" : "SIGTERM"
        if kill(pid, signal) != 0 {
            let err = errno
            let why = err == EPERM ? "permission denied" : String(cString: strerror(err))
            return MemoryReleaseResult(
                ok: false,
                pid: info.pid,
                name: info.name,
                memoryBytes: info.memoryBytes,
                signal: signalName,
                detail: "macOS refused to quit \(info.name) (\(info.pid)): \(why)."
            )
        }

        let verb = force ? "Forced" : "Asked"
        let how = force ? "to exit" : "to quit"
        return MemoryReleaseResult(
            ok: true,
            pid: info.pid,
            name: info.name,
            memoryBytes: info.memoryBytes,
            signal: signalName,
            detail: "\(verb) \(info.name) (\(info.pid)) \(how) (\(signalName)). About \(TextFormat.bytes(info.memoryBytes)) can return for a model."
        )
    }

    private static func availableBytes(fallback: UInt64) -> UInt64 {
        let room = osProcAvailableMemory()
        return room > 0 ? room : fallback
    }

    private static func consumer(from info: ProcessCPUInfo) -> MemoryConsumer {
        if canRelease(pid: info.pid, name: info.name) {
            if isModelRuntime(info.name) {
                return MemoryConsumer(
                    pid: info.pid,
                    name: info.name,
                    memoryBytes: info.memoryBytes,
                    cpuPercent: info.cpuPercent,
                    role: "model",
                    releasable: true,
                    note: "Model runtime"
                )
            }
            return MemoryConsumer(
                pid: info.pid,
                name: info.name,
                memoryBytes: info.memoryBytes,
                cpuPercent: info.cpuPercent,
                role: "app",
                releasable: true,
                note: "App"
            )
        }
        return MemoryConsumer(
            pid: info.pid,
            name: info.name,
            memoryBytes: info.memoryBytes,
            cpuPercent: info.cpuPercent,
            role: "system",
            releasable: false,
            note: "Kept running"
        )
    }

    private static func canRelease(pid: Int32, name: String) -> Bool {
        if pid <= 1 || pid == ProcessInfo.processInfo.processIdentifier {
            return false
        }
        let lowered = name.lowercased()
        if protectedNames.contains(lowered) { return false }
        // Tailscale's macOS process name is the system extension, not `tailscaled`.
        if lowered.contains("tailscale") || lowered.contains("masterfabric") { return false }
        return true
    }

    private static func isModelRuntime(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return modelNameFragments.contains { lowered.contains($0) }
    }

    private static func refused(pid: Int32, name: String, memoryBytes: UInt64, detail: String) -> MemoryReleaseResult {
        MemoryReleaseResult(
            ok: false,
            pid: pid,
            name: name,
            memoryBytes: memoryBytes,
            signal: "",
            detail: detail
        )
    }

    /// Names that keep the Mac, this menu bar, and the pod network up.
    private static let protectedNames: Set<String> = [
        "kernel_task",
        "launchd",
        "launchservicesd",
        "windowserver",
        "loginwindow",
        "sysmond",
        "syslogd",
        "logd",
        "notifyd",
        "distnoted",
        "cfprefsd",
        "usereventagent",
        "runningboardd",
        "trustd",
        "securityd",
        "opendirectoryd",
        "coreservicesd",
        "coreauthd",
        "configd",
        "powerd",
        "thermalmonitord",
        "watchdogd",
        "kernelmanagerd",
        "amfid",
        "syspolicyd",
        "endpointsecurityd",
        "tccd",
        "sandboxd",
        "diskarbitrationd",
        "fseventsd",
        "mdnsresponder",
        "bluetoothd",
        "airportd",
        "coreaudiod",
        "audiomxd",
        "mediaremoted",
        "containermanagerd",
        "lsd",
        "secinitd",
        "masterfabricmenubar",
        "tailscaled",
        "tailscale",
    ]

    private static let modelNameFragments = [
        "ollama",
        "llama-server",
        "llama.cpp",
        "lmstudio",
        "lm studio",
        "mlx",
        "vllm",
        "gpt4all",
    ]
}

public struct MemoryMakeStep: Sendable {
    public var availableBytes: UInt64
    public var targetBytes: UInt64
    public var detail: String
    public var done: Bool

    public init(availableBytes: UInt64, targetBytes: UInt64, detail: String, done: Bool) {
        self.availableBytes = availableBytes
        self.targetBytes = targetBytes
        self.detail = detail
        self.done = done
    }
}

public struct MemoryTrendSample: Sendable, Equatable {
    public var timestamp: Date
    public var availableBytes: UInt64
    public var usedPercent: Double

    public init(timestamp: Date, availableBytes: UInt64, usedPercent: Double) {
        self.timestamp = timestamp
        self.availableBytes = availableBytes
        self.usedPercent = usedPercent
    }
}

/// In-memory allocatable-RAM samples for the live 60-second graph.
public enum MemoryTrendStore {
    public static let window: TimeInterval = 60
    private static let lock = NSLock()
    private static var samples: [MemoryTrendSample] = []

    public static func record(availableBytes: UInt64, usedPercent: Double, now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        samples.append(MemoryTrendSample(timestamp: now, availableBytes: availableBytes, usedPercent: usedPercent))
        let cutoff = now.addingTimeInterval(-window)
        samples.removeAll { $0.timestamp < cutoff }
    }

    public static func snapshot() -> [MemoryTrendSample] {
        lock.lock()
        defer { lock.unlock() }
        return samples
    }
}
