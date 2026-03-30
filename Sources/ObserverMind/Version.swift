import Foundation

public enum ObserverVersion {
    public static let fallback = "dev"

    public static var current: String {
        cachedVersion
    }

    public static func cliBanner() -> String {
        "observer \(current)"
    }

    static let companionFilenameExtension = "version"
    private static let cachedVersion = resolve()

    static func resolve(
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> String {
        if let version = readCompanionVersionFile(arguments: arguments, fileManager: fileManager) {
            return version
        }

        if let version = resolvedEnvironmentVersion(environment) {
            return version
        }

        if let version = readGitDescribe(arguments: arguments, fileManager: fileManager) {
            return version
        }

        return fallback
    }

    static func resolvedEnvironmentVersion(_ environment: [String: String]) -> String? {
        let raw = environment["OBSERVER_VERSION"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, raw.isEmpty == false else {
            return nil
        }
        return raw
    }

    static func readCompanionVersionFile(
        arguments: [String],
        fileManager: FileManager
    ) -> String? {
        guard let executableURL = executableURL(arguments: arguments) else {
            return nil
        }

        let versionURL = executableURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(executableURL.lastPathComponent).\(companionFilenameExtension)")

        guard fileManager.isReadableFile(atPath: versionURL.path),
              let version = try? String(contentsOf: versionURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
              version.isEmpty == false else {
            return nil
        }

        return version
    }

    static func readGitDescribe(arguments: [String], fileManager: FileManager) -> String? {
        guard let repoRoot = repositoryRoot(arguments: arguments, fileManager: fileManager) else {
            return nil
        }

        let runner = ProcessCommandRunner()
        let result = try? runner.run(
            "/usr/bin/git",
            arguments: [
                "-C", repoRoot.path,
                "describe",
                "--tags",
                "--always",
                "--dirty",
                "--match", "v[0-9]*"
            ]
        )
        let version = result?.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let version, version.isEmpty == false else {
            return nil
        }

        return version
    }

    static func repositoryRoot(arguments: [String], fileManager: FileManager) -> URL? {
        guard let executableURL = executableURL(arguments: arguments) else {
            return nil
        }

        var searchPath = executableURL.deletingLastPathComponent().path
        while true {
            let gitPath = (searchPath as NSString).appendingPathComponent(".git")
            let packagePath = (searchPath as NSString).appendingPathComponent("Package.swift")
            if fileManager.fileExists(atPath: gitPath), fileManager.fileExists(atPath: packagePath) {
                return URL(fileURLWithPath: searchPath, isDirectory: true)
            }

            let parentPath = (searchPath as NSString).deletingLastPathComponent
            if parentPath.isEmpty || parentPath == searchPath {
                return nil
            }
            searchPath = parentPath
        }
    }

    static func executableURL(arguments: [String]) -> URL? {
        if let path = arguments.first?.trimmingCharacters(in: .whitespacesAndNewlines),
           path.isEmpty == false {
            if path.hasPrefix("/") {
                return URL(fileURLWithPath: path).standardizedFileURL
            }

            if path.contains("/") {
                let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                return currentDirectory.appendingPathComponent(path).standardizedFileURL
            }
        }

        if let executableURL = Bundle.main.executableURL {
            return executableURL.standardizedFileURL
        }

        return nil
    }
}
