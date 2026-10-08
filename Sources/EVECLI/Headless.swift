import Foundation
import EVECore

/// The Linux counterpart of the macOS AppModel: it turns a link into a viewer
/// launch. There is no menu bar and no settings window, and each capture is its
/// own process, so there is nothing to keep running between links.
@MainActor
public final class Headless {
    public let configuration: Configuration
    public let configPath: String
    public let executablePath: String
    public let notifier: Notifier

    private var captures: [UUID: CaptureSession] = [:]
    private var spawned: [Process] = []
    private var finishedCapture: CheckedContinuation<Void, Never>?

    public init(configuration: Configuration, configPath: String, executablePath: String,
                notifier: Notifier = .system()) {
        self.configuration = configuration
        self.configPath = configPath
        self.executablePath = executablePath
        self.notifier = notifier
    }

    @discardableResult
    public func open(_ raw: String) throws -> Connection.Kind {
        let connection = try Connection(raw)
        switch connection.kind {
        case .telnet: try openConsole(connection)
        case .vnc: try openVNC(connection)
        case .capture: try startCapture(connection, raw: raw)
        }
        return connection.kind
    }

    /// Where a detached capture session's output goes. The child has no
    /// terminal; without this its diagnostics would be discarded.
    public var captureLogPath: String {
        let base = ProcessInfo.processInfo.environment["XDG_STATE_HOME"].flatMap { $0.isEmpty ? nil : $0 }
            ?? NSHomeDirectory() + "/.local/state"
        return base + "/eve-connect/capture.log"
    }

    /// Runs the SSH → Wireshark pipe until both ends are gone. Only ever called
    /// in the detached child, never in the process the launcher spawned.
    public func runCaptureSession(_ raw: String) async throws {
        let connection = try Connection(raw)
        guard connection.kind == .capture, connection.interface != nil else {
            throw ConnectError("A capture link is required.")
        }
        let wireshark = try tool(configuration.wireshark, key: "wireshark")
        let arguments = try LaunchPlan.captureArguments(connection: connection, user: configuration.sshUser,
                                                        identityFile: configuration.identityFile)
        let session = CaptureSession(connection: connection, arguments: arguments, wireshark: wireshark,
                                     report: { [notifier] message in notifier.error(message) },
                                     finished: { [weak self] id in self?.captureFinished(id) })
        try session.start()
        captures[session.id] = session
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if captures.isEmpty {
                continuation.resume()
            } else {
                finishedCapture = continuation
            }
        }
    }

    private func openConsole(_ connection: Connection) throws {
        let terminal = try tool(configuration.terminal, key: "terminal")
        let telnet = try tool(configuration.telnet, key: "telnet")
        let arguments = try LaunchPlan.linuxConsoleArguments(connection: connection, terminal: terminal, telnet: telnet)
        let result = try Command.run(arguments[0], Array(arguments.dropFirst()))
        guard result.status == 0 else {
            throw ConnectError("\(terminal) could not open the console for \(connection.displayName).\n\(result.output)")
        }
    }

    private func openVNC(_ connection: Connection) throws {
        let viewer = try tool(configuration.vnc, key: "vnc")
        spawned.append(try Command.spawnDetached(viewer, [connection.vncTarget]))
    }

    private func startCapture(_ connection: Connection, raw: String) throws {
        // The browser that followed the link should not stay blocked for the
        // life of the capture, so the pipe lives in a detached child.
        let child = try Command.spawnDetached(executablePath, ["--config", configPath, "--capture-session", raw],
                                              logPath: captureLogPath)
        spawned.append(child)
    }

    private func captureFinished(_ id: UUID) {
        captures.removeValue(forKey: id)
        guard captures.isEmpty, let continuation = finishedCapture else { return }
        finishedCapture = nil
        continuation.resume()
    }

    private func tool(_ value: String, key: String) throws -> String {
        guard let resolved = ToolLookup.resolve(value) else {
            throw ConnectError("'\(value)' (config key \(key)) was not found. Install it, or change \(key) in \(configPath).")
        }
        return resolved
    }
}
