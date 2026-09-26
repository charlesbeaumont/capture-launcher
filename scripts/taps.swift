// Lists every CGEventTap on the system, grouped by owning process. A process
// holding hundreds of filtering taps at the HID level is the prime suspect for
// system-wide hover loss. See CLAUDE.md.
//
//   swiftc -O scripts/taps.swift -o ~/bin/taps && taps
import AppKit
import CoreGraphics

var count: UInt32 = 0
CGGetEventTapList(0, nil, &count)
var taps = [CGEventTapInformation](repeating: CGEventTapInformation(), count: Int(count))
CGGetEventTapList(count, &taps, &count)

let mouseMoved: UInt64 = 1 << CGEventType.mouseMoved.rawValue
func name(_ pid: pid_t) -> String {
    NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid \(pid)"
}

struct Row { var total = 0, filtering = 0, hid = 0, enabled = 0, mouseMoved = 0 }
var rows: [pid_t: Row] = [:]
for t in taps {
    var r = rows[t.tappingProcess, default: Row()]
    r.total += 1
    if t.options != .listenOnly { r.filtering += 1 }
    if t.tapPoint == .cghidEventTap { r.hid += 1 }
    if t.enabled { r.enabled += 1 }
    if t.eventsOfInterest & mouseMoved != 0 { r.mouseMoved += 1 }
    rows[t.tappingProcess] = r
}

print("event taps: \(count)   (\(ISO8601DateFormatter().string(from: Date())))")
print("  total filter  hid  enabled mouseMoved  process")
for (pid, r) in rows.sorted(by: { $0.value.total > $1.value.total }) {
    print(String(format: "  %5d %6d %4d %8d %10d  %@ (pid %d)",
                 r.total, r.filtering, r.hid, r.enabled, r.mouseMoved, name(pid), pid))
}
