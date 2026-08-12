import AppKit
import Combine

/// One assessed candidate. Free of AppKit types so it can cross back from the
/// background assessment; the icon is attached on the main actor.
struct ScanResult: Sendable {
    var url: URL
    var name: String
    var accepted: Bool
    var detail: String
    var fingerprint: String
    var provenance: Quarantine.Provenance
}

struct BlockedApp: Identifiable, Equatable {
    var id: String { url.path }
    var url: URL
    var name: String
    var icon: NSImage
    var reason: String
    var provenance: Quarantine.Provenance

    static func == (lhs: BlockedApp, rhs: BlockedApp) -> Bool { lhs.url == rhs.url }

    /// "Downloaded by Chrome · Jun 1" — the trust cue that makes the click an
    /// informed one rather than a reflex.
    var provenanceLine: String {
        var parts: [String] = []
        if let agent = provenance.agent { parts.append("Downloaded by \(agent)") }
        if let date = provenance.downloadedAt {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            parts.append(formatter.string(from: date))
        }
        return parts.joined(separator: " · ")
    }
}

@MainActor
final class BlockedAppStore: ObservableObject {
    @Published private(set) var apps: [BlockedApp] = []
    @Published private(set) var isScanning = false
    /// Folders the scan couldn't read. Surfaced so reduced coverage is visible
    /// rather than looking like a clean result.
    @Published private(set) var deniedFolders: [String] = []
    @Published var lastError: String?

    private var cache = AssessmentCache()

    /// Assessments are independent subprocesses, so they overlap. Capped rather
    /// than unbounded to avoid a burst of processes all hashing at once.
    nonisolated private static let maxConcurrentAssessments = 6

    /// Where unsigned apps realistically land. Scanned one level deep only —
    /// deep-walking the home directory would cost far more than it finds.
    nonisolated private static var searchRoots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            home.appendingPathComponent("Applications"),
            home.appendingPathComponent("Downloads"),
            home.appendingPathComponent("Desktop"),
        ]
    }

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        Task { await runScan() }
    }

    private func runScan() async {
        var found: [BlockedApp] = []
        var seen: Set<String> = []
        var denied: [String] = []

        // One root at a time. ~/Downloads and ~/Desktop are permission-protected:
        // reading them blocks in the kernel until the user answers a consent
        // prompt, which may be never. Handling roots separately means a folder
        // that stalls can't hold back the results already gathered from the ones
        // that didn't.
        for root in Self.searchRoots {
            let scanned = await Task.detached(priority: .userInitiated) {
                Self.quarantinedCandidates(in: root)
            }.value

            if scanned.denied {
                denied.append(FileManager.default.displayName(atPath: root.path))
                deniedFolders = denied
            }
            let candidates = scanned.apps

            // Cache is read here, on the actor, so the concurrent assessment below
            // never has to reach back into `self`.
            let prepared = candidates.map { url -> Candidate in
                let fingerprint = AssessmentCache.fingerprint(for: url)
                return Candidate(url: url, fingerprint: fingerprint,
                                 cached: cache.entry(for: url, fingerprint: fingerprint))
            }

            for await result in Self.assess(prepared) {
                cache.store(
                    .init(fingerprint: result.fingerprint, accepted: result.accepted, detail: result.detail),
                    for: result.url
                )
                guard !result.accepted else { continue }

                // Published as they arrive: a small blocked app surfaces in
                // milliseconds instead of waiting on the largest bundle.
                found.append(Self.makeApp(result))
                apps = Self.sorted(found)
            }

            seen.formUnion(candidates.map(\.path))
        }

        cache.prune(keeping: seen)
        cache.save()
        apps = Self.sorted(found)
        deniedFolders = denied
        isScanning = false
    }

    private struct Candidate: Sendable {
        var url: URL
        var fingerprint: String
        var cached: AssessmentCache.Entry?
    }

    /// Runs assessments concurrently, yielding each as it lands. Bounded by a
    /// sliding window rather than firing every subprocess at once.
    nonisolated private static func assess(_ candidates: [Candidate]) -> AsyncStream<ScanResult> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                await withTaskGroup(of: ScanResult?.self) { group in
                    var iterator = candidates.makeIterator()
                    var inFlight = 0

                    while inFlight < maxConcurrentAssessments, let next = iterator.next() {
                        group.addTask { evaluate(next) }
                        inFlight += 1
                    }

                    while inFlight > 0, let result = await group.next() {
                        inFlight -= 1
                        if let next = iterator.next() {
                            group.addTask { evaluate(next) }
                            inFlight += 1
                        }
                        if let result { continuation.yield(result) }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Only quarantined apps can be blocked, and the check is a single syscall —
    /// so it filters ~200 apps down to the handful worth assessing.
    ///
    /// An unreadable root yields nothing rather than failing the scan: denying the
    /// permission prompt should cost that one folder, not every result. The denial
    /// is reported back, because a folder that silently contributes nothing looks
    /// exactly like a folder with nothing in it.
    nonisolated private static func quarantinedCandidates(in root: URL) -> (apps: [URL], denied: Bool) {
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            return (contents.filter { $0.pathExtension == "app" && Quarantine.isQuarantined(at: $0.path) }, false)
        } catch CocoaError.fileReadNoPermission {
            return ([], true)
        } catch {
            // A root that simply isn't there — ~/Applications often isn't — is
            // not something to report.
            return ([], false)
        }
    }

    nonisolated private static func evaluate(_ candidate: Candidate) -> ScanResult? {
        let url = candidate.url
        let accepted: Bool
        let detail: String

        if let cached = candidate.cached {
            accepted = cached.accepted
            detail = cached.detail
        } else {
            let assessment = Gatekeeper.assess(path: url.path)
            accepted = assessment.accepted
            detail = assessment.detail
        }

        return ScanResult(
            url: url,
            name: FileManager.default.displayName(atPath: url.path),
            accepted: accepted,
            detail: detail,
            fingerprint: candidate.fingerprint,
            provenance: Quarantine.provenance(at: url.path)
        )
    }

    private static func makeApp(_ result: ScanResult) -> BlockedApp {
        BlockedApp(
            url: result.url,
            name: result.name,
            icon: NSWorkspace.shared.icon(forFile: result.url.path),
            reason: result.detail,
            provenance: result.provenance
        )
    }

    private static func sorted(_ apps: [BlockedApp]) -> [BlockedApp] {
        apps.sorted { ($0.provenance.downloadedAt ?? .distantPast) > ($1.provenance.downloadedAt ?? .distantPast) }
    }

    /// The "Open Anyway" action: drop the quarantine flag, repair the signature if
    /// the bundle is damaged, then launch.
    func openAnyway(_ app: BlockedApp) {
        lastError = nil
        let url = app.url
        apps.removeAll { $0.url == url }

        Task.detached(priority: .userInitiated) {
            if let failure = Quarantine.remove(at: url.path) {
                await MainActor.run {
                    self.lastError = failure
                    self.scan()
                }
                return
            }

            // A broken seal blocks launch even with quarantine gone, and only shows
            // up as "damaged" — so repair it here rather than after the user is stuck.
            if Gatekeeper.assess(path: url.path).detail.contains("resources") {
                _ = Gatekeeper.adHocSign(path: url.path)
            }

            await MainActor.run {
                NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
                    guard let error else { return }
                    let message = error.localizedDescription
                    Task { @MainActor in self.lastError = message }
                }
            }
        }
    }

    /// Unblock an arbitrary bundle — drag-and-drop and the file picker land here,
    /// including apps the scan never surfaced.
    func unblock(at url: URL) {
        openAnyway(Self.makeApp(ScanResult(
            url: url,
            name: FileManager.default.displayName(atPath: url.path),
            accepted: false,
            detail: "",
            fingerprint: "",
            provenance: Quarantine.provenance(at: url.path)
        )))
    }
}
