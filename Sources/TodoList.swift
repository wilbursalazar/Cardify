import SwiftUI

struct TodoItem: Identifiable, Codable {
    var id = UUID()
    var text = ""
    var done = false
}

// The marker makes conversion opt-in. Unsupported content remains ordinary
// Markdown instead of being discarded by the structured editor.
struct TodoList: Codable {
    static let marker = "<!-- cardify:todo -->"
    var title = "To-do list"
    var rows: [TodoItem] = [TodoItem()]

    private static func singleLine(_ value: String) -> String {
        value.components(separatedBy: .newlines).joined(separator: " ")
    }

    var printMarkdown: String {
        let heading = Self.singleLine(title)
        var lines = ["# " + (heading.isEmpty ? "To-do list" : heading), ""]
        lines += rows.map { "- [\($0.done ? "x" : " ")] " + Self.singleLine($0.text) }
        return lines.joined(separator: "\n") + "\n"
    }

    var markdown: String { Self.marker + "\n\n" + printMarkdown }

    static func fromMarkdown(_ text: String) -> TodoList? {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var lines = normalized.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        guard lines.count >= 4, lines[0] == marker, lines[1].isEmpty,
              lines[2].hasPrefix("# "), lines[3].isEmpty else { return nil }
        let heading = String(lines[2].dropFirst(2))
        guard !heading.isEmpty else { return nil }
        var items: [TodoItem] = []
        for line in lines.dropFirst(4) {
            let prefix = String(line.prefix(6))
            guard prefix == "- [ ] " || prefix == "- [x] " || prefix == "- [X] " else { return nil }
            items.append(TodoItem(text: String(line.dropFirst(6)), done: prefix != "- [ ] "))
        }
        return TodoList(title: heading, rows: items)
    }
}

struct TodoListEditor: View {
    @Binding var list: TodoList
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("To-do list", text: $list.title).font(.headline).textFieldStyle(.roundedBorder)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach($list.rows) { $item in
                        HStack(spacing: 8) {
                            Button { item.done.toggle() } label: {
                                Image(systemName: item.done ? "checkmark.square" : "square")
                            }.buttonStyle(.plain).help(item.done ? "Mark incomplete" : "Mark complete")
                            TextField("Task", text: $item.text)
                            Button {
                                let id = item.id
                                list.rows.removeAll { $0.id == id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }.buttonStyle(.plain).help("Remove task")
                        }
                    }
                }
            }
            Button("Add task") { list.rows.append(TodoItem()) }
            Text("Click a box to mark or clear a task. You can also write on the printed card.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
