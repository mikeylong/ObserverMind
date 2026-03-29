import Darwin
import Foundation

struct CommandResult {
    var stdout: String
    var stderr: String
    var exitCode: Int32
}

protocol CommandRunning: Sendable {
    func run(_ executable: String, arguments: [String]) throws -> CommandResult
}

enum CommandRunnerError: Error, LocalizedError {
    case executableNotFound(String)
    case nonZeroExit(String, Int32, String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound(let path):
            return "Missing executable: \(path)"
        case .nonZeroExit(let path, let code, let stderr):
            let tail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "Command failed (\(code)): \(path)\(tail.isEmpty ? "" : " - \(tail)")"
        }
    }
}

struct ProcessCommandRunner: CommandRunning, Sendable {
    func run(_ executable: String, arguments: [String]) throws -> CommandResult {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw CommandRunnerError.executableNotFound(executable)
        }

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let result = CommandResult(
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrData, as: UTF8.self),
            exitCode: process.terminationStatus
        )

        if result.exitCode != 0 {
            throw CommandRunnerError.nonZeroExit(executable, result.exitCode, result.stderr)
        }
        return result
    }
}

enum CapabilityDetector {
    static func snapshot() -> CapabilitySnapshot {
        let isRoot = geteuid() == 0
        let powermetricsPath = "/usr/bin/powermetrics"
        let powermetricsAvailable = FileManager.default.isExecutableFile(atPath: powermetricsPath)
        return CapabilitySnapshot(
            isRoot: isRoot,
            powermetricsAvailable: powermetricsAvailable,
            advancedPowerAvailable: isRoot && powermetricsAvailable,
            relaunchHint: "Run `sudo observer dashboard` for power, GPU, and per-process energy metrics."
        )
    }
}
