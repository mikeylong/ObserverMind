import Foundation
import Testing
@testable import ObserverMind

@Test func versionResolverReadsCompanionFileBesideExecutable() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let executableURL = directory.appendingPathComponent("observer")
    let versionURL = directory.appendingPathComponent("observer.version")
    FileManager.default.createFile(atPath: executableURL.path, contents: Data(), attributes: nil)
    try "v9.9.9\n".write(to: versionURL, atomically: true, encoding: .utf8)

    let version = ObserverVersion.resolve(
        arguments: [executableURL.path],
        environment: [:]
    )

    #expect(version == "v9.9.9")
}

@Test func versionResolverFallsBackToEnvironmentWhenNoCompanionFileExists() {
    let fakeExecutable = "/tmp/observer"
    let version = ObserverVersion.resolve(
        arguments: [fakeExecutable],
        environment: ["OBSERVER_VERSION": "v1.2.3"]
    )

    #expect(version == "v1.2.3")
}

@Test func versionResolverUsesFallbackWhenNoSourceIsAvailable() {
    let fakeExecutable = "/tmp/observer"
    let version = ObserverVersion.resolve(
        arguments: [fakeExecutable],
        environment: [:]
    )

    #expect(version == ObserverVersion.fallback)
}
