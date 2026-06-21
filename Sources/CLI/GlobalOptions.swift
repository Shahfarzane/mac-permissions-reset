import ArgumentParser

/// Output flags shared by every subcommand (included via `@OptionGroup`).
struct GlobalOptions: ParsableArguments {
    @Flag(name: .long, help: "Output machine-readable JSON to stdout.")
    var json = false

    @Flag(name: .long, help: "Plain, stable line output (no color, no tables).")
    var plain = false

    @Flag(name: .long, help: "Disable colored output.")
    var noColor = false

    @Flag(name: [.short, .long], help: "Suppress progress and non-essential output.")
    var quiet = false

    @Flag(name: [.short, .long], help: "Print extra detail.")
    var verbose = false

    var console: Console { Console(self) }
}

/// CLI-wide constants.
enum AppResetCLIInfo {
    static let version = "0.1.0"
}
