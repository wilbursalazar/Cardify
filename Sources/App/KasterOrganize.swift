import SwiftUI
import AppKit

/// Shows every planned move before anything changes, backs the vault up, then organizes it.
struct MigrationSheet: View {
    let root: URL
    let artifactFolders: [KasterArtifact: URL]
    let onDone: ([URL: URL]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var plan: KasterVault.MigrationPlan?
    @State private var result: String?
    @State private var failure: String?
    @State private var working = false

    private func display(_ url: URL) -> String {
        KasterVault.relativePath(of: url, in: root) ?? url.path
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Organize Vault into Kaster Folders").font(.title2.bold())
            Text("Cards with a Luhmann ID move to Zettel/ as ID-Title; habit tables, to-do lists and debates move to their workspace folders; everything else becomes a Quick card. Titles come from each card's heading. Links between cards are updated. A zip backup of the whole folder is made first, next to it.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let plan {
                if plan.steps.isEmpty {
                    Label("Everything is already organized.", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                } else {
                    List {
                        Section("\(plan.steps.count) cards") {
                            ForEach(plan.steps) { step in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(display(step.from)).font(.system(size: 12)).foregroundStyle(.secondary)
                                    Text("→ " + display(step.to)).font(.system(size: 12, weight: .medium))
                                }
                            }
                        }
                        if !plan.foldersToRemove.isEmpty {
                            Section("Empty folders removed") {
                                ForEach(plan.foldersToRemove, id: \.path) { Text(display($0)).font(.system(size: 12)) }
                            }
                        }
                    }
                    .frame(minHeight: 260)
                }
            } else {
                ProgressView("Planning…")
            }
            if let result { Label(result, systemImage: "checkmark.circle.fill").foregroundStyle(.green).fixedSize(horizontal: false, vertical: true) }
            if let failure { Label(failure, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Spacer()
                Button(result == nil ? "Cancel" : "Done") { dismiss() }.keyboardShortcut(.cancelAction)
                if result == nil {
                    Button("Back Up & Organize") { apply() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(working || plan?.steps.isEmpty != false)
                }
            }
        }
        .padding(22).frame(width: 640, height: 560)
        .onAppear { plan = KasterVault.migrationPlan(root: root, artifactFolders: artifactFolders) }
    }

    private func apply() {
        guard let plan else { return }
        working = true; failure = nil
        do {
            let backup = try KasterVault.backup(root: root)
            try KasterVault.applyMigration(plan, root: root, changes: VaultChanges(journalFolder: VaultChanges.defaultJournal))
            var moved: [URL: URL] = [:]
            for step in plan.steps { moved[step.from.standardizedFileURL] = step.to }
            onDone(moved)
            result = "Organized \(plan.steps.count) cards. Backup: \(backup.lastPathComponent)"
        } catch {
            failure = "Stopped: \(error.localizedDescription). Your backup zip (if created) is next to the notes folder."
        }
        working = false
    }
}
