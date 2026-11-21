import Foundation

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
