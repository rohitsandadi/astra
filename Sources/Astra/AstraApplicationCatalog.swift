import Foundation

struct AstraCatalogApplication: Identifiable, Hashable, Sendable {
    var id: String { bundleIdentifier }
    var bundleIdentifier: String
    var displayName: String
}

@MainActor
final class AstraApplicationCatalog: ObservableObject {
    @Published private(set) var applications: [AstraCatalogApplication] = []
    @Published private(set) var isLoading = false

    private var didLoad = false

    func load() {
        guard !didLoad else { return }
        didLoad = true
        isLoading = true
        Task {
            let discovered = await Task.detached(priority: .utility) {
                Self.discoverApplications()
            }.value
            applications = discovered
            isLoading = false
        }
    }

    nonisolated static func discoverApplications(
        roots: [URL] = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]
    ) -> [AstraCatalogApplication] {
        let manager = FileManager.default
        var byIdentifier: [String: AstraCatalogApplication] = [:]

        for root in roots where manager.fileExists(atPath: root.path) {
            guard let enumerator = manager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isApplicationKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator where url.pathExtension.lowercased() == "app" {
                guard let bundle = Bundle(url: url),
                      let identifier = bundle.bundleIdentifier,
                      !AstraProtectedApplications.bundleIdentifiers.contains(identifier)
                else { continue }

                let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                byIdentifier[identifier] = AstraCatalogApplication(
                    bundleIdentifier: identifier,
                    displayName: name
                )
            }
        }

        return byIdentifier.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }
}
