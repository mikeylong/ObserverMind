import Foundation
import Testing
@testable import ObserverMind

@Test func snapshotJsonSmokeTest() throws {
    let sampler = try SystemSampler()
    let sample = try sampler.collectSample(previous: nil, intervalSeconds: 1)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let json = String(decoding: try encoder.encode(sample), as: UTF8.self)

    #expect(json.contains("\"cpu\""))
    #expect(json.contains("\"memory\""))
    #expect(json.contains("\"network\""))
}

@Test func shortStreamSmokeTest() throws {
    let sampler = try SystemSampler()
    let first = try sampler.collectSample(previous: nil, intervalSeconds: 1)
    Thread.sleep(forTimeInterval: 1)
    let second = try sampler.collectSample(previous: first, intervalSeconds: 1)

    #expect(second.timestamp >= first.timestamp)
    #expect(second.network.totalBytesIn >= 0)
}
