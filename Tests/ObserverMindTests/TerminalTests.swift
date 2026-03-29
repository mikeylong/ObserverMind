import Darwin
import Testing
@testable import ObserverMind

@Test func dashboardInteractiveTermiosKeepsRawInputAndRestoresLineAnchoring() {
    var current = termios()
    current.c_lflag = tcflag_t(ICANON | ECHO | ISIG)
    current.c_iflag = tcflag_t(ICRNL | IXON)
    current.c_oflag = 0

    let configured = dashboardInteractiveTermios(from: current)

    #expect(configured.c_lflag & tcflag_t(ICANON) == 0)
    #expect(configured.c_lflag & tcflag_t(ECHO) == 0)
    #expect(configured.c_oflag & tcflag_t(OPOST) != 0)
    #expect(configured.c_oflag & tcflag_t(ONLCR) != 0)
}

@Test func dashboardFramePayloadWrapsContentInSingleFrameSequence() {
    let payload = dashboardFramePayload(for: "ObserverMind\nStatus: ok\n")

    #expect(payload.hasPrefix("\u{001B}[H"))
    #expect(payload.contains("\u{001B}[2J") == false)
    #expect(payload.hasSuffix("ObserverMind\nStatus: ok\n"))
}
