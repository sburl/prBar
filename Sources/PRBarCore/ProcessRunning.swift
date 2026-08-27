import Foundation

public struct ProcessResult: Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: Data
    public let stderr: Data

    public init(exitCode: Int32, stdout: Data, stderr: Data) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }

    public var stderrString: String {
        String(data: stderr, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

public protocol ProcessRunning: Sendable {
    func run(
        executable: URL,
        arguments: [String],
        environment: [String: String]
    ) async throws -> ProcessResult
}

public struct FoundationProcessRunner: ProcessRunning {
    public init() {}

    public func run(
        executable: URL,
        arguments: [String],
        environment: [String: String]
    ) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let process = Process()
                    process.executableURL = executable
                    process.arguments = arguments
                    process.environment = environment
                    process.currentDirectoryURL = URL(fileURLWithPath: "/")

                    let stdoutPipe = Pipe()
                    let stderrPipe = Pipe()
                    process.standardOutput = stdoutPipe
                    process.standardError = stderrPipe
                    process.standardInput = FileHandle.nullDevice

                    try process.run()

                    let group = DispatchGroup()
                    let stdoutBox = DataBox()
                    let stderrBox = DataBox()

                    group.enter()
                    DispatchQueue.global(qos: .userInitiated).async {
                        stdoutBox.data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                        group.leave()
                    }

                    group.enter()
                    DispatchQueue.global(qos: .userInitiated).async {
                        stderrBox.data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                        group.leave()
                    }

                    process.waitUntilExit()
                    group.wait()

                    continuation.resume(
                        returning: ProcessResult(
                            exitCode: process.terminationStatus,
                            stdout: stdoutBox.data,
                            stderr: stderrBox.data
                        )
                    )
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private final class DataBox: @unchecked Sendable {
    var data = Data()
}
