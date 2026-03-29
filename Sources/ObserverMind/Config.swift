import Foundation

struct ThresholdConfig: Codable, Sendable {
    var highCPUPercent = 85.0
    var lowMemoryFreePercent = 10.0
    var highSwapGrowthMB = 256.0
    var highDiskMBPerSec = 1024.0
    var highBatteryDrainPercentPerHour = 15.0
}

struct AppConfig: Codable, Sendable {
    var theme: DashboardTheme?
    var thresholds = ThresholdConfig()

    static let `default` = AppConfig(theme: nil, thresholds: ThresholdConfig())
}

enum AppConfigLoader {
    static func configurationURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("ObserverMind", isDirectory: true)
        return base.appendingPathComponent("config.json", isDirectory: false)
    }

    static func load(fileManager: FileManager = .default) -> AppConfig {
        let url = configurationURL(fileManager: fileManager)
        guard let data = try? Data(contentsOf: url) else {
            return .default
        }

        let decoder = JSONDecoder()
        return (try? decoder.decode(AppConfig.self, from: data)) ?? .default
    }
}
