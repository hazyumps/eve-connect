import XCTest
import EVECore
@testable import EVECLI

final class CommandTests: XCTestCase {
    func testRunCapturesBothStreamsAndTheExitStatus() throws {
        let result = try Command.run("/bin/sh", ["-c", "echo out; echo err >&2; exit 3"])
        XCTAssertEqual(result.status, 3)
        XCTAssertTrue(result.output.contains("out"), result.output)
        XCTAssertTrue(result.output.contains("err"), result.output)
    }

    /// Reading a pipe only after the child exits deadlocks past the pipe
    /// buffer, and Ghostty's startup log is not small. This is the regression
    /// test for capturing to a file instead.
    func testRunSurvivesMoreOutputThanThePipeBuffer() throws {
        let result = try Command.run("/bin/sh", ["-c",
            "i=0; while [ $i -lt 20000 ]; do echo padding-padding-padding-$i; i=$((i+1)); done"])
        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("padding-padding-padding-19999"), "output was truncated")
    }

    func testSpawnDetachedDoesNotWaitForTheChild() throws {
        let started = Date()
        let process = try Command.spawnDetached("/bin/sh", ["-c", "sleep 5"])
        XCTAssertLessThan(Date().timeIntervalSince(started), 2.0)
        process.terminate()
    }

    func testSpawnDetachedAppendsToItsLog() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = directory.appendingPathComponent("capture.log").path
        let process = try Command.spawnDetached("/bin/sh", ["-c", "echo first"], logPath: log)
        process.waitUntilExit()
        XCTAssertEqual(try String(contentsOfFile: log, encoding: .utf8), "first\n")
    }
}
