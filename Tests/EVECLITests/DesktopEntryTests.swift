import XCTest
@testable import EVECLI

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
}
