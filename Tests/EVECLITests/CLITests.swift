import XCTest
import EVECore
@testable import EVECLI

final class CLITests: XCTestCase {
    func testParseReadsTheLinkAndItsOptions() throws {
        let parsed = try CLI.parse(arguments: ["eve-connect", "--config", "/tmp/c.toml", "--dry-run", "vnc://eve.example::5901"])
        XCTAssertEqual(parsed.command, .dryRun)
        XCTAssertEqual(parsed.configPath, "/tmp/c.toml")
        XCTAssertEqual(parsed.link, "vnc://eve.example::5901")

        XCTAssertEqual(try CLI.parse(arguments: ["eve-connect", "telnet://eve.example:32769"]).command, .open)
        XCTAssertEqual(try CLI.parse(arguments: ["eve-connect", "--check"]).command, .check)
        XCTAssertEqual(try CLI.parse(arguments: ["eve-connect", "--install"]).command, .install)
        XCTAssertEqual(try CLI.parse(arguments: ["eve-connect", "--init"]).command, .initialize)
        XCTAssertEqual(try CLI.parse(arguments: ["eve-connect", "--capture-session", "capture://eve.example/eth0"]).command,
                       .captureSession)
        XCTAssertTrue(try CLI.parse(arguments: ["eve-connect", "--help"]).help)
        XCTAssertTrue(try CLI.parse(arguments: ["eve-connect", "--version"]).showVersion)
    }

    func testParseRejectsNonsense() {
        XCTAssertThrowsError(try CLI.parse(arguments: ["eve-connect", "--nope"]))
        XCTAssertThrowsError(try CLI.parse(arguments: ["eve-connect", "--config"]))
        XCTAssertThrowsError(try CLI.parse(arguments: ["eve-connect", "telnet://a:1", "telnet://b:2"]))
    }

    func testPlanDescribesEachLinkWithoutLaunchingAnything() throws {
        let console = try CLI.plan("telnet://eve.example:32769",
                                   configuration: Configuration(terminal: "/usr/bin/ghostty", telnet: "/usr/bin/telnet"))
        XCTAssertTrue(console.hasPrefix("console eve.example:32769 in a new /usr/bin/ghostty window\n"), console)
        XCTAssertTrue(console.contains("+new-window"), console)
        XCTAssertTrue(console.contains("'/usr/bin/telnet' 'eve.example' '32769'"), console)

        let vnc = try CLI.plan("vnc://eve.example::32770", configuration: Configuration(vnc: "/usr/bin/vncviewer"))
        XCTAssertEqual(vnc, "vnc eve.example:32770 in /usr/bin/vncviewer\n'/usr/bin/vncviewer' 'eve.example::32770'")

        let capture = try CLI.plan("capture://eve.example/eth0", configuration: Configuration(wireshark: "/usr/bin/wireshark"))
        XCTAssertTrue(capture.hasPrefix("capture eve.example:eth0\n"), capture)
        XCTAssertTrue(capture.contains("'root@eve.example'"), capture)
        XCTAssertTrue(capture.contains("tcpdump"), capture)
        XCTAssertTrue(capture.contains("| '/usr/bin/wireshark' '-k' '-i' '-' '--no-promiscuous-mode'"), capture)
    }

    func testPlanRejectsABadLink() {
        XCTAssertThrowsError(try CLI.plan("ssh://eve.example", configuration: Configuration()))
    }

    func testCheckNamesWhatIsMissing() {
        let configuration = Configuration(terminal: "sh", telnet: "sh", vnc: "eve-connect-not-installed-xyz", wireshark: "sh")
        let (text, missing, _) = CLI.check(configuration: configuration,
                                           configPath: "/tmp/eve-connect-absent/config.toml")
        XCTAssertEqual(missing, ["vnc"])
        XCTAssertTrue(text.contains("NOT FOUND"), text)
        XCTAssertTrue(text.contains("x-scheme-handler/telnet"), text)
        XCTAssertTrue(text.contains("not there yet"), text)
        XCTAssertTrue(text.contains("capture"), text)
    }

    func testAbsoluteExecutableResolvesAndRejects() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("eve-connect")
        try "#!/bin/sh\n".write(to: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
        let expected = URL(fileURLWithPath: path.path).standardizedFileURL.path
        XCTAssertEqual(CLI.absoluteExecutable(path.path), expected)
        XCTAssertNil(CLI.absoluteExecutable("/nonexistent/eve-connect-xyz"))
    }

    func testUsageNamesTheRegisteringStep() {
        let usage = CLI.usage(program: "/home/patrick/.local/bin/eve-connect")
        XCTAssertTrue(usage.contains("eve-connect --install"), usage)
        XCTAssertTrue(usage.contains("capture://host/interface"), usage)
    }
}
