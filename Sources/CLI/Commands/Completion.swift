import ArgumentParser

struct Completion: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "completion",
        abstract: "Generate a shell completion script.",
        discussion: """
        Print a completion script for your shell to stdout. Install, for example:

          appreset completion zsh  > ~/.zsh/completions/_appreset
          appreset completion bash > /usr/local/etc/bash_completion.d/appreset
          appreset completion fish > ~/.config/fish/completions/appreset.fish
        """
    )

    @Argument(help: "Shell: bash, zsh, or fish.")
    var shell: String

    mutating func run() throws {
        let kind: CompletionShell
        switch shell.lowercased() {
        case "bash": kind = .bash
        case "zsh": kind = .zsh
        case "fish": kind = .fish
        default:
            throw ValidationError("Unsupported shell \"\(shell)\". Use bash, zsh, or fish.")
        }
        print(AppResetCLI.completionScript(for: kind))
    }
}
