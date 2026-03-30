import AppKit
import CoreFoundation
import Foundation

struct DashboardAppearanceProvider: Sendable {
    var resolvedSystemTheme: @Sendable () -> ResolvedDashboardTheme?

    static let live = DashboardAppearanceProvider {
        currentSystemTheme()
    }
}

func currentSystemTheme() -> ResolvedDashboardTheme? {
    resolvedSystemTheme(
        appleInterfaceStyle: currentAppleInterfaceStyle(),
        appKitAppearanceName: currentAppKitAppearanceName()
    )
}

func resolvedSystemTheme(
    appleInterfaceStyle: String?,
    appKitAppearanceName: NSAppearance.Name?
) -> ResolvedDashboardTheme? {
    if let theme = resolvedSystemTheme(forAppleInterfaceStyle: appleInterfaceStyle) {
        return theme
    }

    if let theme = resolvedSystemTheme(for: appKitAppearanceName) {
        return theme
    }
    
    return nil
}

func resolvedSystemTheme(for appearanceName: NSAppearance.Name?) -> ResolvedDashboardTheme? {
    switch appearanceName {
    case .darkAqua:
        return .dark
    case .aqua:
        return .light
    case nil:
        return nil
    default:
        return nil
    }
}

func resolvedSystemTheme(forAppleInterfaceStyle style: String?) -> ResolvedDashboardTheme? {
    let trimmedStyle = style?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let trimmedStyle, trimmedStyle.isEmpty == false else {
        return nil
    }

    return trimmedStyle.caseInsensitiveCompare("Dark") == .orderedSame ? .dark : .light
}

func currentAppKitAppearanceName() -> NSAppearance.Name? {
    guard Thread.isMainThread else {
        return nil
    }

    return MainActor.assumeIsolated {
        NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
    }
}

private func currentAppleInterfaceStyle() -> String? {
    _ = CFPreferencesSynchronize(
        kCFPreferencesAnyApplication,
        kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost
    )

    if let style = CFPreferencesCopyValue(
        "AppleInterfaceStyle" as CFString,
        kCFPreferencesAnyApplication,
        kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost
    ) as? String {
        return style
    }

    if let globalDefaults = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain),
       let style = globalDefaults["AppleInterfaceStyle"] as? String {
        return style
    }

    return nil
}

enum ResolvedDashboardTheme: String, Sendable {
    case light
    case dark
}

struct DashboardThemeResolver: Sendable {
    var appearanceProvider: DashboardAppearanceProvider = .live

    func resolve(_ theme: DashboardTheme) -> ResolvedDashboardTheme {
        switch theme {
        case .light:
            return .light
        case .dark:
            return .dark
        case .auto:
            return appearanceProvider.resolvedSystemTheme() ?? .light
        }
    }
}

struct ANSIColor: Sendable {
    var red: Int
    var green: Int
    var blue: Int

    var foregroundCode: String {
        "\u{001B}[38;2;\(red);\(green);\(blue)m"
    }

    var backgroundCode: String {
        "\u{001B}[48;2;\(red);\(green);\(blue)m"
    }
}

struct ANSIStyle: Sendable {
    var foreground: ANSIColor?
    var background: ANSIColor?
    var bold = false
    var dim = false

    var openCode: String {
        var code = ANSI.reset
        if bold {
            code += "\u{001B}[1m"
        }
        if dim {
            code += "\u{001B}[2m"
        }
        if let foreground {
            code += foreground.foregroundCode
        }
        if let background {
            code += background.backgroundCode
        }
        return code
    }

    func overriding(
        foreground: ANSIColor? = nil,
        background: ANSIColor? = nil,
        bold: Bool? = nil,
        dim: Bool? = nil
    ) -> ANSIStyle {
        ANSIStyle(
            foreground: foreground ?? self.foreground,
            background: background ?? self.background,
            bold: bold ?? self.bold,
            dim: dim ?? self.dim
        )
    }
}

enum ANSI {
    static let reset = "\u{001B}[0m"
}

struct DashboardPalette: Sendable {
    var background: ANSIColor
    var primaryText: ANSIColor
    var mutedText: ANSIColor
    var divider: ANSIColor
    var panelBorder: ANSIColor
    var panelTitle: ANSIColor
    var activeTabBackground: ANSIColor
    var activeTabForeground: ANSIColor
    var inactiveTabForeground: ANSIColor
    var selectionBackground: ANSIColor
    var selectionForeground: ANSIColor
    var gaugeTrack: ANSIColor
    var cpuAccent: ANSIColor
    var memoryAccent: ANSIColor
    var networkAccent: ANSIColor
    var powerAccent: ANSIColor
    var gpuAccent: ANSIColor
    var detailAccent: ANSIColor
    var infoAccent: ANSIColor
    var warningAccent: ANSIColor
    var criticalAccent: ANSIColor

    static func `for`(_ theme: ResolvedDashboardTheme) -> DashboardPalette {
        switch theme {
        case .light:
            return DashboardPalette(
                background: ANSIColor(red: 248, green: 248, blue: 250),
                primaryText: ANSIColor(red: 38, green: 42, blue: 48),
                mutedText: ANSIColor(red: 104, green: 114, blue: 126),
                divider: ANSIColor(red: 215, green: 220, blue: 228),
                panelBorder: ANSIColor(red: 211, green: 216, blue: 224),
                panelTitle: ANSIColor(red: 45, green: 50, blue: 57),
                activeTabBackground: ANSIColor(red: 18, green: 123, blue: 255),
                activeTabForeground: ANSIColor(red: 255, green: 255, blue: 255),
                inactiveTabForeground: ANSIColor(red: 72, green: 80, blue: 90),
                selectionBackground: ANSIColor(red: 174, green: 211, blue: 248),
                selectionForeground: ANSIColor(red: 27, green: 31, blue: 35),
                gaugeTrack: ANSIColor(red: 210, green: 216, blue: 224),
                cpuAccent: ANSIColor(red: 20, green: 122, blue: 255),
                memoryAccent: ANSIColor(red: 26, green: 143, blue: 136),
                networkAccent: ANSIColor(red: 35, green: 166, blue: 213),
                powerAccent: ANSIColor(red: 221, green: 136, blue: 29),
                gpuAccent: ANSIColor(red: 65, green: 171, blue: 150),
                detailAccent: ANSIColor(red: 63, green: 129, blue: 155),
                infoAccent: ANSIColor(red: 88, green: 132, blue: 188),
                warningAccent: ANSIColor(red: 206, green: 125, blue: 0),
                criticalAccent: ANSIColor(red: 214, green: 76, blue: 57)
            )
        case .dark:
            return DashboardPalette(
                background: ANSIColor(red: 41, green: 43, blue: 51),
                primaryText: ANSIColor(red: 238, green: 240, blue: 244),
                mutedText: ANSIColor(red: 147, green: 156, blue: 170),
                divider: ANSIColor(red: 77, green: 82, blue: 94),
                panelBorder: ANSIColor(red: 80, green: 86, blue: 99),
                panelTitle: ANSIColor(red: 247, green: 248, blue: 250),
                activeTabBackground: ANSIColor(red: 18, green: 123, blue: 255),
                activeTabForeground: ANSIColor(red: 255, green: 255, blue: 255),
                inactiveTabForeground: ANSIColor(red: 203, green: 208, blue: 216),
                selectionBackground: ANSIColor(red: 101, green: 113, blue: 139),
                selectionForeground: ANSIColor(red: 255, green: 255, blue: 255),
                gaugeTrack: ANSIColor(red: 88, green: 95, blue: 110),
                cpuAccent: ANSIColor(red: 94, green: 185, blue: 255),
                memoryAccent: ANSIColor(red: 88, green: 199, blue: 191),
                networkAccent: ANSIColor(red: 102, green: 210, blue: 255),
                powerAccent: ANSIColor(red: 255, green: 174, blue: 71),
                gpuAccent: ANSIColor(red: 113, green: 217, blue: 167),
                detailAccent: ANSIColor(red: 121, green: 188, blue: 210),
                infoAccent: ANSIColor(red: 154, green: 188, blue: 255),
                warningAccent: ANSIColor(red: 255, green: 188, blue: 75),
                criticalAccent: ANSIColor(red: 255, green: 116, blue: 94)
            )
        }
    }
}

struct DashboardThemeContext: Sendable {
    var resolvedTheme: ResolvedDashboardTheme
    var palette: DashboardPalette

    init(theme: DashboardTheme, appearanceProvider: DashboardAppearanceProvider = .live) {
        let resolvedTheme = DashboardThemeResolver(appearanceProvider: appearanceProvider).resolve(theme)
        self.resolvedTheme = resolvedTheme
        self.palette = .for(resolvedTheme)
    }

    var baseStyle: ANSIStyle {
        ANSIStyle(foreground: palette.primaryText, background: palette.background)
    }

    func segment(
        _ text: String,
        foreground: ANSIColor? = nil,
        background: ANSIColor? = nil,
        bold: Bool = false,
        dim: Bool = false
    ) -> String {
        let style = baseStyle.overriding(
            foreground: foreground,
            background: background,
            bold: bold,
            dim: dim
        )
        return style.openCode + text + baseStyle.openCode
    }

    func wrapLine(_ text: String) -> String {
        baseStyle.openCode + text + ANSI.reset
    }

    func accent(for level: AlertLevel) -> ANSIColor {
        switch level {
        case .info:
            return palette.infoAccent
        case .warning:
            return palette.warningAccent
        case .critical:
            return palette.criticalAccent
        }
    }
}

private let ansiEscapeRegex = try! NSRegularExpression(pattern: "\u{001B}\\[[0-9;]*m", options: [])

private enum ANSIToken {
    case escape(String)
    case text(String)
}

func strippingANSIEscapeSequences(_ text: String) -> String {
    let range = NSRange(text.startIndex..., in: text)
    return ansiEscapeRegex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
}

private func ansiTokens(in text: String) -> [ANSIToken] {
    let range = NSRange(text.startIndex..., in: text)
    let matches = ansiEscapeRegex.matches(in: text, options: [], range: range)
    guard matches.isEmpty == false else {
        return [.text(text)]
    }

    var tokens: [ANSIToken] = []
    var cursor = text.startIndex

    for match in matches {
        guard let matchedRange = Range(match.range, in: text) else {
            continue
        }

        if cursor < matchedRange.lowerBound {
            tokens.append(.text(String(text[cursor..<matchedRange.lowerBound])))
        }

        tokens.append(.escape(String(text[matchedRange])))
        cursor = matchedRange.upperBound
    }

    if cursor < text.endIndex {
        tokens.append(.text(String(text[cursor...])))
    }

    return tokens
}

private func visibleLength(of text: String) -> Int {
    ansiTokens(in: text).reduce(into: 0) { result, token in
        if case let .text(value) = token {
            result += value.count
        }
    }
}

private func truncateANSIPreservingStyle(_ text: String, width: Int) -> String {
    guard width > 0 else {
        return ""
    }

    let targetLength = width == 1 ? 0 : width - 1
    var output = ""
    var visibleCount = 0
    var sawEscape = false
    var shouldAppendEllipsis = false

    outer: for token in ansiTokens(in: text) {
        switch token {
        case let .escape(sequence):
            output += sequence
            sawEscape = true
        case let .text(chunk):
            for character in chunk {
                if visibleCount >= targetLength {
                    shouldAppendEllipsis = true
                    break outer
                }
                output.append(character)
                visibleCount += 1
            }
        }
    }

    if shouldAppendEllipsis || visibleLength(of: text) > width {
        output += "…"
    }

    if sawEscape {
        output += ANSI.reset
    }

    return output
}

func fitLine(_ text: String, width: Int) -> String {
    guard width > 0 else {
        return ""
    }

    let length = visibleLength(of: text)
    if length <= width {
        return text
    }

    if width == 1 {
        return "…"
    }

    return truncateANSIPreservingStyle(text, width: width)
}

func padOrTrim(_ text: String, width: Int) -> String {
    let fitted = fitLine(text, width: width)
    let length = visibleLength(of: fitted)
    if length >= width {
        return fitted
    }
    return fitted + String(repeating: " ", count: width - length)
}
