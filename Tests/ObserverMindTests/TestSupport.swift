import Foundation
@testable import ObserverMind

func fixture(_ name: String) throws -> String {
    let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
    let resource = parts.first ?? name
    let ext = parts.count > 1 ? parts[1] : nil
    guard let url = Bundle.module.url(forResource: resource, withExtension: ext, subdirectory: "Fixtures") else {
        throw NSError(domain: "FixtureError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing fixture: \(name)"])
    }
    return try String(contentsOf: url, encoding: .utf8)
}

struct StubCommandRunner: CommandRunning {
    var results: [String: [CommandResult]]
    private var defaultResult = CommandResult(stdout: "", stderr: "", exitCode: 0)

    init(results: [String: [CommandResult]]) {
        self.results = results
    }

    mutating func dequeue(_ key: String) -> CommandResult {
        var queue = results[key] ?? []
        guard queue.isEmpty == false else { return defaultResult }
        let next = queue.removeFirst()
        results[key] = queue
        return next
    }

    func run(_ executable: String, arguments: [String]) throws -> CommandResult {
        let key = ([executable] + arguments).joined(separator: " ")
        return results[key]?.first ?? defaultResult
    }
}

func makeSample(
    timestamp: Date = .now,
    cpu: Double = 20,
    freePercent: Double = 40,
    swapOutBytes: Int64 = 0,
    diskMBPerSec: Double = 10,
    batteryPercentage: Double = 80,
    batteryState: String = "discharging",
    thermalState: String = "Nominal"
) -> SampleEnvelope {
    SampleEnvelope(
        timestamp: timestamp,
        host: HostSnapshot(
            modelName: "MacBook Pro",
            modelIdentifier: "Mac15,9",
            chip: "Apple M3 Max",
            cpuCoreCount: 16,
            memoryBytes: 128 * 1_024 * 1_024 * 1_024,
            osVersion: "26.4",
            architecture: "arm64",
            gpuModel: "Apple M3 Max",
            gpuCoreCount: 40
        ),
        capabilities: CapabilitySnapshot(
            isRoot: false,
            powermetricsAvailable: true,
            advancedPowerAvailable: false,
            relaunchHint: "Run `sudo observer dashboard` for power, GPU, and per-process energy metrics."
        ),
        cpu: CPUSnapshot(
            userPercent: cpu * 0.6,
            systemPercent: cpu * 0.4,
            idlePercent: 100 - cpu,
            loadAverage1m: 4.5,
            loadAverage5m: 4.2,
            loadAverage15m: 3.9,
            packagePowerWatts: nil
        ),
        memory: MemorySnapshot(
            totalBytes: 128 * 1_024 * 1_024 * 1_024,
            usedBytes: 100 * 1_024 * 1_024 * 1_024,
            freeBytes: 28 * 1_024 * 1_024 * 1_024,
            wiredBytes: 12 * 1_024 * 1_024 * 1_024,
            compressedBytes: 2 * 1_024 * 1_024 * 1_024,
            freePercent: freePercent,
            swapInBytes: 0,
            swapOutBytes: swapOutBytes
        ),
        disk: DiskSnapshot(readMBPerSec: diskMBPerSec / 2, writeMBPerSec: diskMBPerSec / 2, totalMBPerSec: diskMBPerSec),
        network: NetworkSnapshot(
            totalBytesIn: 10_000,
            totalBytesOut: 5_000,
            totalInRateBytesPerSec: 1_000,
            totalOutRateBytesPerSec: 500,
            processes: []
        ),
        battery: BatterySnapshot(
            powerSource: "Battery Power",
            percentage: batteryPercentage,
            state: batteryState,
            timeRemaining: "2:00 remaining"
        ),
        thermal: ThermalSnapshot(state: thermalState, details: []),
        gpu: GPUSnapshot(
            model: "Apple M3 Max",
            coreCount: 40,
            powerWatts: nil,
            anePowerWatts: nil,
            processMetricsLocked: true,
            lockReason: "Run `sudo observer dashboard` for power, GPU, and per-process energy metrics."
        ),
        processes: [],
        alerts: []
    )
}
