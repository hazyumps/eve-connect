import Foundation
import EVECore

/// Turns a configured program name or path into an absolute executable path,
/// the way the macOS app resolved the paths typed into its settings window.
public enum ToolLookup {
    public static let fallbackDirectories = [
        "/usr/local/bin", "/usr/bin", "/bin", "/usr/local/sbin", "/usr/sbin", "/sbin", "/opt/homebrew/bin"
    ]

    /// `~` is expanded and a bare name is searched on PATH. A value containing
    /// a slash is treated as a path and used only if it is executable.
    public static func resolve(_ value: String, searchPath: String? = nil,
                               exists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> String? {
        let expanded = (value as NSString).expandingTildeInPath
        if expanded.contains("/") {
            return exists(expanded) ? expanded : nil
        }
        let path = searchPath ?? ProcessInfo.processInfo.environment["PATH"] ?? ""
        var directories = path.split(separator: ":").map(String.init)
        directories.append(contentsOf: fallbackDirectories)
        for directory in directories where !directory.isEmpty {
            let candidate = directory + "/" + expanded
            if exists(candidate) { return candidate }
        }
        return nil
    }
}
