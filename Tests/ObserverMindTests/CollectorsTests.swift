import Testing
@testable import ObserverMind

@Test func processCommandRunnerCapturesLargeStdoutWithoutBlocking() throws {
    let runner = ProcessCommandRunner()
    let result = try runner.run("/bin/sh", arguments: ["-c", "yes observer | head -c 131072"])

    #expect(result.exitCode == 0)
    #expect(result.stdout.count == 131_072)
    #expect(result.stderr.isEmpty)
}
