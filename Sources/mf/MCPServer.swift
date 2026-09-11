import ArgumentParser
import Foundation
import MasterFabricCore

extension MF {
    /// stdio MCP server for Cursor / Claude Desktop.
    struct MCP: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "mcp",
            abstract: "Start the MasterFabric MCP server (stdio JSON-RPC)."
        )

        func run() throws {
            MCPServer().run()
        }
    }
}

/// Minimal MCP 2024-11-05 compatible stdio server (Content-Length framing).
final class MCPServer {
    func run() {
        // Avoid stdout buffering issues when piped
        setbuf(stdout, nil)

        var buffer = Data()
        let fd = FileHandle.standardInput.fileDescriptor
        var chunk = [UInt8](repeating: 0, count: 65_536)

        while true {
            let n = read(fd, &chunk, chunk.count)
            if n < 0 {
                // Interrupted — retry
                if errno == EINTR { continue }
                break
            }
            if n == 0 {
                // EOF
                while let message = extractMessage(from: &buffer) {
                    handle(message)
                }
                break
            }
            buffer.append(contentsOf: chunk[0..<n])
            while let message = extractMessage(from: &buffer) {
                handle(message)
            }
        }
    }

    private func extractMessage(from buffer: inout Data) -> Data? {
        guard let sep = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            // Newline-delimited JSON fallback (debug / simple clients)
            if let nl = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let line = buffer.subdata(in: buffer.startIndex..<nl)
                let next = buffer.index(after: nl)
                buffer.removeSubrange(buffer.startIndex..<next)
                if line.isEmpty { return extractMessage(from: &buffer) }
                return line
            }
            return nil
        }

        let headerData = buffer.subdata(in: buffer.startIndex..<sep.lowerBound)
        guard let header = String(data: headerData, encoding: .utf8) else {
            buffer.removeSubrange(buffer.startIndex..<sep.upperBound)
            return nil
        }

        var contentLength: Int?
        for line in header.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            if parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                contentLength = Int(parts[1].trimmingCharacters(in: .whitespaces))
            }
        }

        guard let length = contentLength, length >= 0 else {
            buffer.removeSubrange(buffer.startIndex..<sep.upperBound)
            return nil
        }

        let bodyStart = sep.upperBound
        let bodyEndOffset = buffer.distance(from: buffer.startIndex, to: bodyStart) + length
        guard buffer.count >= bodyEndOffset else { return nil }

        let bodyEnd = buffer.index(buffer.startIndex, offsetBy: bodyEndOffset)
        let body = buffer.subdata(in: bodyStart..<bodyEnd)
        buffer.removeSubrange(buffer.startIndex..<bodyEnd)
        return body
    }

    private func handle(_ data: Data) {
        guard
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let method = obj["method"] as? String
        else { return }

        let id = obj["id"]

        // Notifications: no response
        if id == nil { return }

        switch method {
        case "initialize":
            respond(id: id, result: [
                "protocolVersion": "2024-11-05",
                "capabilities": [
                    "tools": [:] as [String: Any],
                    "resources": [:] as [String: Any],
                ],
                "serverInfo": ["name": "masterfabric", "version": AboutInfo.version],
            ])
        case "ping":
            respond(id: id, result: [:] as [String: Any])
        case "tools/list":
            respond(id: id, result: ["tools": tools()])
        case "resources/list":
            respond(id: id, result: [
                "resources": [
                    [
                        "uri": "masterfabric://status",
                        "name": "System status snapshot",
                        "mimeType": "application/json",
                    ],
                ],
            ])
        case "resources/read":
            let params = obj["params"] as? [String: Any] ?? [:]
            let uri = params["uri"] as? String ?? ""
            if uri == "masterfabric://status" {
                let text = (try? JSONOutput.string(StatusService.current())) ?? "{}"
                respond(id: id, result: [
                    "contents": [
                        ["uri": uri, "mimeType": "application/json", "text": text],
                    ],
                ])
            } else {
                respondError(id: id, code: -32002, message: "Resource not found: \(uri)")
            }
        case "tools/call":
            let params = obj["params"] as? [String: Any] ?? [:]
            let name = params["name"] as? String ?? ""
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            do {
                let text = try callTool(name, arguments: arguments)
                respond(id: id, result: [
                    "content": [["type": "text", "text": text]],
                    "isError": false,
                ])
            } catch {
                respond(id: id, result: [
                    "content": [["type": "text", "text": error.localizedDescription]],
                    "isError": true,
                ])
            }
        default:
            respondError(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    private func tools() -> [[String: Any]] {
        [
            tool(name: "get_info", description: "Mac model, chip, macOS version, RAM, uptime, and P/E core counts."),
            tool(name: "get_status", description: "Current CPU/GPU temperatures and fan RPM."),
            tool(name: "get_temp", description: "CPU and GPU temperatures in Celsius."),
            tool(name: "get_fan", description: "Fan RPM list with CPU/GPU roles and mode (empty on fanless Macs)."),
            tool(
                name: "set_fan_mode",
                description: "Set both fans to auto (system thermal) or full (hardware max RPM). Fan0=CPU, Fan1=GPU. macOS often requires admin privileges; if needsPrivilege=true, ask the user to run `sudo mf fan <mode>` or use the menu bar buttons (password prompt).",
                properties: [
                    "mode": [
                        "type": "string",
                        "description": "auto | full",
                    ],
                ]
            ),
            tool(name: "get_battery", description: "Battery percent, health, cycles, watts."),
            tool(name: "get_memory", description: "Memory usage, swap, and pressure."),
            tool(name: "get_disk", description: "Root volume disk capacity."),
            tool(name: "get_network", description: "Network interface byte rates."),
            tool(name: "get_cpu_load", description: "Overall, P/E cluster, and per-core CPU load."),
            tool(name: "get_power", description: "Thermal state and low-power mode."),
            tool(name: "get_top", description: "Top processes by CPU."),
            tool(name: "get_history", description: "One-hour history sparklines."),
            tool(
                name: "set_alert_threshold",
                description: "Update alert thresholds in config.toml.",
                properties: [
                    "cpu_temp_celsius": ["type": "number", "description": "CPU alert threshold °C"],
                    "fan_near_max_percent": ["type": "number"],
                    "enabled": ["type": "boolean"],
                ]
            ),
            tool(name: "get_about", description: "Product version and privacy statement."),
            tool(
                name: "check_version",
                description: "Compare local MasterFabric version to the open-source GitHub repo (releases/tags).",
                properties: [:]
            ),
            tool(
                name: "run_update",
                description: "Upgrade MasterFabric from the open-source GitHub install script. Returns JSON with performed/check/detail.",
                properties: [
                    "force": [
                        "type": "boolean",
                        "description": "Reinstall even when already up to date",
                    ],
                ]
            ),
            tool(
                name: "notify_send",
                description: "Send a message via Slack, Telegram, and/or mail integrations.",
                properties: [
                    "message": ["type": "string", "description": "Message body"],
                    "channel": [
                        "type": "string",
                        "description": "slack | telegram | mail | all",
                    ],
                ]
            ),
            tool(name: "notify_status", description: "Show Slack/Telegram/mail integration status."),
        ]
    }

    private func tool(
        name: String,
        description: String,
        properties: [String: [String: Any]] = [:]
    ) -> [String: Any] {
        [
            "name": name,
            "description": description,
            "inputSchema": [
                "type": "object",
                "properties": properties,
                "additionalProperties": false,
            ],
        ]
    }

    private func callTool(_ name: String, arguments: [String: Any]) throws -> String {
        switch name {
        case "get_info":
            return try JSONOutput.string(SystemInfoService.current())
        case "get_status":
            HistoryStore.record()
            return try JSONOutput.string(StatusService.current())
        case "get_temp":
            return try JSONOutput.string(ThermalService.read())
        case "get_fan":
            return try JSONOutput.string(FanService.read())
        case "set_fan_mode":
            let raw = (arguments["mode"] as? String ?? "").lowercased()
            guard let mode = FanControlMode(rawValue: raw) else {
                throw NSError(
                    domain: "MasterFabricMCP",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "mode must be auto or full"]
                )
            }
            return try JSONOutput.string(FanService.setMode(mode))
        case "get_battery":
            return try JSONOutput.string(BatteryService.current())
        case "get_memory":
            return try JSONOutput.string(MemoryService.current())
        case "get_disk":
            return try JSONOutput.string(DiskService.current())
        case "get_network":
            _ = NetworkService.current()
            Thread.sleep(forTimeInterval: 0.35)
            return try JSONOutput.string(NetworkService.current())
        case "get_cpu_load":
            _ = CPULoadService.current()
            Thread.sleep(forTimeInterval: 0.3)
            return try JSONOutput.string(CPULoadService.current())
        case "get_power":
            return try JSONOutput.string(PowerService.current())
        case "get_top":
            return try JSONOutput.string(ProcessService.top(limit: 10))
        case "get_history":
            HistoryStore.record()
            return try JSONOutput.string(HistoryStore.snapshot())
        case "set_alert_threshold":
            var c = ConfigStore.load()
            if let v = arguments["cpu_temp_celsius"] as? Double { c.alerts.cpuTempCelsius = v }
            if let v = arguments["cpu_temp_celsius"] as? Int { c.alerts.cpuTempCelsius = Double(v) }
            if let v = arguments["gpu_temp_celsius"] as? Double { c.alerts.gpuTempCelsius = v }
            if let v = arguments["gpu_temp_celsius"] as? Int { c.alerts.gpuTempCelsius = Double(v) }
            if let v = arguments["fan_near_max_percent"] as? Double { c.alerts.fanNearMaxPercent = v }
            if let v = arguments["fan_near_max_percent"] as? Int { c.alerts.fanNearMaxPercent = Double(v) }
            if let v = arguments["disk_used_percent_max"] as? Double { c.alerts.diskUsedPercentMax = v }
            if let v = arguments["disk_used_percent_max"] as? Int { c.alerts.diskUsedPercentMax = Double(v) }
            if let v = arguments["battery_percent_min"] as? Double { c.alerts.batteryPercentMin = v }
            if let v = arguments["battery_percent_min"] as? Int { c.alerts.batteryPercentMin = Double(v) }
            if let v = arguments["enabled"] as? Bool { c.alerts.enabled = v }
            if let v = arguments["notify_integrations"] as? Bool { c.alerts.notifyIntegrations = v }
            if let v = arguments["notify_local"] as? Bool { c.alerts.notifyLocal = v }
            try ConfigStore.save(c)
            return try JSONOutput.string(c)
        case "get_about":
            return AboutInfo.text()
        case "check_version":
            return try JSONOutput.string(VersionService.check())
        case "run_update":
            let force = arguments["force"] as? Bool ?? false
            return try JSONOutput.string(UpdateService.update(force: force))
        case "notify_status":
            return try JSONOutput.string(ConfigStore.load().integrations)
        case "notify_send":
            let message = arguments["message"] as? String ?? ""
            let channelRaw = (arguments["channel"] as? String ?? "all").lowercased()
            let channel = NotifyChannel(rawValue: channelRaw) ?? .all
            let results = IntegrationNotifier.send(message, channel: channel)
            return try JSONOutput.string(results)
        default:
            throw NSError(
                domain: "MasterFabricMCP",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unknown tool: \(name)"]
            )
        }
    }

    private func respond(id: Any?, result: [String: Any]) {
        var payload: [String: Any] = ["jsonrpc": "2.0", "result": result]
        if let id { payload["id"] = id }
        write(payload)
    }

    private func respondError(id: Any?, code: Int, message: String) {
        var payload: [String: Any] = [
            "jsonrpc": "2.0",
            "error": ["code": code, "message": message],
        ]
        if let id { payload["id"] = id }
        write(payload)
    }

    private func write(_ payload: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [])
        else { return }
        let header = Data("Content-Length: \(data.count)\r\n\r\n".utf8)
        FileHandle.standardOutput.write(header)
        FileHandle.standardOutput.write(data)
    }
}
