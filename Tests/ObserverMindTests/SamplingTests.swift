import Foundation
import Testing
@testable import ObserverMind

@Test func ringBufferRetainsLatestSamples() {
    var buffer = SampleRingBuffer(capacity: 3)
    buffer.append(makeSample(timestamp: Date(timeIntervalSince1970: 1)))
    buffer.append(makeSample(timestamp: Date(timeIntervalSince1970: 2)))
    buffer.append(makeSample(timestamp: Date(timeIntervalSince1970: 3)))
    buffer.append(makeSample(timestamp: Date(timeIntervalSince1970: 4)))

    #expect(buffer.samples.count == 3)
    #expect(buffer.samples.first?.timestamp == Date(timeIntervalSince1970: 2))
    #expect(buffer.samples.last?.timestamp == Date(timeIntervalSince1970: 4))
}

@Test func alertEvaluationFlagsHotAndLowMemoryStates() {
    let previous = makeSample(timestamp: Date(timeIntervalSince1970: 0), cpu: 20, freePercent: 20, swapOutBytes: 0, diskMBPerSec: 10, batteryPercentage: 80, thermalState: "Nominal")
    let current = makeSample(timestamp: Date(timeIntervalSince1970: 60), cpu: 92, freePercent: 5, swapOutBytes: 600 * 1_024 * 1_024, diskMBPerSec: 1_400, batteryPercentage: 60, thermalState: "Serious")

    let alerts = evaluateAlerts(current: current, previous: previous, thresholds: ThresholdConfig())

    #expect(alerts.contains { $0.message.contains("CPU usage") })
    #expect(alerts.contains { $0.message.contains("Memory free percentage") })
    #expect(alerts.contains { $0.message.contains("Swap grew") })
    #expect(alerts.contains { $0.message.contains("Disk throughput") })
    #expect(alerts.contains { $0.message.contains("Battery is draining") })
    #expect(alerts.contains { $0.message.contains("Thermal pressure") })
}
