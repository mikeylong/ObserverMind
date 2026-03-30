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
        let stdoutCapture = try TemporaryCommandCapture(prefix: "stdout")
        let stderrCapture = try TemporaryCommandCapture(prefix: "stderr")
        defer {
            stdoutCapture.cleanup()
            stderrCapture.cleanup()
        }

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdoutCapture.handle
        process.standardError = stderrCapture.handle
        try process.run()
        try? stdoutCapture.handle.close()
        try? stderrCapture.handle.close()
        process.waitUntilExit()

        let result = CommandResult(
            stdout: try stdoutCapture.readString(),
            stderr: try stderrCapture.readString(),
            exitCode: process.terminationStatus
        )

        if result.exitCode != 0 {
            throw CommandRunnerError.nonZeroExit(executable, result.exitCode, result.stderr)
        }
        return result
    }
}

private struct TemporaryCommandCapture {
    let url: URL
    let handle: FileHandle

    init(prefix: String) throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
        let filename = "ObserverMind-\(prefix)-\(UUID().uuidString).log"
        let url = directory.appendingPathComponent(filename)

        guard fileManager.createFile(atPath: url.path, contents: nil) else {
            throw RuntimeError("Unable to create temporary capture file.")
        }

        self.url = url
        self.handle = try FileHandle(forWritingTo: url)
    }

    func readString() throws -> String {
        String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }

    func cleanup() {
        try? handle.close()
        try? FileManager.default.removeItem(at: url)
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
