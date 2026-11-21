import SwiftUI
import AppKit
import CoreText

struct HabitTrackerEditor: View {
    @Binding var tracker: HabitTracker
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Weekly habits", text: $tracker.title).font(.headline).textFieldStyle(.roundedBorder)
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 3) {
                        Text("Habit").frame(width: 140, alignment: .leading)
                        ForEach(HabitTracker.days, id: \.self) { day in Text(day).font(.caption).frame(width: 28) }
                        Text("").frame(width: 24)
                    }
                    ForEach($tracker.rows) { $row in
                        HStack(spacing: 3) {
                            TextField("Name", text: $row.name).frame(width: 140)
                            ForEach(0..<7, id: \.self) { i in
                                Button { row.checked[i].toggle() } label: {
                                    Text(row.checked[i] ? "X" : " ").font(.system(size: 12, weight: .medium)).frame(width: 26, height: 26).overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.secondary)).contentShape(Rectangle())
                                }.buttonStyle(.plain).help("\(HabitTracker.days[i]): \(row.checked[i] ? "Done" : "Not done")")
                            }
                            Button { tracker.rows.removeAll { $0.id == row.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain).help("Remove habit")
                        }
                    }
                }
            }
            Button("Add habit") { tracker.rows.append(HabitRow()) }
            Text("Click a box to mark or clear an X. Printed cards can also be filled in by hand.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
