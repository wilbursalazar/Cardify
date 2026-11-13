import AppKit
import PDFKit
import Foundation

@main struct Check {
 static func main() {
  let tasks = (0..<40).map { TodoItem(text: "Task\(String(format: "%03d", $0)) study", done: $0 % 2 == 0) }
  let todo = TodoList(title: "Research tasks", rows: tasks)
  let rendered = MarkdownRendering.render(todo.printMarkdown, fontSize: 9).string
  precondition(rendered.contains("☐") && rendered.contains("☑"), "Both unchecked and checked tasks must render")
  for portrait in [false, true] {
   guard let data = CardDocument(text: todo.printMarkdown, portrait: portrait, fontSize: 9).pdf(), let document = PDFDocument(data: data) else { fatalError("To-do PDF missing") }
   let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: " ")
   precondition(!text.contains("cardify:todo") && text.contains("Research tasks"), "To-do marker or heading printed incorrectly")
   for index in 0..<40 { precondition(text.contains("Task\(String(format: "%03d", index))"), "Task lost in pagination") }
   print("\(portrait ? "portrait" : "landscape"): all to-do rows printed across \(document.pageCount) cards")
  }
 }
}
