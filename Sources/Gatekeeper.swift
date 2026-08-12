import Foundation

/// Asks Gatekeeper the same question it asks itself at launch time.
enum Gatekeeper {
    struct Assessment {
        var accepted: Bool
        /// e.g. "Notarized Developer ID", or the rejection reason.
        var detail: String
    }

    /// `spctl -a` is the authoritative answer. Quarantine flag bits look like they
    /// encode the verdict but don't — plenty of notarized apps carry the same bits
    /// as blocked ones, so anything derived from them produces false positives.
    static func assess(path: String) -> Assessment {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/spctl")
        process.arguments = ["--assess", "--type", "execute", "-vv", path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do { try process.run() } catch {
            return Assessment(accepted: true, detail: "")  // fail open; never invent a block
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(data: data, encoding: .utf8) ?? ""
        let accepted = process.terminationStatus == 0

        var detail = ""
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let range = trimmed.range(of: "source=") {
                detail = String(trimmed[range.upperBound...])
                break
            }
            // Rejections put the reason on the line with the path.
            if trimmed.hasPrefix(path + ":") {
                detail = String(trimmed.dropFirst(path.count + 1)).trimmingCharacters(in: .whitespaces)
            }
        }
        return Assessment(accepted: accepted, detail: detail)
    }

    /// Re-apply an ad-hoc signature. Repairs the "app is damaged" case, where the
    /// bundle was modified after signing and the seal no longer verifies.
    @discardableResult
    static func adHocSign(path: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--force", "--deep", "--sign", "-", path]

        let pipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = pipe

        do { try process.run() } catch { return "Couldn't run codesign: \(error.localizedDescription)" }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus != 0 else { return nil }
        let message = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "codesign failed"
        return message.components(separatedBy: .newlines).last
    }
}
