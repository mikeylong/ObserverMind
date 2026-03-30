import Foundation
import Testing
@testable import ObserverMind

@Test func rendererShowsFallbackForTinyTerminals() {
    let sample = makeSample()
    let output = DashboardRenderer.render(
        sample: sample,
        history: [sample],
        state: DashboardRenderState(view: .overview, processSort: .cpu, selectionIndex: 0, processScrollOffset: 0, networkScrollOffset: 0, theme: .light),
        size: TerminalSize(width: 60, height: 10),
        status: "small"
    )

    #expect(output.contains("Terminal too small for the dashboard."))
    assertAllLinesFit(output, width: 60)
}

@Test func compactLayoutHidesHelpAndLimitsAlerts() {
    var sample = makeSample()
    sample.alerts = [
        Alert(level: .warning, message: "cpu hot"),
        Alert(level: .warning, message: "mem low"),
        Alert(level: .critical, message: "thermal high")
    ]

    let output = DashboardRenderer.render(
        sample: sample,
        history: [sample],
        state: DashboardRenderState(view: .overview, processSort: .cpu, selectionIndex: 0, processScrollOffset: 0, networkScrollOffset: 0, theme: .light),
        size: TerminalSize(width: 90, height: 20),
        status: "ok"
    )

    #expect(output.contains("Keys:") == false)
    #expect(output.contains("Compute"))
    #expect(output.contains("┌"))
    #expect(output.contains("[WARNING] cpu hot"))
    #expect(output.contains("[WARNING] mem low") == false)
    assertAllLinesFit(output, width: 90)
}

@Test func fixedFooterKeepsPanelHeightStableAcrossAlertCounts() {
    let cases: [(size: TerminalSize, expectedAlerts: Int)] = [
        (TerminalSize(width: 90, height: 20), 1),
        (TerminalSize(width: 110, height: 26), 2),
        (TerminalSize(width: 150, height: 32), 3)
    ]

    for testCase in cases {
        var noAlerts = makeSample()
        noAlerts.alerts = []

        var maxAlerts = makeSample()
        maxAlerts.alerts = (0..<testCase.expectedAlerts + 1).map { index in
            Alert(level: .warning, message: "alert-\(index)")
        }

        let noAlertOutput = DashboardRenderer.render(
            sample: noAlerts,
            history: [noAlerts],
            state: DashboardRenderState(view: .overview, processSort: .cpu, selectionIndex: 0, processScrollOffset: 0, networkScrollOffset: 0, theme: .light),
            size: testCase.size,
            status: "Updated 2026-03-29T16:00:00Z"
        )
        let maxAlertOutput = DashboardRenderer.render(
            sample: maxAlerts,
            history: [maxAlerts],
            state: DashboardRenderState(view: .overview, processSort: .cpu, selectionIndex: 0, processScrollOffset: 0, networkScrollOffset: 0, theme: .light),
            size: testCase.size,
            status: "Updated 2026-03-29T16:00:00Z"
        )

        #expect(frameLineCount(noAlertOutput) == frameLineCount(maxAlertOutput))
        #expect(frameLineCount(noAlertOutput) == testCase.size.height)
        #expect(lastFooterSeparatorIndex(noAlertOutput, width: testCase.size.width) == lastFooterSeparatorIndex(maxAlertOutput, width: testCase.size.width))
        #expect(noAlertOutput.contains("[INFO] No active alerts."))
        assertAllLinesFit(noAlertOutput, width: testCase.size.width)
        assertAllLinesFit(maxAlertOutput, width: testCase.size.width)
    }
}

@Test func compact80x24OverviewRendersThreePanelsAndClipsLongText() {
    var sample = makeSample()
    sample.host.chip = "Apple M3 Max Ultra Prototype Configuration That Should Clip"
    sample.gpu.model = String(repeating: "GraphicsCluster-", count: 6) + "UNCLIPPED-TAIL"
    sample.alerts = [
        Alert(level: .warning, message: "compact alert visible"),
        Alert(level: .critical, message: "hidden follow-up alert")
    ]
    let status = "Updated with an intentionally long collector status string that should clip"

    let size = TerminalSize(width: 80, height: 24)
    let output = DashboardRenderer.render(
        sample: sample,
        history: Array(repeating: sample, count: 12),
        state: DashboardRenderState(view: .overview, processSort: .cpu, selectionIndex: 0, processScrollOffset: 0, networkScrollOffset: 0, theme: .light),
        size: size,
        status: status
    )

    #expect(DashboardRenderer.layoutMode(for: size) == .compact)
    #expect(output.contains("Compute"))
    #expect(output.contains("GPU"))
    #expect(output.contains("Status locked"))
    #expect(output.contains("Memory"))
    #expect(output.contains("I/O + Power"))
    #expect(output.contains("┌"))
    #expect(output.contains("Keys:") == false)
    #expect(output.contains("[WARNING] compact alert visible"))
    #expect(output.contains("hidden follow-up alert") == false)
    #expect(output.contains(status) == false)
    #expect(output.contains("UNCLIPPED-TAIL") == false)
    #expect(renderedLineCount(output) <= 24)
    assertAllLinesFit(output, width: 80)
}

@Test func mediumOverviewUsesPanelGrid() {
    let sample = makeSample()
    let size = TerminalSize(width: 110, height: 26)
    let output = DashboardRenderer.render(
        sample: sample,
        history: Array(repeating: sample, count: 12),
        state: DashboardRenderState(view: .overview, processSort: .cpu, selectionIndex: 0, processScrollOffset: 0, networkScrollOffset: 0, theme: .light),
        size: size,
        status: "ok"
    )

    #expect(DashboardRenderer.layoutMode(for: size) == .medium)
    #expect(output.contains("CPU / GPU"))
    #expect(output.contains("Status locked"))
    #expect(output.contains("Memory"))
    #expect(output.contains("Network / Disk"))
    #expect(output.contains("Power / Thermal"))
    #expect(occurrenceCount(output, needle: "┌") >= 4)
    assertAllLinesFit(output, width: 110)
}

@Test func mediumOverviewUsesTallHistogramBands() {
    let history = makeLivePowerHistory(cpuValues: [18, 32, 47, 61, 78, 93])
    let output = DashboardRenderer.render(
        sample: history.last,
        history: history,
        state: DashboardRenderState(view: .overview, processSort: .cpu, selectionIndex: 0, processScrollOffset: 0, networkScrollOffset: 0, theme: .light),
        size: TerminalSize(width: 110, height: 26),
        status: "ok"
    )

    #expect(containsPartialHistogramGlyph(output))
    #expect(histogramLineCount(output) >= 8)
    assertAllLinesFit(output, width: 110)
}

@Test func wideOverviewUsesGridLayout() {
    var sample = makeSample()
    sample.capabilities.isRoot = true
    sample.capabilities.advancedPowerAvailable = true
    sample.cpu.packagePowerWatts = 22.75
    sample.gpu.powerWatts = 15.50
    sample.gpu.anePowerWatts = 3.25
    sample.gpu.processMetricsLocked = false
    sample.gpu.lockReason = nil
    let output = DashboardRenderer.render(
        sample: sample,
        history: Array(repeating: sample, count: 18),
        state: DashboardRenderState(view: .overview, processSort: .cpu, selectionIndex: 0, processScrollOffset: 0, networkScrollOffset: 0, theme: .light),
        size: TerminalSize(width: 150, height: 32),
        status: "ok"
    )

    #expect(output.contains("CPU / GPU"))
    #expect(output.contains("Power 15.50W"))
    #expect(output.contains("Memory"))
    #expect(output.contains("Network / Disk"))
    #expect(output.contains("Power / Thermal"))
    #expect(output.contains("Source Battery Power"))
    #expect(output.contains("gpu ") == false)
    #expect(containsPartialHistogramGlyph(output))
    #expect(occurrenceCount(output, needle: "┌") >= 4)
    assertAllLinesFit(output, width: 150)
}

@Test func loadingOverviewUsesStableWideGridBeforeFirstSample() {
    let output = DashboardRenderer.render(
        sample: nil,
        history: [] as [DashboardHistoryPoint],
        state: DashboardRenderState(view: .overview, processSort: .cpu, selectionIndex: 0, processScrollOffset: 0, networkScrollOffset: 0, theme: .light),
        size: TerminalSize(width: 144, height: 48),
        status: "Collecting sample..."
    )

    #expect(output.contains("CPU / GPU"))
    #expect(output.contains("GPU"))
    #expect(output.contains("Memory"))
    #expect(output.contains("Network / Disk"))
    #expect(output.contains("Power / Thermal"))
    #expect(output.contains("Collecting initial sample..."))
    #expect(output.contains("Terminal 144x48") == false)
    assertAllLinesFit(output, width: 144)
}

@Test func rendererProducesFullViewportSizedFrame() {
    let sample = makeSample()
    let size = TerminalSize(width: 110, height: 26)
    let output = DashboardRenderer.render(
        sample: sample,
        history: [sample],
        state: DashboardRenderState(view: .overview, processSort: .cpu, selectionIndex: 0, processScrollOffset: 0, networkScrollOffset: 0, theme: .light),
        size: size,
        status: "ok"
    )

    #expect(output.hasSuffix("\n") == false)
    #expect(frameLineCount(output) == size.height)
    for line in frameLines(output) {
        #expect(line.count == size.width)
    }
}

@Test func explicitLightThemeEmitsANSIAndPreservesVisibleFrame() {
    let sample = makeSample()
    let size = TerminalSize(width: 96, height: 24)
    let output = DashboardRenderer.render(
        sample: sample,
        history: Array(repeating: sample, count: 8),
        state: DashboardRenderState(view: .overview, processSort: .cpu, selectionIndex: 0, processScrollOffset: 0, networkScrollOffset: 0, theme: .light),
        size: size,
        status: "ok"
    )

    #expect(output.contains("\u{001B}["))
    #expect(frameLineCount(output) == size.height)
    for line in frameLines(output) {
        #expect(line.count == size.width)
    }
}

@Test func darkThemeUsesDistinctPaletteFromLightTheme() {
    let sample = makeSample()
    let size = TerminalSize(width: 96, height: 24)
    let lightOutput = DashboardRenderer.render(
        sample: sample,
        history: Array(repeating: sample, count: 8),
        state: DashboardRenderState(view: .overview, processSort: .cpu, selectionIndex: 0, processScrollOffset: 0, networkScrollOffset: 0, theme: .light),
        size: size,
        status: "ok"
    )
    let darkOutput = DashboardRenderer.render(
        sample: sample,
        history: Array(repeating: sample, count: 8),
        state: DashboardRenderState(view: .overview, processSort: .cpu, selectionIndex: 0, processScrollOffset: 0, networkScrollOffset: 0, theme: .dark),
        size: size,
        status: "ok"
    )

    #expect(lightOutput.contains("\u{001B}["))
    #expect(darkOutput.contains("\u{001B}["))
    #expect(lightOutput != darkOutput)
    #expect(strippingANSIEscapeSequences(lightOutput) == strippingANSIEscapeSequences(darkOutput))
}

@Test func autoThemeFollowsInjectedAppearanceProvider() {
    let sample = makeSample()
    let size = TerminalSize(width: 96, height: 24)
    let darkProvider = DashboardAppearanceProvider { .dark }
    let lightProvider = DashboardAppearanceProvider { nil }

    let autoDarkOutput = DashboardRenderer.render(
        sample: sample,
        history: [sample],
        state: DashboardRenderState(view: .overview, processSort: .cpu, selectionIndex: 0, processScrollOffset: 0, networkScrollOffset: 0, theme: .auto),
        size: size,
        status: "ok",
        appearanceProvider: darkProvider
    )
    let explicitDarkOutput = DashboardRenderer.render(
        sample: sample,
        history: [sample],
        state: DashboardRenderState(view: .overview, processSort: .cpu, selectionIndex: 0, processScrollOffset: 0, networkScrollOffset: 0, theme: .dark),
        size: size,
        status: "ok"
    )
    let autoLightOutput = DashboardRenderer.render(
        sample: sample,
        history: [sample],
        state: DashboardRenderState(view: .overview, processSort: .cpu, selectionIndex: 0, processScrollOffset: 0, networkScrollOffset: 0, theme: .auto),
        size: size,
        status: "ok",
        appearanceProvider: lightProvider
    )
    let explicitLightOutput = DashboardRenderer.render(
        sample: sample,
        history: [sample],
        state: DashboardRenderState(view: .overview, processSort: .cpu, selectionIndex: 0, processScrollOffset: 0, networkScrollOffset: 0, theme: .light),
        size: size,
        status: "ok"
    )

    #expect(autoDarkOutput == explicitDarkOutput)
    #expect(autoLightOutput == explicitLightOutput)
}

@Test func renderUsesCommittedLayoutWhileViewportIsChanging() {
    let sample = makeSample()
    let output = DashboardRenderer.render(
        sample: sample,
        history: Array(repeating: sample, count: 12),
        state: DashboardRenderState(view: .overview, processSort: .cpu, selectionIndex: 0, processScrollOffset: 0, networkScrollOffset: 0, theme: .light),
        layoutSize: TerminalSize(width: 90, height: 20),
        viewportSize: TerminalSize(width: 118, height: 28),
        status: "Updated | Resizing… 118x28"
    )

    #expect(output.contains("Compute"))
    #expect(output.contains("GPU"))
    #expect(output.contains("Memory"))
    #expect(output.contains("I/O + Power"))
    #expect(output.contains("Network / Disk") == false)
    #expect(output.contains("Power / Thermal") == false)
    assertAllLinesFit(output, width: 118)
}

@Test func mediumOverviewShowsLiveGPUInSharedComputeSection() {
    var sample = makeSample()
    sample.capabilities.isRoot = true
    sample.capabilities.advancedPowerAvailable = true
    sample.cpu.packagePowerWatts = 19.25
    sample.gpu.powerWatts = 12.75
    sample.gpu.anePowerWatts = 2.10
    sample.gpu.processMetricsLocked = false
    sample.gpu.lockReason = nil

    let output = DashboardRenderer.render(
        sample: sample,
        history: Array(repeating: sample, count: 12),
        state: DashboardRenderState(view: .overview, processSort: .cpu, selectionIndex: 0, processScrollOffset: 0, networkScrollOffset: 0, theme: .light),
        size: TerminalSize(width: 118, height: 28),
        status: "ok"
    )

    #expect(output.contains("CPU / GPU"))
    #expect(output.contains("Power 12.75W"))
    #expect(output.contains("Status locked") == false)
    #expect(output.contains("Source Battery Power"))
    assertAllLinesFit(output, width: 118)
}

@Test func rendererShowsLockedPowerPanel() {
    let sample = makeSample()
    let output = DashboardRenderer.render(
        sample: sample,
        history: [sample],
        state: DashboardRenderState(view: .power, processSort: .cpu, selectionIndex: 0, processScrollOffset: 0, networkScrollOffset: 0, theme: .light),
        size: TerminalSize(width: 120, height: 40),
        status: "ok"
    )

    #expect(output.contains("Advanced Metrics"))
    #expect(output.contains("Status locked"))
    #expect(output.contains("sudo observer dashboard"))
    #expect(output.contains("┌"))
    assertAllLinesFit(output, width: 120)
}

@Test func compactPowerViewGivesTrendPanelMoreHeight() {
    let history = makeLivePowerHistory(cpuValues: [22, 34, 48, 63, 77, 91])
    let output = DashboardRenderer.render(
        sample: history.last,
        history: history,
        state: DashboardRenderState(view: .power, processSort: .cpu, selectionIndex: 0, processScrollOffset: 0, networkScrollOffset: 0, theme: .light),
        size: TerminalSize(width: 90, height: 20),
        status: "ok"
    )

    let lines = frameLines(output)
    let trendStart = panelStartIndex(lines, title: "Power Trend")
    let batteryStart = panelStartIndex(lines, title: "Battery / Thermal")
    let advancedStart = panelStartIndex(lines, title: "Advanced Metrics")

    #expect(trendStart != nil)
    #expect(batteryStart != nil)
    #expect(advancedStart != nil)
    if let trendStart, let batteryStart, let advancedStart {
        #expect((batteryStart - trendStart) > (advancedStart - batteryStart))
    }
    assertAllLinesFit(output, width: 90)
}

@Test func widePowerViewUsesStackedTallHistograms() {
    let history = makeLivePowerHistory(cpuValues: [14, 27, 39, 51, 66, 80, 94])
    let output = DashboardRenderer.render(
        sample: history.last,
        history: history,
        state: DashboardRenderState(view: .power, processSort: .cpu, selectionIndex: 0, processScrollOffset: 0, networkScrollOffset: 0, theme: .light),
        size: TerminalSize(width: 144, height: 32),
        status: "ok"
    )

    #expect(output.contains("cpu"))
    #expect(output.contains("gpu"))
    #expect(output.contains("ane"))
    #expect(containsPartialHistogramGlyph(output))
    #expect(histogramLineCount(output) >= 6)
    assertAllLinesFit(output, width: 144)
}

@Test func processViewShowsRankedBarsAndSelectedPanel() {
    var sample = makeSample()
    sample.processes = [
        ProcessSnapshot(pid: 111, command: "ProcessOne", cpuPercent: 35, memoryBytes: 1_000_000_000, cumulativeCPUTime: "00:01.00", networkBytesIn: 1_000, networkBytesOut: 2_000, networkInRateBytesPerSec: 50, networkOutRateBytesPerSec: 75, energyImpact: 3, gpuTime: 2),
        ProcessSnapshot(pid: 222, command: "ProcessTwo", cpuPercent: 20, memoryBytes: 2_000_000_000, cumulativeCPUTime: "00:02.00", networkBytesIn: 5_000, networkBytesOut: 4_000, networkInRateBytesPerSec: 10, networkOutRateBytesPerSec: 15, energyImpact: 7, gpuTime: 4)
    ]

    let output = DashboardRenderer.render(
        sample: sample,
        history: [sample],
        state: DashboardRenderState(view: .processes, processSort: .cpu, selectionIndex: 1, processScrollOffset: 0, networkScrollOffset: 0, theme: .light),
        size: TerminalSize(width: 120, height: 30),
        status: "ok"
    )

    #expect(output.contains("Processes"))
    #expect(output.contains("Selected Process"))
    #expect(output.contains("ProcessTwo"))
    #expect(containsPartialGaugeGlyph(output))
    assertAllLinesFit(output, width: 120)
}

@Test func networkViewShowsRankedBarsAndSelectedPanel() {
    var sample = makeSample()
    sample.network.processes = [
        NetworkProcessSnapshot(pid: 111, command: "Safari", bytesIn: 10_000, bytesOut: 5_000, inRateBytesPerSec: 1_000, outRateBytesPerSec: 500),
        NetworkProcessSnapshot(pid: 222, command: "Dropbox", bytesIn: 40_000, bytesOut: 20_000, inRateBytesPerSec: 4_000, outRateBytesPerSec: 2_000)
    ]

    let output = DashboardRenderer.render(
        sample: sample,
        history: [sample],
        state: DashboardRenderState(view: .network, processSort: .cpu, selectionIndex: 1, processScrollOffset: 0, networkScrollOffset: 0, theme: .light),
        size: TerminalSize(width: 118, height: 28),
        status: "ok"
    )

    #expect(output.contains("Network"))
    #expect(output.contains("Selected Flow"))
    #expect(output.contains("Dropbox"))
    #expect(containsPartialGaugeGlyph(output))
    assertAllLinesFit(output, width: 118)
}

@Test func rendererTruncatesLongCommandsAndFitsWidth() {
    var sample = makeSample()
    sample.processes = [
        ProcessSnapshot(pid: 111, command: "VeryLongCommandNameThatShouldBeTruncatedForCompactLayouts", cpuPercent: 10, memoryBytes: 1_000_000_000, cumulativeCPUTime: "00:01.00", networkBytesIn: 1_000, networkBytesOut: 2_000, networkInRateBytesPerSec: 50, networkOutRateBytesPerSec: 75, energyImpact: 3, gpuTime: 2)
    ]

    let output = DashboardRenderer.render(
        sample: sample,
        history: [sample],
        state: DashboardRenderState(view: .processes, processSort: .cpu, selectionIndex: 0, processScrollOffset: 0, networkScrollOffset: 0, theme: .light),
        size: TerminalSize(width: 78, height: 20),
        status: "ok"
    )

    #expect(output.contains("…"))
    assertAllLinesFit(output, width: 78)
}

@Test func normalizedStateKeepsSelectedProcessVisibleInViewport() {
    var sample = makeSample()
    sample.processes = makeProcessFixtures(count: 18)

    let initialState = DashboardRenderState(
        view: .processes,
        processSort: .cpu,
        selectionIndex: 17,
        processScrollOffset: 0,
        networkScrollOffset: 0,
        theme: .light
    )
    let normalized = DashboardRenderer.normalizedState(
        state: initialState,
        sample: sample,
        size: TerminalSize(width: 100, height: 24)
    )
    let output = DashboardRenderer.render(
        sample: sample,
        history: [sample],
        state: normalized,
        size: TerminalSize(width: 100, height: 24),
        status: "ok"
    )

    #expect(normalized.processScrollOffset > 0)
    #expect(output.contains("proc-17"))
    #expect(output.contains("proc-0") == false)
    assertAllLinesFit(output, width: 100)
}

@Test func normalizedStateKeepsSelectedNetworkFlowVisibleAfterCommittedHeightChange() {
    var sample = makeSample()
    sample.network.processes = makeNetworkProcessFixtures(count: 18)

    let initialState = DashboardRenderState(
        view: .network,
        processSort: .cpu,
        selectionIndex: 17,
        processScrollOffset: 0,
        networkScrollOffset: 0,
        theme: .light
    )
    let normalized = DashboardRenderer.normalizedState(
        state: initialState,
        sample: sample,
        size: TerminalSize(width: 100, height: 20)
    )
    let output = DashboardRenderer.render(
        sample: sample,
        history: [sample],
        state: normalized,
        size: TerminalSize(width: 100, height: 20),
        status: "ok"
    )

    #expect(normalized.selectionIndex == 17)
    #expect(normalized.networkScrollOffset > 0)
    #expect(output.contains("flow-17"))
    #expect(output.contains("flow-0") == false)
    assertAllLinesFit(output, width: 100)
}

private func assertAllLinesFit(_ output: String, width: Int) {
    for line in strippingANSIEscapeSequences(output).split(separator: "\n", omittingEmptySubsequences: false) {
        #expect(line.count <= width)
    }
}

private func makeProcessFixtures(count: Int) -> [ProcessSnapshot] {
    var fixtures: [ProcessSnapshot] = []
    fixtures.reserveCapacity(count)

    for index in 0..<count {
        fixtures.append(
            ProcessSnapshot(
                pid: 1000 + index,
                command: "proc-\(index)",
                cpuPercent: Double(count - index),
                memoryBytes: Int64(1_000_000_000 + index),
                cumulativeCPUTime: "00:0\(index).00",
                networkBytesIn: nil,
                networkBytesOut: nil,
                networkInRateBytesPerSec: nil,
                networkOutRateBytesPerSec: nil,
                energyImpact: Double(index),
                gpuTime: Double(index)
            )
        )
    }

    return fixtures
}

private func makeNetworkProcessFixtures(count: Int) -> [NetworkProcessSnapshot] {
    var fixtures: [NetworkProcessSnapshot] = []
    fixtures.reserveCapacity(count)

    for index in 0..<count {
        fixtures.append(
            NetworkProcessSnapshot(
                pid: 2000 + index,
                command: "flow-\(index)",
                bytesIn: Int64(index * 2_000),
                bytesOut: Int64(index * 1_000),
                inRateBytesPerSec: Double(count - index) * 100,
                outRateBytesPerSec: Double(count - index) * 50
            )
        )
    }

    return fixtures
}

private func makeLivePowerHistory(cpuValues: [Double]) -> [SampleEnvelope] {
    cpuValues.enumerated().map { index, cpu in
        var sample = makeSample(
            timestamp: Date(timeIntervalSince1970: Double(index)),
            cpu: cpu,
            freePercent: max(18, 70 - Double(index * 7)),
            swapOutBytes: Int64(index) * 128 * 1_024 * 1_024,
            diskMBPerSec: 12 + Double(index * 6),
            batteryPercentage: 88 - Double(index * 4),
            batteryState: "discharging",
            thermalState: index >= cpuValues.count / 2 ? "Fair" : "Nominal"
        )
        sample.capabilities.isRoot = true
        sample.capabilities.advancedPowerAvailable = true
        sample.cpu.packagePowerWatts = 9 + Double(index) * 2.4
        sample.gpu.powerWatts = 4 + Double(index) * 1.7
        sample.gpu.anePowerWatts = 0.8 + Double(index) * 0.6
        sample.gpu.processMetricsLocked = false
        sample.gpu.lockReason = nil
        return sample
    }
}

private func renderedLineCount(_ output: String) -> Int {
    strippingANSIEscapeSequences(output)
        .trimmingCharacters(in: .newlines)
        .split(separator: "\n", omittingEmptySubsequences: false)
        .count
}

private func occurrenceCount(_ output: String, needle: String) -> Int {
    output.components(separatedBy: needle).count - 1
}

private func lastFooterSeparatorIndex(_ output: String, width: Int) -> Int? {
    let separator = String(repeating: "-", count: width)
    let lines = strippingANSIEscapeSequences(output).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    return lines.lastIndex(of: separator)
}

private func frameLineCount(_ output: String) -> Int {
    frameLines(output).count
}

private func frameLines(_ output: String) -> [String] {
    let visible = strippingANSIEscapeSequences(output)
    let lines = visible.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    if visible.hasSuffix("\n") {
        return Array(lines.dropLast())
    }
    return lines
}

private func containsPartialHistogramGlyph(_ output: String) -> Bool {
    let glyphs = "▁▂▃▄▅▆▇"
    return output.contains { glyphs.contains($0) }
}

private func containsPartialGaugeGlyph(_ output: String) -> Bool {
    let glyphs = "▏▎▍▌▋▊▉"
    return output.contains { glyphs.contains($0) }
}

private func histogramLineCount(_ output: String) -> Int {
    let glyphs = "▁▂▃▄▅▆▇█"
    return frameLines(output).filter { line in
        line.contains { glyphs.contains($0) }
    }.count
}

private func panelStartIndex(_ lines: [String], title: String) -> Int? {
    lines.firstIndex { $0.contains(title) }
}
