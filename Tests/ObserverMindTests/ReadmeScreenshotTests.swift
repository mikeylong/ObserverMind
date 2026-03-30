import AppKit
import Foundation
import Testing
@testable import ObserverMind

@Test
@MainActor
func generateReadmeScreenshots() throws {
    let size = TerminalSize(width: 144, height: 32)
    let history = makeReadmeHistory()
    let sample = try #require(history.last)
    let status = "Updated 2026-03-30T16:59:31Z"

    let outputDirectory = repositoryRoot()
        .appendingPathComponent("docs", isDirectory: true)
        .appendingPathComponent("images", isDirectory: true)

    let lightFrame = DashboardRenderer.render(
        sample: sample,
        history: history,
        state: DashboardRenderState(
            view: .overview,
            processSort: .cpu,
            selectionIndex: 0,
            processScrollOffset: 0,
            networkScrollOffset: 0,
            theme: .light
        ),
        size: size,
        status: status
    )
    let darkFrame = DashboardRenderer.render(
        sample: sample,
        history: history,
        state: DashboardRenderState(
            view: .overview,
            processSort: .cpu,
            selectionIndex: 0,
            processScrollOffset: 0,
            networkScrollOffset: 0,
            theme: .dark
        ),
        size: size,
        status: status
    )

    try ReadmeScreenshotRenderer.writePNG(
        frame: lightFrame,
        theme: .light,
        to: outputDirectory.appendingPathComponent("dashboard-light.png", isDirectory: false)
    )
    try ReadmeScreenshotRenderer.writePNG(
        frame: darkFrame,
        theme: .dark,
        to: outputDirectory.appendingPathComponent("dashboard-dark.png", isDirectory: false)
    )

    #expect(lightFrame != darkFrame)
    #expect(
        FileManager.default.fileExists(
            atPath: outputDirectory.appendingPathComponent("dashboard-light.png", isDirectory: false).path
        )
    )
    #expect(
        FileManager.default.fileExists(
            atPath: outputDirectory.appendingPathComponent("dashboard-dark.png", isDirectory: false).path
        )
    )
}

private enum ReadmeScreenshotError: Error {
    case unableToCreateBitmap
    case unableToEncodePNG
}

@MainActor
private enum ReadmeScreenshotRenderer {
    static let padding = CGSize(width: 24, height: 24)
    static let fontSize: CGFloat = 16

    static var regularFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    static var boldFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
    }

    static func writePNG(frame: String, theme: ResolvedDashboardTheme, to url: URL) throws {
        let palette = DashboardPalette.for(theme)
        let defaultStyle = ParsedANSIStyle(
            foreground: nsColor(palette.primaryText),
            background: nsColor(palette.background),
            bold: false,
            dim: false
        )
        let lines = parse(frame: frame, defaultStyle: defaultStyle)
        let metrics = cellMetrics()
        let width = lines.map(\.count).max() ?? 0
        let pixelWidth = Int(ceil(CGFloat(width) * metrics.cellWidth + padding.width * 2))
        let pixelHeight = Int(ceil(CGFloat(lines.count) * metrics.cellHeight + padding.height * 2))

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: max(pixelWidth, 1),
            pixelsHigh: max(pixelHeight, 1),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw ReadmeScreenshotError.unableToCreateBitmap
        }

        guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw ReadmeScreenshotError.unableToCreateBitmap
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext

        let canvasRect = CGRect(x: 0, y: 0, width: CGFloat(pixelWidth), height: CGFloat(pixelHeight))
        nsColor(palette.background).setFill()
        NSBezierPath(rect: canvasRect).fill()

        for (rowIndex, line) in lines.enumerated() {
            let rowY = CGFloat(pixelHeight) - padding.height - CGFloat(rowIndex + 1) * metrics.cellHeight

            for (columnIndex, cell) in line.enumerated() {
                let cellRect = CGRect(
                    x: padding.width + CGFloat(columnIndex) * metrics.cellWidth,
                    y: rowY,
                    width: metrics.cellWidth,
                    height: metrics.cellHeight
                )

                if sameColor(cell.style.background, nsColor(palette.background)) == false {
                    cell.style.background.setFill()
                    NSBezierPath(rect: cellRect).fill()
                }

                let font = cell.style.bold ? boldFont : regularFont
                let foreground = cell.style.dim
                    ? cell.style.foreground.withAlphaComponent(0.68)
                    : cell.style.foreground
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: foreground
                ]

                let textRect = CGRect(
                    x: cellRect.minX,
                    y: cellRect.minY + metrics.textYOffset,
                    width: metrics.cellWidth + 2,
                    height: metrics.glyphHeight
                )
                (String(cell.character) as NSString).draw(in: textRect, withAttributes: attributes)
            }
        }

        NSGraphicsContext.restoreGraphicsState()

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw ReadmeScreenshotError.unableToEncodePNG
        }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if let existing = try? Data(contentsOf: url), existing == data {
            return
        }

        try data.write(to: url, options: .atomic)
    }

    private static func parse(frame: String, defaultStyle: ParsedANSIStyle) -> [[ParsedCell]] {
        var style = defaultStyle
        var lines: [[ParsedCell]] = [[]]
        var index = frame.startIndex

        while index < frame.endIndex {
            let character = frame[index]

            if character == "\u{001B}" {
                let next = frame.index(after: index)
                if next < frame.endIndex, frame[next] == "[" {
                    var end = frame.index(after: next)
                    while end < frame.endIndex, frame[end] != "m" {
                        end = frame.index(after: end)
                    }
                    if end < frame.endIndex {
                        let codeStart = frame.index(after: next)
                        let rawCodes = String(frame[codeStart..<end])
                        applyANSI(
                            codes: rawCodes.split(separator: ";").compactMap { Int($0) },
                            to: &style,
                            defaultStyle: defaultStyle
                        )
                        index = frame.index(after: end)
                        continue
                    }
                }
            }

            if character == "\n" {
                lines.append([])
                index = frame.index(after: index)
                continue
            }

            lines[lines.count - 1].append(ParsedCell(character: character, style: style))
            index = frame.index(after: index)
        }

        return lines
    }

    private static func applyANSI(
        codes: [Int],
        to style: inout ParsedANSIStyle,
        defaultStyle: ParsedANSIStyle
    ) {
        if codes.isEmpty {
            style = defaultStyle
            return
        }

        var index = 0
        while index < codes.count {
            switch codes[index] {
            case 0:
                style = defaultStyle
                index += 1
            case 1:
                style.bold = true
                index += 1
            case 2:
                style.dim = true
                index += 1
            case 22:
                style.bold = false
                style.dim = false
                index += 1
            case 38:
                if index + 4 < codes.count, codes[index + 1] == 2 {
                    style.foreground = NSColor(
                        srgbRed: CGFloat(codes[index + 2]) / 255.0,
                        green: CGFloat(codes[index + 3]) / 255.0,
                        blue: CGFloat(codes[index + 4]) / 255.0,
                        alpha: 1.0
                    )
                    index += 5
                } else {
                    index += 1
                }
            case 39:
                style.foreground = defaultStyle.foreground
                index += 1
            case 48:
                if index + 4 < codes.count, codes[index + 1] == 2 {
                    style.background = NSColor(
                        srgbRed: CGFloat(codes[index + 2]) / 255.0,
                        green: CGFloat(codes[index + 3]) / 255.0,
                        blue: CGFloat(codes[index + 4]) / 255.0,
                        alpha: 1.0
                    )
                    index += 5
                } else {
                    index += 1
                }
            case 49:
                style.background = defaultStyle.background
                index += 1
            default:
                index += 1
            }
        }
    }

    private static func cellMetrics() -> CellMetrics {
        let regularGlyph = ("M" as NSString).size(withAttributes: [.font: regularFont])
        let boldGlyph = ("M" as NSString).size(withAttributes: [.font: boldFont])
        let glyphWidth = ceil(max(regularGlyph.width, boldGlyph.width))
        let glyphHeight = ceil(max(regularGlyph.height, boldGlyph.height))
        let lineHeight = ceil(
            max(
                regularFont.ascender - regularFont.descender + regularFont.leading,
                boldFont.ascender - boldFont.descender + boldFont.leading
            ) + 2
        )

        return CellMetrics(
            cellWidth: glyphWidth,
            cellHeight: max(lineHeight, glyphHeight + 2),
            glyphHeight: glyphHeight,
            textYOffset: floor((max(lineHeight, glyphHeight + 2) - glyphHeight) / 2)
        )
    }

    private static func nsColor(_ color: ANSIColor) -> NSColor {
        NSColor(
            srgbRed: CGFloat(color.red) / 255.0,
            green: CGFloat(color.green) / 255.0,
            blue: CGFloat(color.blue) / 255.0,
            alpha: 1.0
        )
    }

    private static func sameColor(_ lhs: NSColor, _ rhs: NSColor) -> Bool {
        let left = lhs.usingColorSpace(.deviceRGB) ?? lhs
        let right = rhs.usingColorSpace(.deviceRGB) ?? rhs
        return abs(left.redComponent - right.redComponent) < 0.001
            && abs(left.greenComponent - right.greenComponent) < 0.001
            && abs(left.blueComponent - right.blueComponent) < 0.001
            && abs(left.alphaComponent - right.alphaComponent) < 0.001
    }
}

private struct ParsedANSIStyle {
    var foreground: NSColor
    var background: NSColor
    var bold: Bool
    var dim: Bool
}

private struct ParsedCell {
    var character: Character
    var style: ParsedANSIStyle
}

private struct CellMetrics {
    var cellWidth: CGFloat
    var cellHeight: CGFloat
    var glyphHeight: CGFloat
    var textYOffset: CGFloat
}

private func makeReadmeHistory() -> [SampleEnvelope] {
    let totalMemoryBytes: Int64 = 128 * 1_024 * 1_024 * 1_024
    let start = Date(timeIntervalSince1970: 1_711_817_400)

    let samples = (0..<24).map { index -> SampleEnvelope in
        let cpu = 24.0 + Double((index * 9) % 20)
        let freePercent = 22.0 - Double(index % 5)
        let diskRead = 160.0 + Double((index * 11) % 45)
        let diskWrite = 110.0 + Double((index * 7) % 35)
        let freeBytes = Int64(Double(totalMemoryBytes) * (freePercent / 100.0))
        let usedBytes = totalMemoryBytes - freeBytes

        var sample = makeSample(
            timestamp: start.addingTimeInterval(Double(index) * 15.0),
            cpu: cpu,
            freePercent: freePercent,
            swapOutBytes: Int64(index * 18) * 1_024 * 1_024,
            diskMBPerSec: diskRead + diskWrite,
            batteryPercentage: 88.0 - Double(index) * 0.35,
            batteryState: "discharging",
            thermalState: index > 17 ? "Fair" : "Nominal"
        )

        sample.host.modelName = "MacBook Pro 16-inch"
        sample.capabilities.isRoot = true
        sample.capabilities.powermetricsAvailable = true
        sample.capabilities.advancedPowerAvailable = true
        sample.capabilities.relaunchHint = "Run `observer dashboard` for the full-screen cockpit."
        sample.cpu.loadAverage1m = 5.40
        sample.cpu.loadAverage5m = 4.95
        sample.cpu.loadAverage15m = 4.32
        sample.cpu.packagePowerWatts = 18.6 + Double(index % 6) * 1.1
        sample.memory.totalBytes = totalMemoryBytes
        sample.memory.usedBytes = usedBytes
        sample.memory.freeBytes = freeBytes
        sample.memory.wiredBytes = 18 * 1_024 * 1_024 * 1_024
        sample.memory.compressedBytes = 6 * 1_024 * 1_024 * 1_024
        sample.disk.readMBPerSec = diskRead
        sample.disk.writeMBPerSec = diskWrite
        sample.disk.totalMBPerSec = diskRead + diskWrite
        sample.network.totalBytesIn = 9_400_000_000 + Int64(index) * 165_000_000
        sample.network.totalBytesOut = 6_200_000_000 + Int64(index) * 110_000_000
        sample.network.totalInRateBytesPerSec = 2_200_000 + Double(index) * 95_000
        sample.network.totalOutRateBytesPerSec = 1_050_000 + Double(index) * 62_000
        sample.battery.powerSource = "Battery Power"
        sample.battery.timeRemaining = "3:18 remaining"
        sample.gpu.powerWatts = 11.8 + Double(index % 5) * 0.85
        sample.gpu.anePowerWatts = 1.9 + Double(index % 4) * 0.2
        sample.gpu.processMetricsLocked = false
        sample.gpu.lockReason = nil
        sample.alerts = []

        return sample
    }

    guard var final = samples.last else {
        return []
    }

    final.alerts = [
        Alert(level: .info, message: "Rendering 24-sample history across live dashboard panels."),
        Alert(level: .warning, message: "Memory free percentage is trending down to 18.0%."),
        Alert(level: .warning, message: "Battery drain is elevated during sustained observer sessions.")
    ]

    return Array(samples.dropLast()) + [final]
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
