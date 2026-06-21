import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// How the CLI renders results.
enum OutputFormat {
    case text    // human-friendly, possibly colored
    case plain   // stable line-based text, no color, no tables
    case json    // machine-readable JSON
}

/// Centralizes output: stdout for results, stderr for diagnostics, color/format
/// rules per the clig.dev guidelines (honoring NO_COLOR, TERM=dumb, TTY, flags).
struct Console: Sendable {
    let format: OutputFormat
    let useColor: Bool
    let quiet: Bool
    let verbose: Bool

    init(_ options: GlobalOptions) {
        if options.json {
            self.format = .json
        } else if options.plain {
            self.format = .plain
        } else {
            self.format = .text
        }
        self.useColor = Self.detectColor(noColor: options.noColor, format: format)
        self.quiet = options.quiet
        self.verbose = options.verbose
    }

    private static func detectColor(noColor: Bool, format: OutputFormat) -> Bool {
        if noColor || format != .text { return false }
        let env = ProcessInfo.processInfo.environment
        if env["NO_COLOR"] != nil { return false }
        if env["TERM"] == "dumb" { return false }
        return isatty(STDOUT_FILENO) != 0
    }

    // MARK: - Streams

    /// Primary result data → stdout.
    func out(_ text: String = "") {
        print(text)
    }

    /// Diagnostics / progress → stderr (suppressed when --quiet).
    func info(_ text: String) {
        guard !quiet else { return }
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }

    /// Extra detail → stderr, only with --verbose.
    func detail(_ text: String) {
        guard verbose, !quiet else { return }
        FileHandle.standardError.write(Data((style(text, .dim) + "\n").utf8))
    }

    /// Errors → stderr (always shown).
    func error(_ text: String) {
        FileHandle.standardError.write(Data((style("error: ", .red, .bold) + text + "\n").utf8))
    }

    func warn(_ text: String) {
        guard !quiet else { return }
        FileHandle.standardError.write(Data((style("warning: ", .yellow) + text + "\n").utf8))
    }

    // MARK: - JSON

    func json<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(value), let string = String(data: data, encoding: .utf8) {
            print(string)
        }
    }

    // MARK: - Styling

    enum Style: String {
        case bold = "1"
        case dim = "2"
        case red = "31"
        case green = "32"
        case yellow = "33"
        case blue = "34"
        case magenta = "35"
        case cyan = "36"
    }

    func style(_ text: String, _ styles: Style...) -> String {
        guard useColor, !styles.isEmpty else { return text }
        let codes = styles.map(\.rawValue).joined(separator: ";")
        return "\u{001B}[\(codes)m\(text)\u{001B}[0m"
    }

    func heading(_ text: String) -> String { style(text, .bold) }

    // MARK: - Formatting helpers

    /// Human-readable byte count (e.g. "12.4 MB").
    static func bytes(_ count: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: count)
    }

    /// Print an aligned, optionally colored table to stdout. Column widths are
    /// derived from the content; the header row is bold.
    func table(headers: [String], rows: [[String]]) {
        guard !headers.isEmpty else { return }
        let columnCount = headers.count
        var widths = headers.map { $0.count }
        for row in rows {
            for index in 0..<min(columnCount, row.count) {
                widths[index] = max(widths[index], row[index].count)
            }
        }

        func render(_ cells: [String], bold: Bool) -> String {
            var parts: [String] = []
            for index in 0..<columnCount {
                let value = index < cells.count ? cells[index] : ""
                // Don't pad the final column (avoids trailing whitespace).
                let padded = index == columnCount - 1
                    ? value
                    : value.padding(toLength: widths[index], withPad: " ", startingAt: 0)
                parts.append(bold ? style(padded, .bold) : padded)
            }
            return parts.joined(separator: "  ")
        }

        // Skip the header row for key/value tables (all-empty headers).
        if !headers.allSatisfy(\.isEmpty) {
            out(render(headers, bold: true))
        }
        for row in rows {
            out(render(row, bold: false))
        }
    }
}
