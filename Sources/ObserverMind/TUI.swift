import Foundation

final class DashboardApp {
    private let sampler: SystemSampler
    private let intervalSeconds: Int
    private let theme: DashboardTheme

    init(sampler: SystemSampler, intervalSeconds: Int, theme: DashboardTheme) {
        self.sampler = sampler
        self.intervalSeconds = intervalSeconds
        self.theme = theme
    }

    func run() throws {
        let terminal = TerminalController()
        try terminal.prepareInteractiveTerminal()
        defer { terminal.restoreTerminal() }

        var state = DashboardRenderState(theme: theme)
        var resizeCoordinator = DashboardResizeCoordinator()
        var normalizedSampleTimestamp: Date?
        var needsNormalization = true
        let runtime = DashboardRuntimeState()
        runtime.setStatus("Collecting sample...")
        let sampler = self.sampler
        let intervalSeconds = self.intervalSeconds

        let samplingQueue = DispatchQueue(label: "ObserverMind.dashboard.sampling")
        samplingQueue.async {
            var previous: SampleEnvelope?
            while runtime.shouldContinue {
                do {
                    let sample = try sampler.collectSample(previous: previous, intervalSeconds: intervalSeconds)
                    previous = sample
                    runtime.update(with: sample)
                } catch {
                    runtime.setStatus(error.localizedDescription)
                }

                let deadline = Date().addingTimeInterval(Double(intervalSeconds))
                while runtime.shouldContinue, Date() < deadline {
                    if runtime.consumeRefreshTrigger() {
                        break
                    }
                    Thread.sleep(forTimeInterval: 0.05)
                }
            }
        }

        while true {
            let snapshot = runtime.snapshot()
            let resize = resizeCoordinator.update(liveSize: terminal.size())
            let layoutSize = resize.layoutSize
            let viewportSize = resize.viewportSize
            let sampleTimestamp = snapshot.sample?.timestamp

            if sampleTimestamp != normalizedSampleTimestamp {
                needsNormalization = true
            }

            if needsNormalization || resize.committedChanged {
                state = DashboardRenderer.normalizedState(state: state, sample: snapshot.sample, size: layoutSize)
                normalizedSampleTimestamp = sampleTimestamp
                needsNormalization = false
            }

            let frame = DashboardRenderer.render(
                sample: snapshot.sample,
                history: snapshot.history,
                state: state,
                layoutSize: layoutSize,
                viewportSize: viewportSize,
                status: renderStatus(baseStatus: snapshot.status, resize: resize)
            )
            terminal.draw(frame)

            if let key = terminal.pollKey() {
                switch key {
                case .character("q"), .character("Q"), .interrupt:
                    runtime.stop()
                    return
                case .character("1"):
                    state.view = .overview
                    state.selectionIndex = 0
                    needsNormalization = true
                case .character("2"):
                    state.view = .processes
                    state.selectionIndex = 0
                    state.processScrollOffset = 0
                    needsNormalization = true
                case .character("3"):
                    state.view = .network
                    state.selectionIndex = 0
                    state.networkScrollOffset = 0
                    needsNormalization = true
                case .character("4"):
                    state.view = .power
                    state.selectionIndex = 0
                    needsNormalization = true
                case .character("s"), .character("S"):
                    if state.view == .processes {
                        state.processSort = nextSort(after: state.processSort)
                        needsNormalization = true
                    }
                case .character("r"), .character("R"):
                    runtime.triggerImmediateRefresh()
                case .character("j"), .arrowDown:
                    if state.view == .processes || state.view == .network {
                        state.selectionIndex += 1
                        needsNormalization = true
                    }
                case .character("k"), .arrowUp:
                    if state.view == .processes || state.view == .network {
                        state.selectionIndex = max(0, state.selectionIndex - 1)
                        needsNormalization = true
                    }
                case .character("h"), .arrowLeft:
                    state.view = previousView(before: state.view)
                    resetViewportState(for: &state)
                    needsNormalization = true
                case .character("l"), .arrowRight:
                    state.view = nextView(after: state.view)
                    resetViewportState(for: &state)
                    needsNormalization = true
                default:
                    break
                }
            }

            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    private func nextSort(after sort: ProcessSortKey) -> ProcessSortKey {
        let all = ProcessSortKey.allCases
        guard let index = all.firstIndex(of: sort) else { return .cpu }
        return all[(index + 1) % all.count]
    }

    private func previousView(before view: DashboardView) -> DashboardView {
        let all = DashboardView.allCases
        guard let index = all.firstIndex(of: view) else { return .overview }
        return all[(index + all.count - 1) % all.count]
    }

    private func nextView(after view: DashboardView) -> DashboardView {
        let all = DashboardView.allCases
        guard let index = all.firstIndex(of: view) else { return .overview }
        return all[(index + 1) % all.count]
    }

    private func resetViewportState(for state: inout DashboardRenderState) {
        switch state.view {
        case .processes:
            state.selectionIndex = 0
            state.processScrollOffset = 0
        case .network:
            state.selectionIndex = 0
            state.networkScrollOffset = 0
        case .overview, .power:
            state.selectionIndex = 0
        }
    }

    private func renderStatus(baseStatus: String, resize: DashboardResizeUpdate) -> String {
        guard resize.isResizing else {
            return baseStatus
        }
        return "\(baseStatus) | Resizing… \(resize.viewportSize.width)x\(resize.viewportSize.height)"
    }
}

struct DashboardRuntimeSnapshot {
    var sample: SampleEnvelope?
    var history: [SampleEnvelope]
    var status: String
}

final class DashboardRuntimeState: @unchecked Sendable {
    private let lock = NSLock()
    private var sample: SampleEnvelope?
    private var history = SampleRingBuffer(capacity: 3_600)
    private var status = "Collecting sample..."
    private var running = true
    private var forceRefresh = false

    var shouldContinue: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    func snapshot() -> DashboardRuntimeSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return DashboardRuntimeSnapshot(sample: sample, history: history.samples, status: status)
    }

    func update(with sample: SampleEnvelope) {
        lock.lock()
        self.sample = sample
        history.append(sample)
        status = "Updated \(iso8601(sample.timestamp))"
        forceRefresh = false
        lock.unlock()
    }

    func setStatus(_ status: String) {
        lock.lock()
        self.status = status
        lock.unlock()
    }

    func stop() {
        lock.lock()
        running = false
        lock.unlock()
    }

    func triggerImmediateRefresh() {
        lock.lock()
        forceRefresh = true
        lock.unlock()
    }

    func consumeRefreshTrigger() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if forceRefresh {
            forceRefresh = false
            return true
        }
        return false
    }
}

enum DashboardLayoutMode {
    case fallback
    case compact
    case medium
    case wide
}

private struct DashboardLayout {
    var mode: DashboardLayoutMode
    var width: Int
    var height: Int
    var showHelp: Bool
    var alertLimit: Int
    var headerHeight: Int
    var footerHeight: Int
    var bodyHeight: Int
}

private struct ProcessViewLayout {
    var splitDetail: Bool
    var listWidth: Int
    var detailWidth: Int
    var listHeight: Int
    var detailHeight: Int
    var rowCapacity: Int
}

private struct NetworkViewLayout {
    var splitDetail: Bool
    var listWidth: Int
    var detailWidth: Int
    var listHeight: Int
    var detailHeight: Int
    var rowCapacity: Int
}

private struct PanelSpec {
    var title: String
    var width: Int
    var height: Int

    var innerWidth: Int {
        max(width - 2, 1)
    }

    var innerHeight: Int {
        max(height - 2, 1)
    }
}

enum DashboardRenderer {
    static func layoutMode(for size: TerminalSize) -> DashboardLayoutMode {
        layout(for: size, alertCount: 0).mode
    }

    static func normalizedState(
        state: DashboardRenderState,
        sample: SampleEnvelope?,
        size: TerminalSize
    ) -> DashboardRenderState {
        var state = state
        let layout = layout(for: size, alertCount: sample?.alerts.count ?? 0)

        guard let sample else {
            state.selectionIndex = 0
            state.processScrollOffset = 0
            state.networkScrollOffset = 0
            return state
        }

        switch state.view {
        case .processes:
            let processes = sample.processes.sorted(by: state.processSort)
            state.selectionIndex = clamp(state.selectionIndex, lower: 0, upper: max(processes.count - 1, 0))
            let viewLayout = processViewLayout(for: layout)
            state.processScrollOffset = adjustedOffset(
                current: state.processScrollOffset,
                selection: state.selectionIndex,
                rowCapacity: viewLayout.rowCapacity,
                itemCount: processes.count
            )
        case .network:
            let flows = sortedNetworkProcesses(from: sample)
            state.selectionIndex = clamp(state.selectionIndex, lower: 0, upper: max(flows.count - 1, 0))
            let viewLayout = networkViewLayout(for: layout)
            state.networkScrollOffset = adjustedOffset(
                current: state.networkScrollOffset,
                selection: state.selectionIndex,
                rowCapacity: viewLayout.rowCapacity,
                itemCount: flows.count
            )
        case .overview, .power:
            state.selectionIndex = 0
        }

        return state
    }

    static func render(
        sample: SampleEnvelope?,
        history: [SampleEnvelope],
        state: DashboardRenderState,
        size: TerminalSize,
        status: String
    ) -> String {
        render(
            sample: sample,
            history: history,
            state: state,
            layoutSize: size,
            viewportSize: size,
            status: status
        )
    }

    static func render(
        sample: SampleEnvelope?,
        history: [SampleEnvelope],
        state: DashboardRenderState,
        layoutSize: TerminalSize,
        viewportSize: TerminalSize,
        status: String
    ) -> String {
        let layout = layout(for: layoutSize, alertCount: sample?.alerts.count ?? 0)

        if layout.mode == .fallback {
            return finalize(
                lines: fallbackLines(size: layoutSize, status: status),
                width: viewportSize.width,
                height: viewportSize.height
            )
        }

        guard let sample else {
            let header = standardHeader(sample: nil, layout: layout, state: state, status: status)
            let body = loadingBodyLines(state: state, layout: layout)
            return finalize(
                lines: header + Array(body.prefix(layout.bodyHeight)),
                width: viewportSize.width,
                height: viewportSize.height
            )
        }

        let header = standardHeader(sample: sample, layout: layout, state: state, status: status)
        let body = bodyLines(sample: sample, history: history, state: state, layout: layout)
        let footer = footerLines(alerts: sample.alerts, layout: layout)

        return finalize(
            lines: header + Array(body.prefix(layout.bodyHeight)) + footer,
            width: viewportSize.width,
            height: viewportSize.height
        )
    }

    private static func bodyLines(
        sample: SampleEnvelope,
        history: [SampleEnvelope],
        state: DashboardRenderState,
        layout: DashboardLayout
    ) -> [String] {
        switch state.view {
        case .overview:
            return overviewLines(sample: sample, history: history, layout: layout)
        case .processes:
            return processLines(sample: sample, state: state, layout: layout)
        case .network:
            return networkLines(sample: sample, state: state, layout: layout)
        case .power:
            return powerLines(sample: sample, history: history, layout: layout)
        }
    }

    private static func loadingBodyLines(
        state: DashboardRenderState,
        layout: DashboardLayout
    ) -> [String] {
        switch state.view {
        case .overview:
            return loadingOverviewLines(layout: layout)
        case .processes:
            return loadingProcessLines(layout: layout)
        case .network:
            return loadingNetworkLines(layout: layout)
        case .power:
            return loadingPowerLines(layout: layout)
        }
    }

    private static func layout(for size: TerminalSize, alertCount _: Int) -> DashboardLayout {
        let mode: DashboardLayoutMode
        if size.width < 72 || size.height < 18 {
            mode = .fallback
        } else if size.width < 100 || size.height < 24 {
            mode = .compact
        } else if size.width >= 140 && size.height >= 28 {
            mode = .wide
        } else {
            mode = .medium
        }

        if mode == .fallback {
            return DashboardLayout(
                mode: mode,
                width: size.width,
                height: size.height,
                showHelp: false,
                alertLimit: 0,
                headerHeight: 0,
                footerHeight: 0,
                bodyHeight: max(size.height, 1)
            )
        }

        let showHelp = mode != .compact
        let desiredAlertLimit: Int
        switch mode {
        case .compact:
            desiredAlertLimit = 1
        case .medium:
            desiredAlertLimit = 2
        case .wide:
            desiredAlertLimit = 3
        case .fallback:
            desiredAlertLimit = 0
        }

        let alertLimit = desiredAlertLimit
        let headerHeight = showHelp ? 5 : 4
        let footerHeight = alertLimit > 0 ? 1 + alertLimit : 0
        let bodyHeight = max(size.height - headerHeight - footerHeight, 1)

        return DashboardLayout(
            mode: mode,
            width: size.width,
            height: size.height,
            showHelp: showHelp,
            alertLimit: alertLimit,
            headerHeight: headerHeight,
            footerHeight: footerHeight,
            bodyHeight: bodyHeight
        )
    }

    private static func standardHeader(
        sample: SampleEnvelope?,
        layout: DashboardLayout,
        state: DashboardRenderState,
        status: String
    ) -> [String] {
        let banner: String
        if let sample {
            if layout.mode == .compact {
                banner = "ObserverMind  \(sample.host.chip)  macOS \(sample.host.osVersion)"
            } else {
                banner = "ObserverMind  \(sample.host.modelName) / \(sample.host.chip) / macOS \(sample.host.osVersion)"
            }
        } else {
            banner = "ObserverMind"
        }

        let tabs = DashboardView.allCases
            .map { view in
                let label = layout.mode == .compact ? String(view.rawValue.prefix(4)) : view.rawValue
                return view == state.view ? "[\(label)]" : " \(label) "
            }
            .joined(separator: " ")

        var lines = [
            fitLine(banner, width: layout.width),
            fitLine(tabs, width: layout.width),
            fitLine("Status: \(status)", width: layout.width)
        ]

        if layout.showHelp {
            lines.append(fitLine("Keys: 1-4 views | h/l cycle | j/k move | s sort | r refresh | q quit", width: layout.width))
        }

        lines.append(String(repeating: "-", count: layout.width))
        return lines
    }

    private static func footerLines(alerts: [Alert], layout: DashboardLayout) -> [String] {
        guard layout.alertLimit > 0 else {
            return []
        }

        var renderedAlerts = Array(alerts.prefix(layout.alertLimit)).map { alert in
            fitLine("[\(alert.level.rawValue.uppercased())] \(alert.message)", width: layout.width)
        }

        if renderedAlerts.isEmpty {
            renderedAlerts.append(fitLine("[INFO] No active alerts.", width: layout.width))
        }

        while renderedAlerts.count < layout.alertLimit {
            renderedAlerts.append("")
        }

        return [String(repeating: "-", count: layout.width)] + renderedAlerts
    }

    private static func overviewLines(
        sample: SampleEnvelope,
        history: [SampleEnvelope],
        layout: DashboardLayout
    ) -> [String] {
        switch layout.mode {
        case .compact:
            return compactOverviewLines(sample: sample, history: history, layout: layout)
        case .medium, .wide:
            return gridOverviewLines(sample: sample, history: history, layout: layout)
        case .fallback:
            return fallbackLines(size: TerminalSize(width: layout.width, height: layout.height), status: "Loading")
        }
    }

    private static func loadingOverviewLines(layout: DashboardLayout) -> [String] {
        switch layout.mode {
        case .compact:
            let heights = distributeHeights(total: layout.bodyHeight, count: 3)
            return renderPanel(
                title: "Compute",
                width: layout.width,
                height: heights[0],
                content: loadingPanelRows(
                    primary: "Collecting CPU and GPU telemetry...",
                    secondary: "The dashboard will stay in this layout.",
                    width: max(layout.width - 2, 1),
                    height: max(heights[0] - 2, 1)
                )
            ) + renderPanel(
                title: "Memory",
                width: layout.width,
                height: heights[1],
                content: loadingPanelRows(
                    primary: "Collecting memory pressure and swap...",
                    secondary: "Charts will populate on the first sample.",
                    width: max(layout.width - 2, 1),
                    height: max(heights[1] - 2, 1)
                )
            ) + renderPanel(
                title: "I/O + Power",
                width: layout.width,
                height: heights[2],
                content: loadingPanelRows(
                    primary: "Collecting disk, network, battery, and thermal...",
                    secondary: "Live rates appear after the initial pass.",
                    width: max(layout.width - 2, 1),
                    height: max(heights[2] - 2, 1)
                )
            )
        case .medium, .wide:
            let rowHeights = distributeHeights(total: layout.bodyHeight, count: 2)
            let leftWidth = max((layout.width - 2) / 2, 24)
            let rightWidth = max(layout.width - leftWidth - 2, 24)
            let cpu = renderPanel(
                title: "CPU",
                width: leftWidth,
                height: rowHeights[0],
                content: loadingPanelRows(
                    primary: "Collecting CPU and GPU telemetry...",
                    secondary: "Trend history starts with the first sample.",
                    width: max(leftWidth - 2, 1),
                    height: max(rowHeights[0] - 2, 1)
                )
            )
            let memory = renderPanel(
                title: "Memory",
                width: rightWidth,
                height: rowHeights[0],
                content: loadingPanelRows(
                    primary: "Collecting memory pressure and swap...",
                    secondary: "Compression and free memory fill in next.",
                    width: max(rightWidth - 2, 1),
                    height: max(rowHeights[0] - 2, 1)
                )
            )
            let io = renderPanel(
                title: "Network / Disk",
                width: leftWidth,
                height: rowHeights[1],
                content: loadingPanelRows(
                    primary: "Collecting disk and network throughput...",
                    secondary: "Per-process rates will appear shortly.",
                    width: max(leftWidth - 2, 1),
                    height: max(rowHeights[1] - 2, 1)
                )
            )
            let power = renderPanel(
                title: "Power / Thermal",
                width: rightWidth,
                height: rowHeights[1],
                content: loadingPanelRows(
                    primary: "Collecting battery and thermal state...",
                    secondary: "Advanced metrics unlock after sampling.",
                    width: max(rightWidth - 2, 1),
                    height: max(rowHeights[1] - 2, 1)
                )
            )
            return combineColumns(left: cpu, right: memory, leftWidth: leftWidth, rightWidth: rightWidth)
                + combineColumns(left: io, right: power, leftWidth: leftWidth, rightWidth: rightWidth)
        case .fallback:
            return fallbackLines(size: TerminalSize(width: layout.width, height: layout.height), status: "Collecting initial sample...")
        }
    }

    private static func compactOverviewLines(
        sample: SampleEnvelope,
        history: [SampleEnvelope],
        layout: DashboardLayout
    ) -> [String] {
        let heights = distributeHeights(total: layout.bodyHeight, count: 3)
        let compute = PanelSpec(title: "Compute", width: layout.width, height: heights[0])
        let memory = PanelSpec(title: "Memory", width: layout.width, height: heights[1])
        let ioPower = PanelSpec(title: "I/O + Power", width: layout.width, height: heights[2])

        return renderPanel(
            title: compute.title,
            width: compute.width,
            height: compute.height,
            content: compactComputePanelRows(sample: sample, history: history, width: compute.innerWidth, height: compute.innerHeight)
        ) + renderPanel(
            title: memory.title,
            width: memory.width,
            height: memory.height,
            content: compactMemoryPanelRows(sample: sample, history: history, width: memory.innerWidth, height: memory.innerHeight)
        ) + renderPanel(
            title: ioPower.title,
            width: ioPower.width,
            height: ioPower.height,
            content: compactIOPowerPanelRows(sample: sample, history: history, width: ioPower.innerWidth, height: ioPower.innerHeight)
        )
    }

    private static func gridOverviewLines(
        sample: SampleEnvelope,
        history: [SampleEnvelope],
        layout: DashboardLayout
    ) -> [String] {
        let rowHeights = distributeHeights(total: layout.bodyHeight, count: 2)
        let leftWidth = max((layout.width - 2) / 2, 24)
        let rightWidth = max(layout.width - leftWidth - 2, 24)
        let isWide = layout.mode == .wide

        let cpu = renderPanel(
            title: "CPU",
            width: leftWidth,
            height: rowHeights[0],
            content: cpuPanelRows(sample: sample, history: history, width: leftWidth - 2, height: rowHeights[0] - 2, isWide: isWide)
        )
        let memory = renderPanel(
            title: "Memory",
            width: rightWidth,
            height: rowHeights[0],
            content: memoryPanelRows(sample: sample, history: history, width: rightWidth - 2, height: rowHeights[0] - 2, isWide: isWide)
        )
        let io = renderPanel(
            title: "Network / Disk",
            width: leftWidth,
            height: rowHeights[1],
            content: ioPanelRows(sample: sample, history: history, width: leftWidth - 2, height: rowHeights[1] - 2, isWide: isWide)
        )
        let power = renderPanel(
            title: "Power / Thermal",
            width: rightWidth,
            height: rowHeights[1],
            content: powerThermalPanelRows(sample: sample, history: history, width: rightWidth - 2, height: rowHeights[1] - 2, isWide: isWide)
        )

        return combineColumns(left: cpu, right: memory, leftWidth: leftWidth, rightWidth: rightWidth)
            + combineColumns(left: io, right: power, leftWidth: leftWidth, rightWidth: rightWidth)
    }

    private static func processLines(
        sample: SampleEnvelope,
        state: DashboardRenderState,
        layout: DashboardLayout
    ) -> [String] {
        let processes = sample.processes.sorted(by: state.processSort)
        guard processes.isEmpty == false else {
            return ["Processes", "No process data available."]
        }

        let viewLayout = processViewLayout(for: layout)
        let rangeStart = min(state.processScrollOffset, max(processes.count - viewLayout.rowCapacity, 0))
        let rangeEnd = min(rangeStart + viewLayout.rowCapacity, processes.count)
        let visible = Array(processes[rangeStart..<rangeEnd])
        let selected = processes[state.selectionIndex]
        let listPanel = renderPanel(
            title: "Processes",
            width: viewLayout.listWidth,
            height: viewLayout.listHeight,
            content: processListPanelRows(
                processes: processes,
                visible: visible,
                selectedIndex: state.selectionIndex,
                rangeStart: rangeStart,
                sort: state.processSort,
                width: max(viewLayout.listWidth - 2, 1)
            )
        )
        let detailPanel = renderPanel(
            title: "Selected Process",
            width: viewLayout.detailWidth,
            height: viewLayout.detailHeight,
            content: processDetailPanelRows(
                process: selected,
                allProcesses: processes,
                sample: sample,
                width: max(viewLayout.detailWidth - 2, 1),
                height: max(viewLayout.detailHeight - 2, 1)
            )
        )

        if viewLayout.splitDetail {
            return combineColumns(
                left: listPanel,
                right: detailPanel,
                leftWidth: viewLayout.listWidth,
                rightWidth: viewLayout.detailWidth
            )
        }

        var lines = listPanel
        if viewLayout.detailHeight > 0 {
            lines.append(contentsOf: detailPanel)
        }
        return lines
    }

    private static func loadingProcessLines(layout: DashboardLayout) -> [String] {
        let viewLayout = processViewLayout(for: layout)
        let listPanel = renderPanel(
            title: "Processes",
            width: viewLayout.listWidth,
            height: viewLayout.listHeight,
            content: loadingPanelRows(
                primary: "Collecting top process list...",
                secondary: "CPU, memory, energy, and network bars follow.",
                width: max(viewLayout.listWidth - 2, 1),
                height: max(viewLayout.listHeight - 2, 1)
            )
        )
        let detailPanel = renderPanel(
            title: "Selected Process",
            width: viewLayout.detailWidth,
            height: viewLayout.detailHeight,
            content: loadingPanelRows(
                primary: "Waiting for process detail...",
                secondary: "Selection stays anchored after sampling.",
                width: max(viewLayout.detailWidth - 2, 1),
                height: max(viewLayout.detailHeight - 2, 1)
            )
        )

        if viewLayout.splitDetail {
            return combineColumns(
                left: listPanel,
                right: detailPanel,
                leftWidth: viewLayout.listWidth,
                rightWidth: viewLayout.detailWidth
            )
        }

        var lines = listPanel
        if viewLayout.detailHeight > 0 {
            lines.append(contentsOf: detailPanel)
        }
        return lines
    }

    private static func networkLines(
        sample: SampleEnvelope,
        state: DashboardRenderState,
        layout: DashboardLayout
    ) -> [String] {
        let processes = sortedNetworkProcesses(from: sample)
        guard processes.isEmpty == false else {
            return ["Network", "No network data available."]
        }

        let viewLayout = networkViewLayout(for: layout)
        let rangeStart = min(state.networkScrollOffset, max(processes.count - viewLayout.rowCapacity, 0))
        let rangeEnd = min(rangeStart + viewLayout.rowCapacity, processes.count)
        let visible = Array(processes[rangeStart..<rangeEnd])
        let selected = processes[state.selectionIndex]
        let listPanel = renderPanel(
            title: "Network",
            width: viewLayout.listWidth,
            height: viewLayout.listHeight,
            content: networkListPanelRows(
                sample: sample,
                processes: processes,
                visible: visible,
                selectedIndex: state.selectionIndex,
                rangeStart: rangeStart,
                width: max(viewLayout.listWidth - 2, 1)
            )
        )
        let detailPanel = renderPanel(
            title: "Selected Flow",
            width: viewLayout.detailWidth,
            height: viewLayout.detailHeight,
            content: networkDetailPanelRows(
                process: selected,
                allProcesses: processes,
                sample: sample,
                width: max(viewLayout.detailWidth - 2, 1),
                height: max(viewLayout.detailHeight - 2, 1)
            )
        )

        if viewLayout.splitDetail {
            return combineColumns(
                left: listPanel,
                right: detailPanel,
                leftWidth: viewLayout.listWidth,
                rightWidth: viewLayout.detailWidth
            )
        }

        var lines = listPanel
        if viewLayout.detailHeight > 0 {
            lines.append(contentsOf: detailPanel)
        }
        return lines
    }

    private static func loadingNetworkLines(layout: DashboardLayout) -> [String] {
        let viewLayout = networkViewLayout(for: layout)
        let listPanel = renderPanel(
            title: "Network",
            width: viewLayout.listWidth,
            height: viewLayout.listHeight,
            content: loadingPanelRows(
                primary: "Collecting top network flows...",
                secondary: "Inbound and outbound rates appear shortly.",
                width: max(viewLayout.listWidth - 2, 1),
                height: max(viewLayout.listHeight - 2, 1)
            )
        )
        let detailPanel = renderPanel(
            title: "Selected Flow",
            width: viewLayout.detailWidth,
            height: viewLayout.detailHeight,
            content: loadingPanelRows(
                primary: "Waiting for flow detail...",
                secondary: "Per-flow gauges fill in after the first pass.",
                width: max(viewLayout.detailWidth - 2, 1),
                height: max(viewLayout.detailHeight - 2, 1)
            )
        )

        if viewLayout.splitDetail {
            return combineColumns(
                left: listPanel,
                right: detailPanel,
                leftWidth: viewLayout.listWidth,
                rightWidth: viewLayout.detailWidth
            )
        }

        var lines = listPanel
        if viewLayout.detailHeight > 0 {
            lines.append(contentsOf: detailPanel)
        }
        return lines
    }

    private static func powerLines(
        sample: SampleEnvelope,
        history: [SampleEnvelope],
        layout: DashboardLayout
    ) -> [String] {
        switch layout.mode {
        case .compact:
            let heights = distributeHeights(total: layout.bodyHeight, count: 3)
            let trend = renderPanel(
                title: "Power Trend",
                width: layout.width,
                height: heights[0],
                content: powerTrendPanelRows(sample: sample, history: history, width: layout.width - 2, height: heights[0] - 2, isWide: false)
            )
            let battery = renderPanel(
                title: "Battery / Thermal",
                width: layout.width,
                height: heights[1],
                content: batteryThermalPanelRows(sample: sample, history: history, width: layout.width - 2, height: heights[1] - 2)
            )
            let advanced = renderPanel(
                title: "Advanced Metrics",
                width: layout.width,
                height: heights[2],
                content: advancedMetricsPanelRows(sample: sample, width: layout.width - 2, height: heights[2] - 2)
            )
            return trend + battery + advanced
        case .medium, .wide:
            let leftWidth = max((layout.width * 3) / 5, 36)
            let rightWidth = max(layout.width - leftWidth - 2, 28)
            let rightHeights = distributeHeights(total: layout.bodyHeight, count: 2)
            let left = renderPanel(
                title: "Power Trend",
                width: leftWidth,
                height: layout.bodyHeight,
                content: powerTrendPanelRows(sample: sample, history: history, width: leftWidth - 2, height: layout.bodyHeight - 2, isWide: layout.mode == .wide)
            )
            let right = renderPanel(
                title: "Battery / Thermal",
                width: rightWidth,
                height: rightHeights[0],
                content: batteryThermalPanelRows(sample: sample, history: history, width: rightWidth - 2, height: rightHeights[0] - 2)
            ) + renderPanel(
                title: "Advanced Metrics",
                width: rightWidth,
                height: rightHeights[1],
                content: advancedMetricsPanelRows(sample: sample, width: rightWidth - 2, height: rightHeights[1] - 2)
            )
            return combineColumns(left: left, right: right, leftWidth: leftWidth, rightWidth: rightWidth)
        case .fallback:
            return fallbackLines(size: TerminalSize(width: layout.width, height: layout.height), status: "Loading")
        }
    }

    private static func loadingPowerLines(layout: DashboardLayout) -> [String] {
        switch layout.mode {
        case .compact:
            let heights = distributeHeights(total: layout.bodyHeight, count: 3)
            let trend = renderPanel(
                title: "Power Trend",
                width: layout.width,
                height: heights[0],
                content: loadingPanelRows(
                    primary: "Collecting package, GPU, and ANE power...",
                    secondary: "Trend strips start on the first sample.",
                    width: max(layout.width - 2, 1),
                    height: max(heights[0] - 2, 1)
                )
            )
            let battery = renderPanel(
                title: "Battery / Thermal",
                width: layout.width,
                height: heights[1],
                content: loadingPanelRows(
                    primary: "Collecting battery and thermal state...",
                    secondary: "Current source and remaining time follow.",
                    width: max(layout.width - 2, 1),
                    height: max(heights[1] - 2, 1)
                )
            )
            let advanced = renderPanel(
                title: "Advanced Metrics",
                width: layout.width,
                height: heights[2],
                content: loadingPanelRows(
                    primary: "Checking advanced power capability...",
                    secondary: "Locked or live status appears after sampling.",
                    width: max(layout.width - 2, 1),
                    height: max(heights[2] - 2, 1)
                )
            )
            return trend + battery + advanced
        case .medium, .wide:
            let leftWidth = max((layout.width * 3) / 5, 36)
            let rightWidth = max(layout.width - leftWidth - 2, 28)
            let rightHeights = distributeHeights(total: layout.bodyHeight, count: 2)
            let left = renderPanel(
                title: "Power Trend",
                width: leftWidth,
                height: layout.bodyHeight,
                content: loadingPanelRows(
                    primary: "Collecting package, GPU, and ANE power...",
                    secondary: "Trend history starts with the first sample.",
                    width: max(leftWidth - 2, 1),
                    height: max(layout.bodyHeight - 2, 1)
                )
            )
            let right = renderPanel(
                title: "Battery / Thermal",
                width: rightWidth,
                height: rightHeights[0],
                content: loadingPanelRows(
                    primary: "Collecting battery and thermal state...",
                    secondary: "Current levels will populate shortly.",
                    width: max(rightWidth - 2, 1),
                    height: max(rightHeights[0] - 2, 1)
                )
            ) + renderPanel(
                title: "Advanced Metrics",
                width: rightWidth,
                height: rightHeights[1],
                content: loadingPanelRows(
                    primary: "Checking advanced power capability...",
                    secondary: "Privilege status follows after sampling.",
                    width: max(rightWidth - 2, 1),
                    height: max(rightHeights[1] - 2, 1)
                )
            )
            return combineColumns(left: left, right: right, leftWidth: leftWidth, rightWidth: rightWidth)
        case .fallback:
            return fallbackLines(size: TerminalSize(width: layout.width, height: layout.height), status: "Collecting initial sample...")
        }
    }

    private static func processViewLayout(for layout: DashboardLayout) -> ProcessViewLayout {
        switch layout.mode {
        case .wide:
            let detailWidth = max(36, min(48, layout.width / 3))
            let listWidth = max(layout.width - detailWidth - 2, 52)
            return ProcessViewLayout(
                splitDetail: true,
                listWidth: listWidth,
                detailWidth: detailWidth,
                listHeight: layout.bodyHeight,
                detailHeight: layout.bodyHeight,
                rowCapacity: max(layout.bodyHeight - 3, 1)
            )
        case .medium:
            let detailWidth = max(34, min(42, layout.width / 3))
            let listWidth = max(layout.width - detailWidth - 2, 44)
            return ProcessViewLayout(
                splitDetail: true,
                listWidth: listWidth,
                detailWidth: detailWidth,
                listHeight: layout.bodyHeight,
                detailHeight: layout.bodyHeight,
                rowCapacity: max(layout.bodyHeight - 3, 1)
            )
        case .compact:
            let detailHeight = layout.bodyHeight >= 14 ? 6 : 0
            let listHeight = max(layout.bodyHeight - detailHeight, 5)
            return ProcessViewLayout(
                splitDetail: false,
                listWidth: layout.width,
                detailWidth: layout.width,
                listHeight: listHeight,
                detailHeight: detailHeight,
                rowCapacity: max(listHeight - 3, 1)
            )
        case .fallback:
            return ProcessViewLayout(splitDetail: false, listWidth: layout.width, detailWidth: layout.width, listHeight: layout.bodyHeight, detailHeight: 0, rowCapacity: 1)
        }
    }

    private static func networkViewLayout(for layout: DashboardLayout) -> NetworkViewLayout {
        switch layout.mode {
        case .wide:
            let detailWidth = max(36, min(46, layout.width / 3))
            let listWidth = max(layout.width - detailWidth - 2, 50)
            return NetworkViewLayout(
                splitDetail: true,
                listWidth: listWidth,
                detailWidth: detailWidth,
                listHeight: layout.bodyHeight,
                detailHeight: layout.bodyHeight,
                rowCapacity: max(layout.bodyHeight - 3, 1)
            )
        case .medium:
            let detailWidth = max(34, min(42, layout.width / 3))
            let listWidth = max(layout.width - detailWidth - 2, 42)
            return NetworkViewLayout(
                splitDetail: true,
                listWidth: listWidth,
                detailWidth: detailWidth,
                listHeight: layout.bodyHeight,
                detailHeight: layout.bodyHeight,
                rowCapacity: max(layout.bodyHeight - 3, 1)
            )
        case .compact:
            let detailHeight = layout.bodyHeight >= 14 ? 6 : 0
            let listHeight = max(layout.bodyHeight - detailHeight, 5)
            return NetworkViewLayout(
                splitDetail: false,
                listWidth: layout.width,
                detailWidth: layout.width,
                listHeight: listHeight,
                detailHeight: detailHeight,
                rowCapacity: max(listHeight - 3, 1)
            )
        case .fallback:
            return NetworkViewLayout(splitDetail: false, listWidth: layout.width, detailWidth: layout.width, listHeight: layout.bodyHeight, detailHeight: 0, rowCapacity: 1)
        }
    }
}

private func compactComputePanelRows(
    sample: SampleEnvelope,
    history: [SampleEnvelope],
    width: Int,
    height: Int
) -> [String] {
    [
        fitLine("CPU \(formatPercent(sample.totalCPUPercent))  load \(formatNumber(sample.cpu.loadAverage1m))/\(formatNumber(sample.cpu.loadAverage5m))", width: width),
        fitLine("Idle \(formatPercent(sample.cpu.idlePercent))  pkg \(formatWatts(sample.cpu.packagePowerWatts))", width: width),
        fitLine("cpu " + trendStrip(values: history.map(\.totalCPUPercent), maxWidth: max(width - 4, 8)), width: width),
        fitLine("gpu " + trendStrip(values: history.compactMap { $0.gpu.powerWatts }, maxWidth: max(width - 4, 8)), width: width)
    ].prefix(height).map { $0 }
}

private func combineColumns(left: [String], right: [String], leftWidth: Int, rightWidth: Int, gap: Int = 2) -> [String] {
    let lineCount = max(left.count, right.count)
    let spacer = String(repeating: " ", count: gap)
    return (0..<lineCount).map { index in
        let leftLine = index < left.count ? padOrTrim(left[index], width: leftWidth) : String(repeating: " ", count: leftWidth)
        let rightLine = index < right.count ? padOrTrim(right[index], width: rightWidth) : String(repeating: " ", count: rightWidth)
        return leftLine + spacer + rightLine
    }
}

private func compactMemoryPanelRows(
    sample: SampleEnvelope,
    history: [SampleEnvelope],
    width: Int,
    height: Int
) -> [String] {
    [
        fitLine("Used \(formatBytes(sample.memory.usedBytes)) / \(formatBytes(sample.memory.totalBytes))", width: width),
        fitLine("Free \(formatBytes(sample.memory.freeBytes))  Wired \(formatBytes(sample.memory.wiredBytes))", width: width),
        fitLine("mem " + trendStrip(values: history.compactMap { $0.memory.freePercent }, maxWidth: max(width - 4, 8)), width: width),
        fitLine("Comp \(formatBytes(sample.memory.compressedBytes))  Swap \(formatBytes(sample.memory.swapOutBytes))", width: width)
    ].prefix(height).map { $0 }
}

private func compactIOPowerPanelRows(
    sample: SampleEnvelope,
    history: [SampleEnvelope],
    width: Int,
    height: Int
) -> [String] {
    let totalNetwork = history.map { ($0.network.totalInRateBytesPerSec ?? 0) + ($0.network.totalOutRateBytesPerSec ?? 0) }
    return [
        fitLine("Net \(formatRateBytes(sample.network.totalInRateBytesPerSec)) in  \(formatRateBytes(sample.network.totalOutRateBytesPerSec)) out", width: width),
        fitLine("Disk \(formatRateMB(sample.disk.totalMBPerSec))  Batt \(formatOptionalPercent(sample.battery.percentage))", width: width),
        fitLine("io  " + trendStrip(values: totalNetwork, maxWidth: max(width - 4, 8)), width: width),
        fitLine("Thermal \(sample.thermal.state)  GPU \(fitLine(sample.gpu.model ?? "Unknown", width: max(width - 19, 8)))", width: width)
    ].prefix(height).map { $0 }
}

private func cpuPanelRows(
    sample: SampleEnvelope,
    history: [SampleEnvelope],
    width: Int,
    height: Int,
    isWide: Bool
) -> [String] {
    let textRows = [
        fitLine("Total \(formatPercent(sample.totalCPUPercent))  Idle \(formatPercent(sample.cpu.idlePercent))", width: width),
        fitLine("User \(formatPercent(sample.cpu.userPercent))  Sys \(formatPercent(sample.cpu.systemPercent))", width: width),
        fitLine("Load \(formatNumber(sample.cpu.loadAverage1m)) / \(formatNumber(sample.cpu.loadAverage5m)) / \(formatNumber(sample.cpu.loadAverage15m))", width: width)
    ] + (isWide ? [fitLine("Pkg \(formatWatts(sample.cpu.packagePowerWatts))", width: width)] : [])
    return panelRowsWithChart(staticRows: textRows, chartValues: history.map(\.totalCPUPercent), width: width, height: height)
}

private func memoryPanelRows(
    sample: SampleEnvelope,
    history: [SampleEnvelope],
    width: Int,
    height: Int,
    isWide: Bool
) -> [String] {
    let textRows = [
        fitLine("Used \(formatBytes(sample.memory.usedBytes)) / \(formatBytes(sample.memory.totalBytes))", width: width),
        fitLine("Free \(formatBytes(sample.memory.freeBytes))  \(formatOptionalPercent(sample.memory.freePercent))", width: width),
        fitLine("Wired \(formatBytes(sample.memory.wiredBytes))  Compr \(formatBytes(sample.memory.compressedBytes))", width: width)
    ] + (isWide ? [fitLine("Swap in \(formatBytes(sample.memory.swapInBytes))  out \(formatBytes(sample.memory.swapOutBytes))", width: width)] : [])
    return panelRowsWithChart(staticRows: textRows, chartValues: history.compactMap { $0.memory.freePercent }, width: width, height: height)
}

private func ioPanelRows(
    sample: SampleEnvelope,
    history: [SampleEnvelope],
    width: Int,
    height: Int,
    isWide: Bool
) -> [String] {
    let networkHistory = history.map { ($0.network.totalInRateBytesPerSec ?? 0) + ($0.network.totalOutRateBytesPerSec ?? 0) }
    let diskHistory = history.map(\.disk.totalMBPerSec)
    var rows = [
        fitLine("Net \(formatRateBytes(sample.network.totalInRateBytesPerSec)) in  \(formatRateBytes(sample.network.totalOutRateBytesPerSec)) out", width: width),
        fitLine("Disk \(formatRateMB(sample.disk.readMBPerSec)) read  \(formatRateMB(sample.disk.writeMBPerSec)) write", width: width),
        fitLine("net " + trendStrip(values: networkHistory, maxWidth: max(width - 4, 8)), width: width),
        fitLine("io  " + trendStrip(values: diskHistory, maxWidth: max(width - 4, 8)), width: width)
    ]
    if isWide {
        rows.append(fitLine("Totals \(formatBytes(sample.network.totalBytesIn)) in / \(formatBytes(sample.network.totalBytesOut)) out", width: width))
    }
    return Array(rows.prefix(height))
}

private func powerThermalPanelRows(
    sample: SampleEnvelope,
    history: [SampleEnvelope],
    width: Int,
    height: Int,
    isWide: Bool
) -> [String] {
    var rows = [
        fitLine("Battery \(formatOptionalPercent(sample.battery.percentage)) \(sample.battery.state)", width: width),
        fitLine("Thermal \(sample.thermal.state)", width: width),
        fitLine("cpu " + trendStrip(values: history.compactMap { $0.cpu.packagePowerWatts }, maxWidth: max(width - 4, 8)), width: width),
        fitLine("gpu " + trendStrip(values: history.compactMap { $0.gpu.powerWatts }, maxWidth: max(width - 4, 8)), width: width)
    ]
    if isWide {
        rows.append(fitLine("ANE \(formatWatts(sample.gpu.anePowerWatts))  Remaining \(sample.battery.timeRemaining ?? "n/a")", width: width))
    }
    return Array(rows.prefix(height))
}

private func processListPanelRows(
    processes: [ProcessSnapshot],
    visible: [ProcessSnapshot],
    selectedIndex: Int,
    rangeStart: Int,
    sort: ProcessSortKey,
    width: Int
) -> [String] {
    let scaleMax = processScaleMax(processes: processes, sort: sort)
    let header = fitLine("ranked by \(sort.rawValue)  \(selectedIndex + 1)/\(processes.count)", width: width)
    return [header] + visible.enumerated().map { offset, process in
        let isSelected = rangeStart + offset == selectedIndex
        return rankedProcessRow(
            process: process,
            isSelected: isSelected,
            sort: sort,
            scaleMax: scaleMax,
            width: width
        )
    }
}

private func processDetailPanelRows(
    process: ProcessSnapshot,
    allProcesses: [ProcessSnapshot],
    sample: SampleEnvelope,
    width: Int,
    height: Int
) -> [String] {
    let maxNetwork = max(allProcesses.map(processNetworkRate).max() ?? 0, 1)
    let maxEnergy = max(allProcesses.compactMap(\.energyImpact).max() ?? 0, 1)
    let maxGPU = max(allProcesses.compactMap(\.gpuTime).max() ?? 0, 1)
    let totalMemory = Double(max(sample.memory.totalBytes ?? 1, 1))
    var rows = wrapText("\(process.command) • pid \(process.pid)", width: width, maxLines: min(2, height))
    let gauges = [
        metricGaugeLine(label: "CPU", value: formatOptionalPercent(process.cpuPercent), ratio: (process.cpuPercent ?? 0) / 100, width: width),
        metricGaugeLine(label: "MEM", value: formatBytes(process.memoryBytes), ratio: Double(process.memoryBytes ?? 0) / totalMemory, width: width),
        metricGaugeLine(label: "NET", value: formatRateBytes(processNetworkRate(process)), ratio: processNetworkRate(process) / maxNetwork, width: width),
        metricGaugeLine(label: "ENG", value: formatNumber(process.energyImpact), ratio: (process.energyImpact ?? 0) / maxEnergy, width: width),
        metricGaugeLine(label: "GPU", value: formatNumber(process.gpuTime), ratio: (process.gpuTime ?? 0) / maxGPU, width: width),
        fitLine("Time \(process.cumulativeCPUTime ?? "n/a")", width: width)
    ]
    rows.append(contentsOf: gauges)
    return Array(rows.prefix(height))
}

private func finalize(lines: [String], width: Int, height: Int) -> String {
    let targetHeight = max(height, 1)
    var frameLines = Array(lines.prefix(targetHeight))
    while frameLines.count < targetHeight {
        frameLines.append("")
    }

    return frameLines
        .map { padOrTrim($0, width: width) }
        .joined(separator: "\n")
}

private func fallbackLines(size: TerminalSize, status: String) -> [String] {
    [
        fitLine("ObserverMind", width: size.width),
        "",
        fitLine("Terminal too small for the dashboard.", width: size.width),
        fitLine("Current size: \(size.width)x\(size.height)", width: size.width),
        fitLine("Resize to at least 72x18.", width: size.width),
        "",
        fitLine("Status: \(status)", width: size.width)
    ]
}

private func powerTrendPanelRows(
    sample: SampleEnvelope,
    history: [SampleEnvelope],
    width: Int,
    height: Int,
    isWide: Bool
) -> [String] {
    var rows = [
        fitLine("Pkg \(formatWatts(sample.cpu.packagePowerWatts))  GPU \(formatWatts(sample.gpu.powerWatts))  ANE \(formatWatts(sample.gpu.anePowerWatts))", width: width),
        fitLine("cpu " + trendStrip(values: history.compactMap { $0.cpu.packagePowerWatts }, maxWidth: max(width - 4, 8)), width: width),
        fitLine("gpu " + trendStrip(values: history.compactMap { $0.gpu.powerWatts }, maxWidth: max(width - 4, 8)), width: width),
        fitLine("ane " + trendStrip(values: history.compactMap { $0.gpu.anePowerWatts }, maxWidth: max(width - 4, 8)), width: width)
    ]
    if isWide {
        rows.append(fitLine("CPU total \(formatPercent(sample.totalCPUPercent))", width: width))
    }
    return Array(rows.prefix(height))
}

private func batteryThermalPanelRows(
    sample: SampleEnvelope,
    history: [SampleEnvelope],
    width: Int,
    height: Int
) -> [String] {
    let batteryRatio = (sample.battery.percentage ?? 0) / 100
    var rows = [
        fitLine("Battery \(formatOptionalPercent(sample.battery.percentage)) \(sample.battery.state)", width: width),
        metricGaugeLine(label: "BATT", value: formatOptionalPercent(sample.battery.percentage), ratio: batteryRatio, width: width),
        fitLine("Thermal \(sample.thermal.state)", width: width),
        fitLine("Source \(sample.battery.powerSource)", width: width)
    ]
    let batteryHistory = history.compactMap { $0.battery.percentage }
    if height > 4 {
        rows.append(fitLine("hist " + trendStrip(values: batteryHistory, maxWidth: max(width - 5, 8)), width: width))
    }
    if height > 5 {
        rows.append(fitLine("Remaining \(sample.battery.timeRemaining ?? "n/a")", width: width))
    }
    return Array(rows.prefix(height))
}

private func advancedMetricsPanelRows(
    sample: SampleEnvelope,
    width: Int,
    height: Int
) -> [String] {
    var rows = [
        fitLine("Status " + (sample.gpu.processMetricsLocked ? "locked" : "available"), width: width)
    ]
    let message = sample.gpu.processMetricsLocked
        ? (sample.gpu.lockReason ?? sample.capabilities.relaunchHint)
        : "Per-process energy and GPU metrics are live. Open Processes to inspect current bars."
    rows.append(contentsOf: wrapText(message, width: width, maxLines: max(height - rows.count, 0)))
    return Array(rows.prefix(height))
}

private func networkListPanelRows(
    sample: SampleEnvelope,
    processes: [NetworkProcessSnapshot],
    visible: [NetworkProcessSnapshot],
    selectedIndex: Int,
    rangeStart: Int,
    width: Int
) -> [String] {
    let header = fitLine("top talkers  \(formatRateBytes(sample.network.totalInRateBytesPerSec)) in / \(formatRateBytes(sample.network.totalOutRateBytesPerSec)) out", width: width)
    let scaleMax = max(processes.map(networkTotalRate).max() ?? 0, 1)
    return [header] + visible.enumerated().map { offset, process in
        let isSelected = rangeStart + offset == selectedIndex
        return rankedNetworkRow(process: process, isSelected: isSelected, scaleMax: scaleMax, width: width)
    }
}

private func networkDetailPanelRows(
    process: NetworkProcessSnapshot,
    allProcesses: [NetworkProcessSnapshot],
    sample: SampleEnvelope,
    width: Int,
    height: Int
) -> [String] {
    let maxInRate = max(allProcesses.compactMap(\.inRateBytesPerSec).max() ?? 0, 1)
    let maxOutRate = max(allProcesses.compactMap(\.outRateBytesPerSec).max() ?? 0, 1)
    let totalIn = Double(max(sample.network.totalBytesIn, 1))
    let totalOut = Double(max(sample.network.totalBytesOut, 1))
    var rows = wrapText("\(process.command) • pid \(process.pid.map(String.init) ?? "-")", width: width, maxLines: min(2, height))
    rows.append(metricGaugeLine(label: "IN", value: formatRateBytes(process.inRateBytesPerSec), ratio: (process.inRateBytesPerSec ?? 0) / maxInRate, width: width))
    rows.append(metricGaugeLine(label: "OUT", value: formatRateBytes(process.outRateBytesPerSec), ratio: (process.outRateBytesPerSec ?? 0) / maxOutRate, width: width))
    rows.append(metricGaugeLine(label: "TIN", value: formatBytes(process.bytesIn), ratio: Double(process.bytesIn) / totalIn, width: width))
    rows.append(metricGaugeLine(label: "TOUT", value: formatBytes(process.bytesOut), ratio: Double(process.bytesOut) / totalOut, width: width))
    return Array(rows.prefix(height))
}

private func processScaleMax(processes: [ProcessSnapshot], sort: ProcessSortKey) -> Double {
    switch sort {
    case .cpu:
        return 100
    case .memory:
        return max(processes.map { Double($0.memoryBytes ?? 0) }.max() ?? 0, 1)
    case .energy:
        return max(processes.compactMap(\.energyImpact).max() ?? 0, 1)
    case .gpu:
        return max(processes.compactMap(\.gpuTime).max() ?? 0, 1)
    case .network:
        return max(processes.map(processNetworkRate).max() ?? 0, 1)
    }
}

private func processMetricValue(_ process: ProcessSnapshot, sort: ProcessSortKey) -> Double {
    switch sort {
    case .cpu:
        return process.cpuPercent ?? 0
    case .memory:
        return Double(process.memoryBytes ?? 0)
    case .energy:
        return process.energyImpact ?? 0
    case .gpu:
        return process.gpuTime ?? 0
    case .network:
        return processNetworkRate(process)
    }
}

private func processMetricDisplay(_ process: ProcessSnapshot, sort: ProcessSortKey) -> String {
    switch sort {
    case .cpu:
        return formatOptionalPercent(process.cpuPercent)
    case .memory:
        return formatBytes(process.memoryBytes)
    case .energy:
        return formatNumber(process.energyImpact)
    case .gpu:
        return formatNumber(process.gpuTime)
    case .network:
        return formatRateBytes(processNetworkRate(process))
    }
}

private func processNetworkRate(_ process: ProcessSnapshot) -> Double {
    (process.networkInRateBytesPerSec ?? 0) + (process.networkOutRateBytesPerSec ?? 0)
}

private func networkTotalRate(_ process: NetworkProcessSnapshot) -> Double {
    (process.inRateBytesPerSec ?? 0) + (process.outRateBytesPerSec ?? 0)
}

private func rankedProcessRow(
    process: ProcessSnapshot,
    isSelected: Bool,
    sort: ProcessSortKey,
    scaleMax: Double,
    width: Int
) -> String {
    let value = processMetricValue(process, sort: sort)
    let display = processMetricDisplay(process, sort: sort)
    let label = "\(isSelected ? "›" : " ") \(process.pid) \(process.command)"
    return rankedBarRow(label: label, value: display, ratio: value / max(scaleMax, 1), width: width)
}

private func rankedNetworkRow(
    process: NetworkProcessSnapshot,
    isSelected: Bool,
    scaleMax: Double,
    width: Int
) -> String {
    let label = "\(isSelected ? "›" : " ") \(process.pid.map(String.init) ?? "-") \(process.command)"
    return rankedBarRow(label: label, value: formatRateBytes(networkTotalRate(process)), ratio: networkTotalRate(process) / max(scaleMax, 1), width: width)
}

private func rankedBarRow(label: String, value: String, ratio: Double, width: Int) -> String {
    let barWidth = clamp(width / 4, lower: 8, upper: 14)
    let valueWidth = max(min(max(value.count, 5), max(width / 5, 6)), 5)
    let labelWidth = max(width - barWidth - valueWidth - 2, 10)
    return padOrTrim(label, width: labelWidth)
        + " "
        + padOrTrim(value, width: valueWidth)
        + " "
        + gaugeBar(ratio: ratio, width: barWidth)
}

private func renderPanel(title: String, width: Int, height: Int, content: [String]) -> [String] {
    guard width >= 3, height >= 3 else {
        return Array(content.prefix(max(height, 1))).map { fitLine($0, width: width) }
    }

    let innerWidth = max(width - 2, 1)
    let innerHeight = max(height - 2, 0)
    let rows = Array(content.prefix(innerHeight))
    let filledRows = rows + Array(repeating: "", count: max(innerHeight - rows.count, 0))

    return [panelTopBorder(title: title, width: width)]
        + filledRows.map { "│" + padOrTrim($0, width: innerWidth) + "│" }
        + [panelBottomBorder(width: width)]
}

private func panelTopBorder(title: String, width: Int) -> String {
    guard width >= 2 else {
        return fitLine(title, width: width)
    }
    let innerWidth = max(width - 2, 0)
    let titleText = fitLine(" \(title) ", width: innerWidth)
    let remaining = max(innerWidth - titleText.count, 0)
    return "┌" + titleText + String(repeating: "─", count: remaining) + "┐"
}

private func panelBottomBorder(width: Int) -> String {
    guard width >= 2 else {
        return String(repeating: "─", count: max(width, 0))
    }
    return "└" + String(repeating: "─", count: max(width - 2, 0)) + "┘"
}

private func panelRowsWithChart(
    staticRows: [String],
    chartValues: [Double],
    width: Int,
    height: Int
) -> [String] {
    let chartHeight = max(min(height - min(staticRows.count, max(height - 1, 1)), 4), 1)
    let visibleStatic = Array(staticRows.prefix(max(height - chartHeight, 0)))
    return visibleStatic + trendChart(values: chartValues, width: width, height: chartHeight)
}

private func loadingPanelRows(
    primary: String,
    secondary: String,
    width: Int,
    height: Int
) -> [String] {
    let rows = [
        fitLine(primary, width: width),
        fitLine(secondary, width: width),
        fitLine("Collecting initial sample...", width: width)
    ]
    return Array(rows.prefix(max(height, 0)))
}

private func distributeHeights(total: Int, count: Int) -> [Int] {
    guard count > 0 else { return [] }
    let base = max(total / count, 1)
    var heights = Array(repeating: base, count: count)
    let used = base * count
    let remainder = max(total - used, 0)
    for index in 0..<min(remainder, count) {
        heights[index] += 1
    }
    return heights
}

private func trendChart(values: [Double], width: Int, height: Int) -> [String] {
    guard width > 0, height > 0 else {
        return []
    }

    guard values.isEmpty == false else {
        return Array(repeating: String(repeating: " ", count: width), count: max(height - 1, 0))
            + [padOrTrim("(no history)", width: width)]
    }

    let reduced = Array(values.suffix(width))
    let maxValue = reduced.max() ?? 0
    let minValue = reduced.min() ?? 0
    let range = maxValue - minValue
    let levels: [Int]
    if range < 0.0001 {
        let flatLevel = maxValue > 0 ? max(1, height / 2) : 0
        levels = Array(repeating: flatLevel, count: reduced.count)
    } else {
        levels = reduced.map { value in
            Int(round(((value - minValue) / range) * Double(height)))
        }
    }

    return stride(from: height, through: 1, by: -1).map { row in
        let line = levels.map { $0 >= row ? "█" : " " }.joined()
        return padOrTrim(line, width: width)
    }
}

private func trendStrip(values: [Double], maxWidth: Int) -> String {
    guard maxWidth > 0 else {
        return ""
    }

    guard values.isEmpty == false else {
        return fitLine("(no history)", width: maxWidth)
    }

    let glyphs = Array("▁▂▃▄▅▆▇█")
    let reduced = Array(values.suffix(maxWidth))
    let maxValue = reduced.max() ?? 0
    let minValue = reduced.min() ?? 0
    let range = maxValue - minValue

    if range < 0.0001 {
        let glyph = maxValue > 0 ? glyphs[3] : glyphs[0]
        return String(repeating: String(glyph), count: reduced.count)
    }

    return reduced.map { value in
        let normalized = (value - minValue) / range
        let index = min(Int(round(normalized * Double(glyphs.count - 1))), glyphs.count - 1)
        return String(glyphs[index])
    }.joined()
}

private func gaugeBar(ratio: Double, width: Int) -> String {
    guard width > 0 else {
        return ""
    }
    let clamped = min(max(ratio, 0), 1)
    let filled = min(max(Int(round(clamped * Double(width))), 0), width)
    return String(repeating: "█", count: filled) + String(repeating: "░", count: max(width - filled, 0))
}

private func metricGaugeLine(label: String, value: String, ratio: Double, width: Int) -> String {
    let labelWidth = 4
    let valueWidth = max(min(max(value.count, 5), max(width / 4, 6)), 5)
    let barWidth = max(width - labelWidth - valueWidth - 2, 4)
    return fitLine(
        padOrTrim(label, width: labelWidth)
            + " "
            + padOrTrim(value, width: valueWidth)
            + " "
            + gaugeBar(ratio: ratio, width: barWidth),
        width: width
    )
}

private func wrapText(_ text: String, width: Int, maxLines: Int) -> [String] {
    guard width > 0, maxLines > 0 else {
        return []
    }

    let words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
    guard words.isEmpty == false else {
        return []
    }

    var lines: [String] = []
    var current = ""
    var index = 0

    while index < words.count {
        let word = words[index]
        let candidate = current.isEmpty ? word : current + " " + word
        if candidate.count <= width {
            current = candidate
            index += 1
            continue
        }

        if current.isEmpty {
            lines.append(fitLine(word, width: width))
            index += 1
        } else {
            lines.append(current)
            current = ""
        }

        if lines.count == maxLines {
            return Array(lines.prefix(maxLines - 1)) + [fitLine(lines[maxLines - 1], width: width)]
        }
    }

    if current.isEmpty == false, lines.count < maxLines {
        lines.append(current)
    }

    if lines.count > maxLines {
        return Array(lines.prefix(maxLines))
    }

    return lines
}

private func sortedNetworkProcesses(from sample: SampleEnvelope) -> [NetworkProcessSnapshot] {
    sample.network.processes.sorted {
        networkTotalRate($0) > networkTotalRate($1)
    }
}

private func adjustedOffset(current: Int, selection: Int, rowCapacity: Int, itemCount: Int) -> Int {
    guard itemCount > 0 else { return 0 }
    let maxOffset = max(itemCount - rowCapacity, 0)
    var offset = clamp(current, lower: 0, upper: maxOffset)
    if selection < offset {
        offset = selection
    } else if selection >= offset + rowCapacity {
        offset = selection - rowCapacity + 1
    }
    return clamp(offset, lower: 0, upper: maxOffset)
}

private func fitLine(_ text: String, width: Int) -> String {
    guard width > 0 else {
        return ""
    }

    let characters = Array(text)
    if characters.count <= width {
        return text
    }

    if width == 1 {
        return "…"
    }

    return String(characters.prefix(width - 1)) + "…"
}

private func padOrTrim(_ text: String, width: Int) -> String {
    let fitted = fitLine(text, width: width)
    let length = fitted.count
    if length >= width {
        return fitted
    }
    return fitted + String(repeating: " ", count: width - length)
}

private func clamp(_ value: Int, lower: Int, upper: Int) -> Int {
    min(max(value, lower), upper)
}

private func formatBytes(_ bytes: Int64?) -> String {
    guard let bytes else { return "n/a" }
    let units = ["B", "K", "M", "G", "T"]
    var value = Double(bytes)
    var unitIndex = 0
    while value >= 1024, unitIndex < units.count - 1 {
        value /= 1024
        unitIndex += 1
    }
    if value >= 10 || unitIndex == 0 {
        return String(format: "%.0f%@", value, units[unitIndex])
    }
    return String(format: "%.1f%@", value, units[unitIndex])
}

private func formatPercent(_ value: Double) -> String {
    String(format: "%.1f%%", value)
}

private func formatOptionalPercent(_ value: Double?) -> String {
    guard let value else { return "n/a" }
    return formatPercent(value)
}

private func formatNumber(_ value: Double?) -> String {
    guard let value else { return "n/a" }
    return String(format: "%.1f", value)
}

private func formatWatts(_ value: Double?) -> String {
    guard let value else { return "n/a" }
    return String(format: "%.2fW", value)
}

private func formatRateMB(_ value: Double?) -> String {
    guard let value else { return "n/a" }
    return String(format: "%.1fMB/s", value)
}

private func formatRateBytes(_ value: Double?) -> String {
    guard let value else { return "n/a" }
    return "\(formatBytes(Int64(value)))/s"
}

private func iso8601(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
}
