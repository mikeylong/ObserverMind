import Foundation
import Testing
@testable import ObserverMind

@Test func triggerImmediateRefreshKeepsLastVisibleStatus() {
    let runtime = DashboardRuntimeState()
    let sample = makeSample(timestamp: Date(timeIntervalSince1970: 1_234))

    runtime.update(with: sample)
    let statusBeforeRefresh = runtime.snapshot().status

    runtime.triggerImmediateRefresh()
    let statusAfterRefresh = runtime.snapshot().status

    #expect(statusBeforeRefresh == "Updated 1970-01-01T00:20:34Z")
    #expect(statusAfterRefresh == statusBeforeRefresh)
    #expect(runtime.consumeRefreshTrigger())
}

@Test func runtimeSnapshotStoresCompactHistoryPoints() {
    let runtime = DashboardRuntimeState()
    var sample = makeSample(timestamp: Date(timeIntervalSince1970: 10), cpu: 44, freePercent: 17, diskMBPerSec: 96, batteryPercentage: 71)
    sample.network.totalInRateBytesPerSec = 2_000
    sample.network.totalOutRateBytesPerSec = 500
    sample.cpu.packagePowerWatts = 13.5
    sample.gpu.powerWatts = 6.5
    sample.gpu.anePowerWatts = 1.25

    runtime.update(with: sample)

    let snapshot = runtime.snapshot()
    #expect(snapshot.sample?.timestamp == sample.timestamp)
    #expect(snapshot.history.count == 1)
    #expect(snapshot.history.first == DashboardHistoryPoint(sample: sample))
}

@Test func runtimeSnapshotCapsDashboardHistoryAtOneHour() {
    let runtime = DashboardRuntimeState()

    for index in 0...3_601 {
        runtime.update(
            with: makeSample(
                timestamp: Date(timeIntervalSince1970: Double(index)),
                cpu: Double(index)
            )
        )
    }

    let snapshot = runtime.snapshot()
    #expect(snapshot.history.count == 3_600)
    #expect(snapshot.history.first?.timestamp == Date(timeIntervalSince1970: 2))
    #expect(snapshot.history.last?.timestamp == Date(timeIntervalSince1970: 3_601))
}
