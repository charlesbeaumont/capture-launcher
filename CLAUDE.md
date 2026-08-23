# Capture — agent notes

## What this is

Single-purpose macOS overlay launcher for Charles's Bear-based second brain. Press a global hotkey, a flat themed bar opens, type a thought, hit Enter — then a destination picker filters projects/people/personal areas as you type. Enter on the pinned Inbox row (or with nothing typed) sends the capture to the pinned Bear "Inbox" note; Enter on a destination files it **immediately** into that project's note and spawns a short-lived Claude agent to reposition it within the note. A second hotkey opens Process Inbox: Tinder-style triage of existing inbox items.

The point is **speed**: hotkey → bar → Enter → gone. Lives entirely as a menu-bar app. No history, no plugins, no main window, no Dock icon. Esc / Enter / the hotkey / clicking another app all hide the bar. Multi-line capture grows the bar downward up to 5 lines, then scrolls internally.

## Design principles (Charles's explicit choices — don't violate)

1. **Speed is the product.** Every keystroke-to-paint under 300ms; in practice <1ms because the keystroke path never does I/O. Destinations live in memory (refreshed async at launch, on every panel show, and via the Refresh Projects menu item). All Bear writes are optimistic: the panel hides / triage advances instantly, work happens behind it.
2. **bearcli for everything.** All Bear I/O goes through the `BearCLI` actor wrapping `/Applications/Bear.app/Contents/MacOS/bearcli` (ships inside Bear 2.8+, works headless). Writes only via CAS: `cat --format json` (returns `content` + `hash`) → transform → `overwrite --base <hash>`; a concurrent Bear.app change rejects the write (exit 1, "Note has changed since last read") and we re-read and retry ×3. **A whole-note `cat` is the only source of the hash.** It used to be `show --fields hash,content`; bearcli 2.9.x dropped `hash` from `show`'s field set, which broke every read with "Unknown field: hash" — triage closed instantly and captures silently took the fallback path (2026-08-23). Re-check this if bearcli is upgraded. **Never write Bear's SQLite directly.** The x-callback URI template survives only as the fallback path.
3. **No daemons.** No queues, no Redis, no background workers, no launchd. Agents are spawned per capture (`claude -p`, detached, `FilingAgent.swift`) and exit. Charles explicitly rejected daemon infra — don't reintroduce it.
4. **A capture is never lost.** Every failure path degrades to an Inbox write via the fallback URI template with a backtick-wrapped `` → `#tag` `` marker (backticks so Bear doesn't tag the Inbox note) plus a notification. The triage parser skips marker-carrying blocks.
5. **Human decides, agents assist.** The picker is Charles's routing decision. The filing agent only repositions the entry *within* the destination he chose (or its sibling sub-notes); if unsure it leaves the entry in `## Captured`.
6. **Themed minimal UI, modelled on [Gyors](https://github.com/balintb/Gyors)** (2026-08 restyle; its macOS layer is SwiftUI over an `NSPanel`, so its numbers port directly). **Ember default** — Gyors' published theme, verbatim: bg `#120C10`, accent `#F97316`, text `#FBF3EC`/`#A89B91`/`#6B5E54`, backgroundOpacity 0.88. Eleven themes in Settings (`Theme.swift`, one struct literal each: Ember, Solarized Light/Dark, Gruvbox Light/Dark, Catppuccin Latte/Mocha, Nord, Dracula, Tokyo Night, Mono Dark).
   - **Three text tiers**: `foreground` (primary) / `secondary` (banner, status — real content) / `dim` (hints, placeholders, ms readout). **Never bake `.opacity()` into a text colour** — over the blur substrate the alpha multiplies and the text goes mushy. Use a solid hex. Alpha on `selectionBackground` is fine; it's a background.
   - **Translucency**: `NSVisualEffectView` (`.popover`, `.behindWindow`, `.active`) as a sibling of the hosting view; per-theme `usesBlur` + `backgroundOpacity`. Charles declined Raycast's glass in 2026-07 but chose Gyors' in 2026-08.
   - **Geometry**: 720 wide, cornerRadius 14 (was 16), 20pt gutter everywhere so the leaf name lines up under the typed text, 36pt rows, no border, instant show/hide, no row icons, no footer bar, no `>` prompt glyph.
   - **Type**: SF Pro throughout (Charles found a pixel font "too much"). Both inputs 22pt `.light`; leaf name 14pt `.medium`; banner 13; chip 11 semibold; hints and ms readout 11.
   - **Selection**: flat full-bleed `accent × selectionOpacity` across the whole row, radius 0, no inset (replaced 2026-07's inset rounded highlight).
   - **`Divider().opacity(0.3)`** full-bleed between the query row and the list.
   - **TheyDo chips** right-aligned per row (2026-07, replaced rainbow badges Charles disliked): one shared hue set `Theme.theydoKinds` (violet/pink/teal/amber/blue/ink-gray/orange for lists/grape for agendas), a pastel **gradient** fill + same-hue tinted text via `Theme.chip(for:)`, derived against each theme's background/foreground so chips adapt to light/dark. `kindColors` stays per-theme-overridable (Mono Dark overrides to stay monochrome).
   - Fixed-height 8-row **scrollable** viewport (empty query lists *all* destinations; the panel never resizes while filtering — only on stage transitions).
   - Placeholder text must be explicitly themed via `prompt: Text(...).foregroundColor(theme.secondary)` — default placeholders ignore the theme and vanish on dark themes. `secondary`, not `dim`: `dim` is the tertiary tone and reads too dark for a placeholder (Charles, 2026-08-21).

## Project layout

```
project.yml                 XcodeGen spec — single source of truth for the Xcode project
Sources/
  CaptureApp.swift          @main App + MenuBarExtra (Open/Process Inbox/Refresh) + Settings scene
  AppDelegate.swift         .accessory policy, both hotkeys, panel lifecycle, --show-on-launch dev flag
  LauncherPanel.swift       NSPanel subclass (non-activating, transparent, blur sibling, children clipped)
  LauncherView.swift        Stage-driven SwiftUI view: compose / route / loading / done
  LauncherModel.swift       @Observable stage machine (capture + triage modes, all transitions)
  DestinationListView.swift Fixed-height scrollable viewport, TheyDo chips right-aligned, full-bleed accent selection
  Theme.swift               Eleven Theme structs (Ember default), three text tiers, blur/opacity knobs, chip hues
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
- **ONE `LauncherPanel` for the app's lifetime — never create a panel per show.** The v0.2–v0.3 pattern (fresh panel per hotkey toggle) gave WindowServer a new window identity seizing key on every toggle and is the prime suspect for the 2026-07-08 bug: after days of uptime, *other* focused apps (Slack, Dia) lost CSS hover/tooltips/cursor changes until Capture was killed. The panel is created once (`ensurePanel`), has `isReleasedWhenClosed = false`, is hidden with `orderOut` only, and is **never** `close()`d. Per-show freshness = `setContent(_:)` installing a **new `NSHostingView` + fresh `LauncherModel`** — a new hosting view is mandatory (not a `rootView` swap: same-type rootView replacement keeps SwiftUI structural identity, so `.onAppear` focus setup and `@FocusState` would not reset). `showPanel` resets to `seedHeight` (72) so a triage session's height never leaks into the next show.
- **`showPanel` ACTIVATES, then orders front** (2026-08, the Gyors fix): `NSApp.activate(ignoringOtherApps: true)` followed by `makeKeyAndOrderFront(nil)`. Under `.accessory` there is no Dock icon and no menu bar, so activating is invisible. This is the Spotlight / Alfred / Raycast / Gyors model.
  - **Why, and what it replaced:** until 2026-08 `showPanel` took key with `orderFrontRegardless()` + `makeKey()` and never activated. That leaves the previously-focused app *active* but with no key window anywhere in its process — and CSS hover, tooltips and cursor rects all hang off `NSTrackingArea` with `.activeInKeyWindow`, plus `mouseMoved` delivery requires key status. All three die together, in the foreground app, until Capture is killed. That is the 2026-07-08 bug's symptom exactly. Earlier suspects (per-toggle panel churn, the `frontmostApplication` hand-back) were both removed and the bug survived both.
  - **`hidePanel` is EXACTLY `orderOut(nil)` — nothing else.** No hand-back, no `makeFirstResponder(nil)`. Activation on show means `orderOut` is a normal deactivation and AppKit restores the previous app as both active *and* key on its own.
  - Still FORBIDDEN in the hide path: **`makeFirstResponder(nil)` before `orderOut`** (kills AppKit key-window return EVERY cycle — the v0.3.1 regression, 100% reproducible) and **`becomesKeyOnlyIfNeeded = true`** (makes key return flaky, 1 in 3). Panel keeps the NSPanel default (`false`).
  - This is a **multi-day soak bug** — per-cycle keyboard tests give false negatives (key return can work while hover return is broken). Verify by hovering Slack/Dia after days of uptime, not by toggling ten times.
- **Panel settings** (`Sources/LauncherPanel.swift`):
  - `hidesOnDeactivate = false` — still, even though `showPanel` now activates. **`NSApp.activate` is asynchronous**: measured 2026-08-21, the app is `active=0 key=0` at `makeKeyAndOrderFront` and only reaches `active=1 key=1` about 500ms later. Any deactivate landing in that gap makes `true` swallow the panel entirely — it simply never appears, intermittently. Gyors keeps `true` as belt-and-braces alongside its observer; don't copy that. The resign-key observer covers dismiss-on-focus-loss with a precise signal and a benign failure mode (panel stays up).
  - `styleMask` is `[.nonactivatingPanel, .borderless]`. **No `.fullSizeContentView`** — it is only meaningful alongside `.titled`, and without that macOS 26 falls back to a content backing that ignores `isOpaque = false`, killing translucency.
  - `canBecomeKey = true`, `canBecomeMain = false`.
  - `backgroundColor = .clear`, `isOpaque = false`, `animationBehavior = .none`.
  - **Rounding lives on the children, never the container.** `cornerRadius` + `masksToBounds` together force offscreen rasterisation, and on macOS 26 that buffer composites *opaque*. The container stays a plain transparent `NSView`; the blur view and the hosting view each carry their own `cornerRadius` + `.continuous` + `masksToBounds`. Clipping the hosting view directly is what stops `windowBackgroundColor` leaking around the themed background.
  - `host.layer.isOpaque = false` in `setContent`. `NSHostingView` on macOS 26 defaults it to `true` even with a clear background, so CoreAnimation skips alpha compositing and no blur shows through.
  - `invalidateShadow()` after every resize so the drop shadow re-traces the silhouette.
- **Dismiss on resign-key IS the signal now** (2026-08) — one observer, installed once in `ensurePanel`, scoped to `object: panel` so the Settings window does not trigger it. It was banned until 2026-08 because a non-activating panel in an *inactive* app loses key for OS-internal reasons and the panel vanished ~1s after showing; once we are genuinely the active app, resign-key means a real focus loss. Never install it in `showPanel` — that accumulates one observer per show.
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
