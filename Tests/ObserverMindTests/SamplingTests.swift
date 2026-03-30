import Foundation
import Testing
@testable import ObserverMind

@Test func dashboardHistoryPointCapturesTrendFields() {
    var sample = makeSample(timestamp: Date(timeIntervalSince1970: 42), cpu: 37, freePercent: 18, diskMBPerSec: 88, batteryPercentage: 73)
    sample.network.totalInRateBytesPerSec = 1_500
    sample.network.totalOutRateBytesPerSec = 250
    sample.cpu.packagePowerWatts = 12.5
    sample.gpu.powerWatts = 7.25
    sample.gpu.anePowerWatts = 1.75

    let point = DashboardHistoryPoint(sample: sample)

    #expect(point.timestamp == sample.timestamp)
    #expect(point.totalCPUPercent == sample.totalCPUPercent)
    #expect(point.memoryFreePercent == 18)
    #expect(point.networkTotalRateBytesPerSec == 1_750)
    #expect(point.diskTotalMBPerSec == 88)
    #expect(point.batteryPercentage == 73)
    #expect(point.cpuPackagePowerWatts == 12.5)
    #expect(point.gpuPowerWatts == 7.25)
    #expect(point.anePowerWatts == 1.75)
}

@Test func dashboardHistoryRingBufferRetainsLatestPoints() {
    var buffer = DashboardHistoryRingBuffer(capacity: 3)
    buffer.append(sample: makeSample(timestamp: Date(timeIntervalSince1970: 1), cpu: 10))
    buffer.append(sample: makeSample(timestamp: Date(timeIntervalSince1970: 2), cpu: 20))
    buffer.append(sample: makeSample(timestamp: Date(timeIntervalSince1970: 3), cpu: 30))
    buffer.append(sample: makeSample(timestamp: Date(timeIntervalSince1970: 4), cpu: 40))

    #expect(buffer.points.count == 3)
    #expect(buffer.points.first?.timestamp == Date(timeIntervalSince1970: 2))
    #expect(buffer.points.last?.timestamp == Date(timeIntervalSince1970: 4))
    #expect(buffer.points.last?.totalCPUPercent == 40)
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
