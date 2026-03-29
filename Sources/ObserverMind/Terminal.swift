import Darwin
import Foundation

struct TerminalSize: Equatable, Sendable {
    var width: Int
    var height: Int
}

func dashboardInteractiveTermios(from current: termios) -> termios {
    var raw = current
    cfmakeraw(&raw)
    // Keep raw keyboard input, but restore output processing so `\n` returns to column 0.
    raw.c_oflag |= tcflag_t(OPOST | ONLCR)
    return raw
}

func dashboardFramePayload(for content: String) -> String {
    "\u{001B}[H" + content
}

enum KeyInput {
    case character(Character)
    case arrowUp
    case arrowDown
    case arrowLeft
    case arrowRight
    case interrupt
}

final class TerminalController {
    private var originalTermios: termios?
    private var originalFlags: Int32?

    func prepareInteractiveTerminal() throws {
        var current = termios()
        guard tcgetattr(STDIN_FILENO, &current) == 0 else {
            throw RuntimeError("Unable to read terminal attributes.")
        }
        originalTermios = current

        var raw = dashboardInteractiveTermios(from: current)
        guard tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) == 0 else {
            throw RuntimeError("Unable to switch terminal to raw mode.")
        }

        let flags = fcntl(STDIN_FILENO, F_GETFL)
        originalFlags = flags
        _ = fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK)

        write("\u{001B}[?1049h\u{001B}[?25l")
    }

    func restoreTerminal() {
        if let originalTermios {
            var restore = originalTermios
            _ = tcsetattr(STDIN_FILENO, TCSAFLUSH, &restore)
        }
        if let originalFlags {
            _ = fcntl(STDIN_FILENO, F_SETFL, originalFlags)
        }
        write("\u{001B}[?25h\u{001B}[?1049l")
    }

    func draw(_ content: String) {
        write(dashboardFramePayload(for: content))
    }

    func size() -> TerminalSize {
        var window = winsize()
        if ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &window) == 0, window.ws_col > 0, window.ws_row > 0 {
            return TerminalSize(width: Int(window.ws_col), height: Int(window.ws_row))
        }

        let env = ProcessInfo.processInfo.environment
        let width = Int(env["COLUMNS"] ?? "") ?? 120
        let height = Int(env["LINES"] ?? "") ?? 40
        return TerminalSize(width: width, height: height)
    }

    func pollKey() -> KeyInput? {
        var buffer = [UInt8](repeating: 0, count: 8)
        let count = read(STDIN_FILENO, &buffer, buffer.count)
        guard count > 0 else {
            return nil
        }

        if buffer[0] == 3 || buffer[0] == 4 {
            return .interrupt
        }

        if count >= 3, buffer[0] == 27, buffer[1] == 91 {
            switch buffer[2] {
            case 65: return .arrowUp
            case 66: return .arrowDown
            case 67: return .arrowRight
            case 68: return .arrowLeft
            default: break
            }
        }

        let scalar = UnicodeScalar(buffer[0])
        return .character(Character(scalar))
    }

    private func write(_ text: String) {
        let bytes = Array(text.utf8)
        var offset = 0

        while offset < bytes.count {
            let remaining = bytes.count - offset
            let written = bytes.withUnsafeBytes { buffer -> Int in
                guard let baseAddress = buffer.baseAddress else {
                    return 0
                }
                let pointer = baseAddress.advanced(by: offset)
                return Darwin.write(STDOUT_FILENO, pointer, remaining)
            }

            if written > 0 {
                offset += written
                continue
            }

            if errno == EINTR || errno == EAGAIN {
                Thread.sleep(forTimeInterval: 0.01)
                continue
            }

            break
        }
    }
}
