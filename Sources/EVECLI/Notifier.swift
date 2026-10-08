import Foundation
import EVECore

/// The macOS app surfaces failures in its settings window and brings the app
/// forward. A desktop-launched CLI has no window, so failures go to stderr
/// (which the capture log or the launching terminal keeps) and, when a
/// notification daemon is reachable, to the desktop as well.
public struct Notifier: Sendable {
    public let notifySendPath: String?

    public init(notifySendPath: String?) {
        self.notifySendPath = notifySendPath
    }

    public static func system() -> Notifier {
        Notifier(notifySendPath: ToolLookup.resolve("notify-send"))
    }

    public func error(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        guard let notifySendPath else { return }
        _ = try? Command.run(notifySendPath, ["-a", "EVE Connect", "-i", "utilities-terminal", "EVE Connect", message])
    }
}
