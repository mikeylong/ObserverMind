import Foundation

enum RuntimeGuard {
    static func ensureSupportedHost() throws {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        guard os.majorVersion >= 26 else {
            throw RuntimeError("ObserverMind v1 targets macOS 26 or newer.")
        }

        let architecture = ProcessInfo.processInfo.environment["PROCESSOR_ARCHITECTURE"] ?? ""
        if architecture.isEmpty == false, architecture.contains("arm64") == false {
            throw RuntimeError("ObserverMind v1 targets Apple Silicon only.")
        }
    }
}

struct RuntimeError: Error, LocalizedError {
    var message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

final class SystemSampler: @unchecked Sendable {
    private let runner: CommandRunning
    private let config: AppConfig
    private let host: HostSnapshot

    init(runner: CommandRunning = ProcessCommandRunner(), config: AppConfig = AppConfigLoader.load()) throws {
        self.runner = runner
        self.config = config
        try RuntimeGuard.ensureSupportedHost()

        let osVersion = (try? runner.run("/usr/bin/sw_vers", arguments: ["-productVersion"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? "Unknown"
        let architecture = (try? runner.run("/usr/bin/uname", arguments: ["-m"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? "arm64"
        let profilerText = (try? runner.run("/usr/sbin/system_profiler", arguments: ["SPHardwareDataType", "SPDisplaysDataType"]).stdout) ?? ""
        self.host = Parser.parseHostSnapshot(hardwareText: profilerText, osVersion: osVersion, architecture: architecture)
    }

    func collectSample(previous: SampleEnvelope?, intervalSeconds: Int) throws -> SampleEnvelope {
        let capabilities = CapabilityDetector.snapshot()
        let topText = try runner.run("/usr/bin/top", arguments: ["-l", "1", "-n", "12", "-o", "cpu", "-stats", "pid,command,cpu,mem,time"]).stdout
        let vmStatText = try runner.run("/usr/bin/vm_stat", arguments: []).stdout
        let memoryPressureText = try runner.run("/usr/bin/memory_pressure", arguments: []).stdout
        let iostatText = try runner.run("/usr/sbin/iostat", arguments: ["-w", "1", "-c", "1"]).stdout
        let nettopText = try runner.run("/usr/bin/nettop", arguments: ["-P", "-L", "1", "-x", "-n", "-J", "bytes_in,bytes_out", "-k", "state"]).stdout
        let batteryText = try runner.run("/usr/bin/pmset", arguments: ["-g", "batt"]).stdout
        let thermalText = try runner.run("/usr/bin/pmset", arguments: ["-g", "therm"]).stdout

        let powerText: String?
        if capabilities.advancedPowerAvailable {
            powerText = try? runner.run(
                "/usr/bin/powermetrics",
                arguments: ["-n", "1", "--samplers", "tasks,cpu_power,gpu_power,ane_power,thermal", "--show-process-gpu", "--show-process-energy"]
            ).stdout
        } else {
            powerText = nil
        }

        let top = Parser.parseTop(topText)
        let vmStat = Parser.parseVMStat(vmStatText)
        let memoryPressure = Parser.parseMemoryPressure(memoryPressureText)
        let iostat = Parser.parseIostat(iostatText)
        let networkProcesses = Parser.parseNettop(nettopText)
        let battery = Parser.parseBattery(batteryText)
        let thermal = Parser.parseThermal(thermalText)
        let power = powerText.map(Parser.parsePowermetrics) ?? .empty

        let memory = buildMemorySnapshot(
            host: host,
            top: top,
            vmStat: vmStat,
            memoryPressure: memoryPressure
        )
        let network = buildNetworkSnapshot(
            processes: networkProcesses,
            previous: previous?.network,
            intervalSeconds: intervalSeconds
        )
        let processes = mergeProcesses(
            topProcesses: top.processes,
            networkProcesses: network.processes,
            powerMetrics: power.perProcessMetrics
        )
        let thermalState = power.thermalState ?? thermal.state
        let gpu = GPUSnapshot(
            model: host.gpuModel,
            coreCount: host.gpuCoreCount,
            powerWatts: power.gpuPowerWatts,
            anePowerWatts: power.anePowerWatts,
            processMetricsLocked: capabilities.advancedPowerAvailable == false,
            lockReason: capabilities.advancedPowerAvailable ? nil : capabilities.relaunchHint
        )

        var sample = SampleEnvelope(
            timestamp: Date(),
            host: host,
            capabilities: capabilities,
            cpu: CPUSnapshot(
                userPercent: top.cpu.userPercent,
                systemPercent: top.cpu.systemPercent,
                idlePercent: top.cpu.idlePercent,
                loadAverage1m: top.cpu.loadAverage1m,
                loadAverage5m: top.cpu.loadAverage5m,
                loadAverage15m: top.cpu.loadAverage15m,
                packagePowerWatts: power.cpuPowerWatts
            ),
            memory: memory,
            disk: DiskSnapshot(
                readMBPerSec: iostat.readMBPerSec,
                writeMBPerSec: iostat.writeMBPerSec,
                totalMBPerSec: iostat.readMBPerSec + iostat.writeMBPerSec
            ),
            network: network,
            battery: BatterySnapshot(
                powerSource: battery.powerSource,
                percentage: battery.percentage,
                state: battery.state,
                timeRemaining: battery.timeRemaining
            ),
            thermal: ThermalSnapshot(
                state: thermalState,
                details: thermal.details
            ),
            gpu: gpu,
            processes: processes.sorted(by: .cpu),
            alerts: []
        )

        sample.alerts = evaluateAlerts(current: sample, previous: previous, thresholds: config.thresholds)
        return sample
    }
}

private func buildMemorySnapshot(
    host: HostSnapshot,
    top: TopParseResult,
    vmStat: VMStatParseResult,
    memoryPressure: MemoryPressureParseResult
) -> MemorySnapshot {
    let pageBytes = vmStat.pageSize
    let freeBytes = vmStat.pagesFree.map { $0 * pageBytes } ?? top.physMemUnusedBytes
    let wiredBytes = vmStat.pagesWired.map { $0 * pageBytes } ?? top.physMemWiredBytes
    let compressedBytes = vmStat.pagesCompressed.map { $0 * pageBytes } ?? top.physMemCompressedBytes
    let totalBytes = host.memoryBytes
    let usedBytes = top.physMemUsedBytes ?? {
        guard let totalBytes, let freeBytes else { return nil }
        return max(totalBytes - freeBytes, 0)
    }()
    let freePercent = {
        guard let totalBytes, let freeBytes, totalBytes > 0 else { return nil }
        return Double(freeBytes) * 100 / Double(totalBytes)
    }() ?? memoryPressure.freePercent

    return MemorySnapshot(
        totalBytes: totalBytes,
        usedBytes: usedBytes,
        freeBytes: freeBytes,
        wiredBytes: wiredBytes,
        compressedBytes: compressedBytes,
        freePercent: freePercent,
        swapInBytes: vmStat.swapins.map { $0 * pageBytes },
        swapOutBytes: vmStat.swapouts.map { $0 * pageBytes }
    )
}

private func buildNetworkSnapshot(
    processes: [NetworkProcessSnapshot],
    previous: NetworkSnapshot?,
    intervalSeconds: Int
) -> NetworkSnapshot {
    let previousMap = Dictionary(uniqueKeysWithValues: (previous?.processes ?? []).map { (($0.pid ?? -1), $0) })
    let interval = max(Double(intervalSeconds), 1)
    let updated = processes.map { process -> NetworkProcessSnapshot in
        let previousProcess = previousMap[process.pid ?? -1]
        let inRate = previousProcess.map { max(Double(process.bytesIn - $0.bytesIn), 0) / interval }
        let outRate = previousProcess.map { max(Double(process.bytesOut - $0.bytesOut), 0) / interval }
        return NetworkProcessSnapshot(
            pid: process.pid,
            command: process.command,
            bytesIn: process.bytesIn,
            bytesOut: process.bytesOut,
            inRateBytesPerSec: inRate,
            outRateBytesPerSec: outRate
        )
    }

    let totalIn = updated.reduce(into: Int64(0)) { $0 += $1.bytesIn }
    let totalOut = updated.reduce(into: Int64(0)) { $0 += $1.bytesOut }
    let previousIn = previous?.totalBytesIn ?? totalIn
    let previousOut = previous?.totalBytesOut ?? totalOut

    return NetworkSnapshot(
        totalBytesIn: totalIn,
        totalBytesOut: totalOut,
        totalInRateBytesPerSec: max(Double(totalIn - previousIn), 0) / interval,
        totalOutRateBytesPerSec: max(Double(totalOut - previousOut), 0) / interval,
        processes: updated
    )
}

private func mergeProcesses(
    topProcesses: [ProcessSnapshot],
    networkProcesses: [NetworkProcessSnapshot],
    powerMetrics: [Int: (energy: Double?, gpuTime: Double?)]
) -> [ProcessSnapshot] {
    var merged = Dictionary(uniqueKeysWithValues: topProcesses.map { ($0.pid, $0) })

    for networkProcess in networkProcesses {
        if let pid = networkProcess.pid {
            if merged[pid] == nil {
                merged[pid] = ProcessSnapshot(
                    pid: pid,
                    command: networkProcess.command,
                    cpuPercent: nil,
                    memoryBytes: nil,
                    cumulativeCPUTime: nil,
                    networkBytesIn: nil,
                    networkBytesOut: nil,
                    networkInRateBytesPerSec: nil,
                    networkOutRateBytesPerSec: nil,
                    energyImpact: nil,
                    gpuTime: nil
                )
            }
            merged[pid]?.networkBytesIn = networkProcess.bytesIn
            merged[pid]?.networkBytesOut = networkProcess.bytesOut
            merged[pid]?.networkInRateBytesPerSec = networkProcess.inRateBytesPerSec
            merged[pid]?.networkOutRateBytesPerSec = networkProcess.outRateBytesPerSec
        }
    }

    for (pid, metrics) in powerMetrics {
        if merged[pid] == nil {
            merged[pid] = ProcessSnapshot(
                pid: pid,
                command: "pid-\(pid)",
                cpuPercent: nil,
                memoryBytes: nil,
                cumulativeCPUTime: nil,
                networkBytesIn: nil,
                networkBytesOut: nil,
                networkInRateBytesPerSec: nil,
                networkOutRateBytesPerSec: nil,
                energyImpact: nil,
                gpuTime: nil
            )
        }
        merged[pid]?.energyImpact = metrics.energy
        merged[pid]?.gpuTime = metrics.gpuTime
    }

    return Array(merged.values)
}

func evaluateAlerts(
    current: SampleEnvelope,
    previous: SampleEnvelope?,
    thresholds: ThresholdConfig
) -> [Alert] {
    var alerts: [Alert] = []

    if current.totalCPUPercent >= thresholds.highCPUPercent {
        alerts.append(Alert(level: .warning, message: "CPU usage is above \(Int(thresholds.highCPUPercent))%."))
    }

    if let freePercent = current.memory.freePercent, freePercent <= thresholds.lowMemoryFreePercent {
        alerts.append(Alert(level: .critical, message: "Memory free percentage is down to \(String(format: "%.1f", freePercent))%."))
    }

    if let currentSwap = current.memory.swapOutBytes,
       let previousSwap = previous?.memory.swapOutBytes {
        let deltaMB = Double(max(currentSwap - previousSwap, 0)) / 1_048_576
        if deltaMB >= thresholds.highSwapGrowthMB {
            alerts.append(Alert(level: .warning, message: "Swap grew by \(String(format: "%.1f", deltaMB)) MB in the last sample."))
        }
    }

    if current.disk.totalMBPerSec >= thresholds.highDiskMBPerSec {
        alerts.append(Alert(level: .warning, message: "Disk throughput is \(String(format: "%.1f", current.disk.totalMBPerSec)) MB/s."))
    }

    if current.thermal.state.lowercased().contains("serious") || current.thermal.state.lowercased().contains("critical") {
        alerts.append(Alert(level: .critical, message: "Thermal pressure is \(current.thermal.state)."))
    }

    if current.battery.state == "discharging",
       let currentPercent = current.battery.percentage,
       let previousPercent = previous?.battery.percentage,
       previousPercent > currentPercent {
        let elapsedHours = max(current.timestamp.timeIntervalSince(previous?.timestamp ?? current.timestamp) / 3600, 1.0 / 3600)
        let drainRate = (previousPercent - currentPercent) / elapsedHours
        if drainRate >= thresholds.highBatteryDrainPercentPerHour {
            alerts.append(Alert(level: .warning, message: "Battery is draining at \(String(format: "%.1f", drainRate))% per hour."))
        }
    }

    if alerts.isEmpty {
        alerts.append(Alert(level: .info, message: "No active alerts."))
    }

    return alerts
}
