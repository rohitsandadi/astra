import Foundation

public enum DomainRuleError: Error, Equatable, Sendable {
    case empty
    case invalidHost
    case loopbackHost
}

public struct DomainRule: Hashable, Codable, Sendable {
    public let host: String
    public let includeSubdomains: Bool

    public init(_ input: String, includeSubdomains: Bool = true) throws {
        self.host = try Self.normalize(input)
        self.includeSubdomains = includeSubdomains
    }

    public static func normalize(_ input: String) throws -> String {
        var candidate = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { throw DomainRuleError.empty }

        // URLComponents needs a scheme to distinguish a host from a path.
        if !candidate.contains("://") {
            candidate = "https://\(candidate)"
        }

        guard let components = URLComponents(string: candidate),
              var normalized = components.host?.lowercased(),
              !normalized.isEmpty
        else {
            throw DomainRuleError.invalidHost
        }

        // A single trailing dot is valid fully-qualified-domain notation. A
        // leading dot is not a host and must not be silently repaired.
        if normalized.hasSuffix(".") {
            normalized.removeLast()
        }
        if normalized.hasPrefix("www.") {
            normalized.removeFirst(4)
        }

        guard !normalized.isEmpty, normalized.count <= 253 else {
            throw DomainRuleError.invalidHost
        }
        if isLoopback(normalized) {
            throw DomainRuleError.loopbackHost
        }
        guard isValidHost(normalized) else {
            throw DomainRuleError.invalidHost
        }
        return normalized
    }

    public func matches(host candidate: String) -> Bool {
        guard let normalizedCandidate = try? Self.normalize(candidate) else { return false }
        if normalizedCandidate == host { return true }
        return includeSubdomains && normalizedCandidate.hasSuffix(".\(host)")
    }

    public func matches(url: URL) -> Bool {
        guard let candidateHost = url.host else { return false }
        return matches(host: candidateHost)
    }

    private static func isLoopback(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".localhost") {
            return true
        }

        let unwrapped = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if unwrapped == "::1" || unwrapped == "0:0:0:0:0:0:0:1" {
            return true
        }

        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        if octets.count == 4,
           let first = Int(octets[0]),
           first == 127,
           octets.allSatisfy({ part in
               guard let value = Int(part) else { return false }
               return (0 ... 255).contains(value)
           }) {
            return true
        }
        return false
    }

    private static func isValidHost(_ host: String) -> Bool {
        // IPv6 hosts are accepted after URLComponents has parsed them. The
        // loopback forms above remain forbidden.
        if host.contains(":") {
            return host.unicodeScalars.allSatisfy {
                CharacterSet(charactersIn: "0123456789abcdef:[]").contains($0)
            }
        }

        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard !labels.isEmpty else { return false }
        if labels.count == 4, labels.allSatisfy({ Int($0) != nil }) {
            return labels.allSatisfy { label in
                guard let octet = Int(label) else { return false }
                return (0 ... 255).contains(octet)
            }
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        return labels.allSatisfy { label in
            guard !label.isEmpty,
                  label.count <= 63,
                  label.first != "-",
                  label.last != "-"
            else {
                return false
            }
            return label.unicodeScalars.allSatisfy { allowed.contains($0) }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case host
        case includeSubdomains
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedHost = try container.decode(String.self, forKey: .host)
        let includeSubdomains = try container.decode(Bool.self, forKey: .includeSubdomains)
        do {
            try self.init(decodedHost, includeSubdomains: includeSubdomains)
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .host,
                in: container,
                debugDescription: "Invalid domain rule: \(error)"
            )
        }
    }
}
