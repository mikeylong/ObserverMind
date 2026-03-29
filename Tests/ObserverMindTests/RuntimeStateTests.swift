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
