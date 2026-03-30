import Foundation
import Testing
@testable import ObserverMind

@Test func overviewRenderMatchesCompactHistoryAndFullSamples() {
    let samples = makeDashboardHistorySamples()
    let compactHistory = samples.dashboardHistoryPoints()
    let state = DashboardRenderState(
        view: .overview,
        processSort: .cpu,
        selectionIndex: 0,
        processScrollOffset: 0,
        networkScrollOffset: 0,
        theme: .light
    )

    let fullOutput = DashboardRenderer.render(
        sample: samples.last,
        history: samples,
        state: state,
        size: TerminalSize(width: 118, height: 28),
        status: "ok"
    )
    let compactOutput = DashboardRenderer.render(
        sample: samples.last,
        history: compactHistory,
        state: state,
        size: TerminalSize(width: 118, height: 28),
        status: "ok"
    )

    #expect(compactOutput == fullOutput)
}

@Test func powerRenderMatchesCompactHistoryAndFullSamples() {
    let samples = makeDashboardHistorySamples()
    let compactHistory = samples.dashboardHistoryPoints()
    let state = DashboardRenderState(
        view: .power,
        processSort: .cpu,
        selectionIndex: 0,
        processScrollOffset: 0,
        networkScrollOffset: 0,
        theme: .light
    )

    let fullOutput = DashboardRenderer.render(
        sample: samples.last,
        history: samples,
        state: state,
        size: TerminalSize(width: 144, height: 32),
        status: "ok"
    )
    let compactOutput = DashboardRenderer.render(
        sample: samples.last,
        history: compactHistory,
        state: state,
        size: TerminalSize(width: 144, height: 32),
        status: "ok"
    )

    #expect(compactOutput == fullOutput)
}

private func makeDashboardHistorySamples() -> [SampleEnvelope] {
    (0..<12).map { index in
        var sample = makeSample(
            timestamp: Date(timeIntervalSince1970: Double(index)),
            cpu: 18 + Double(index * 5),
            freePercent: max(14, 48 - Double(index * 2)),
            swapOutBytes: Int64(index) * 96 * 1_024 * 1_024,
            diskMBPerSec: 20 + Double(index * 6),
            batteryPercentage: 92 - Double(index * 2),
            batteryState: "discharging",
            thermalState: index > 7 ? "Fair" : "Nominal"
        )
        sample.capabilities.isRoot = true
        sample.capabilities.advancedPowerAvailable = true
        sample.cpu.packagePowerWatts = 8 + Double(index) * 1.8
        sample.gpu.powerWatts = 3 + Double(index) * 1.2
        sample.gpu.anePowerWatts = 1 + Double(index) * 0.4
        sample.gpu.processMetricsLocked = false
        sample.gpu.lockReason = nil
        sample.network.totalInRateBytesPerSec = 1_000 + Double(index * 200)
        sample.network.totalOutRateBytesPerSec = 500 + Double(index * 120)
        return sample
    }
}
