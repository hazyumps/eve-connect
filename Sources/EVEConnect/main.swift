import AppKit
import SwiftUI
import EVECore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let model = AppModel()
    private var window: NSWindow?
    private var statusItem: NSStatusItem?
    private var stopItem: NSMenuItem?

    func applicationWillFinishLaunching(_ notification: Notification) {
        model.onError = { [weak self] in self?.showWindow() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        menu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit EVE Connect", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let editItem = NSMenuItem()
        editItem.title = "Edit"
        menu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        editItem.submenu = editMenu
        NSApp.mainMenu = menu
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "EVE Connect")
        statusItem.button?.toolTip = "EVE Connect — consoles and captures"
        let statusMenu = NSMenu()
        statusMenu.autoenablesItems = false
        statusMenu.delegate = self
        let settings = statusMenu.addItem(withTitle: "EVE Connect Settings…", action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        let stop = statusMenu.addItem(withTitle: "Stop capture streams", action: #selector(stopStreams), keyEquivalent: "")
        stop.target = self
        stopItem = stop
        statusMenu.addItem(.separator())
        let quit = statusMenu.addItem(withTitle: "Quit EVE Connect", action: #selector(quitApp), keyEquivalent: "")
        quit.target = self
        statusItem.menu = statusMenu
        self.statusItem = statusItem
        model.refreshHandlers()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { model.open(url.absoluteString) }
    }

    // Browsers can send a reopen/activation event before delivering a URL.
    // Neither normal launch nor reopen is an explicit request for settings.
    // Only the menu-bar Settings action (or a reported error) opens the window.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func menuNeedsUpdate(_ menu: NSMenu) {
        stopItem?.isEnabled = model.captureCount > 0
        stopItem?.title = model.captureCount > 0 ? "Stop capture streams (\(model.captureCount) sessions)" : "No capture sessions"
    }

    @objc private func openSettings() { showWindow() }
    @objc private func stopStreams() { model.stopCaptures() }
    @objc private func quitApp() { NSApp.terminate(nil) }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        return false
    }

    func applicationWillTerminate(_ notification: Notification) { model.prepareToQuit() }

    private func showWindow() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 620),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "EVE Connect"
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @AppStorage("preferTab") private var preferTab = false
    @AppStorage("telnetPath") private var telnetPath = "/opt/homebrew/bin/telnet"
    @AppStorage("vncPath") private var vncPath = "/Applications/VNC Viewer.app/Contents/MacOS/vncviewer"
    @AppStorage("wiresharkPath") private var wiresharkPath = FileManager.default.fileExists(atPath: "/Applications/Wireshark.app")
        ? "/Applications/Wireshark.app/Contents/MacOS/Wireshark" : "/Applications/Eve Wireshark.app/Contents/MacOS/Wireshark"
    @AppStorage("sshUser") private var sshUser = "root"
    @AppStorage("identityFile") private var identityFile = ""
    @State private var link = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 52, height: 52)
                VStack(alignment: .leading) {
                    Text("EVE Connect").font(.title.bold())
                    Text("Close this window — EVE links keep working in the background.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Form {
                Section("Console") {
                    Toggle("Open consoles in a new Ghostty tab", isOn: $preferTab)
                    dependency("Telnet", path: $telnetPath)
                }
                Section("Viewers") {
                    dependency("VNC Viewer", path: $vncPath)
                    dependency("Wireshark", path: $wiresharkPath)
                }
                Section("Capture authentication") {
                    TextField("SSH user", text: $sshUser)
                    TextField("Identity file (optional)", text: $identityFile)
                    Text("Leave identity blank to use SSH config / agent. The server must already be trusted and key authentication working. No passwords are stored.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped)
            HStack {
                TextField("telnet://host:port", text: $link)
                    .textFieldStyle(.roundedBorder).onSubmit { model.open(link) }
                Button("Open link") { model.open(link) }.disabled(link.isEmpty)
            }
            HStack {
                Text(["telnet", "vnc", "capture"].map { "\($0): \(model.handlers[$0] ?? "…")" }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Refresh") { model.refreshHandlers() }
            }
            HStack {
                Button("Make default for EVE links") { Task { await model.makeDefault() } }
                Spacer()
                if model.captureCount > 0 {
                    Button("Stop capture streams (\(model.captureCount))") { model.stopCaptures() }
                }
            }
            Text(model.status).font(.caption).lineLimit(3).textSelection(.enabled)
        }
        .padding(24).frame(width: 660, height: 620)
        .alert("EVE Connect", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private func dependency(_ name: String, path: Binding<String>) -> some View {
        HStack {
            TextField(name, text: path)
            Image(systemName: FileManager.default.isExecutableFile(atPath: (path.wrappedValue as NSString).expandingTildeInPath) ? "checkmark.circle.fill" : "exclamationmark.triangle")
                .accessibilityLabel("Executable availability")
        }
    }
}

// Headless validation exercises the same parser and launch plans without
// registering handlers, starting applications, or making network connections.
if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--dry-run" {
    do {
        let connection = try Connection(CommandLine.arguments[2])
        switch connection.kind {
        case .telnet:
            print(try LaunchPlan.ghosttyScript(connection: connection, telnet: "/opt/homebrew/bin/telnet", preferTab: false))
        case .vnc:
            print("VNC Viewer argument: \(connection.vncTarget)")
        case .capture:
            print(try LaunchPlan.captureArguments(connection: connection, user: "root", identityFile: ""))
        }
    } catch {
        FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
        exit(1)
    }
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
