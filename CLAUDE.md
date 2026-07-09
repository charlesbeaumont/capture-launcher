# Capture — agent notes

## What this is

Single-purpose macOS overlay launcher for Charles's Bear-based second brain. Press a global hotkey, a flat themed bar opens, type a thought, hit Enter — then a destination picker filters projects/people/personal areas as you type. Enter on the pinned Inbox row (or with nothing typed) sends the capture to the pinned Bear "Inbox" note; Enter on a destination files it **immediately** into that project's note and spawns a short-lived Claude agent to reposition it within the note. A second hotkey opens Process Inbox: Tinder-style triage of existing inbox items.

The point is **speed**: hotkey → bar → Enter → gone. Lives entirely as a menu-bar app. No history, no plugins, no main window, no Dock icon. The bar persists when focus is lost (only Esc / Enter / the hotkey itself hide it). Multi-line capture grows the bar downward up to 5 lines, then scrolls internally.

## Design principles (Charles's explicit choices — don't violate)

1. **Speed is the product.** Every keystroke-to-paint under 300ms; in practice <1ms because the keystroke path never does I/O. Destinations live in memory (refreshed async at launch, on every panel show, and via the Refresh Projects menu item). All Bear writes are optimistic: the panel hides / triage advances instantly, work happens behind it.
2. **bearcli for everything.** All Bear I/O goes through the `BearCLI` actor wrapping `/Applications/Bear.app/Contents/MacOS/bearcli` (ships inside Bear 2.8+, works headless). Writes only via CAS: `show --fields hash,content` → transform → `overwrite --base <hash>`; a concurrent Bear.app change rejects the write (exit 1, "Note has changed since last read") and we re-read and retry ×3. **Never write Bear's SQLite directly.** The x-callback URI template survives only as the fallback path.
3. **No daemons.** No queues, no Redis, no background workers, no launchd. Agents are spawned per capture (`claude -p`, detached, `FilingAgent.swift`) and exit. Charles explicitly rejected daemon infra — don't reintroduce it.
4. **A capture is never lost.** Every failure path degrades to an Inbox write via the fallback URI template with a backtick-wrapped `` → `#tag` `` marker (backticks so Bear doesn't tag the Inbox note) plus a notification. The triage parser skips marker-carrying blocks.
5. **Human decides, agents assist.** The picker is Charles's routing decision. The filing agent only repositions the entry *within* the destination he chose (or its sibling sub-notes); if unsure it leaves the entry in `## Captured`.
6. **Themed minimal UI.** Solarized Light default; ten themes switchable in Settings (`Theme.swift` — one struct literal per theme: Solarized Light/Dark, Gruvbox Light/Dark, Catppuccin Latte/Mocha, Nord, Dracula, Tokyo Night, Mono Dark). System font (SF Pro — Charles found a pixel font "too much"), **no border** (he disliked it), cornerRadius 6, instant show/hide, inverted-block selection, per-kind **colored badges** on the right of each row drawn from each theme's own accent palette (`kindColors`: project/person/personal/reference/general/inbox — keep the badge palette per-theme, never hardcoded), fixed 8-row list viewport (the panel never resizes while filtering — only on stage transitions), dim "ms" filter-latency readout. Placeholder text must use `prompt: Text(...).foregroundColor(theme.dim)` — default placeholders ignore the theme and vanish on dark themes.

## Project layout

```
project.yml                 XcodeGen spec — single source of truth for the Xcode project
Sources/
  CaptureApp.swift          @main App + MenuBarExtra (Open/Process Inbox/Refresh) + Settings scene
  AppDelegate.swift         .accessory policy, both hotkeys, panel lifecycle, --show-on-launch dev flag
  LauncherPanel.swift       NSPanel subclass (non-activating, transparent, rounded contentView mask)
  LauncherView.swift        Stage-driven SwiftUI view: compose / route / loading / done
  LauncherModel.swift       @Observable stage machine (capture + triage modes, all transitions)
  DestinationListView.swift Fixed-viewport list, kind label right-aligned, inverted selection
  Theme.swift               Theme structs (Solarized Light/Dark, Mono Dark), kind badge colors
  BearCLI.swift             actor — Process wrapper for bearcli, CAS casEdit core
  Destination.swift         Destination + Kind + IndexedDestination (precomputed normalization)
  DestinationStore.swift    In-memory list + JSON cache, registry parsing, MRU usage
  DestinationRanker.swift   Pure per-keystroke ranking (prefix > word-boundary > subsequence)
  CaptureRouter.swift       All write orchestration + pure text transforms + routings.jsonl
  InboxParser.swift         Inbox note → [InboxEntry] (oldest-first, marker/tag-line aware)
  FilingAgent.swift         Detached claude -p spawn per routed capture
  Notify.swift              Failure-only UserNotifications
  DailyCapture.swift        FALLBACK x-callback path ({content}/{time}/{date}/{datetime}/{marker})
  HotkeyName.swift          .toggleLauncher (⌃⌘Space) + .triageInbox (⌃⌘⇧Space)
  SettingsView.swift        Theme, hotkey recorders, destinations status, filing config, fallback template
Resources/
  AppIcon.icns
scripts/
  dev.sh                    fswatch + xcodegen + xcodebuild Debug + relaunch loop
  release.sh                xcodegen + xcodebuild Release + ditto zip for GitHub Releases
```

The `.xcodeproj` is generated by XcodeGen and gitignored: `xcodegen generate` after editing `project.yml` or adding/removing source files (`scripts/dev.sh` does it on every save).

## Data flow

```
capture:  ⏎ text → picker → ⏎ dest ──BearCLI casEdit──▶ dest note "## Captured" ──spawn──▶ claude -p repositions
                          → ⏎ inbox ──BearCLI casEdit──▶ Inbox note (prepend under H1)
triage:   entry prefilled (editable) → picker → ⏎ dest    same as above + remove block from Inbox
                                              → ⏎ empty   file to general-reference note + remove block
                                              → ⌘⌫        remove block only  ·  ⇥ skip  ·  esc exit
any bearcli failure ─▶ DailyCapture.send(text, marker:) → Inbox via x-callback + notification
```

- **Capture registry** — a Bear note (default title "Capture registry", `#reference`) is authoritative for destination status: `- project/x` lines, `!paused` hides from the default list, `- tag → <note-id>` overrides the target note, `general-reference: <note-id>` names the triage empty-Enter target. The tag scan (bearcli `list`) discovers unregistered tags (shown `·new`). Charles's second-brain skills maintain this note.
- **Root note rule**: captures land in the tag's note whose title has no `" - <topic>"` suffix (fallback: most recently modified). The filing agent may move entries to sibling sub-notes. With "Tidy spelling & grammar" on (default), the agent may also fix obvious spelling/grammar — never rephrasing or translating (captures are Dutch or English).
- **Ranking**: leaf-prefix 100 > word-boundary 80 > fuzzy subsequence 40+compactness, plus recency `20·exp(−ageDays/14)` and MRU `15·exp(−idx/5)`. Empty query = top rows by recency+MRU with Inbox (capture) / general reference (triage) pinned at row 0 — so ⏎⏎ still means "straight to inbox".
- **Logs**: `~/Library/Logs/Capture/routings.jsonl` (every routing decision — weekly-review reads this for contribution stats) and `filing.log` (agent transcripts).

## Build / verify

- Full build: `xcodegen generate && xcodebuild -project Capture.xcodeproj -scheme Capture -configuration Debug build`, or ⌘R in Xcode.
- Launch with the panel already open (no hotkey needed): pass `--show-on-launch` or `--triage-on-launch` to the binary.
- Pure logic (transforms, parser, ranker, registry parsing) can be smoke-tested by compiling the non-UI sources with a scratch `main.swift`:
  `swiftc -enable-bare-slash-regex -target arm64-apple-macos26.0 Sources/{Notify,BearCLI,Destination,DestinationStore,DestinationRanker,InboxParser,CaptureRouter,FilingAgent,DailyCapture}.swift /tmp/main.swift -o /tmp/t && /tmp/t`
- Behavior is otherwise verified by running the app against Bear.

## Hard constraints

- **macOS 26 Tahoe only**, Swift 6. Personal tool; no backward-compat fallbacks.
- **AppKit `NSPanel`** (not SwiftUI `Window`) — the overlay must be `.nonactivatingPanel`; SwiftUI windows always steal focus.
- **ONE `LauncherPanel` for the app's lifetime — never create a panel per show.** The v0.2–v0.3 pattern (fresh panel per hotkey toggle) gave WindowServer a new window identity seizing key on every toggle and is the prime suspect for the 2026-07-08 bug: after days of uptime, *other* focused apps (Slack, Dia) lost CSS hover/tooltips/cursor changes until Capture was killed. The panel is created once (`ensurePanel`), has `isReleasedWhenClosed = false`, is hidden with `orderOut` only, and is **never** `close()`d. Per-show freshness = `setContent(_:)` installing a **new `NSHostingView` + fresh `LauncherModel`** — a new hosting view is mandatory (not a `rootView` swap: same-type rootView replacement keeps SwiftUI structural identity, so `.onAppear` focus setup and `@FocusState` would not reset). `showPanel` resets to `seedHeight` (88) so a triage session's height never leaks into the next show.
- **Deterministic focus hand-back.** `showPanel` snapshots `NSWorkspace.shared.frontmostApplication` before taking key; `hidePanel`, after `orderOut`, calls `previous.activate(from: .current, options: [])` guarded by *still-frontmost / not-us / not-terminated*. Never remove the still-frontmost guard — "panel persists on focus loss" depends on it (dismissing after a mid-session Cmd+Tab must not yank the user back). Bare `orderOut` leaves key-window return to WindowServer heuristics — the state that decayed in the hover bug.
- **`becomesKeyOnlyIfNeeded = true`** — key is taken exactly once per show via the explicit `makeKey()` in `showPanel`, never incidentally from ordering or chrome clicks. (Explicit `makeKey()` consults `canBecomeKey`, not this flag.) Severable if SwiftUI focus bridging ever misbehaves.
- **Hard-won non-activating panel settings** (`Sources/LauncherPanel.swift`):
  - `hidesOnDeactivate = false`. With `.accessory` + `.nonactivatingPanel`, the system fires app-deactivated almost immediately on subsequent shows; with `true`, the panel auto-hides on every show after the first.
  - `canBecomeKey = true`, `canBecomeMain = false`.
  - `backgroundColor = .clear`, `isOpaque = false`, `animationBehavior = .none`.
  - `container.layer.cornerRadius = Theme.cornerRadius` + `masksToBounds = true` — the mask stays mandatory: it clips the hosting view's rectangular corners so `windowBackgroundColor` never leaks around the themed background.
  - `invalidateShadow()` after every resize so the drop shadow re-traces the silhouette.
- **No "panel resigned key" as a dismiss signal.** Non-activating panels routinely lose key status for OS-internal reasons; `didResignKeyNotification`-based dismissal made the panel vanish ~1s after showing. Dismiss only on Esc / Enter / hotkey toggle — all of which funnel through `hidePanel()`; keep that invariant (the focus hand-back depends on it).
- **Show/hide is instant** (no fade since v0.3 — performance aesthetic). Keep `animationBehavior = .none` regardless: the system's implicit panel animations fight manual ordering.
- **Panel height**: `HeightKey` preference → `panel.resize(toHeight:)`, top edge preserved, grows downward. Compose stage is dynamic (1–5 lines); route stage height is fixed per stage so filtering never resizes.
- **Esc via `.onExitCommand`** on the container (TextField Esc delivery is unreliable); the model decides per stage whether Esc means "back to compose" or "hide".
- **Focus swaps between stages need `DispatchQueue.main.async`** — the target TextField is created in the same transaction as the stage change.
- **One runtime dependency**: [`KeyboardShortcuts`](https://github.com/sindresorhus/KeyboardShortcuts) (global hotkeys). Declared in `project.yml`'s `packages:`.
- **`NSWorkspace.open` with `config.activates = false`** on the fallback path so Bear never steals focus.

## Hotkeys

`⌃⌘Space` capture, `⌃⌘⇧Space` process inbox — both rebindable via `KeyboardShortcuts.Recorder` rows in Settings (persisted in UserDefaults; the `default:` in `HotkeyName.swift` only affects fresh installs).

## The Inbox note

Pinned Bear note, id `E01000CB-BE7D-4FCB-8340-BBE23A4569B9` (configurable in Settings). Blocks are `**yyyy-MM-dd HH:mm**\ntext`, newest on top, blank-line separated; the note ends with the `#inbox` tag line. `InboxParser` tolerates date-only headers and empty bodies, and skips blocks whose header contains `→` (fallback-parked). The note must stay unencrypted.

## Distribution

Personal use, ad-hoc signed. `scripts/release.sh <version>` produces a zipped `.app` for a GitHub Release. Gatekeeper prompts once: right-click → Open, or `xattr -dr com.apple.quarantine /Applications/Capture.app`.
