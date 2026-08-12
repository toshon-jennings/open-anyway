import Foundation

/// Gatekeeper assessment is expensive — it hashes the entire bundle, which costs
/// seconds on a large app. Results are cached against a fingerprint that changes
/// whenever the bundle or its quarantine record does, so repeat scans are free.
struct AssessmentCache {
    struct Entry: Codable, Sendable {
        var fingerprint: String
        var accepted: Bool
        var detail: String
    }

    private static let defaultsKey = "assessmentCache.v1"
    private var entries: [String: Entry]

    init() {
        let data = UserDefaults.standard.data(forKey: Self.defaultsKey) ?? Data()
        entries = (try? JSONDecoder().decode([String: Entry].self, from: data)) ?? [:]
    }

    /// Bundle mtime plus the raw quarantine value: a rebuild moves the first, a
    /// re-download moves the second.
    static func fingerprint(for url: URL) -> String {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate?.timeIntervalSince1970 ?? 0
        let quarantine = Quarantine.rawValue(at: url.path) ?? ""
        return "\(modified)|\(quarantine)"
    }

    func entry(for url: URL, fingerprint: String) -> Entry? {
        guard let entry = entries[url.path], entry.fingerprint == fingerprint else { return nil }
        return entry
    }

    mutating func store(_ entry: Entry, for url: URL) {
        entries[url.path] = entry
    }

    /// Drop apps that are no longer candidates so the cache can't grow without bound.
    mutating func prune(keeping paths: Set<String>) {
        entries = entries.filter { paths.contains($0.key) }
    }

    func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}
