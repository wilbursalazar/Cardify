import Foundation

let utc = TimeZone(secondsFromGMT: 0)!
let date = ISO8601DateFormatter().date(from: "2026-11-13T14:37:00Z")!
func id(_ style: TimestampDateStyle, _ time: Bool, _ existing: Set<String> = []) -> String {
    BranchIDs.timestamp(at: date, timeZone: utc, existing: existing, style: style, includeTime: time)
}
precondition(id(.sortable, true) == "202611131437")
precondition(id(.sortable, false) == "20261113")
precondition(id(.dayFirst, false) == "13-11-26")
precondition(id(.monthFirst, false) == "11-13-26")
precondition(id(.dayFirst, true) == "13-11-26-1437")
precondition(id(.monthFirst, true) == "11-13-26-1437")
precondition(id(.dayFirst, false, ["13-11-26", "13-11-26-02"]) == "13-11-26-03")
for value in ["202611131437", "20261113", "13-11-26", "11-13-26-1437", "13-11-26-1437-02"] {
    let url = URL(fileURLWithPath: "/tmp/\(value) title.md")
    precondition(BranchIDs.filenameID(for: url) == value, "Failed to recognize \(value)")
}
precondition(CardIDs.newID(mode: .timestamp, existing: [], at: date, timeZone: utc, timestampStyle: .monthFirst, timestampIncludeTime: false) == "11-13-26")
print("Timestamp formats and collision checks passed")
