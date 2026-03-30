import ArgumentParser
import Foundation

public struct ObserverCLI: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "observer",
        abstract: "CLI-based monitoring cockpit for Apple Silicon Macs.",
        version: ObserverVersion.current,
        subcommands: [
            DashboardCommand.self,
            SnapshotCommand.self,
            StreamCommand.self
        ]
    )

    public init() {}
}

extension DashboardTheme: ExpressibleByArgument {}

enum SnapshotFormat: String, ExpressibleByArgument {
    case table
    case json
}

enum StreamFormat: String, ExpressibleByArgument {
    case jsonl
}

public struct DashboardCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "dashboard",
        abstract: "Run the full-screen ObserverMind dashboard."
    )

    @Option(name: .long, help: "Sampling interval in seconds.")
    var interval: Int = 1

    @Option(name: .long, help: "Dashboard theme.")
    var theme: DashboardTheme?

    public init() {}

    public mutating func run() throws {
        let config = AppConfigLoader.load()
        let sampler = try SystemSampler(config: config)
        let resolvedTheme = theme ?? config.theme ?? .auto
        let app = DashboardApp(sampler: sampler, intervalSeconds: validInterval(interval), theme: resolvedTheme)
        try app.run()
    }
}

public struct SnapshotCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "snapshot",
        abstract: "Capture one normalized ObserverMind sample."
    )

    @Option(name: .long, help: "Output format.")
    var format: SnapshotFormat = .table

    public init() {}

    public mutating func run() throws {
        let sampler = try SystemSampler(config: AppConfigLoader.load())
        let sample = try sampler.collectSample(previous: nil, intervalSeconds: 1)

        switch format {
        case .table:
            print(renderSnapshotTable(sample))
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(sample)
            print(String(decoding: data, as: UTF8.self))
        }
    }
}

public struct StreamCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "stream",
        abstract: "Stream normalized samples as JSON lines."
    )

    @Option(name: .long, help: "Sampling interval in seconds.")
    var interval: Int = 1

    @Option(name: .long, help: "Optional duration in seconds.")
    var duration: Int?

    @Option(name: .long, help: "Output format.")
    var format: StreamFormat = .jsonl

    public init() {}

    public mutating func run() throws {
        let resolvedInterval = validInterval(interval)
        let sampler = try SystemSampler(config: AppConfigLoader.load())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let start = Date()
        var previous: SampleEnvelope?

        while duration.map({ Date().timeIntervalSince(start) < Double($0) }) ?? true {
            let line = try autoreleasepool { () -> Result<String, Error> in
                Result {
                    let sample = try sampler.collectSample(previous: previous, intervalSeconds: resolvedInterval)
                    previous = sample
                    let data = try encoder.encode(sample)
                    return String(decoding: data, as: UTF8.self)
                }
            }.get()
            print(line)
            fflush(stdout)
            Thread.sleep(forTimeInterval: Double(resolvedInterval))
        }
    }
}

private func validInterval(_ rawValue: Int) -> Int {
    switch rawValue {
    case 2, 5:
        return rawValue
    default:
        return 1
    }
}

func renderSnapshotTable(_ sample: SampleEnvelope) -> String {
    let topProcesses = sample.processes.sorted(by: .cpu).prefix(8)
    var lines: [String] = []
    lines.append("ObserverMind snapshot")
    lines.append("Timestamp: \(ISO8601DateFormatter().string(from: sample.timestamp))")
    lines.append("Host: \(sample.host.modelName) / \(sample.host.chip) / macOS \(sample.host.osVersion)")
    lines.append("CPU: \(String(format: "%.1f", sample.totalCPUPercent))% total | load \(String(format: "%.2f", sample.cpu.loadAverage1m))/\(String(format: "%.2f", sample.cpu.loadAverage5m))/\(String(format: "%.2f", sample.cpu.loadAverage15m))")
    lines.append("Memory: used \(renderByteCount(sample.memory.usedBytes)) / total \(renderByteCount(sample.memory.totalBytes)) | free \(renderByteCount(sample.memory.freeBytes)) (\(renderPercent(sample.memory.freePercent)))")
    lines.append("Disk: \(String(format: "%.1f", sample.disk.totalMBPerSec)) MB/s total")
    lines.append("Network: in \(renderByteCount(sample.network.totalBytesIn)) @ \(renderByteRate(sample.network.totalInRateBytesPerSec)) | out \(renderByteCount(sample.network.totalBytesOut)) @ \(renderByteRate(sample.network.totalOutRateBytesPerSec))")
    lines.append("Battery: \(renderPercent(sample.battery.percentage)) | \(sample.battery.state) | \(sample.battery.timeRemaining ?? "n/a")")
    lines.append("Thermal: \(sample.thermal.state)")
    lines.append("GPU: \(sample.gpu.model ?? "Unknown") | power \(sample.gpu.powerWatts.map { String(format: "%.2f W", $0) } ?? "n/a")")
    lines.append("")
    lines.append("Top processes")
    lines.append("PID    CPU%   MEM    Net/s   CMD")

    for process in topProcesses {
        let rate = (process.networkInRateBytesPerSec ?? 0) + (process.networkOutRateBytesPerSec ?? 0)
        lines.append(
            "\(padField("\(process.pid)", 6)) \(padField(String(format: "%.1f", process.cpuPercent ?? 0), 6)) \(padField(renderByteCount(process.memoryBytes), 6)) \(padField(renderByteRate(rate), 7)) \(process.command)"
        )
    }

    lines.append("")
    lines.append("Alerts")
    for alert in sample.alerts {
        lines.append("- [\(alert.level.rawValue)] \(alert.message)")
    }
    return lines.joined(separator: "\n")
}

private func renderByteCount(_ value: Int64?) -> String {
    guard let value else { return "n/a" }
    let units = ["B", "K", "M", "G", "T"]
    var current = Double(value)
    var index = 0
    while current >= 1024, index < units.count - 1 {
        current /= 1024
        index += 1
    }
    return current >= 10 ? String(format: "%.0f%@", current, units[index]) : String(format: "%.1f%@", current, units[index])
}

private func renderByteRate(_ value: Double?) -> String {
    guard let value else { return "n/a" }
    return "\(renderByteCount(Int64(value)))/s"
}

private func renderPercent(_ value: Double?) -> String {
    guard let value else { return "n/a" }
    return String(format: "%.1f%%", value)
}

private func padField(_ value: String, _ width: Int) -> String {
    if value.count >= width {
        return String(value.prefix(width))
    }
    return value + String(repeating: " ", count: width - value.count)
}
