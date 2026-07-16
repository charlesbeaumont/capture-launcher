import Foundation

/// Spawns a short-lived, detached `claude -p` per routed capture to move the
/// entry from ## Captured to the right place inside the note (respecting
/// embedded conventions like "## 1-on-1 log — append at top"). Fire-and-
/// forget: the deterministic write already happened, so an agent failure
/// costs nothing. No queues, no daemons.
enum FilingAgent {
    static let enabledKey = "filingAgentEnabled"
    static let tidyKey = "filingAgentTidy"
    static let pathKey = "claudePath"
    static let modelKey = "filingAgentModel"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    static var tidyEnabled: Bool {
        UserDefaults.standard.object(forKey: tidyKey) as? Bool ?? true
    }

    static var claudePath: String {
        let stored = UserDefaults.standard.string(forKey: pathKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stored.isEmpty
            ? NSHomeDirectory() + "/.local/bin/claude"
            : (stored as NSString).expandingTildeInPath
    }

    /// Empty = whatever the claude CLI defaults to.
    static var model: String {
        UserDefaults.standard.string(forKey: modelKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static var logURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Capture/filing.log")
    }

    // Retain running processes so termination handlers fire.
    // Guarded by `lock` — hence the unsafe opt-out.
    private static nonisolated(unsafe) var running: [Int32: Process] = [:]
    private static let lock = NSLock()

    static func spawn(noteId: String, noteTitle: String, tag: String, text: String, datetime: String) {
        guard isEnabled else { return }
        let wordRule = tidyEnabled
            ? """
              You may fix obvious spelling, grammar, and punctuation mistakes in the \
              capture text, preserving its meaning, tone, and original language \
              (captures are Dutch or English — never translate, never rephrase, \
              never expand).
              """
            : "Never alter the capture's words."
        let prompt = """
        A capture was just appended to the "## Captured" section of the Bear note \
        with id \(noteId) (title: "\(noteTitle)", tag #\(tag)):

        - \(datetime) — \(text)

        Read that note. If an embedded convention or a clearly topical section fits \
        (e.g. "## 1-on-1 log — append new entries at the top", "## Standing agreements", \
        "## Current threads", or a matching `---` section), MOVE the entry there, \
        matching the note's existing formatting (bullet style, date style). If this \
        destination has sub-notes (other notes tagged #\(tag) titled "\(noteTitle) - <topic>") \
        and one clearly fits better, move it there instead. If nothing clearly fits, \
        leave the entry in ## Captured. \(wordRule) \
        Never touch other content. After any edit, re-read and verify the capture \
        appears exactly once across the notes you touched; if it appears twice, remove \
        the copy you added, keeping the original in ## Captured.
        """

        var args = ["-p", prompt, "--allowedTools", "mcp__bear", "--max-turns", "12"]
        let model = model
        if !model.isEmpty { args += ["--model", model] }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = args
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

        let logDir = logURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        if let handle = try? FileHandle(forWritingTo: logURL) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data("\n--- filing \(Date()) → #\(tag) (\(noteTitle))\n".utf8))
            process.standardOutput = handle
            process.standardError = handle
        }

        process.terminationHandler = { finished in
            lock.lock()
            running.removeValue(forKey: finished.processIdentifier)
            lock.unlock()
            if let handle = finished.standardOutput as? FileHandle {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: Data("--- exit \(finished.terminationStatus)\n".utf8))
                try? handle.close()
            }
        }

        do {
            try process.run()
            lock.lock()
            running[process.processIdentifier] = process
            lock.unlock()
        } catch {
            let message = "Filing agent failed to launch (claude at \(claudePath)): \(error.localizedDescription)"
            Task { @MainActor in Notify.failure(message) }
        }
    }
}
