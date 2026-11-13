import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
let initial = TodoList(title: "Research & errands", rows: [TodoItem(text: "Read [book] \\ notes", done: true), TodoItem(text: "Write **draft**", done: false), TodoItem(text: "", done: false)])
let saved = initial.markdown
let restored = TodoList.fromMarkdown(saved)!
check(restored.title == initial.title, "title round trip")
check(restored.rows.map(\.text) == initial.rows.map(\.text), "task content and escaping round trip")
check(restored.rows.map(\.done) == [true, false, false], "completion round trip")
check(restored.markdown == saved, "saved Markdown unchanged after round trip")
check(!initial.printMarkdown.contains(TodoList.marker), "marker omitted from printed output")
check(initial.printMarkdown.contains("- [x] Read"), "printed output contains completed task")
check(TodoList.fromMarkdown("# unrelated\n- [ ] task\n") == nil, "arbitrary Markdown not converted")
check(TodoList.fromMarkdown(saved + "Extra paragraph\n") == nil, "extra content not dropped")
check(TodoList.fromMarkdown(saved.replacingOccurrences(of: TodoList.marker, with: "<!-- other -->")) == nil, "different marker not converted")
check(TodoList.fromMarkdown(saved.replacingOccurrences(of: "\n", with: "\r\n"))?.rows.count == 3, "CRLF line endings")
check(TodoList.fromMarkdown(TodoList(title: "Empty", rows: []).markdown)?.rows.isEmpty == true, "empty list")
print("To-do Markdown round trip, completion, print output and lossless import checks passed")
