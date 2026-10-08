import XCTest
@testable import EVECore

@MainActor
final class CaptureTests: XCTestCase {
    private func fixture(_ body: String, name: String, in directory: URL) throws -> String {
        let path = directory.appendingPathComponent(name)
        try ("#!/bin/sh\n" + body + "\n").write(to: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path.path)
        return path.path
    }

    private func scratch() throws -> URL {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        return path
    }

    func testCaptureDeliversBytesAndEOFToViewer() throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let received = directory.appendingPathComponent("received")
        let ssh = try fixture("printf 'capture bytes'", name: "ssh", in: directory)
        let viewer = try fixture("exec /bin/cat > \(LaunchPlan.shellQuote(received.path))", name: "viewer", in: directory)
        let finished = expectation(description: "Both capture processes exit")
        var errors: [String] = []
        let session = CaptureSession(connection: try Connection("capture://localhost/eth0"), arguments: [],
                                     wireshark: viewer, sshExecutable: ssh,
                                     report: { errors.append($0) }, finished: { _ in finished.fulfill() })
        try session.start()
        defer { session.stop() }
        wait(for: [finished], timeout: 3)
        XCTAssertEqual(try String(contentsOf: received, encoding: .utf8), "capture bytes")
        XCTAssertTrue(errors.isEmpty, errors.joined(separator: "\n"))
    }

    func testClosingViewerEndsProducer() throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let ssh = try fixture("exec /bin/cat /dev/zero", name: "ssh", in: directory)
        let viewer = try fixture("exec /bin/dd bs=1 count=10 of=/dev/null 2>/dev/null", name: "viewer", in: directory)
        let finished = expectation(description: "Closing the viewer releases the producer")
        let session = CaptureSession(connection: try Connection("capture://localhost/eth0"), arguments: [],
                                     wireshark: viewer, sshExecutable: ssh,
                                     report: { _ in }, finished: { _ in finished.fulfill() })
        try session.start()
        defer { session.stop() }
        wait(for: [finished], timeout: 3)
    }

    func testSSHFailureIsReported() throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let ssh = try fixture("printf 'Permission denied\\n' >&2; exit 255", name: "ssh", in: directory)
        let viewer = try fixture("exec /bin/cat >/dev/null", name: "viewer", in: directory)
        let finished = expectation(description: "Failed capture exits")
        var errors: [String] = []
        let session = CaptureSession(connection: try Connection("capture://localhost/eth0"), arguments: [],
                                     wireshark: viewer, sshExecutable: ssh,
                                     report: { errors.append($0) }, finished: { _ in finished.fulfill() })
        try session.start()
        defer { session.stop() }
        wait(for: [finished], timeout: 3)
        XCTAssertTrue(errors.contains { $0.contains("SSH exit 255") }, errors.joined(separator: "\n"))
    }
}
