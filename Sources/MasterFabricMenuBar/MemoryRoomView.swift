import SwiftUI
import MasterFabricCore

@MainActor
final class MemoryRoomFormState: ObservableObject {
    @Published var confirmPID: Int32 = 0
    @Published var confirmMakeRoom = false
}

/// RAM usage plus one-at-a-time quit, so a model has memory it can allocate.
struct MemoryRoomView: View {
    @ObservedObject var model: MenuBarModel
    @StateObject private var form = MemoryRoomFormState()

    var body: some View {
        let room = model.memoryRoom
        let memory = room.memory
        VStack(alignment: .leading, spacing: 8) {
            header
            Text("Room for a model")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(TextFormat.bytes(room.availableBytes))
                .font(.title2.monospacedDigit().weight(.semibold))
                .foregroundStyle(roomColor(memory.pressure))
            Text(usageLine(memory))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            usageBar(percent: memory.usedPercent, pressure: memory.pressure)
            targetRow(available: room.availableBytes)
            makeRoomButton(available: room.availableBytes)
            MemoryTrendChart(
                samples: model.memoryTrend,
                targetBytes: MemoryRoomService.targetBytes(gigabytes: model.displayConfig.modelRoomTargetGB)
            )
            HStack {
                Text("60s ago")
                Spacer()
                Text(trendCaption)
                Spacer()
                Text("now")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            Text(detailLine(memory, quittable: room.quittableBytes))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Make N GB asks before it quits eligible apps, one at a time, until that much is allocatable. Cursor and this menu bar stay.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            if room.consumers.isEmpty {
                Text("Reading processes…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(room.consumers, id: \.pid) { consumer in
                    consumerRow(consumer)
                }
            }

            if !model.memoryRoomMessage.isEmpty {
                Text(model.memoryRoomMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var header: some View {
        HStack {
            Button {
                form.confirmPID = 0
                form.confirmMakeRoom = false
                model.closeMemoryRoom()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderless)
            Text("RAM")
                .font(.headline)
            Spacer()
            Button {
                model.refreshMemoryRoom()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .disabled(model.releasingPID != 0)
            .help("Refresh RAM")
        }
    }

    private func consumerRow(_ consumer: MemoryConsumer) -> some View {
        let confirming = form.confirmPID == consumer.pid
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(consumer.name)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("\(consumer.note) · \(consumer.pid)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Text(TextFormat.bytes(consumer.memoryBytes))
                    .font(.caption.monospacedDigit())
                if consumer.releasable {
                    if confirming {
                        Button("Quit") {
                            form.confirmPID = 0
                            model.releaseMemory(pid: consumer.pid)
                        }
                        .buttonStyle(.borderless)
                        .font(.caption.weight(.semibold))
                        .disabled(model.releasingPID != 0 || model.isMakingRoom)
                    } else {
                        Button("Free") {
                            form.confirmPID = consumer.pid
                        }
                        .buttonStyle(.borderless)
                        .font(.caption.weight(.semibold))
                        .disabled(model.releasingPID != 0 || model.isMakingRoom)
                    }
                } else {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .help("Protected — left running")
                }
            }
            if confirming {
                Text("Quit \(consumer.name)? About \(TextFormat.bytes(consumer.memoryBytes)) can return for a model.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Cancel") { form.confirmPID = 0 }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    Spacer()
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func usageLine(_ memory: MemoryInfo) -> String {
        let percent = String(format: "%.0f%%", memory.usedPercent)
        return "\(TextFormat.bytes(memory.usedBytes)) / \(TextFormat.bytes(memory.totalBytes)) · \(percent) · \(memory.pressure)"
    }

    private func detailLine(_ memory: MemoryInfo, quittable: UInt64) -> String {
        let wired = TextFormat.bytes(memory.wiredBytes)
        let compressed = TextFormat.bytes(memory.compressedBytes)
        let swap = TextFormat.bytes(memory.swapUsedBytes)
        let listed = TextFormat.bytes(quittable)
        return "Wired \(wired) · Compressed \(compressed) · Swap \(swap) · Quittable apps \(listed). Room is what a model can allocate; macOS reclaims cached memory first."
    }

    private func usageBar(percent: Double, pressure: String) -> some View {
        let fraction = CGFloat(min(max(percent / 100, 0), 1))
        return Capsule()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 8)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule()
                        .fill(roomColor(pressure))
                        .frame(width: max(4, geo.size.width * fraction))
                }
            }
    }

    private func makeRoomButton(available: UInt64) -> some View {
        let gigabytes = Int(model.displayConfig.modelRoomTargetGB.rounded())
        let target = MemoryRoomService.targetBytes(gigabytes: model.displayConfig.modelRoomTargetGB)
        let ready = available >= target && !model.isMakingRoom
        return VStack(alignment: .leading, spacing: 6) {
            if form.confirmMakeRoom, !model.isMakingRoom {
                Text("Free RAM until \(gigabytes) GB is allocatable?")
                    .font(.caption.weight(.semibold))
                Text("This quits the largest eligible apps one at a time. Cursor and this menu bar stay open. Unsaved work in those apps can be lost.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Cancel") { form.confirmMakeRoom = false }
                        .buttonStyle(.borderless)
                    Spacer()
                    Button("Free RAM") {
                        form.confirmMakeRoom = false
                        model.toggleMakeRoom()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            } else {
                Button {
                    if model.isMakingRoom {
                        model.toggleMakeRoom()
                    } else {
                        form.confirmMakeRoom = true
                    }
                } label: {
                    Text(model.isMakingRoom ? "Stop" : (ready ? "Room ready" : "Make \(gigabytes) GB"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(ready)
                .help("Ask before quitting the largest apps until the target RAM is free")
            }
        }
    }

    private func targetRow(available: UInt64) -> some View {
        let targetGB = model.displayConfig.modelRoomTargetGB
        let target = MemoryRoomService.targetBytes(gigabytes: targetGB)
        let gap: String
        if available >= target {
            gap = "reached"
        } else {
            gap = "need \(TextFormat.bytes(target - available)) more"
        }
        return HStack(spacing: 8) {
            Text("Target")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("−") { model.setModelRoomTargetGB(targetGB - 1) }
                .buttonStyle(.borderless)
                .font(.caption.weight(.semibold))
            Text("\(Int(targetGB.rounded())) GB")
                .font(.caption.monospacedDigit().weight(.semibold))
            Button("+") { model.setModelRoomTargetGB(targetGB + 1) }
                .buttonStyle(.borderless)
                .font(.caption.weight(.semibold))
            Spacer(minLength: 4)
            Text(gap)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var trendCaption: String {
        let samples = model.memoryTrend
        guard let first = samples.first, let last = samples.last, samples.count >= 2 else {
            return "collecting"
        }
        let delta = Int64(last.availableBytes) - Int64(first.availableBytes)
        let sign = delta >= 0 ? "+" : "−"
        return "\(sign)\(TextFormat.bytes(UInt64(abs(delta)))) room"
    }

    private func roomColor(_ pressure: String) -> Color {
        switch pressure {
        case "high": return .orange
        case "medium": return .yellow
        default: return .green
        }
    }
}

/// Allocatable RAM over the last 60 seconds, with the model target as a dashed line.
struct MemoryTrendChart: View {
    var samples: [MemoryTrendSample]
    var targetBytes: UInt64

    var body: some View {
        Canvas { context, size in
            let width = size.width
            let height = size.height
            let now = Date()
            let start = now.addingTimeInterval(-MemoryTrendStore.window)
            let peak = samples.map { Double($0.availableBytes) }.max() ?? 0
            let maxY = max(Double(targetBytes), peak, 1)

            func xPosition(_ date: Date) -> CGFloat {
                let fraction = date.timeIntervalSince(start) / MemoryTrendStore.window
                return CGFloat(min(max(fraction, 0), 1)) * width
            }
            func yPosition(_ bytes: Double) -> CGFloat {
                let fraction = bytes / maxY
                return height * (1 - CGFloat(fraction))
            }

            var target = Path()
            let targetY = yPosition(Double(targetBytes))
            target.move(to: CGPoint(x: 0, y: targetY))
            target.addLine(to: CGPoint(x: width, y: targetY))
            context.stroke(
                target,
                with: .color(Color.orange.opacity(0.9)),
                style: StrokeStyle(lineWidth: 1, dash: [4, 3])
            )

            guard let first = samples.first else { return }
            if samples.count == 1 {
                let dot = CGRect(
                    x: xPosition(first.timestamp) - 2.5,
                    y: yPosition(Double(first.availableBytes)) - 2.5,
                    width: 5,
                    height: 5
                )
                context.fill(Path(ellipseIn: dot), with: .color(Color.green))
                return
            }

            var line = Path()
            var fill = Path()
            fill.move(to: CGPoint(x: xPosition(first.timestamp), y: height))
            for (index, sample) in samples.enumerated() {
                let point = CGPoint(
                    x: xPosition(sample.timestamp),
                    y: yPosition(Double(sample.availableBytes))
                )
                if index == 0 {
                    line.move(to: point)
                    fill.addLine(to: point)
                } else {
                    line.addLine(to: point)
                    fill.addLine(to: point)
                }
            }
            if let last = samples.last {
                fill.addLine(to: CGPoint(x: xPosition(last.timestamp), y: height))
            }
            fill.closeSubpath()
            context.fill(fill, with: .color(Color.green.opacity(0.18)))
            context.stroke(line, with: .color(Color.green), lineWidth: 1.5)
        }
        .frame(height: 76)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.04))
        )
    }
}
