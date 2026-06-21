import Foundation

/// Reference box so concurrent pipe-draining closures write through a shared
/// reference (with the dispatch group as the synchronisation barrier) instead of
/// mutating a captured `var`.
private final class DataBox: @unchecked Sendable {
    var value = Data()
}

/// Result of running an external command.
public struct ProcessResult: Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32
    public var ok: Bool { exitCode == 0 }

    public init(stdout: String, stderr: String, exitCode: Int32) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }
}

/// Async wrapper around `Foundation.Process`. All work happens off the calling
/// actor on a background dispatch queue; both pipes are drained concurrently so
/// large output (e.g. `mdfind`) can't deadlock the child. `Sendable` so the Kit
/// and both front-ends can share a single instance.
public struct ProcessRunner: Sendable {
    public init() {}

    /// Run `executable` with `arguments`. If `executable` is an absolute path it
    /// is used directly; otherwise it is resolved on PATH via `/usr/bin/env`.
    public func run(
        _ executable: String,
        _ arguments: [String] = [],
        stdin: Data? = nil
    ) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ProcessResult, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                if executable.hasPrefix("/") {
                    process.executableURL = URL(fileURLWithPath: executable)
                    process.arguments = arguments
                } else {
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                    process.arguments = [executable] + arguments
                }

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                var inPipe: Pipe?
                if stdin != nil {
                    let pipe = Pipe()
                    process.standardInput = pipe
                    inPipe = pipe
                }

                do {
                    try process.run()
                } catch {
                    continuation.resume(
                        throwing: AppResetError.processLaunchFailed(
                            tool: executable,
                            underlying: error.localizedDescription
                        )
                    )
                    return
                }

                if let stdin, let inPipe {
                    let handle = inPipe.fileHandleForWriting
                    handle.write(stdin)
                    try? handle.close()
                }

                // Drain both pipes concurrently to avoid pipe-buffer deadlock.
                // Boxes are captured by reference; the dispatch group is the barrier.
                let outBox = DataBox()
                let errBox = DataBox()
                let group = DispatchGroup()

                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    outBox.value = outPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    errBox.value = errPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }

                process.waitUntilExit()
                group.wait()

                let result = ProcessResult(
                    stdout: String(decoding: outBox.value, as: UTF8.self),
                    stderr: String(decoding: errBox.value, as: UTF8.self),
                    exitCode: process.terminationStatus
                )
                continuation.resume(returning: result)
            }
        }
    }

    /// Run a command and throw `AppResetError.processFailed` on a non-zero exit.
    @discardableResult
    public func runChecked(
        _ executable: String,
        _ arguments: [String] = [],
        stdin: Data? = nil
    ) async throws -> ProcessResult {
        let result = try await run(executable, arguments, stdin: stdin)
        guard result.ok else {
            let command = ([executable] + arguments).joined(separator: " ")
            throw AppResetError.processFailed(
                command: command,
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }
        return result
    }
}
