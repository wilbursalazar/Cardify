import SwiftUI
import AppKit

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
