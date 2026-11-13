import Foundation
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
check(WorkflowPreference.defaults(for: "") == nil, "unset preserves current configuration")
check(WorkflowPreference.defaults(for: "configured") == nil, "configured preserves current configuration")
check(WorkflowPreference.defaults(for: "unrecognized") == nil, "unknown preference preserves current configuration")
let luhmann = WorkflowPreference.defaults(for: "luhmann")!
check(luhmann.idMode == .luhmann && luhmann.template == .idea, "Luhmann starts an idea with Luhmann ID")
let eco = WorkflowPreference.defaults(for: "eco")!
check(eco.idMode == .titleOnly && eco.template == .reading, "Eco starts a reading card with title-only ID")
check(eco.template!.markdown.contains("Source:"), "reading template retains source field")
let obsidian = WorkflowPreference.defaults(for: "obsidian")!
check(obsidian.idMode == .titleOnly && obsidian.template == nil, "Obsidian starts blank and title-only")
check(WorkflowPreference.allCases.count == 4, "all choices are available")
print("Workflow defaults and existing-install fallback passed")
