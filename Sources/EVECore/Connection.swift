import Foundation
import Darwin

public struct Connection: Equatable, Sendable {
    public enum Kind: String, Sendable { case telnet, vnc, capture }
    public let kind: Kind
    public let host: String
    public let port: Int?
    public let interface: String?

    public init(_ raw: String) throws {
        // Parse the actual EVE wire format, including VNC's host::port notation.
        // Deliberately reject credentials, escapes, queries and shell syntax.
        let pattern = #"^(telnet|vnc|capture)://(\[[0-9A-Fa-f:]+\]|[A-Za-z0-9][A-Za-z0-9._-]*)(?:(::?)([0-9]{1,5}))?(/[^?#]*)?$"#
        let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let range = NSRange(raw.startIndex..., in: raw)
        guard let match = regex.firstMatch(in: raw, range: range), match.range == range else {
            throw ConnectError("Expected telnet://host:port, vnc://host:port, or capture://host/interface.")
        }
        func part(_ index: Int) -> String {
            guard let range = Range(match.range(at: index), in: raw) else { return "" }
            return String(raw[range])
        }
        kind = Kind(rawValue: part(1).lowercased())!
        let authority = part(2)
        host = authority.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if authority.hasPrefix("[") {
            var address = in6_addr()
            guard inet_pton(AF_INET6, host, &address) == 1 else { throw ConnectError("Invalid IPv6 address.") }
        } else {
            let labels = host.hasSuffix(".") ? String(host.dropLast()).split(separator: ".", omittingEmptySubsequences: false) : host.split(separator: ".", omittingEmptySubsequences: false)
            guard host.count <= 253, labels.allSatisfy({ !$0.isEmpty && $0.count <= 63 && !$0.hasPrefix("-") && !$0.hasSuffix("-") }) else {
                throw ConnectError("Invalid host name.")
            }
        }
        guard part(3) != "::" || kind == .vnc else { throw ConnectError("Double-colon ports are only supported for VNC.") }
        let specifiedPort = Int(part(4))
        if let specifiedPort, !(1...65535).contains(specifiedPort) { throw ConnectError("Port must be between 1 and 65535.") }
        if kind == .capture {
            guard specifiedPort == nil, part(5).hasPrefix("/") else { throw ConnectError("Capture links require a host and interface, without a port.") }
            let name = String(part(5).dropFirst())
            guard name.range(of: #"^[A-Za-z0-9][A-Za-z0-9_.:-]{0,14}$"#, options: .regularExpression) != nil,
                  !name.contains("\n") else { throw ConnectError("Invalid capture interface name.") }
            interface = name
            port = nil
        } else {
            guard part(5).isEmpty || part(5) == "/" else { throw ConnectError("Console links cannot contain a path.") }
            interface = nil
            port = specifiedPort ?? (kind == .telnet ? 23 : 5900)
        }
    }

    public var displayName: String { "\(host):\(interface ?? String(port ?? 0))" }

    // RealVNC uses a double colon for an absolute TCP port, not a display number.
    public var vncTarget: String { "\(host.contains(":") ? "[\(host)]" : host)::\(port!)" }
}

public struct ConnectError: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
