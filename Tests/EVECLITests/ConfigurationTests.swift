import XCTest
import EVECore
@testable import EVECLI

final class ConfigurationTests: XCTestCase {
    func testDefaultsAreProgramNamesSoPathLookupCanFindThem() {
        let configuration = Configuration()
        XCTAssertEqual(configuration.terminal, "ghostty")
        XCTAssertEqual(configuration.telnet, "telnet")
        XCTAssertEqual(configuration.vnc, "vncviewer")
        XCTAssertEqual(configuration.wireshark, "wireshark")
        XCTAssertEqual(configuration.sshUser, "root")
        XCTAssertEqual(configuration.identityFile, "")
    }

    func testParseAcceptsQuotesCommentsAndBareValues() throws {
        let text = """
        # EVE Connect
        terminal = "ghostty"
        telnet   = '/usr/bin/telnet'

        vnc = vncviewer   # trailing comment
        ssh_user = "root"
        identity_file = "~/.ssh/eve"
        """
        let (configuration, warnings) = try Configuration.parse(text)
        XCTAssertEqual(configuration.terminal, "ghostty")
        XCTAssertEqual(configuration.telnet, "/usr/bin/telnet")
        XCTAssertEqual(configuration.vnc, "vncviewer")
        XCTAssertEqual(configuration.sshUser, "root")
        XCTAssertEqual(configuration.identityFile, "~/.ssh/eve")
        XCTAssertTrue(warnings.isEmpty)
    }

    func testUnknownKeysWarnInsteadOfFailing() throws {
        let (configuration, warnings) = try Configuration.parse("terminal = \"kitty\"\nfuture_key = \"x\"\n")
        XCTAssertEqual(configuration.terminal, "kitty")
        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings[0].contains("future_key"), warnings[0])
    }

    func testMalformedLinesThrow() {
        XCTAssertThrowsError(try Configuration.parse("terminal ghostty\n"))
        XCTAssertThrowsError(try Configuration.parse("terminal = \"ghostty\n"))
        XCTAssertThrowsError(try Configuration.parse("terminal = \"ghostty\" extra\n"))
    }

    func testRenderRoundTripsIncludingAwkwardPaths() throws {
        var configuration = Configuration()
        configuration.vnc = "/opt/VNC Viewer/vncviewer"
        configuration.identityFile = "~/.ssh/eve"
        configuration.telnet = "/odd/ter\"minal\\name"
        let (parsed, warnings) = try Configuration.parse(configuration.render())
        XCTAssertEqual(parsed, configuration)
        XCTAssertTrue(warnings.isEmpty)
    }

    func testLoadMissingFileUsesDefaultsWithoutFailing() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("eve-connect-absent-\(UUID().uuidString)/config.toml")
        let loaded = try Configuration.load(path: missing.path)
        XCTAssertFalse(loaded.exists)
        XCTAssertEqual(loaded.configuration, Configuration())
    }

    func testWriteThenLoad() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("eve-connect/config.toml")
        var configuration = Configuration()
        configuration.sshUser = "lab"
        configuration.wireshark = "/usr/bin/wireshark"
        try configuration.write(to: path.path)
        let loaded = try Configuration.load(path: path.path)
        XCTAssertTrue(loaded.exists)
        XCTAssertEqual(loaded.configuration, configuration)
    }

    func testDefaultPathHonoursXdgConfigHome() {
        XCTAssertEqual(Configuration.defaultPath(home: "/home/p", environment: [:]),
                       "/home/p/.config/eve-connect/config.toml")
        XCTAssertEqual(Configuration.defaultPath(home: "/home/p", environment: ["XDG_CONFIG_HOME": "/cfg"]),
                       "/cfg/eve-connect/config.toml")
    }
}
