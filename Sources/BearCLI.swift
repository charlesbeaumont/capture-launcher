import Foundation

/// All Bear I/O goes through this actor, via the `bearcli` binary bundled
/// inside Bear.app. Reads are plain subcommands; every write is a CAS
/// (compare-and-swap) `overwrite --base <hash>` so a concurrent change by
/// Bear.app rejects the write and we re-read and retry. Never touch Bear's
/// SQLite directly.
actor BearCLI {
    struct NoteMeta: Codable, Sendable {
        let id: String
        let title: String
        let tags: [String]
        let modified: Date?
    }

    struct NoteRead: Codable, Sendable {
        let hash: String
        let content: String
    }

    enum Failure: Error, CustomStringConvertible {
        case launchFailed(String)
        case exit(code: Int32, stderr: String)
        case badOutput(String)
        case casConflictPersisted(noteId: String)

        var description: String {
            switch self {
            case .launchFailed(let msg): "bearcli launch failed: \(msg)"
            case .exit(let code, let stderr): "bearcli exit \(code): \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
            case .badOutput(let msg): "bearcli unexpected output: \(msg)"
            case .casConflictPersisted(let noteId): "bearcli CAS conflict persisted on note \(noteId)"
            }
        }
    }

    static let defaultPath = "/Applications/Bear.app/Contents/MacOS/bearcli"
    static let pathKey = "bearcliPath"

    private static var cliPath: String {
        let stored = UserDefaults.standard.string(forKey: pathKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stored.isEmpty ? defaultPath : stored
    }

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Logged once at launch so a Bear update changing the CLI surface is visible.
    func version() async throws -> String {
        let data = try await run(["--version"])
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func listNotes() async throws -> [NoteMeta] {
        let data = try await run(["list", "--format", "json", "--fields", "id,title,tags,modified"])
        do {
            return try decoder.decode([NoteMeta].self, from: data)
        } catch {
            throw Failure.badOutput("list decode: \(error)")
        }
    }

    /// Single call returns hash + content together — the atomic CAS read.
    func readNote(id: String) async throws -> NoteRead {
        let data = try await run(["show", id, "--format", "json", "--fields", "hash,content"])
        do {
            return try decoder.decode(NoteRead.self, from: data)
        } catch {
            throw Failure.badOutput("show decode: \(error)")
        }
    }

    /// Read → transform → hash-guarded overwrite. `transform` returning nil
    /// means "nothing to do" (idempotent no-op). Any rejected write re-reads
    /// and retries; content goes via stdin so no escape mangling.
    func casEdit(noteId: String, transform: @Sendable (String) -> String?) async throws {
        var lastError: Failure?
        for _ in 0..<3 {
            let note = try await readNote(id: noteId)
            guard let newContent = transform(note.content) else { return }
            do {
                _ = try await run(
                    ["overwrite", noteId, "--base", note.hash],
                    stdin: Data(newContent.utf8)
                )
                return
            } catch let failure as Failure {
                if case .exit(1, _) = failure {
                    lastError = failure // likely CAS rejection — re-read and retry
                    continue
                }
                throw failure
            }
        }
        throw lastError ?? Failure.casConflictPersisted(noteId: noteId)
    }

    /// Creates a note from raw content (title derived from the first heading,
    /// tags from #hashtags). Returns the new note id.
    func createNote(content: String) async throws -> String {
        let data = try await run(["create", "--format", "json"], stdin: Data(content.utf8))
        struct Created: Codable { let id: String }
        do {
            return try decoder.decode(Created.self, from: data).id
        } catch {
            throw Failure.badOutput("create decode: \(error)")
        }
    }

    private func run(_ args: [String], stdin: Data? = nil) async throws -> Data {
        let path = Self.cliPath
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = args
                let out = Pipe()
                let err = Pipe()
                process.standardOutput = out
                process.standardError = err

                let input: Pipe?
                if stdin != nil {
                    let pipe = Pipe()
                    process.standardInput = pipe
                    input = pipe
                } else {
                    process.standardInput = FileHandle.nullDevice
                    input = nil
                }

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: Failure.launchFailed(error.localizedDescription))
                    return
                }

                if let stdin, let input {
                    input.fileHandleForWriting.write(stdin)
                    try? input.fileHandleForWriting.close()
                }

                let outData = out.fileHandleForReading.readDataToEndOfFile()
                let errData = err.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                if process.terminationStatus == 0 {
                    continuation.resume(returning: outData)
                } else {
                    continuation.resume(throwing: Failure.exit(
                        code: process.terminationStatus,
                        stderr: String(decoding: errData, as: UTF8.self)
                    ))
                }
            }
        }
    }
}
