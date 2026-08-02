import Foundation

struct AstraGitHubRelease: Decodable, Sendable {
    let tagName: String
    let pageURL: URL

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case pageURL = "html_url"
    }
}

struct AstraUpdateChecker: Sendable {
    static let latestReleaseEndpoint = URL(
        string: "https://api.github.com/repos/rohitsandadi/astra/releases/latest"
    )!

    func latestRelease(currentVersion: String) async throws -> AstraGitHubRelease {
        var request = URLRequest(url: Self.latestReleaseEndpoint)
        request.timeoutInterval = 12
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Astra/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ..< 300).contains(httpResponse.statusCode)
        else {
            throw AstraUpdateError.unavailable
        }
        return try JSONDecoder().decode(AstraGitHubRelease.self, from: data)
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let lhs = components(candidate)
        let rhs = components(current)
        for index in 0 ..< max(lhs.count, rhs.count) {
            let candidatePart = index < lhs.count ? lhs[index] : 0
            let currentPart = index < rhs.count ? rhs[index] : 0
            if candidatePart != currentPart { return candidatePart > currentPart }
        }
        return false
    }

    private static func components(_ version: String) -> [Int] {
        version
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: ".")
            .map { component in
                Int(component.prefix(while: \.isNumber)) ?? 0
            }
    }
}

enum AstraUpdateError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "GitHub Releases is unavailable right now. Try again later."
    }
}
