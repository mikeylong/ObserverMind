import Foundation

struct TopParseResult {
    var cpu: CPUSnapshot
    var physMemUsedBytes: Int64?
    var physMemWiredBytes: Int64?
    var physMemCompressedBytes: Int64?
    var physMemUnusedBytes: Int64?
    var processes: [ProcessSnapshot]
}

struct VMStatParseResult {
    var pageSize: Int64
    var pagesFree: Int64?
    var pagesWired: Int64?
    var pagesCompressed: Int64?
    var swapins: Int64?
    var swapouts: Int64?
}

struct MemoryPressureParseResult {
    var freePercent: Double?
}

struct IostatParseResult {
    var readMBPerSec: Double
    var writeMBPerSec: Double
}

struct BatteryParseResult {
    var powerSource: String
    var percentage: Double?
    var state: String
    var timeRemaining: String?
}

struct ThermalParseResult {
    var state: String
    var details: [String]
}

struct PowerMetricsParseResult {
    var cpuPowerWatts: Double?
    var gpuPowerWatts: Double?
    var anePowerWatts: Double?
    var thermalState: String?
    var perProcessMetrics: [Int: (energy: Double?, gpuTime: Double?)]

    static let empty = PowerMetricsParseResult(
        cpuPowerWatts: nil,
        gpuPowerWatts: nil,
        anePowerWatts: nil,
        thermalState: nil,
        perProcessMetrics: [:]
    )
}

enum Parser {
    static func parseTop(_ text: String) -> TopParseResult {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var loadAverage = (0.0, 0.0, 0.0)
        var cpuUsage = (0.0, 0.0, 100.0)
        var usedBytes: Int64?
        var wiredBytes: Int64?
        var compressedBytes: Int64?
        var unusedBytes: Int64?
        var processes: [ProcessSnapshot] = []

        var processTableStarted = false

        for line in lines {
            if line.hasPrefix("Load Avg:") {
                let values = line
                    .replacingOccurrences(of: "Load Avg:", with: "")
                    .split(separator: ",")
                    .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                if values.count >= 3 {
                    loadAverage = (values[0], values[1], values[2])
                }
            } else if line.hasPrefix("CPU usage:") {
                let clean = line.replacingOccurrences(of: "CPU usage:", with: "")
                let parts = clean.split(separator: ",")
                if parts.count >= 3 {
                    cpuUsage.0 = parseLeadingDouble(parts[0]) ?? 0
                    cpuUsage.1 = parseLeadingDouble(parts[1]) ?? 0
                    cpuUsage.2 = parseLeadingDouble(parts[2]) ?? 0
                }
            } else if line.hasPrefix("PhysMem:") {
                let metrics = line.replacingOccurrences(of: "PhysMem:", with: "")
                let groups = metrics.split(separator: ",")
                if groups.count >= 2 {
                    usedBytes = parseByteCount(in: String(groups[0]))
                    unusedBytes = parseByteCount(in: String(groups.last ?? ""))
                }
                if let wiredRange = metrics.range(of: "\\(([^)]*)\\)", options: .regularExpression) {
                    let inner = String(metrics[wiredRange]).trimmingCharacters(in: CharacterSet(charactersIn: "()"))
                    for component in inner.split(separator: ",") {
                        let part = component.trimmingCharacters(in: .whitespaces)
                        if part.contains("wired") {
                            wiredBytes = parseByteCount(in: part)
                        } else if part.contains("compressor") {
                            compressedBytes = parseByteCount(in: part)
                        }
                    }
                }
            } else if line.hasPrefix("PID") {
                processTableStarted = true
            } else if processTableStarted, !line.trimmingCharacters(in: .whitespaces).isEmpty {
                let columns = line.split(omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
                guard columns.count >= 5, let pid = Int(columns[0]) else {
                    continue
                }
                processes.append(ProcessSnapshot(
                    pid: pid,
                    command: String(columns[1]),
                    cpuPercent: Double(columns[2]) ?? 0,
                    memoryBytes: parseByteCount(in: String(columns[3])),
                    cumulativeCPUTime: String(columns[4]),
                    networkBytesIn: nil,
                    networkBytesOut: nil,
                    networkInRateBytesPerSec: nil,
                    networkOutRateBytesPerSec: nil,
                    energyImpact: nil,
                    gpuTime: nil
                ))
            }
        }

        return TopParseResult(
            cpu: CPUSnapshot(
                userPercent: cpuUsage.0,
                systemPercent: cpuUsage.1,
                idlePercent: cpuUsage.2,
                loadAverage1m: loadAverage.0,
                loadAverage5m: loadAverage.1,
                loadAverage15m: loadAverage.2,
                packagePowerWatts: nil
            ),
            physMemUsedBytes: usedBytes,
            physMemWiredBytes: wiredBytes,
            physMemCompressedBytes: compressedBytes,
            physMemUnusedBytes: unusedBytes,
            processes: processes
        )
    }

    static func parseVMStat(_ text: String) -> VMStatParseResult {
        var pageSize: Int64 = 4096
        if let match = text.firstMatch(of: /page size of ([0-9]+)/) {
            pageSize = Int64(match.1) ?? 4096
        }

        return VMStatParseResult(
            pageSize: pageSize,
            pagesFree: parseIntMetric(text, key: "Pages free"),
            pagesWired: parseIntMetric(text, key: "Pages wired down"),
            pagesCompressed: parseIntMetric(text, key: "Pages occupied by compressor"),
            swapins: parseIntMetric(text, key: "Swapins"),
            swapouts: parseIntMetric(text, key: "Swapouts")
        )
    }

    static func parseMemoryPressure(_ text: String) -> MemoryPressureParseResult {
        let freePercent = text.firstMatch(of: /System-wide memory free percentage:\s+([0-9.]+)/).flatMap {
            Double($0.1)
        }
        return MemoryPressureParseResult(freePercent: freePercent)
    }

    static func parseIostat(_ text: String) -> IostatParseResult {
        let lines = text.split(separator: "\n").map(String.init)
        guard let valuesLine = lines.last else {
            return IostatParseResult(readMBPerSec: 0, writeMBPerSec: 0)
        }

        let numbers = valuesLine.split(whereSeparator: \.isWhitespace).compactMap { Double($0) }
        guard numbers.count >= 9 else {
            return IostatParseResult(readMBPerSec: 0, writeMBPerSec: 0)
        }

        let diskValueCount = max(numbers.count - 6, 0)
        let diskCount = diskValueCount / 3
        var totalMBPerSec = 0.0
        for diskIndex in 0..<diskCount {
            let mbIndex = diskIndex * 3 + 2
            if mbIndex < numbers.count {
                totalMBPerSec += numbers[mbIndex]
            }
        }

        return IostatParseResult(
            readMBPerSec: totalMBPerSec / 2.0,
            writeMBPerSec: totalMBPerSec / 2.0
        )
    }

    static func parseNettop(_ text: String) -> [NetworkProcessSnapshot] {
        text
            .split(separator: "\n")
            .compactMap { line -> NetworkProcessSnapshot? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, trimmed.hasPrefix(",") == false else {
                    return nil
                }

                let columns = trimmed.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
                guard columns.count >= 3 else {
                    return nil
                }

                let identity = columns[0]
                let bytesIn = Int64(columns[1]) ?? 0
                let bytesOut = Int64(columns[2]) ?? 0
                let pid: Int?
                let command: String
                if let separator = identity.lastIndex(of: "."),
                   let parsedPID = Int(identity[identity.index(after: separator)...]) {
                    pid = parsedPID
                    command = String(identity[..<separator])
                } else {
                    pid = nil
                    command = identity
                }

                return NetworkProcessSnapshot(
                    pid: pid,
                    command: command,
                    bytesIn: bytesIn,
                    bytesOut: bytesOut,
                    inRateBytesPerSec: nil,
                    outRateBytesPerSec: nil
                )
            }
    }

    static func parseBattery(_ text: String) -> BatteryParseResult {
        let lines = text.split(separator: "\n").map(String.init)
        let powerSource = lines.first?.replacingOccurrences(of: "Now drawing from '", with: "")
            .replacingOccurrences(of: "'", with: "") ?? "Unknown"
        guard lines.count >= 2 else {
            return BatteryParseResult(powerSource: powerSource, percentage: nil, state: "unknown", timeRemaining: nil)
        }

        let detail = lines[1]
        let percentage = detail.firstMatch(of: /([0-9]+)%/).flatMap { Double($0.1) }
        let state: String
        if detail.contains("not charging") {
            state = "not charging"
        } else if detail.contains("charging") {
            state = "charging"
        } else if detail.contains("discharging") {
            state = "discharging"
        } else {
            state = "unknown"
        }
        let timeRemaining = detail.firstMatch(of: /([0-9]+:[0-9]+ remaining)/).map { String($0.1) }
        return BatteryParseResult(
            powerSource: powerSource,
            percentage: percentage,
            state: state,
            timeRemaining: timeRemaining
        )
    }

    static func parseThermal(_ text: String) -> ThermalParseResult {
        let lines = text.split(separator: "\n").map(String.init)
        if lines.allSatisfy({ $0.contains("No ") }) {
            return ThermalParseResult(state: "Nominal", details: lines)
        }

        let state = lines.contains { $0.localizedCaseInsensitiveContains("critical") } ? "Critical" :
            (lines.contains { $0.localizedCaseInsensitiveContains("warning") } ? "Warning" : "Active")
        return ThermalParseResult(state: state, details: lines)
    }

    static func parseHostSnapshot(
        hardwareText: String,
        osVersion: String,
        architecture: String
    ) -> HostSnapshot {
        let modelName = value(in: hardwareText, after: "Model Name:") ?? "Mac"
        let identifier = value(in: hardwareText, after: "Model Identifier:") ?? "Unknown"
        let chip = value(in: hardwareText, after: "Chip:") ?? "Unknown"
        let coreLine = value(in: hardwareText, after: "Total Number of Cores:")
        let cpuCoreCount = coreLine?.split(separator: " ").first.flatMap { Int($0) }
        let memoryLine = value(in: hardwareText, after: "Memory:")
        let memoryBytes = parseByteCount(in: memoryLine ?? "")
        let gpuModel = value(in: hardwareText, after: "Chipset Model:")
        let gpuCoreLine = hardwareText
            .split(separator: "\n")
            .map(String.init)
            .first { $0.contains("Graphics/Displays:") == false && $0.contains("Total Number of Cores:") && $0.contains("Performance") == false }
        let gpuCoreCount = gpuCoreLine.flatMap { line in
            line.split(separator: ":").last?.split(separator: " ").first.flatMap { Int($0) }
        }

        return HostSnapshot(
            modelName: modelName,
            modelIdentifier: identifier,
            chip: chip,
            cpuCoreCount: cpuCoreCount,
            memoryBytes: memoryBytes,
            osVersion: osVersion,
            architecture: architecture,
            gpuModel: gpuModel,
            gpuCoreCount: gpuCoreCount
        )
    }

    static func parsePowermetrics(_ text: String) -> PowerMetricsParseResult {
        let lower = text.lowercased()
        var result = PowerMetricsParseResult.empty
        result.cpuPowerWatts = parsePowerMetric(in: text, labels: ["CPU Power:", "cpu power:"])
        result.gpuPowerWatts = parsePowerMetric(in: text, labels: ["GPU Power:", "gpu power:"])
        result.anePowerWatts = parsePowerMetric(in: text, labels: ["ANE Power:", "ane power:"])

        if let thermal = text
            .split(separator: "\n")
            .map(String.init)
            .first(where: { $0.lowercased().contains("thermal pressure") }) {
            if let value = thermal.split(separator: ":").last {
                result.thermalState = value.trimmingCharacters(in: .whitespaces)
            }
        } else if lower.contains("serious") {
            result.thermalState = "Serious"
        }

        let lines = text.split(separator: "\n").map(String.init)
        for line in lines {
            let columns = line.split(whereSeparator: \.isWhitespace)
            guard columns.count >= 4, let pid = Int(columns[0]) else {
                continue
            }
            let energyToken = columns.first { $0.starts(with: "energy=") }
            let gpuToken = columns.first { $0.starts(with: "gpu=") || $0.starts(with: "gpu_time=") }
            let energy = energyToken.flatMap { Double($0.split(separator: "=").last ?? "") }
            let gpuTime = gpuToken.flatMap { Double($0.split(separator: "=").last ?? "") }
            if energy != nil || gpuTime != nil {
                result.perProcessMetrics[pid] = (energy, gpuTime)
            }
        }

        return result
    }
}

private func parseLeadingDouble<S: StringProtocol>(_ slice: S) -> Double? {
    let token = slice.trimmingCharacters(in: .whitespaces).split(separator: " ").first ?? ""
    return Double(token.replacingOccurrences(of: "%", with: ""))
}

private func parseIntMetric(_ text: String, key: String) -> Int64? {
    let pattern = "\(NSRegularExpression.escapedPattern(for: key)):\\s*([0-9]+)"
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return nil
    }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = regex.firstMatch(in: text, range: range),
          let valueRange = Range(match.range(at: 1), in: text) else {
        return nil
    }
    return Int64(text[valueRange])
}

private func value(in text: String, after prefix: String) -> String? {
    text
        .split(separator: "\n")
        .map(String.init)
        .first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix(prefix) })?
        .split(separator: ":", maxSplits: 1)
        .last
        .map { String($0).trimmingCharacters(in: .whitespaces) }
}

private func parsePowerMetric(in text: String, labels: [String]) -> Double? {
    for label in labels {
        if let line = text.split(separator: "\n").map(String.init).first(where: { $0.contains(label) }) {
            let token = line
                .split(separator: ":")
                .last?
                .trimmingCharacters(in: .whitespaces)
                .split(separator: " ")
                .first
            if let raw = token.flatMap({ Double($0) }) {
                if line.lowercased().contains("mw") {
                    return raw / 1000.0
                }
                return raw
            }
        }
    }
    return nil
}

func parseByteCount(in text: String) -> Int64? {
    let tokens = text.replacingOccurrences(of: ",", with: "")
        .split(whereSeparator: \.isWhitespace)
        .map(String.init)

    guard let firstIndex = tokens.firstIndex(where: { $0.rangeOfCharacter(from: .decimalDigits) != nil }) else {
        return nil
    }

    var candidate = tokens[firstIndex]
    if candidate.rangeOfCharacter(from: .letters) == nil,
       firstIndex + 1 < tokens.count,
       tokens[firstIndex + 1].rangeOfCharacter(from: .letters) != nil {
        candidate += tokens[firstIndex + 1]
    }

    let cleaned = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "();"))
    let regex = try? NSRegularExpression(pattern: #"([0-9]+(?:\.[0-9]+)?)([KMGTP]?)(?:i?B?)?"#)
    let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
    guard let match = regex?.firstMatch(in: cleaned, range: range),
          let valueRange = Range(match.range(at: 1), in: cleaned),
          let unitRange = Range(match.range(at: 2), in: cleaned),
          let value = Double(cleaned[valueRange]) else {
        return nil
    }

    let unit = String(cleaned[unitRange]).uppercased()
    let multiplier: Double
    switch unit {
    case "K":
        multiplier = 1_024
    case "M":
        multiplier = 1_024 * 1_024
    case "G":
        multiplier = 1_024 * 1_024 * 1_024
    case "T":
        multiplier = 1_024 * 1_024 * 1_024 * 1_024
    case "P":
        multiplier = 1_024 * 1_024 * 1_024 * 1_024 * 1_024
    default:
        multiplier = 1
    }
    return Int64(value * multiplier)
}
