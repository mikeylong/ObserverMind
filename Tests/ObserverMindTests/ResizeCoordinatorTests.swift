import Foundation
import Testing
@testable import ObserverMind

@Test func resizeCoordinatorDebouncesCompactToMediumTransition() {
    var coordinator = DashboardResizeCoordinator()
    let start = Date(timeIntervalSince1970: 1_000)

    let initial = coordinator.update(
        liveSize: TerminalSize(width: 99, height: 24),
        now: start
    )
    let midDrag = coordinator.update(
        liveSize: TerminalSize(width: 100, height: 24),
        now: start.addingTimeInterval(0.05)
    )
    let settled = coordinator.update(
        liveSize: TerminalSize(width: 100, height: 24),
        now: start.addingTimeInterval(0.30)
    )

    #expect(initial.committedChanged)
    #expect(DashboardRenderer.layoutMode(for: initial.layoutSize) == .compact)
    #expect(midDrag.isResizing)
    #expect(midDrag.committedChanged == false)
    #expect(DashboardRenderer.layoutMode(for: midDrag.layoutSize) == .compact)
    #expect(settled.committedChanged)
    #expect(settled.isResizing == false)
    #expect(DashboardRenderer.layoutMode(for: settled.layoutSize) == .medium)
}

@Test func resizeCoordinatorDebouncesMediumToWideTransition() {
    var coordinator = DashboardResizeCoordinator()
    let start = Date(timeIntervalSince1970: 2_000)

    _ = coordinator.update(
        liveSize: TerminalSize(width: 139, height: 28),
        now: start
    )
    let midDrag = coordinator.update(
        liveSize: TerminalSize(width: 140, height: 28),
        now: start.addingTimeInterval(0.03)
    )
    let settled = coordinator.update(
        liveSize: TerminalSize(width: 140, height: 28),
        now: start.addingTimeInterval(0.30)
    )

    #expect(midDrag.isResizing)
    #expect(DashboardRenderer.layoutMode(for: midDrag.layoutSize) == .medium)
    #expect(settled.committedChanged)
    #expect(DashboardRenderer.layoutMode(for: settled.layoutSize) == .wide)
}

@Test func resizeCoordinatorHoldsCommittedLayoutUntilSmallViewportSettles() {
    var coordinator = DashboardResizeCoordinator()
    let start = Date(timeIntervalSince1970: 3_000)

    _ = coordinator.update(
        liveSize: TerminalSize(width: 80, height: 24),
        now: start
    )
    let midDrag = coordinator.update(
        liveSize: TerminalSize(width: 71, height: 17),
        now: start.addingTimeInterval(0.04)
    )
    let settled = coordinator.update(
        liveSize: TerminalSize(width: 71, height: 17),
        now: start.addingTimeInterval(0.30)
    )

    #expect(midDrag.isResizing)
    #expect(DashboardRenderer.layoutMode(for: midDrag.layoutSize) == .compact)
    #expect(DashboardRenderer.layoutMode(for: settled.layoutSize) == .fallback)
}
