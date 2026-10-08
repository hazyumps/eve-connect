import XCTest
@testable import EVECore

/// The Linux console plan is argv, not a shell string: Ghostty's `+new-window`
/// takes everything after `-e` verbatim.
final class ConsolePlanTests: XCTestCase {
    private func scratch() throws -> URL {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        return path
    }

    private func fixture(_ body: String, name: String, in directory: URL) throws -> String {
        let path = directory.appendingPathComponent(name)
        try ("#!/bin/sh\n" + body + "\n").write(to: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path.path)
        return path.path
    }

    func testPlanHandsTheCommandToTheRunningInstance() throws {
        let arguments = try LaunchPlan.linuxConsoleArguments(
            connection: Connection("telnet://eve.example:32769"),
            terminal: "/usr/bin/ghostty", telnet: "/usr/bin/telnet")
        XCTAssertEqual(Array(arguments.prefix(3)), ["/usr/bin/ghostty", "+new-window", "-e"])
        let command = Array(arguments.dropFirst(3))
        XCTAssertEqual(command[0], "/bin/sh")
        XCTAssertEqual(command[1], "-c")
        XCTAssertEqual(command[2], LaunchPlan.linuxConsoleWrapper)
        XCTAssertEqual(Array(command.suffix(4)), ["eve-console", "/usr/bin/telnet", "eve.example", "32769"])
        XCTAssertThrowsError(try LaunchPlan.linuxConsoleArguments(
            connection: Connection("capture://eve.example/eth0"), terminal: "ghostty", telnet: "telnet"))
    }

    /// A console that fails must stay on screen; `+new-window` cannot carry
    /// Ghostty's `wait-after-command`, so the wrapper holds it instead.
    func testWrapperPreservesArgumentsAndHoldsAFailure() throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let telnet = try fixture("printf '<%s>\\n' \"$@\"; exit 7", name: "telnet", in: directory)
        let arguments = try LaunchPlan.linuxConsoleArguments(
            connection: Connection("telnet://eve.example:32769"),
            terminal: "/usr/bin/ghostty", telnet: telnet)
        let command = Array(arguments.dropFirst(3))

        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: command[0])
        process.arguments = Array(command.dropFirst())
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 7, "the telnet exit status must survive the wrapper")
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("<eve.example>\n<32769>\n"), text)
        XCTAssertTrue(text.contains("console command exited 7."), text)
        XCTAssertTrue(text.contains("Press Enter to close this window."), text)
    }

    func testWrapperClosesQuietlyOnSuccess() throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let telnet = try fixture("printf 'connected\\n'; exit 0", name: "telnet", in: directory)
        let arguments = try LaunchPlan.linuxConsoleArguments(
            connection: Connection("telnet://eve.example"), terminal: "ghostty", telnet: telnet)
        let command = Array(arguments.dropFirst(3))

        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: command[0])
        process.arguments = Array(command.dropFirst())
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(text, "connected\n")
    }
}
