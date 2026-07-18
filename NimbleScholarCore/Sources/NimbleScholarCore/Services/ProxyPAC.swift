import Foundation

/// Builds the PAC (Proxy Auto-Config) script handed to URLSession when the download
/// proxy is enabled: try the user's proxy first, and fall back to a DIRECT connection
/// when the proxy isn't reachable (e.g. the VPN app behind it isn't running). Plain
/// "HTTPProxy"-style proxy keys have no fallback semantics — with those, a dead proxy
/// port fails every request instead of degrading to a direct connection.
public enum ProxyPAC {
    /// PAC script routing every request "PROXY host:port; DIRECT".
    /// Returns nil when host/port can't form a valid proxy endpoint.
    public static func script(host: String, port: Int) -> String? {
        guard (1...65535).contains(port), let host = sanitizedHost(host) else { return nil }
        return "function FindProxyForURL(url, host) { return \"PROXY \(host):\(port); DIRECT\"; }"
    }

    /// Hostname/IPv4 allowlist — refuses anything that could escape the quoted PAC
    /// string (spaces, quotes, semicolons). IPv6 literals aren't valid in PAC "PROXY"
    /// entries, so ":" is rejected too.
    static func sanitizedHost(_ raw: String) -> String? {
        let host = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, host.count <= 253,
              host.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") })
        else { return nil }
        return host
    }
}
