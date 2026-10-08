import XCTest
@testable import EVECore

final class ConnectionTests: XCTestCase {
    func testConsoleLinks() throws {
        let telnet = try Connection("telnet://10.1.2.100:32769/")
        XCTAssertEqual(telnet.kind, .telnet)
        XCTAssertEqual(telnet.host, "10.1.2.100")
        XCTAssertEqual(telnet.port, 32769)
        XCTAssertEqual(try Connection("TELNET://eve.example").port, 23)
        XCTAssertEqual(try Connection("telnet://[2001:db8::1]:32769").host, "2001:db8::1")
    }

    func testVNCAlwaysUsesAbsolutePort() throws {
        for link in ["vnc://eve.example:32770", "vnc://eve.example::32770/"] {
            XCTAssertEqual(try Connection(link).vncTarget, "eve.example::32770")
        }
        XCTAssertEqual(try Connection("vnc://eve.example").vncTarget, "eve.example::5900")
        XCTAssertEqual(try Connection("vnc://[::1]:5901").vncTarget, "[::1]::5901")
    }

    func testCaptureLink() throws {
        let capture = try Connection("capture://eve.example/vunl0_1_0")
        XCTAssertEqual(capture.kind, .capture)
        XCTAssertEqual(capture.interface, "vunl0_1_0")
        XCTAssertNil(capture.port)
    }

    func testRejectsMalformedAndExecutableInput() {
        let links = [
            "", "ssh://eve.example:22", "telnet://-oProxyCommand=evil:23",
            "telnet://user@host:23", "telnet://user:password@host:23",
            "telnet://host:0", "telnet://host:65536", "telnet://host:-1",
            "telnet://host:", "telnet://host::23", "telnet://[:::1]:23",
            "telnet://host/path", "telnet://host?arg=x", "telnet://host#fragment",
            "telnet://host\n", "telnet://host;touch /tmp/no", "telnet://host%20:23",
            "telnet://host..example:23", "telnet://host.-example:23",
            "capture://host", "capture://host/", "capture://host:22/eth0",
            "capture://host/eth0/other", "capture://host/eth0;id",
            "capture://host/$(id)", "capture://host/`id`", "capture://host/-w",
            "capture://host/eth0%3Bid", "capture://host/eth0\n", "capture://host/abcdefghijklmnop"
        ]
        for link in links {
            XCTAssertThrowsError(try Connection(link), "Should reject \(link.debugDescription)")
        }
    }

    func testCaptureArgumentsUseNoninteractiveTrustedSSH() throws {
        let connection = try Connection("capture://eve.example/vunl0_1_0")
        let args = try LaunchPlan.captureArguments(connection: connection, user: "root", identityFile: "/a path/key")
        XCTAssertTrue(args.contains("BatchMode=yes"))
        XCTAssertTrue(args.contains("StrictHostKeyChecking=yes"))
        XCTAssertEqual(args.suffix(4), ["-i", "/a path/key", "root@eve.example", "exec tcpdump -U -n -i 'vunl0_1_0' -w -"])
        XCTAssertThrowsError(try LaunchPlan.captureArguments(connection: connection, user: "root;id", identityFile: ""))
        XCTAssertThrowsError(try LaunchPlan.captureArguments(connection: connection, user: "root\n", identityFile: ""))
    }

    func testShellQuotingRoundTripsLiteralArguments() throws {
        for value in ["normal", "a path/with spaces", "one'two", "$(printf unsafe)", "a\"b\\c"] {
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", "printf '%s' \(LaunchPlan.shellQuote(value))"]
            process.standardOutput = output
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0)
            XCTAssertEqual(String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self), value)
        }
    }

    func testConsoleWrapperMarksOnlyItsOutputAndPreservesArguments() throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let executable = scratch.appendingPathComponent("telnet with 'quotes'")
        try "#!/bin/sh\nprintf '<%s>\\n' \"$@\"\nexit 7\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let command = try LaunchPlan.consoleCommand(connection: Connection("telnet://eve.example:32769"), telnet: executable.path)
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        // Match Ghostty's macOS exec wrapper, including login argv handling.
        process.arguments = ["--noprofile", "--norc", "-c", "exec -l \(command)"]
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 7, "exec must preserve the telnet process exit status")
        let bytes = output.fileHandleForReading.readDataToEndOfFile()
        XCTAssertEqual(String(decoding: bytes, as: UTF8.self), "\u{1b}]133;A\u{7}\u{1b}]133;B\u{7}<eve.example>\n<32769>\n")
    }

    #if os(macOS)
    func testGhosttyScriptCompilesWithInstalledDictionary() throws {
        guard FileManager.default.fileExists(atPath: "/Applications/Ghostty.app") else {
            throw XCTSkip("Ghostty must be installed to compile its AppleScript dictionary.")
        }
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        for preferTab in [false, true] {
            let script = try LaunchPlan.ghosttyScript(connection: Connection("telnet://eve.example:32769"),
                                                       telnet: "/a path/quote'and\"slash\\/telnet", preferTab: preferTab)
            let source = scratch.appendingPathComponent("console.applescript")
            try script.write(to: source, atomically: true, encoding: .utf8)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osacompile")
            process.arguments = ["-o", scratch.appendingPathComponent("console.scpt").path, source.path]
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0)
        }
    }
    #endif
}
