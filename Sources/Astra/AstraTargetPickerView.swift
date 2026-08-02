import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AstraTargetPickerView: View {
    @Binding var draft: AstraPreset
    @StateObject private var catalog = AstraApplicationCatalog()
    @State private var section: TargetSection = .apps
    @State private var search = ""
    @State private var domainEntry = ""
    @State private var domainError: String?
    @State private var showsFileImporter = false

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Picker("Targets", selection: $section) {
                    ForEach(TargetSection.allCases) { section in
                        Label(section.title, systemImage: section.systemImage).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 360)

                Spacer()

                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Group {
                switch section {
                case .apps: apps
                case .websites: websites
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .task { catalog.load() }
        .fileImporter(
            isPresented: $showsFileImporter,
            allowedContentTypes: [.applicationBundle],
            allowsMultipleSelection: true,
            onCompletion: handleAppSelection
        )
        .alert(
            "That target could not be added",
            isPresented: Binding(
                get: { domainError != nil },
                set: { if !$0 { domainError = nil } }
            )
        ) {
            Button("OK") { domainError = nil }
        } message: {
            Text(domainError ?? "")
        }
    }

    private var apps: some View {
        VStack(spacing: 12) {
            HStack(spacing: 9) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search installed apps", text: $search)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 1)
                }

                Button("Choose Other…") { showsFileImporter = true }
                    .buttonStyle(.bordered)
            }

            if catalog.isLoading {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Finding apps on this Mac…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredApplications.isEmpty {
                ContentUnavailableView.search(text: search)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredApplications.prefix(100)) { application in
                            applicationRow(application)
                            if application.id != filteredApplications.prefix(100).last?.id {
                                Divider().padding(.leading, 49)
                            }
                        }
                    }
                }
                .background(Color.white.opacity(0.028), in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.075), lineWidth: 1)
                }
            }
        }
    }

    private func applicationRow(_ application: AstraCatalogApplication) -> some View {
        let isSelected = draft.applications.contains(where: {
            $0.bundleIdentifier == application.bundleIdentifier
        })
        let blocked = AstraBlockedApplication(
            bundleIdentifier: application.bundleIdentifier,
            displayName: application.displayName
        )

        return Button {
            toggle(blocked)
        } label: {
            HStack(spacing: 12) {
                AstraAppIcon(application: blocked, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(application.displayName)
                        .foregroundStyle(.primary)
                    Text(application.bundleIdentifier)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.body.weight(.medium))
                    .foregroundStyle(isSelected ? Color.astraAccent : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    private var websites: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Add a website")
                    .font(.headline)
                HStack(spacing: 9) {
                    TextField("Paste a URL or type a domain", text: $domainEntry)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addDomain)
                    Button("Add") { addDomain() }
                        .buttonStyle(.bordered)
                        .disabled(domainEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Text("Astra stores only the domain and includes its subdomains. Paths are discarded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Common pulls")
                    .font(.headline)
                Spacer()
                TextField("Filter suggestions", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 190)
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredWebsiteSuggestions) { suggestion in
                        websiteRow(suggestion)
                        if suggestion.id != filteredWebsiteSuggestions.last?.id {
                            Divider().padding(.leading, 42)
                        }
                    }
                }
            }
            .frame(minHeight: 140, maxHeight: 210)
            .background(Color.white.opacity(0.028), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.075), lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Selected websites")
                    .font(.headline)
                if draft.domains.isEmpty {
                    Label("No websites selected", systemImage: "globe")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                } else {
                    FlowLayout(spacing: 7) {
                        ForEach(draft.domains, id: \.self) { domain in
                            HStack(spacing: 6) {
                                Text(domain)
                                Button {
                                    draft.domains.removeAll(where: { $0 == domain })
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove \(domain)")
                            }
                            .font(.callout)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.055), in: Capsule())
                            .overlay { Capsule().stroke(Color.white.opacity(0.075), lineWidth: 1) }
                        }
                    }
                }
            }
        }
    }

    private func websiteRow(_ suggestion: WebsiteSuggestion) -> some View {
        let isSelected = draft.domains.contains(suggestion.domain)
        return Button {
            if isSelected {
                draft.domains.removeAll(where: { $0 == suggestion.domain })
            } else {
                draft.domains.append(suggestion.domain)
                draft.domains.sort()
            }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: suggestion.systemImage)
                    .foregroundStyle(isSelected ? Color.astraAccent : .secondary)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(suggestion.name).foregroundStyle(.primary)
                    Text(suggestion.domain).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.astraAccent : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var filteredApplications: [AstraCatalogApplication] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return catalog.applications }
        return catalog.applications.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
                || $0.bundleIdentifier.localizedCaseInsensitiveContains(query)
        }
    }

    private var filteredWebsiteSuggestions: [WebsiteSuggestion] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return WebsiteSuggestion.defaults }
        return WebsiteSuggestion.defaults.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.domain.localizedCaseInsensitiveContains(query)
        }
    }

    private var summary: String {
        "\(draft.applications.count) apps · \(draft.domains.count) websites"
    }

    private func toggle(_ application: AstraBlockedApplication) {
        if let index = draft.applications.firstIndex(where: {
            $0.bundleIdentifier == application.bundleIdentifier
        }) {
            draft.applications.remove(at: index)
        } else {
            draft.applications.append(application)
            draft.applications.sort {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        }
    }

    private func addDomain() {
        do {
            let domain = try AstraDomainNormalizer.normalize(domainEntry)
            if !draft.domains.contains(domain) {
                draft.domains.append(domain)
                draft.domains.sort()
            }
            domainEntry = ""
        } catch {
            domainError = error.localizedDescription
        }
    }

    private func handleAppSelection(_ result: Result<[URL], Error>) {
        do {
            for url in try result.get() {
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
                guard let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier else { continue }
                guard !AstraProtectedApplications.bundleIdentifiers.contains(identifier),
                      identifier != Bundle.main.bundleIdentifier else {
                    domainError = "Astra cannot block itself or a critical macOS process."
                    continue
                }
                guard !draft.applications.contains(where: { $0.bundleIdentifier == identifier }) else { continue }
                let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                draft.applications.append(
                    AstraBlockedApplication(bundleIdentifier: identifier, displayName: name)
                )
            }
            draft.applications.sort {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        } catch {
            domainError = "The selected apps could not be read: \(error.localizedDescription)"
        }
    }
}

private enum TargetSection: String, CaseIterable, Identifiable {
    case apps
    case websites

    var id: Self { self }
    var title: String { self == .apps ? "Apps" : "Websites" }
    var systemImage: String { self == .apps ? "app.dashed" : "globe" }
}

private struct WebsiteSuggestion: Identifiable {
    var id: String { domain }
    var name: String
    var domain: String
    var systemImage: String

    static let defaults: [WebsiteSuggestion] = [
        .init(name: "YouTube", domain: "youtube.com", systemImage: "play.rectangle"),
        .init(name: "Reddit", domain: "reddit.com", systemImage: "bubble.left.and.bubble.right"),
        .init(name: "Instagram", domain: "instagram.com", systemImage: "camera"),
        .init(name: "TikTok", domain: "tiktok.com", systemImage: "music.note"),
        .init(name: "X", domain: "x.com", systemImage: "text.bubble"),
        .init(name: "Facebook", domain: "facebook.com", systemImage: "person.2"),
        .init(name: "Twitch", domain: "twitch.tv", systemImage: "livephoto.play"),
        .init(name: "Netflix", domain: "netflix.com", systemImage: "film"),
        .init(name: "LinkedIn", domain: "linkedin.com", systemImage: "briefcase")
    ]
}

/// Compact wrapping layout for locally stored domain tokens.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(
        proposal: ProposedViewSize,
        subviews: Subviews
    ) -> (size: CGSize, points: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var points: [CGPoint] = []
        var cursor = CGPoint.zero
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursor.x > 0, cursor.x + size.width > maxWidth {
                cursor.x = 0
                cursor.y += rowHeight + spacing
                rowHeight = 0
            }
            points.append(cursor)
            cursor.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            usedWidth = max(usedWidth, cursor.x - spacing)
        }
        return (CGSize(width: usedWidth, height: cursor.y + rowHeight), points)
    }
}
