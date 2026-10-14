// Snapshot of system focus/window state, to be run THE MOMENT hover dies in
// another app. Turns an occurrence of the multi-day hover bug into evidence
// instead of another guess. See CLAUDE.md.
//
//   swiftc -O scripts/hoverdump.swift -o /tmp/hoverdump && /tmp/hoverdump
//
// Needs Accessibility permission for the invoking terminal (the AX section
// degrades gracefully without it; everything else still works).

import AppKit
import ApplicationServices

func ax(_ element: AXUIElement, _ attr: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, attr as CFString, &value) == .success ? value : nil
}

func axString(_ element: AXUIElement, _ attr: String) -> String {
    (ax(element, attr) as? String) ?? "—"
}

let stamp = ISO8601DateFormatter().string(from: Date())
print("hoverdump \(stamp)")
print(String(repeating: "=", count: 72))

// 1. Who does the OS think is active?
let ws = NSWorkspace.shared
let front = ws.frontmostApplication
let menuOwner = ws.menuBarOwningApplication
print("\n[ACTIVE]")
print("  frontmost      : \(front?.localizedName ?? "nil") pid=\(front?.processIdentifier ?? -1)")
print("  menuBarOwning  : \(menuOwner?.localizedName ?? "nil") pid=\(menuOwner?.processIdentifier ?? -1)")
print("  AX trusted     : \(AXIsProcessTrusted())")

// 2. Which window does each GUI app consider focused? A victim of this bug
//    should show a focused window that is NOT AXMain, or no focused window.
print("\n[FOCUS PER APP]  (regular apps + Capture)")
for app in ws.runningApplications
    where app.activationPolicy == .regular || (app.localizedName ?? "").contains("Capture") {
    let element = AXUIElementCreateApplication(app.processIdentifier)
    guard let win = ax(element, kAXFocusedWindowAttribute as String) else {
        print("  \(app.localizedName ?? "?")  focusedWindow=NONE  active=\(app.isActive)")
        continue
    }
    // swiftlint:disable:next force_cast
    let w = win as! AXUIElement
    let isMain = (ax(w, kAXMainAttribute as String) as? Bool).map(String.init) ?? "—"
    let isFocused = (ax(element, kAXFocusedAttribute as String) as? Bool).map(String.init) ?? "—"
    print("  \(app.localizedName ?? "?")  active=\(app.isActive) appFocused=\(isFocused) win=\"\(axString(w, kAXTitleAttribute as String))\" main=\(isMain)")
}

// 3. Every on-screen window: leaked Capture panels show up here.
print("\n[ON-SCREEN WINDOWS]")
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
var byOwner: [String: Int] = [:]
for w in list {
    let owner = (w[kCGWindowOwnerName as String] as? String) ?? "?"
    byOwner[owner, default: 0] += 1
    guard owner.contains("Capture") else { continue }
    let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
    print("  CAPTURE win#\(w[kCGWindowNumber as String] ?? "?") layer=\(w[kCGWindowLayer as String] ?? "?") alpha=\(w[kCGWindowAlpha as String] ?? "?") bounds=\(b)")
}
let captureWindows = byOwner.filter { $0.key.contains("Capture") }.values.reduce(0, +)
print("  total on-screen windows: \(list.count)   Capture windows: \(captureWindows)  << >1 means a leak")

// 4. What sits under the cursor? A stale transparent window here eats hover.
let mouse = NSEvent.mouseLocation
print("\n[CURSOR]  at \(Int(mouse.x)),\(Int(mouse.y))")
if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) {
    let flipped = CGPoint(x: mouse.x, y: screen.frame.maxY - mouse.y)
    let under = list.filter { w in
        guard let d = w[kCGWindowBounds as String] as? [String: Any],
              let x = d["X"] as? CGFloat, let y = d["Y"] as? CGFloat,
              let width = d["Width"] as? CGFloat, let height = d["Height"] as? CGFloat
        else { return false }
        return CGRect(x: x, y: y, width: width, height: height).contains(flipped)
    }
    for w in under.prefix(5) {
        print("  \(w[kCGWindowOwnerName as String] ?? "?")  win#\(w[kCGWindowNumber as String] ?? "?") layer=\(w[kCGWindowLayer as String] ?? "?")")
    }
}

// 5. Capture's own resource footprint — leaks that grow over days.
if let cap = ws.runningApplications.first(where: { ($0.localizedName ?? "").contains("Capture") }) {
    let pid = cap.processIdentifier
    print("\n[CAPTURE PROCESS] pid=\(pid) launched=\(cap.launchDate.map { ISO8601DateFormatter().string(from: $0) } ?? "?")")
    for (label, args) in [("open FDs", ["-c", "lsof -p \(pid) 2>/dev/null | wc -l"]),
                          ("threads ", ["-c", "ps -M \(pid) 2>/dev/null | tail -n +2 | wc -l"]),
                          ("children", ["-c", "pgrep -P \(pid) 2>/dev/null | wc -l"])] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe
        try? p.run(); p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        print("  \(label): \(out.trimmingCharacters(in: .whitespacesAndNewlines))")
    }
} else {
    print("\n[CAPTURE PROCESS] not running")
}
print("\n" + String(repeating: "=", count: 72))
