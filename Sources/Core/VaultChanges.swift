import Foundation

/// A planned change to the vault: folders to create, files to write, and files or folders to
/// move or put in the Trash, in order. Written down before it starts, so an interruption can be
/// finished or undone.
struct VaultChange: Codable, Equatable {
    enum Step: Codable, Equatable {
        case makeFolder(String)
        /// Replace (or create) a file's contents.
        case write(String, Data)
        /// Replace a file's contents only if it still holds `from` (what the plan was made from),
        /// so an edit made meanwhile (in Obsidian, say) is never overwritten.
        case update(String, from: Data, to: Data)
        /// Move a file or folder; the destination must be free.
        case move(String, String)
        case trash(String)
    }
    /// What the person asked for, for messages ("Rename “A” to “B”").
    var summary: String
    var steps: [Step]

    var isEmpty: Bool { steps.isEmpty }
}

/// The file operations the engine performs. Replaceable in tests to simulate failures.
protocol VaultFileOperations {
    /// The file's bytes, or nil when nothing is there.
    func read(_ url: URL) throws -> Data?
    func exists(_ url: URL) -> Bool
    func write(_ data: Data, to url: URL, creating: Bool) throws
    func remove(_ url: URL) throws
    func move(_ from: URL, to: URL) throws
    func makeFolder(_ url: URL) throws
    /// Moves to the macOS Trash; returns where it went.
    func trash(_ url: URL) throws -> URL?
}

struct RealFileOperations: VaultFileOperations {
    func read(_ url: URL) throws -> Data? { try CardFiles.diskContents(at: url) }
    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
    func write(_ data: Data, to url: URL, creating: Bool) throws {
        try data.write(to: url, options: creating ? .withoutOverwriting : .atomic)
    }
    func remove(_ url: URL) throws { try FileManager.default.removeItem(at: url) }
    func move(_ from: URL, to: URL) throws {
        if from.path.lowercased() == to.path.lowercased() && from.path != to.path {
            // Case-only rename on a case-insensitive volume: go through a temporary name.
            let temporary = from.deletingLastPathComponent().appendingPathComponent(".kaster-move-\(UUID().uuidString)")
            try FileManager.default.moveItem(at: from, to: temporary)
            try FileManager.default.moveItem(at: temporary, to: to)
        } else {
            try FileManager.default.moveItem(at: from, to: to)
        }
    }
    func makeFolder(_ url: URL) throws { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
    func trash(_ url: URL) throws -> URL? {
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        return resulting as URL?
    }
}

/// Applies vault changes so they can't silently leave the vault half-changed: each change is
/// journaled (outside the vault) before its first step, every write is read back, and if any
/// step fails every finished step is undone and the error is reported. A journal left behind by
/// a crash or quit is finished or undone by `recoverInterrupted()` at the next launch.
struct VaultChanges {
    let journalFolder: URL
    var files: VaultFileOperations = RealFileOperations()
    /// Tests only: stop after this many steps, as if Kaster had quit, leaving the journal.
    var stopAfter: Int?

    /// ~/Library/Application Support/<app>/Changes, separate for each app (so a test copy never
    /// touches the real app's journal).
    static var defaultJournal: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent(Bundle.main.bundleIdentifier ?? "Kaster", isDirectory: true)
            .appendingPathComponent("Changes", isDirectory: true)
    }

    struct Failure: LocalizedError, Equatable {
        let summary: String
        let reason: String
        /// Every finished step was undone, so the vault is as it was.
        let undone: Bool
        /// Files the undo had to leave as they are (changed by someone else meanwhile).
        let leftAsIs: [String]
        var errorDescription: String? {
            "\(summary) failed: \(reason)" + (undone ? " Nothing was changed." :
                " Kaster could not undo every step" + (leftAsIs.isEmpty ? "" : " (left as they are: \(leftAsIs.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")))") + "; it will try again at the next launch.")
        }
    }

    /// What happened to a change that was interrupted.
    struct Recovery: Equatable {
        enum Outcome: Equatable { case finished, undone, partlyUndone(leftAsIs: [String]) }
        let summary: String
        let outcome: Outcome
        var message: String {
            switch outcome {
            case .finished: return "Kaster finished an interrupted change: \(summary)."
            case .undone: return "Kaster undid an interrupted change, so nothing was half done: \(summary)."
            case .partlyUndone(let left):
                return "Kaster undid most of an interrupted change (\(summary)). These files had changed since and were left as they are: \(left.map { ($0 as NSString).lastPathComponent }.joined(separator: ", "))."
            }
        }
    }

    // MARK: Journal records

    private struct Record: Codable {
        let summary: String
        let steps: [VaultChange.Step]
        /// For each write: the file's bytes before (nil = it didn't exist). Nil entries for other steps.
        let before: [Data?]
    }
    private struct Progress: Codable {
        var done: Int
        /// Step index → where the Trash put it.
        var trashed: [Int: String] = [:]
        /// Step indexes of folders this change created.
        var createdFolders: [Int] = []
    }

    private func save<T: Encodable>(_ value: T, _ url: URL) throws {
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
    }

    // MARK: Applying

    /// Applies `change`. Throws `Failure` after undoing what it had done.
    func apply(_ change: VaultChange) throws {
        guard !change.isEmpty else { return }
        let folder = journalFolder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let before: [Data?]
        do {
            before = try change.steps.map { step -> Data? in
                if case .write(let path, _) = step { return try files.read(URL(fileURLWithPath: path)) }
                if case .update(_, let from, _) = step { return from }
                return nil
            }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try save(Record(summary: change.summary, steps: change.steps, before: before), folder.appendingPathComponent("change.json"))
            try save(Progress(done: 0), folder.appendingPathComponent("progress.json"))
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw Failure(summary: change.summary, reason: error.localizedDescription, undone: true, leftAsIs: [])
        }
        var progress = Progress(done: 0)
        for (index, step) in change.steps.enumerated() {
            if let stopAfter, index == stopAfter { return }
            do {
                try perform(step, index: index, progress: &progress)
                progress.done = index + 1
                try save(progress, folder.appendingPathComponent("progress.json"))
            } catch {
                // perform may have finished the step before failing to record it.
                if index == progress.done, isDone(step, before: before[index]) { progress.done = index + 1 }
                let left = undo(change.steps, before: before, progress: progress)
                if left == nil { try? FileManager.default.removeItem(at: folder) }
                throw Failure(summary: change.summary, reason: error.localizedDescription, undone: left == nil, leftAsIs: left ?? [])
            }
        }
        try? FileManager.default.removeItem(at: folder)
    }

    private func perform(_ step: VaultChange.Step, index: Int, progress: inout Progress) throws {
        switch step {
        case .makeFolder(let path):
            let url = URL(fileURLWithPath: path, isDirectory: true)
            guard !files.exists(url) else { return }
            try files.makeFolder(url)
            progress.createdFolders.append(index)
        case .write(let path, let data):
            let url = URL(fileURLWithPath: path)
            let current = try files.read(url)
            guard current != data else { return }
            try files.write(data, to: url, creating: current == nil)
            guard try files.read(url) == data else { throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: "\((path as NSString).lastPathComponent) did not save correctly."]) }
        case .update(let path, let from, let to):
            let url = URL(fileURLWithPath: path)
            let current = try files.read(url)
            guard current != to else { return }
            guard current == from else { throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: "\((path as NSString).lastPathComponent) changed while Kaster was updating it."]) }
            try files.write(to, to: url, creating: false)
            guard try files.read(url) == to else { throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: "\((path as NSString).lastPathComponent) did not save correctly."]) }
        case .move(let from, let to):
            let source = URL(fileURLWithPath: from), destination = URL(fileURLWithPath: to)
            let caseOnly = from.lowercased() == to.lowercased()
            guard files.exists(source) else { throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "\((from as NSString).lastPathComponent) is missing."]) }
            guard caseOnly || !files.exists(destination) else { throw CocoaError(.fileWriteFileExists, userInfo: [NSLocalizedDescriptionKey: "\((to as NSString).lastPathComponent) already exists."]) }
            try files.move(source, to: destination)
        case .trash(let path):
            if let resulting = try files.trash(URL(fileURLWithPath: path)) { progress.trashed[index] = resulting.path }
        }
    }

    /// Whether a step has already happened (the disk is in its after-state).
    private func isDone(_ step: VaultChange.Step, before: Data?) -> Bool {
        switch step {
        case .makeFolder(let path): return files.exists(URL(fileURLWithPath: path))
        case .write(let path, let data): return (try? files.read(URL(fileURLWithPath: path))) == data
        case .update(let path, _, let to): return (try? files.read(URL(fileURLWithPath: path))) == to
        case .move(let from, let to):
            if from.lowercased() == to.lowercased() { return realName(to) == (to as NSString).lastPathComponent }
            return !files.exists(URL(fileURLWithPath: from)) && files.exists(URL(fileURLWithPath: to))
        case .trash(let path): return !files.exists(URL(fileURLWithPath: path))
        }
    }

    /// Whether a step can still happen (the disk is in its before-state).
    private func canDo(_ step: VaultChange.Step, before: Data?) -> Bool {
        switch step {
        case .makeFolder: return true
        case .write(let path, _): return (try? files.read(URL(fileURLWithPath: path))) == before
        case .update(let path, let from, _): return (try? files.read(URL(fileURLWithPath: path))) == from
        case .move(let from, let to):
            if from.lowercased() == to.lowercased() { return realName(from) == (from as NSString).lastPathComponent }
            return files.exists(URL(fileURLWithPath: from)) && !files.exists(URL(fileURLWithPath: to))
        case .trash(let path): return files.exists(URL(fileURLWithPath: path))
        }
    }

    private func realName(_ path: String) -> String? {
        let folder = (path as NSString).deletingLastPathComponent
        let name = (path as NSString).lastPathComponent
        return (try? FileManager.default.contentsOfDirectory(atPath: folder))?.first { $0.lowercased() == name.lowercased() }
    }

    /// Undoes finished steps, newest first. Nil when everything was undone; otherwise the paths
    /// left as they are because someone changed them since.
    private func undo(_ steps: [VaultChange.Step], before: [Data?], progress: Progress) -> [String]? {
        var left: [String] = []
        for index in stride(from: progress.done - 1, through: 0, by: -1) {
            switch steps[index] {
            case .makeFolder(let path):
                guard progress.createdFolders.contains(index) else { continue }
                let url = URL(fileURLWithPath: path, isDirectory: true)
                let contents = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
                if contents.allSatisfy({ $0 == ".DS_Store" }) { try? files.remove(url) }
            case .write(let path, let data):
                let url = URL(fileURLWithPath: path)
                guard (try? files.read(url)) == data else {
                    if (try? files.read(url)) != before[index] { left.append(path) }
                    continue
                }
                do {
                    if let original = before[index] { try files.write(original, to: url, creating: false) } else { try files.remove(url) }
                } catch { left.append(path) }
            case .update(let path, let from, let to):
                let url = URL(fileURLWithPath: path)
                guard (try? files.read(url)) == to else {
                    if (try? files.read(url)) != from { left.append(path) }
                    continue
                }
                do { try files.write(from, to: url, creating: false) } catch { left.append(path) }
            case .move(let from, let to):
                let source = URL(fileURLWithPath: from), destination = URL(fileURLWithPath: to)
                let caseOnly = from.lowercased() == to.lowercased()
                guard caseOnly ? realName(to) == (to as NSString).lastPathComponent : files.exists(destination) && !files.exists(source) else { left.append(to); continue }
                do { try files.move(destination, to: source) } catch { left.append(to) }
            case .trash(let path):
                guard let trashed = progress.trashed[index], files.exists(URL(fileURLWithPath: trashed)), !files.exists(URL(fileURLWithPath: path)) else { left.append(path); continue }
                do { try files.move(URL(fileURLWithPath: trashed), to: URL(fileURLWithPath: path)) } catch { left.append(path) }
            }
        }
        return left.isEmpty ? nil : left
    }

    // MARK: Recovery

    /// Changes a previous run left unfinished (a crash or quit in the middle): finishes each one
    /// when every remaining step can still happen as planned, otherwise undoes what was done.
    func recoverInterrupted() -> [Recovery] {
        let folders = ((try? FileManager.default.contentsOfDirectory(at: journalFolder, includingPropertiesForKeys: [.creationDateKey])) ?? [])
            .filter { $0.hasDirectoryPath || (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .sorted { ((try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) < ((try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) }
        var reports: [Recovery] = []
        for folder in folders {
            guard let recordData = try? Data(contentsOf: folder.appendingPathComponent("change.json")),
                  let record = try? JSONDecoder().decode(Record.self, from: recordData) else {
                try? FileManager.default.removeItem(at: folder)   // never got past writing its plan: nothing changed
                continue
            }
            var progress = (try? Data(contentsOf: folder.appendingPathComponent("progress.json"))).flatMap { try? JSONDecoder().decode(Progress.self, from: $0) } ?? Progress(done: 0)
            // The step after the last one recorded may have happened just before the interruption.
            if progress.done < record.steps.count, isDone(record.steps[progress.done], before: record.before[progress.done]),
               !canDo(record.steps[progress.done], before: record.before[progress.done]) {
                progress.done += 1
            }
            let remaining = Array(record.steps.indices.dropFirst(progress.done))
            var outcome: Recovery.Outcome
            if remaining.allSatisfy({ canDo(record.steps[$0], before: record.before[$0]) }) {
                do {
                    for index in remaining {
                        try perform(record.steps[index], index: index, progress: &progress)
                        progress.done = index + 1
                    }
                    outcome = .finished
                } catch {
                    let left = undo(record.steps, before: record.before, progress: progress)
                    outcome = left.map { .partlyUndone(leftAsIs: $0) } ?? .undone
                }
            } else {
                let left = undo(record.steps, before: record.before, progress: progress)
                outcome = left.map { .partlyUndone(leftAsIs: $0) } ?? .undone
            }
            try? FileManager.default.removeItem(at: folder)
            reports.append(Recovery(summary: record.summary, outcome: outcome))
        }
        return reports
    }
}
