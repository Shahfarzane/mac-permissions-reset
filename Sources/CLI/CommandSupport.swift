import ArgumentParser
import AppResetKit

/// Run a command body, translating Kit errors into clean exit codes and stderr
/// messages instead of ArgumentParser's default stack-trace-ish output.
///
/// Exit codes: 0 success, 1 runtime failure, 2 usage error (ArgumentParser),
/// 64 confirmation required in non-interactive mode (thrown directly by callers).
func runCommand(_ console: Console, _ body: () async throws -> Void) async throws {
    do {
        try await body()
    } catch let code as ExitCode {
        throw code
    } catch let error as AppResetError {
        console.error(error.description)
        throw ExitCode(1)
    } catch {
        console.error("\(error)")
        throw ExitCode(1)
    }
}
