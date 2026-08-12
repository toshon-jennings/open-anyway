import Foundation

/// Everything to do with reading (and removing) the `com.apple.quarantine`
/// extended attribute, plus recovering where a file actually came from.
enum Quarantine {
    static let attrName = "com.apple.quarantine"

    /// Raw attribute value, e.g. `0081;6a7a89ad;Chrome;57F62A1B-...`
    /// Fields are: flags ; hex download timestamp ; downloading agent ; event UUID.
    static func rawValue(at path: String) -> String? {
        let size = getxattr(path, attrName, nil, 0, 0, XATTR_NOFOLLOW)
        guard size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        let read = getxattr(path, attrName, &buffer, size, 0, XATTR_NOFOLLOW)
        guard read > 0 else { return nil }
        return String(bytes: buffer[0..<read], encoding: .utf8)
    }

    static func isQuarantined(at path: String) -> Bool {
        getxattr(path, attrName, nil, 0, 0, XATTR_NOFOLLOW) > 0
    }

    /// Where the app came from, for the provenance line under the app name.
    ///
    /// The origin URL is deliberately not surfaced: it lives in the 4th field's
    /// LaunchServices event record, but modern macOS no longer populates that
    /// column (0 of 3377 rows on the machine this was built against), so reading
    /// it can only ever return nothing.
    struct Provenance: Sendable {
        var agent: String?
        var downloadedAt: Date?
    }

    static func provenance(at path: String) -> Provenance {
        guard let raw = rawValue(at: path) else { return Provenance() }
        let fields = raw.components(separatedBy: ";")

        var result = Provenance()

        if fields.count > 1, let seconds = UInt32(fields[1], radix: 16) {
            result.downloadedAt = Date(timeIntervalSince1970: TimeInterval(seconds))
        }
        if fields.count > 2, !fields[2].isEmpty {
            result.agent = fields[2]
        }
        return result
    }

    /// Strip the quarantine attribute from the whole bundle. This is what actually
    /// unblocks the app: Gatekeeper only assesses files that carry the attribute.
    /// Returns nil on success, or a human-readable reason on failure.
    @discardableResult
    static func remove(at path: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-r", "-d", attrName, path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do { try process.run() } catch { return "Couldn't run xattr: \(error.localizedDescription)" }
        process.waitUntilExit()

        // xattr exits non-zero when a nested file simply had no attribute to remove,
        // so trust the actual state of the bundle rather than the exit code.
        guard isQuarantined(at: path) else { return nil }

        return FileManager.default.isWritableFile(atPath: path)
            ? "Couldn't remove the quarantine flag."
            : "\(URL(fileURLWithPath: path).lastPathComponent) isn't writable by you — it likely needs admin rights."
    }
}
