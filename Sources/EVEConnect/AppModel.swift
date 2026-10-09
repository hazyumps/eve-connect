import AppKit
import SwiftUI
import EVECore

@MainActor
final class AppModel: ObservableObject {
    @Published var status = "Ready. Open an EVE link or paste one below."
    @Published var captureCount = 0
    @Published var handlers: [String: String] = [:]
    @Published var errorMessage: String?
    var onError: (() -> Void)?
    private var captures: [UUID: CaptureSession] = [:]
    private var scripts: [UUID: Process] = [:]

    func refreshHandlers() {
        for scheme in ["telnet", "vnc", "capture"] {
            handlers[scheme] = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "\(scheme)://localhost")!)?
                .deletingPathExtension().lastPathComponent ?? "None"
        }
    }

    func makeDefault() async {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            fail(ConnectError("Build and open the .app bundle before setting URL handlers.")); return
        }
        do {
            for scheme in ["telnet", "vnc", "capture"] {
                try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: scheme)
            }
            status = "EVE Connect now handles telnet, VNC, and capture links."
        } catch { fail(error) }
        refreshHandlers()
    }

    func open(_ raw: String) {
        do {
            let connection = try Connection(raw)
            switch connection.kind {
            case .telnet: try openConsole(connection)
            case .vnc: try openVNC(connection)
            case .capture: try openCapture(connection)
            }
        } catch { fail(error) }
    }

    func stopCaptures() {
        for capture in captures.values { capture.stop() }
        status = "Capture streams stopped. Wireshark windows remain available for saving."
    }

    func prepareToQuit() {
        stopCaptures()
        for process in scripts.values where process.isRunning { process.terminate() }
    }

    func fail(_ error: Error) {
        errorMessage = error.localizedDescription
        status = error.localizedDescription
        onError?()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setting(_ key: String, fallback: String) -> String {
        UserDefaults.standard.string(forKey: key) ?? fallback
    }

    private func executable(_ path: String) throws -> String {
        let expanded = (path as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: expanded) else {
            throw ConnectError("Executable not found: \(expanded). Check its path in EVE Connect settings.")
        }
        return expanded
    }

    private func openConsole(_ connection: Connection) throws {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.mitchellh.ghostty") != nil else {
            throw ConnectError("Install Ghostty 1.3.1 or newer to open console sessions.")
        }
        let telnet = try executable(setting("telnetPath", fallback: "/opt/homebrew/bin/telnet"))
        let script = try LaunchPlan.ghosttyScript(connection: connection, telnet: telnet,
                                                  preferTab: UserDefaults.standard.bool(forKey: "preferTab"))
        let process = Process()
        let output = Pipe()
        let id = UUID()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = output
        // osascript's diagnostics are short. Drain off the main thread so an
        // Automation permission prompt never freezes the settings window.
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            let detail = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.scripts.removeValue(forKey: id)
                if status != 0 {
                    self.fail(ConnectError("Ghostty could not open the console.\n\(detail)\nAllow Automation access to Ghostty, and ensure macos-applescript is enabled in Ghostty."))
                } else { self.status = "Opened \(connection.displayName) in Ghostty." }
            }
        }
        try process.run()
        try? output.fileHandleForWriting.close()
        scripts[id] = process
        status = "Opening \(connection.displayName) in Ghostty…"
    }

    private func openVNC(_ connection: Connection) throws {
        let path = try executable(setting("vncPath", fallback: "/Applications/VNC Viewer.app/Contents/MacOS/vncviewer"))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = [connection.vncTarget]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            guard status != 0 else { return }
            Task { @MainActor [weak self] in
                self?.fail(ConnectError("VNC Viewer for \(connection.displayName) exited with status \(status). Check the viewer and the node's console port."))
            }
        }
        try process.run()
        status = "Opened \(connection.displayName) in VNC Viewer."
    }

    private func openCapture(_ connection: Connection) throws {
        let defaultWireshark = FileManager.default.fileExists(atPath: "/Applications/Wireshark.app")
            ? "/Applications/Wireshark.app/Contents/MacOS/Wireshark"
            : "/Applications/Eve Wireshark.app/Contents/MacOS/Wireshark"
        let path = try executable(setting("wiresharkPath", fallback: defaultWireshark))
        let arguments = try LaunchPlan.captureArguments(connection: connection,
            user: setting("sshUser", fallback: "root"), identityFile: setting("identityFile", fallback: ""))
        let session = CaptureSession(connection: connection, arguments: arguments, wireshark: path,
            report: { [weak self] message in
                Task { @MainActor in self?.fail(ConnectError(message)) }
            },
            finished: { [weak self] id in
                Task { @MainActor in
                    self?.captures.removeValue(forKey: id)
                    self?.captureCount = self?.captures.count ?? 0
                }
            })
        // Register before starting: the process handlers run on Foundation's own
        // threads now, so a capture can finish before start() returns.
        captures[session.id] = session
        captureCount = captures.count
        do {
            try session.start()
        } catch {
            captures.removeValue(forKey: session.id)
            captureCount = captures.count
            throw error
        }
        status = "Started capture for \(connection.displayName)."
    }
}
