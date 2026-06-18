import AppKit
import Charts
import SwiftUI

struct MenuBarLabel: View {
    let monitor: SystemMonitor
    @State private var pulse = false

    var body: some View {
        Image(nsImage: statusImage(cpu: monitor.cpu, memory: monitor.memory))
            .renderingMode(.original)
        .opacity(monitor.overallLevel == .severe && pulse ? 0.58 : 1)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                pulse.toggle()
            }
        }
        .accessibilityLabel(
            "处理器 \(percent(monitor.cpu))，内存 \(percent(monitor.memory))"
        )
    }
}

private func statusImage(cpu: Double, memory: Double) -> NSImage {
    let image = NSImage(size: NSSize(width: 112, height: 18), flipped: true) { rect in
        let cpuColor = statusNSColor(cpu)
        let memoryColor = statusNSColor(memory)
        let textStyle: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)
        ]

        drawStatusText(percent(cpu), in: NSRect(x: 0, y: 2, width: 30, height: 14), color: .white, style: textStyle)
        drawStatusText(percent(memory), in: NSRect(x: 82, y: 2, width: 30, height: 14), color: .white, style: textStyle)

        let gaugeRect = NSRect(x: 34, y: 3, width: 44, height: 12)
        let outline = NSBezierPath(roundedRect: gaugeRect, xRadius: 6, yRadius: 6)
        NSColor.labelColor.withAlphaComponent(0.72).setStroke()
        outline.lineWidth = 1
        outline.stroke()

        let inner = gaugeRect.insetBy(dx: 2, dy: 2)
        let gap: CGFloat = 2
        let chamberWidth = (inner.width - gap) / 2
        drawChamber(
            NSRect(x: inner.minX, y: inner.minY, width: chamberWidth, height: inner.height),
            value: cpu,
            color: cpuColor,
            direction: .leftToRight
        )
        drawChamber(
            NSRect(x: inner.minX + chamberWidth + gap, y: inner.minY, width: chamberWidth, height: inner.height),
            value: memory,
            color: memoryColor,
            direction: .rightToLeft
        )
        return true
    }
    image.isTemplate = false
    return image
}

private func drawStatusText(
    _ text: String,
    in rect: NSRect,
    color: NSColor,
    style: [NSAttributedString.Key: Any]
) {
    var attributes = style
    attributes[.foregroundColor] = color
    let attributed = NSAttributedString(string: text, attributes: attributes)
    let size = attributed.size()
    attributed.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
}

private enum FillDirection {
    case leftToRight
    case rightToLeft
}

private func drawChamber(
    _ rect: NSRect,
    value: Double,
    color: NSColor,
    direction: FillDirection
) {
    let background = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
    NSColor.labelColor.withAlphaComponent(0.12).setFill()
    background.fill()

    let fillWidth = max(1.5, rect.width * CGFloat(min(max(value, 0), 1)))
    let fillX = direction == .leftToRight ? rect.minX : rect.maxX - fillWidth
    let fillRect = NSRect(x: fillX, y: rect.minY, width: fillWidth, height: rect.height)
    let fill = NSBezierPath(roundedRect: fillRect, xRadius: rect.height / 2, yRadius: rect.height / 2)
    color.setFill()
    fill.fill()
}

private func statusNSColor(_ value: Double) -> NSColor {
    switch UsageLevel(value) {
    case .normal: NSColor(red: 0.22, green: 0.88, blue: 0.38, alpha: 1)
    case .warning: .systemOrange
    case .critical: .systemRed
    case .severe: NSColor(red: 0.48, green: 0.0, blue: 0.03, alpha: 1)
    }
}

struct DualChamberGauge: View {
    let cpu: Double
    let memory: Double

    var body: some View {
        GeometryReader { proxy in
            let chamberWidth = (proxy.size.width - 5) / 2
            HStack(spacing: 3) {
                chamber(
                    value: cpu,
                    color: UsageLevel(cpu).color,
                    width: chamberWidth,
                    alignment: .leading
                )
                chamber(
                    value: memory,
                    color: UsageLevel(memory).color,
                    width: chamberWidth,
                    alignment: .trailing
                )
            }
            .padding(2)
            .background(.primary.opacity(0.08), in: Capsule())
            .overlay(Capsule().stroke(.primary.opacity(0.65), lineWidth: 1))
        }
    }

    private func chamber(
        value: Double,
        color: Color,
        width: CGFloat,
        alignment: Alignment
    ) -> some View {
        ZStack(alignment: alignment) {
            Capsule().fill(.primary.opacity(0.09))
            Capsule()
                .fill(color)
                .frame(width: max(1.5, width * min(max(value, 0), 1)))
                .animation(.smooth(duration: 0.45), value: value)
        }
    }
}

struct MonitorPopover: View {
    @Bindable var monitor: SystemMonitor

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            MetricSection(
                title: "处理器",
                systemImage: "cpu",
                value: monitor.cpu,
                color: UsageLevel(monitor.cpu).color,
                history: monitor.cpuHistory
            ) {
                HStack(spacing: 18) {
                    StatDot(label: "系统", value: percent(monitor.cpuSystem), color: .green)
                    StatDot(label: "用户", value: percent(monitor.cpuUser), color: UsageLevel(monitor.cpu).color)
                    StatDot(label: "空闲", value: percent(monitor.cpuIdle), color: .secondary)
                }
            }
            Divider()
            MetricSection(
                title: "内存",
                systemImage: "memorychip",
                value: monitor.memory,
                color: UsageLevel(monitor.memory).color,
                history: monitor.memoryHistory
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 14) {
                        StatDot(label: "已用", value: bytes(monitor.usedBytes), color: UsageLevel(monitor.memory).color)
                        StatDot(label: "活跃", value: bytes(monitor.activeBytes), color: .blue)
                        StatDot(label: "可用", value: bytes(monitor.availableBytes), color: .secondary)
                    }
                    HStack(spacing: 14) {
                        StatDot(label: "Wired", value: bytes(monitor.wiredBytes), color: .purple)
                        StatDot(label: "压缩", value: bytes(monitor.compressedBytes), color: .orange)
                        StatDot(label: "可清除", value: bytes(monitor.purgeableBytes), color: .green)
                    }
                    if monitor.swapTotalBytes > 0 {
                        HStack(spacing: 14) {
                            StatDot(label: "Swap", value: bytes(monitor.swapUsedBytes), color: monitor.swapUsedBytes > 0 ? .red : .secondary)
                            StatDot(label: "Swap 总量", value: bytes(monitor.swapTotalBytes), color: .secondary)
                            Spacer()
                        }
                    }
                }
            }
            Divider()
            MemoryAnalysisSection(monitor: monitor)
            Divider()
            settings
        }
        .frame(width: 420)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.green)
                .frame(width: 48, height: 48)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text("System Pulse")
                    .font(.title2.weight(.semibold))
                HStack(spacing: 4) {
                    Text("总体状态：")
                        .foregroundStyle(.secondary)
                    Text(monitor.statusText)
                        .foregroundStyle(monitor.overallLevel.color)
                }
                .font(.subheadline)
            }
            Spacer()
        }
        .padding(18)
    }

    private var settings: some View {
        VStack(spacing: 0) {
            SettingRow(icon: "arrow.clockwise", title: "刷新频率") {
                Picker("", selection: $monitor.refreshInterval) {
                    Text("1 秒").tag(1.0)
                    Text("2 秒").tag(2.0)
                    Text("5 秒").tag(5.0)
                }
                .labelsHidden()
                .frame(width: 92)
            }

            Divider().padding(.leading, 54)

            SettingRow(icon: "power", title: "开机自动启动") {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { monitor.launchAtLogin },
                        set: { monitor.setLaunchAtLogin($0) }
                    )
                )
                .labelsHidden()
            }

            if let error = monitor.launchAtLoginError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 56)
                    .padding(.bottom, 8)
            }

            Divider().padding(.leading, 54)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                SettingRow(icon: "power", title: "退出 System Pulse") {
                    Text("⌘ Q")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
    }
}

struct MetricSection<Details: View>: View {
    let title: String
    let systemImage: String
    let value: Double
    let color: Color
    let history: [Double]
    @ViewBuilder let details: Details

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(color)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(percent(value))
                        .font(.system(size: 34, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(color)
                        .contentTransition(.numericText())
                }
                .frame(width: 105, alignment: .leading)

                HistoryChart(values: history, color: color)
                    .frame(height: 72)
            }
            details
                .font(.caption)
                .padding(.leading, 46)
        }
        .padding(18)
    }
}

struct HistoryChart: View {
    let values: [Double]
    let color: Color

    var body: some View {
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                AreaMark(
                    x: .value("Sample", index),
                    y: .value("Usage", value)
                )
                .foregroundStyle(
                    .linearGradient(
                        colors: [color.opacity(0.24), color.opacity(0.01)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Sample", index),
                    y: .value("Usage", value)
                )
                .foregroundStyle(color)
                .lineStyle(.init(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }

            RuleMark(y: .value("警告", 0.80))
                .foregroundStyle(.orange.opacity(0.7))
                .lineStyle(.init(lineWidth: 1, dash: [3, 3]))

            RuleMark(y: .value("红色警告", 0.90))
                .foregroundStyle(.red.opacity(0.7))
                .lineStyle(.init(lineWidth: 1, dash: [3, 3]))

            RuleMark(y: .value("严重拥塞", 0.95))
                .foregroundStyle(Color(red: 0.55, green: 0.02, blue: 0.04).opacity(0.9))
                .lineStyle(.init(lineWidth: 1.5, dash: [2, 2]))
        }
        .chartXScale(domain: 0...59)
        .chartYScale(domain: 0...1)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }
}

struct StatDot: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .monospacedDigit()
        }
        .lineLimit(1)
        .minimumScaleFactor(0.72)
    }
}

struct SettingRow<Trailing: View>: View {
    let icon: String
    let title: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .frame(width: 24)
            Text(title)
            Spacer()
            trailing
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 18)
    }
}

struct MemoryAnalysisSection: View {
    @Bindable var monitor: SystemMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(monitor.memoryPressure.color)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text("内存分析")
                        .font(.headline)
                    HStack(spacing: 4) {
                        Image(systemName: monitor.memoryPressure.systemImage)
                            .foregroundStyle(monitor.memoryPressure.color)
                            .font(.caption)
                        Text(monitor.memoryPressure.label)
                            .foregroundStyle(monitor.memoryPressure.color)
                    }
                    .font(.subheadline)
                }
                Spacer()
            }

            // I/O rates
            HStack(spacing: 18) {
                StatDot(label: "Page-ins", value: "\(Int(monitor.pageinsPerSec))/s", color: monitor.pageinsPerSec > 100 ? .orange : .secondary)
                StatDot(label: "Swap-ins", value: "\(Int(monitor.swapinsPerSec))/s", color: monitor.swapinsPerSec > 10 ? .red : .secondary)
            }
            .font(.caption)
            .padding(.leading, 42)

            // Optimization tips
            if !monitor.optimizationTips.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("优化建议")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(Array(monitor.optimizationTips.enumerated()), id: \.offset) { _, tip in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "lightbulb.fill")
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                                .frame(width: 12)
                                .padding(.top, 2)
                            Text(tip)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.leading, 42)
            }

            // Top processes
            if !monitor.topProcesses.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("内存占用 Top \(monitor.topProcesses.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 42)

                    ForEach(monitor.topProcesses) { process in
                        ProcessRow(process: process, totalBytes: monitor.totalBytes)
                    }
                }
                .padding(.leading, 42)
            }
        }
        .padding(18)
    }
}

struct ProcessRow: View {
    let process: ProcessMemoryInfo
    let totalBytes: UInt64

    private var ratio: Double {
        totalBytes > 0 ? Double(process.residentBytes) / Double(totalBytes) : 0
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(process.name)
                .font(.caption.monospaced())
                .frame(width: 120, alignment: .leading)
                .lineLimit(1)

            Text("PID \(process.pid)")
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .frame(width: 52, alignment: .leading)

            Spacer()

            Text(bytes(process.residentBytes))
                .font(.caption.monospacedDigit())
                .foregroundStyle(UsageLevel(ratio).color)
                .frame(width: 62, alignment: .trailing)

            // Mini bar
            GeometryReader { proxy in
                Capsule()
                    .fill(UsageLevel(ratio).color.opacity(0.6))
                    .frame(width: max(2, proxy.size.width * min(ratio, 1)))
            }
            .frame(width: 40, height: 6)
        }
        .padding(.vertical, 2)
    }
}

@MainActor
private let byteFormatter: ByteCountFormatter = {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useGB, .useMB]
    formatter.countStyle = .memory
    formatter.includesUnit = true
    formatter.isAdaptive = true
    return formatter
}()

func percent(_ value: Double) -> String {
    "\(Int((value * 100).rounded()))%"
}

@MainActor
func bytes(_ value: UInt64) -> String {
    byteFormatter.string(fromByteCount: Int64(value))
}
