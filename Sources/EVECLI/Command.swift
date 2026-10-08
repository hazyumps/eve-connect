import Foundation
import EVECore

/// Running external tools, with their output captured to a file rather than a
/// pipe. Reading a pipe only after the child exits deadlocks as soon as the
/// child writes more than the pipe buffer, which Ghostty's startup log can.
public enum Command {
    public struct Result: Sendable {
        public let status: Int32
        public let output: String
    }

    public static func run(_ tool: String, _ arguments: [String]) throws -> Result {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("eve-connect-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: path.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: path) }
        let output = try FileHandle(forWritingTo: path)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        try? output.close()
        let text = (try? String(contentsOf: path, encoding: .utf8)) ?? ""
        return Result(status: process.terminationStatus, output: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Starts a viewer or a capture session and returns immediately. The caller
    /// must hold the returned process: letting it deallocate would be a request
    /// to stop tracking a child that is supposed to outlive us.
    @discardableResult
    public static func spawnDetached(_ tool: String, _ arguments: [String], logPath: String? = nil) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        if let logPath {
            try FileManager.default.createDirectory(atPath: (logPath as NSString).deletingLastPathComponent,
                                                   withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: logPath) {
                FileManager.default.createFile(atPath: logPath, contents: nil)
            }
            let log = try FileHandle(forWritingTo: URL(fileURLWithPath: logPath))
            _ = try? log.seekToEnd()
            process.standardOutput = log
            process.standardError = log
        } else {
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
        }
        try process.run()
        return process
    }
}
