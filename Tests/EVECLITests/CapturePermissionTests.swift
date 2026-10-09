import XCTest
@testable import EVECLI

final class CapturePermissionTests: XCTestCase {
    func testAGroupGateItCannotCrossIsReportedWithTheRemedy() {
        let status = CapturePermission.status(dumpcap: "/usr/bin/dumpcap", isExecutable: { _ in false })
        XCTAssertTrue(status.blocked)
        XCTAssertTrue(status.text.contains("usermod -aG wireshark"), status.text)
        XCTAssertTrue(status.text.contains("capture nothing"), status.text)
    }

    func testAnExecutableDumpcapIsNotABlocker() {
        let status = CapturePermission.status(dumpcap: "/usr/bin/dumpcap", isExecutable: { _ in true })
        XCTAssertFalse(status.blocked)
        XCTAssertTrue(status.text.contains("executable"), status.text)
    }

    /// macOS bundles dumpcap inside the app, so there is no gate to report.
    func testNoDumpcapOnPathIsNotTreatedAsABlocker() {
        let status = CapturePermission.status(dumpcap: nil)
        XCTAssertFalse(status.blocked)
        XCTAssertTrue(status.text.contains("no group gate to check"), status.text)
    }
}
