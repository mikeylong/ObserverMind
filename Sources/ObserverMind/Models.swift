import Foundation

public enum DashboardTheme: String, Codable, CaseIterable, Sendable {
    case auto
    case dark
    case light
}

enum DashboardView: String, CaseIterable, Sendable {
    case overview = "Overview"
    case processes = "Processes"
    case network = "Network"
    case power = "Power"
}

enum ProcessSortKey: String, CaseIterable, Sendable {
    case cpu = "CPU"
    case memory = "Memory"
    case energy = "Energy"
    case gpu = "GPU"
    case network = "Network"
}

enum AlertLevel: String, Codable, Sendable {
    case info
    case warning
    case critical
}

struct Alert: Codable, Sendable {
    var level: AlertLevel
    var message: String
}

struct CapabilitySnapshot: Codable, Sendable {
    var isRoot: Bool
    var powermetricsAvailable: Bool
    var advancedPowerAvailable: Bool
    var relaunchHint: String
}

struct HostSnapshot: Codable, Sendable {
    var modelName: String
    var modelIdentifier: String
    var chip: String
    var cpuCoreCount: Int?
    var memoryBytes: Int64?
    var osVersion: String
    var architecture: String
    var gpuModel: String?
    var gpuCoreCount: Int?
}

struct CPUSnapshot: Codable, Sendable {
    var userPercent: Double
    var systemPercent: Double
    var idlePercent: Double
    var loadAverage1m: Double
    var loadAverage5m: Double
    var loadAverage15m: Double
    var packagePowerWatts: Double?
}

struct MemorySnapshot: Codable, Sendable {
    var totalBytes: Int64?
    var usedBytes: Int64?
    var freeBytes: Int64?
    var wiredBytes: Int64?
    var compressedBytes: Int64?
    var freePercent: Double?
    var swapInBytes: Int64?
    var swapOutBytes: Int64?
}

struct DiskSnapshot: Codable, Sendable {
    var readMBPerSec: Double
    var writeMBPerSec: Double
    var totalMBPerSec: Double
}

struct NetworkProcessSnapshot: Codable, Sendable {
    var pid: Int?
    var command: String
    var bytesIn: Int64
    var bytesOut: Int64
    var inRateBytesPerSec: Double?
    var outRateBytesPerSec: Double?
}

struct NetworkSnapshot: Codable, Sendable {
    var totalBytesIn: Int64
    var totalBytesOut: Int64
    var totalInRateBytesPerSec: Double?
    var totalOutRateBytesPerSec: Double?
    var processes: [NetworkProcessSnapshot]
}

struct BatterySnapshot: Codable, Sendable {
    var powerSource: String
    var percentage: Double?
    var state: String
    var timeRemaining: String?
}

struct ThermalSnapshot: Codable, Sendable {
    var state: String
    var details: [String]
}

struct GPUSnapshot: Codable, Sendable {
    var model: String?
    var coreCount: Int?
    var powerWatts: Double?
    var anePowerWatts: Double?
    var processMetricsLocked: Bool
    var lockReason: String?
}

struct ProcessSnapshot: Codable, Sendable {
    var pid: Int
    var command: String
    var cpuPercent: Double?
    var memoryBytes: Int64?
    var cumulativeCPUTime: String?
    var networkBytesIn: Int64?
    var networkBytesOut: Int64?
    var networkInRateBytesPerSec: Double?
    var networkOutRateBytesPerSec: Double?
    var energyImpact: Double?
    var gpuTime: Double?
}

struct SampleEnvelope: Codable, Sendable {
    var timestamp: Date
    var host: HostSnapshot
    var capabilities: CapabilitySnapshot
    var cpu: CPUSnapshot
    var memory: MemorySnapshot
    var disk: DiskSnapshot
    var network: NetworkSnapshot
    var battery: BatterySnapshot
    var thermal: ThermalSnapshot
    var gpu: GPUSnapshot
    var processes: [ProcessSnapshot]
    var alerts: [Alert]
}

extension SampleEnvelope {
    var totalCPUPercent: Double {
        cpu.userPercent + cpu.systemPercent
    }
}

struct DashboardRenderState: Sendable {
    var view: DashboardView = .overview
    var processSort: ProcessSortKey = .cpu
    var selectionIndex = 0
    var processScrollOffset = 0
    var networkScrollOffset = 0
    var theme: DashboardTheme = .auto
}

struct DashboardResizeState: Sendable {
    var committedSize: TerminalSize?
    var pendingSize: TerminalSize?
    var liveSize: TerminalSize?
    var lastSizeChangeAt: Date?
    var isResizing = false
}

struct DashboardResizeUpdate: Sendable {
    var layoutSize: TerminalSize
    var viewportSize: TerminalSize
    var committedChanged: Bool
    var isResizing: Bool
}

struct DashboardResizeCoordinator: Sendable {
    static let debounceInterval: TimeInterval = 0.2

    private(set) var state = DashboardResizeState()

    mutating func update(liveSize: TerminalSize, now: Date = Date()) -> DashboardResizeUpdate {
        state.liveSize = liveSize

        guard let committedSize = state.committedSize else {
            state.committedSize = liveSize
            state.pendingSize = nil
            state.lastSizeChangeAt = nil
            state.isResizing = false
            return DashboardResizeUpdate(
                layoutSize: liveSize,
                viewportSize: liveSize,
                committedChanged: true,
                isResizing: false
            )
        }

        guard liveSize != committedSize else {
            state.pendingSize = nil
            state.lastSizeChangeAt = nil
            state.isResizing = false
            return DashboardResizeUpdate(
                layoutSize: committedSize,
                viewportSize: liveSize,
                committedChanged: false,
                isResizing: false
            )
        }

        if state.pendingSize != liveSize {
            state.pendingSize = liveSize
            state.lastSizeChangeAt = now
            state.isResizing = true
            return DashboardResizeUpdate(
                layoutSize: committedSize,
                viewportSize: liveSize,
                committedChanged: false,
                isResizing: true
            )
        }

        if let lastSizeChangeAt = state.lastSizeChangeAt,
           now.timeIntervalSince(lastSizeChangeAt) >= Self.debounceInterval {
            state.committedSize = liveSize
            state.pendingSize = nil
            state.lastSizeChangeAt = nil
            state.isResizing = false
            return DashboardResizeUpdate(
                layoutSize: liveSize,
                viewportSize: liveSize,
                committedChanged: true,
                isResizing: false
            )
        }

        state.isResizing = true
        return DashboardResizeUpdate(
            layoutSize: committedSize,
            viewportSize: liveSize,
            committedChanged: false,
            isResizing: true
        )
    }
}

struct SampleRingBuffer: Sendable {
    private(set) var samples: [SampleEnvelope] = []
    let capacity: Int

    init(capacity: Int) {
        self.capacity = max(capacity, 1)
    }

    mutating func append(_ sample: SampleEnvelope) {
        samples.append(sample)
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
    }
}

extension Array where Element == ProcessSnapshot {
    func sorted(by key: ProcessSortKey) -> [ProcessSnapshot] {
        sorted { lhs, rhs in
            switch key {
            case .cpu:
                return (lhs.cpuPercent ?? -1) > (rhs.cpuPercent ?? -1)
            case .memory:
                return (lhs.memoryBytes ?? -1) > (rhs.memoryBytes ?? -1)
            case .energy:
                return (lhs.energyImpact ?? -1) > (rhs.energyImpact ?? -1)
            case .gpu:
                return (lhs.gpuTime ?? -1) > (rhs.gpuTime ?? -1)
            case .network:
                return ((lhs.networkInRateBytesPerSec ?? 0) + (lhs.networkOutRateBytesPerSec ?? 0)) >
                    ((rhs.networkInRateBytesPerSec ?? 0) + (rhs.networkOutRateBytesPerSec ?? 0))
            }
        }
    }
}
