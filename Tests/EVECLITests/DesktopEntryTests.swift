import XCTest
import EVECore
@testable import EVECLI

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

final class DesktopEntryTests: XCTestCase {
    private func installer(_ executable: String = "/home/patrick/.local/bin/eve-connect") -> SchemeInstaller {
        SchemeInstaller(executablePath: executable, applicationsDirectory: "/home/patrick/.local/share/applications")
    }

    func testEntryClaimsAllThreeSchemesAndRunsHeadless() {
        let entry = installer().entryContents
        XCTAssertTrue(entry.hasPrefix("[Desktop Entry]\n"))
        XCTAssertTrue(entry.contains("Exec=/home/patrick/.local/bin/eve-connect %u"), entry)
        XCTAssertTrue(entry.contains("MimeType=x-scheme-handler/telnet;x-scheme-handler/vnc;x-scheme-handler/capture;"), entry)
        XCTAssertTrue(entry.contains("NoDisplay=true"), entry)
        XCTAssertTrue(entry.contains("Terminal=false"), entry)
        XCTAssertEqual(installer().entryPath, "/home/patrick/.local/share/applications/eve-connect.desktop")
    }

    func testExecIsQuotedAndEscapedOnlyWhenItNeedsToBe() {
        XCTAssertTrue(installer("/opt/eve connect/eve-connect").entryContents
            .contains("Exec=\"/opt/eve connect/eve-connect\" %u"))
        XCTAssertTrue(installer("/opt/$bin/eve-connect").entryContents
            .contains("Exec=\"/opt/\\$bin/eve-connect\" %u"))
    }

    func testRegistrationCommandOrder() {
        let commands = installer().commands
        XCTAssertEqual(commands.map { $0.tool },
                       ["update-desktop-database", "xdg-mime", "xdg-mime", "xdg-mime"])
        XCTAssertEqual(commands[0].arguments, ["/home/patrick/.local/share/applications"])
        XCTAssertEqual(commands[1].arguments, ["default", "eve-connect.desktop", "x-scheme-handler/telnet"])
        XCTAssertEqual(commands[2].arguments, ["default", "eve-connect.desktop", "x-scheme-handler/vnc"])
        XCTAssertEqual(commands[3].arguments, ["default", "eve-connect.desktop", "x-scheme-handler/capture"])
    }

    func testApplicationsDirectoryHonoursXdgDataHome() {
        XCTAssertEqual(SchemeInstaller.defaultApplicationsDirectory(home: "/home/p", environment: ["XDG_DATA_HOME": "/data"]),
                       "/data/applications")
        XCTAssertEqual(SchemeInstaller.defaultApplicationsDirectory(home: "/home/p", environment: [:]),
                       "/home/p/.local/share/applications")
    }

    /// The registration tools are named, not pathed, so they have to be resolved
    /// before Process sees them — a bare name is looked up as `/xdg-mime`.
    func testInstallWritesTheEntryAndRunsResolvedTools() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bin = directory.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let record = directory.appendingPathComponent("calls")
        for tool in ["update-desktop-database", "xdg-mime"] {
            let path = bin.appendingPathComponent(tool)
            try "#!/bin/sh\nprintf '%s\\n' \"\(tool) $*\" >> \(LaunchPlan.shellQuote(record.path))\nexit 0\n"
                .write(to: path, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
        }

        let original = ProcessInfo.processInfo.environment["PATH"]
        setenv("PATH", bin.path, 1)
        defer { if let original { setenv("PATH", original, 1) } }

        let installer = SchemeInstaller(executablePath: "/usr/local/bin/eve-connect",
                                       applicationsDirectory: directory.appendingPathComponent("applications").path)
        try installer.install()

        XCTAssertTrue(FileManager.default.fileExists(atPath: installer.entryPath))
        let calls = try String(contentsOfFile: record.path, encoding: .utf8)
        let lines = calls.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 4, calls)
        XCTAssertEqual(lines[0], "update-desktop-database \(directory.appendingPathComponent("applications").path)")
        XCTAssertEqual(lines[1], "xdg-mime default eve-connect.desktop x-scheme-handler/telnet")
        XCTAssertEqual(lines[3], "xdg-mime default eve-connect.desktop x-scheme-handler/capture")
    }
}
