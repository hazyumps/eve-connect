import Foundation

/// Each capture owns an independent SSH → Wireshark pipe. Closing Wireshark
/// ends SSH; an SSH error leaves Wireshark open so captured packets can be saved.
///
/// Foundation delivers process termination handlers on its own reaper thread and
/// the error pipe's handler on a dispatch queue, so the state they touch is
/// guarded by a lock rather than by an actor. That keeps this type usable from
/// the AppKit app and from a plain Linux CLI alike — swift-corelibs-xctest
/// cannot even discover `@MainActor` test methods, which is how the capture
/// pipeline stays covered on both platforms.
public final class CaptureSession: @unchecked Sendable {
    public let id = UUID()
    public let name: String
    private let ssh = Process()
    private let viewer = Process()
    private let stream = Pipe()
    private let errors = Pipe()
    private let lock = NSLock()
    private var diagnostics = Data()
    private var stopping = false
    private var sshEnded = false
    private var viewerEnded = false
    private let report: (String) -> Void
    private let finished: (UUID) -> Void

    public init(connection: Connection, arguments: [String], wireshark: String, sshExecutable: String = "/usr/bin/ssh",
         report: @escaping (String) -> Void, finished: @escaping (UUID) -> Void) {
        name = connection.displayName
        self.report = report
        self.finished = finished
        ssh.executableURL = URL(fileURLWithPath: sshExecutable)
        ssh.arguments = arguments
        ssh.standardInput = FileHandle.nullDevice
        // Pass handles, not Pipe objects: Process closes the parent's child-side
        // handle automatically for a Pipe, which breaks sharing it with a second child.
        ssh.standardOutput = stream.fileHandleForWriting
        ssh.standardError = errors.fileHandleForWriting
        viewer.executableURL = URL(fileURLWithPath: wireshark)
        viewer.arguments = ["-k", "-i", "-", "--no-promiscuous-mode"]
        viewer.standardInput = stream.fileHandleForReading
        viewer.standardOutput = FileHandle.nullDevice
        // Wireshark presents its own capture errors; also retain stderr here.
        viewer.standardError = errors.fileHandleForWriting
    }

    public func start() throws {
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            guard let self else { return }
            self.lock.lock()
            self.diagnostics.append(data)
            self.diagnostics = self.diagnostics.suffix(8192)
            self.lock.unlock()
        }
        ssh.terminationHandler = { [weak self] process in
            self?.sshExited(process.terminationStatus)
        }
        viewer.terminationHandler = { [weak self] process in
            self?.viewerExited(process.terminationStatus)
        }
        do {
            try viewer.run()
            try ssh.run()
        } catch {
            lock.lock(); stopping = true; lock.unlock()
            if viewer.isRunning { viewer.terminate() }
            closeParentHandles()
            errors.fileHandleForReading.readabilityHandler = nil
            throw error
        }
        // The parent must not hold either end open: Wireshark needs EOF when
        // SSH exits, and SSH needs a broken pipe when the viewer closes.
        closeParentHandles()
    }

    public func stop() {
        lock.lock(); stopping = true; lock.unlock()
        if ssh.isRunning { ssh.terminate() }
        // Leave Wireshark open to let the user save captured data.
    }

    private func closeParentHandles() {
        try? stream.fileHandleForReading.close()
        try? stream.fileHandleForWriting.close()
        try? errors.fileHandleForWriting.close()
    }

    private func sshExited(_ status: Int32) {
        lock.lock()
        sshEnded = true
        let quiet = stopping
        let detail = quiet ? "" : String(decoding: diagnostics, as: UTF8.self)
        lock.unlock()
        if status != 0 && !quiet {
            report("Capture \(name) ended (SSH exit \(status)).\n\(detail)\nCheck SSH key authentication, the known-hosts entry, and the interface name.")
        }
        completeIfFinished()
    }

    private func viewerExited(_ status: Int32) {
        lock.lock()
        viewerEnded = true
        let quiet = stopping
        let detail = String(decoding: diagnostics, as: UTF8.self)
        let producerRunning = ssh.isRunning
        if producerRunning { stopping = true }
        lock.unlock()
        if status != 0 && !quiet {
            report("Wireshark for \(name) exited with status \(status).\n\(detail)")
        }
        if producerRunning { ssh.terminate() }
        completeIfFinished()
    }

    private func completeIfFinished() {
        lock.lock()
        let done = sshEnded && viewerEnded
        lock.unlock()
        guard done else { return }
        errors.fileHandleForReading.readabilityHandler = nil
        finished(id)
    }
}
