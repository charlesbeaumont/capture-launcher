# Capture — agent notes

## What this is

Single-purpose macOS overlay launcher for Charles's Bear-based second brain. Press a global hotkey, a flat themed bar opens, type a thought, hit Enter — then a destination picker filters projects/people/personal areas as you type. Enter on the pinned Inbox row (or with nothing typed) sends the capture to the pinned Bear "Inbox" note; Enter on a destination files it **immediately**, verbatim, into that note. A second hotkey opens Process Inbox: Tinder-style triage of existing inbox items.

The point is **speed**: hotkey → bar → Enter → gone. Lives entirely as a menu-bar app. No history, no plugins, no main window, no Dock icon. The bar persists when focus is lost — only Esc / Enter / the hotkey itself hide it. Multi-line capture grows the bar downward up to 5 lines, then scrolls internally.

## Design principles (Charles's explicit choices — don't violate)

1. **Speed is the product.** Every keystroke-to-paint under 300ms; in practice <1ms because the keystroke path never does I/O. Destinations live in memory (refreshed async at launch, on every panel show, and via the Refresh Projects menu item). All Bear writes are optimistic: the panel hides / triage advances instantly, work happens behind it.
2. **bearcli for everything.** All Bear I/O goes through the `BearCLI` actor wrapping `/Applications/Bear.app/Contents/MacOS/bearcli` (ships inside Bear 2.8+, works headless). Writes only via CAS: `cat --format json` (returns `content` + `hash`) → transform → `overwrite --base <hash>`; a concurrent Bear.app change rejects the write (exit 1, "Note has changed since last read") and we re-read and retry ×3. **A whole-note `cat` is the only source of the hash.** It used to be `show --fields hash,content`; bearcli 2.9.x dropped `hash` from `show`'s field set, which broke every read with "Unknown field: hash" — triage closed instantly and captures silently took the fallback path (2026-08-23). Re-check this if bearcli is upgraded. **Never write Bear's SQLite directly.** The x-callback URI template survives only as the fallback path.
3. **No daemons, no background agents.** No queues, no Redis, no background workers, no launchd. Charles explicitly rejected daemon infra — don't reintroduce it. The per-capture `claude -p` filing agent was removed on 2026-10-13: the second brain's rule is that nothing writes to Bear in the background.
4. **A capture is never lost.** Every failure path degrades to an Inbox write via the fallback URI template with a backtick-wrapped `` → `#tag` `` marker (backticks so Bear doesn't tag the Inbox note) plus a notification. The triage parser skips marker-carrying blocks.
5. **Human decides, verbatim lands.** The picker is Charles's routing decision. A capture lands exactly as typed and stays where it lands; turning captures into notes is his job.
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
  DestinationStore.swift    Merged list across providers, per-provider state + cache, MRU usage
  Destinations/             DestinationProvider protocol; BearProvider; FifteenFive{Provider,Auth}; MCPClient
  DestinationRanker.swift   Pure per-keystroke ranking (prefix > word-boundary > subsequence)
  CaptureRouter.swift       All write orchestration + pure text transforms + routings.jsonl
  InboxParser.swift         Inbox note → [InboxEntry] (oldest-first, marker/tag-line aware)
  Notify.swift              Failure-only UserNotifications
  DailyCapture.swift        FALLBACK x-callback path ({content}/{time}/{date}/{datetime}/{marker})
  HotkeyName.swift          .toggleLauncher (⌃⌘Space) + .triageInbox (⌃⌘⇧Space)
  SettingsView.swift        Theme, hotkeys, one section per destination (Bear, 15Five sign-in), fallback template
Resources/
  AppIcon.icns
scripts/
  dev.sh                    fswatch + xcodegen + xcodebuild Debug + relaunch loop
  release.sh                xcodegen + xcodebuild Release + ditto zip for GitHub Releases
```

The `.xcodeproj` is generated by XcodeGen and gitignored: `xcodegen generate` after editing `project.yml` or adding/removing source files (`scripts/dev.sh` does it on every save).

## Data flow

```
capture:  ⏎ text → picker → ⏎ dest ──BearCLI casEdit──▶ dest note's section (see below)
                          → ⏎ inbox ──BearCLI casEdit──▶ Inbox note (prepend under H1)
triage:   entry prefilled (editable) → picker → ⏎ dest    same, under the entry's ORIGINAL timestamp, + remove block
                                              → ⏎ inbox   keep it in the Inbox and move on (same as ⇥)
                                              → ⌘⌫        remove block only  ·  ⇥ skip  ·  esc exit
any bearcli failure ─▶ DailyCapture.send(text, marker:) → Inbox via x-callback + notification
```

- **Destination providers** (`Sources/Destinations/`). A `DestinationProvider` lists destinations and files a capture; `DestinationStore` merges every enabled provider into one picker list, sorted by recency, and keeps per-provider state and cache (`destinations-<provider>.json`). A failing provider keeps its cached rows. Ids are provider-qualified (`bear:<note id>`, `fifteenFive:<person id>`). Enable flags: UserDefaults `destination.<provider>.enabled` (Bear on, others off by default). The Inbox row and triage mechanics stay in `CaptureRouter`, always Bear. A failed write parks the capture in the Inbox with ` → Title` (Bear) or ` → Title (15Five)`. Adding a destination = a new provider + a case in `ProviderID` + a Settings section.
- **15Five** (`FifteenFiveProvider`). Remote MCP at `https://my.15five.com/mcp`, the only 15Five write path: the public REST API's `/one-on-one/` is GET-only. Needs 15Five MCP **Access** and **Updates** switched on in Agents Hub > Integrations. One row per person from `list_one_on_one_counterparts`, ranked by next meeting date; Enter calls `add_one_on_one_talking_point` (starts an undated 1-on-1 if none is upcoming; the other person sees it). Talking points only, never action items (Charles, 2026-10-14). Called as a plain API with the exact contract read from the live `tools/list` (2026-10-14), no guessing: both tools wrap arguments in `params`. List: `{params: {limit: 100, offset}}`, paging on `has_more`/`next_offset`, rows `user_id`, `name`, `next_meeting_date`. Write: `{params: {with_user_id, description, request_id}}`, success when `receipt.applied` (or `replay` for a retried `request_id`). A changed shape throws `MCPError` naming the tool and the capture parks in the Inbox. Live schemas are logged to `~/Library/Logs/Capture/15five-tools.json` on each refresh for diagnosis only.
  - **Auth**: OAuth discovered at `/.well-known/oauth-authorization-server`: dynamic registration, auth code + PKCE S256, public client, refresh tokens, scope `mcp:tools`, redirect `http://127.0.0.1:<port>/callback` from a one-shot `NWListener` (`LoopbackCallback`), login opened in the default browser. 15Five rejects custom-scheme redirects (`capture://` → `invalid_redirect_uri`), so `ASWebAuthenticationSession` with a custom scheme can't work; each sign-in registers a client with that exact port. Credentials live in the Keychain (`com.charlesbeaumont.Capture.15five`); `FifteenFiveTokens` serialises refreshes. Unused connections expire after 30 days: sign in again from Settings.
  - **MCP client**: `NativeMCPClient`, a ~150-line Streamable HTTP client (initialize, tools/list, tools/call, JSON or SSE responses, one retry on 401/404) instead of the Swift MCP SDK, to keep one dependency. `MCPToolCaller` is the seam if another transport is ever wanted.
- **Destinations follow the second brain** (`~/Workspace/second-brain/CLAUDE.md`, flattened 2026-10). Tags are flat and the title is the identity: every note tagged `#project`, `#personal`, `#person`, `#list` or `#agenda` is one destination, shown by title. `#archive`, `#unsorted`, `#reference`, `#output`, `#reflection` are never routable. No registry note, no paused state, no nested `project/x` tags; all three are gone.
- **Write contract** (matches the `review-captures` skill): one line `- **YYYY-MM-DD HH:MM**: text`, multi-line bodies indented two spaces. Projects, personal and people: top of `## Captures` (newest first). Lists: bottom of `## Captures`. Agendas: bottom of `## Topics`. A missing section is created above the trailing tag line, or at the end when the tag isn't last. Never write anywhere else in a note.
- **Fallback marker**: a parked capture's header gets ` → <destination title>`, the routing hint `review-captures` reads.
- **Ranking**: title-prefix 100 > word-boundary 80 > fuzzy subsequence 40+compactness, plus recency `20·exp(−ageDays/14)` and MRU `15·exp(−idx/5)` keyed by note id. Empty query = top rows by recency+MRU with Inbox pinned at row 0, so ⏎⏎ means "straight to inbox" (capture) or "keep it there" (triage).
- **Logs**: `~/Library/Logs/Capture/routings.jsonl`, one record per routing decision with the destination title and note id.

## Build / verify

- Full build: `xcodegen generate && xcodebuild -project Capture.xcodeproj -scheme Capture -configuration Debug build`, or ⌘R in Xcode.
- Launch with the panel already open (no hotkey needed): pass `--show-on-launch` or `--triage-on-launch` to the binary.
- Pure logic (transforms, parser, ranker, destination discovery) can be smoke-tested by compiling the non-UI sources with a scratch `main.swift`:
  `swiftc -enable-bare-slash-regex -target arm64-apple-macos26.0 Sources/{Notify,BearCLI,Destination,DestinationStore,DestinationRanker,InboxParser,CaptureRouter,DailyCapture}.swift Sources/Destinations/*.swift /tmp/main.swift -o /tmp/t && /tmp/t`
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
- **Hover bug evidence as of 2026-09-26. Read this before touching Capture's focus code again.**
  - Barbee 4.3 (build 20260609002) leaks CGEventTaps: about 36 per day, all filtering, all at the HID tap point, all disabled and never released. Measured twice: 742 taps after 23 days (Aug), 820 after 23 days (Sep). Public report with the same build, still open and unanswered: https://github.com/HsiangHo/Barbee-Feedback/issues/6. WindowServer shows the load: ~26% CPU at idle, 20k Mach ports.
  - Capture holds zero event taps and zero global monitors. The broken-state dump showed 0 Capture windows, 53 FDs, 6 threads.
  - The Capture key-window theory is weak. In the broken-state dump Slack was active and its window was AXMain. Chromium drops `mouseMoved` only when its window is neither key nor main, so that filter was not firing.
  - Every victim so far is Chromium (Slack, Dia, Chrome). A killed cause does not heal a victim already stuck; it must be relaunched.
  - `scripts/taps.swift` (installed `~/bin/taps`) lists taps per process. Run it with `hoverdump` at the next occurrence.

- **When the hover bug next strikes, run `hoverdump` BEFORE quitting anything.** `scripts/hoverdump.swift`, installed at `~/bin/hoverdump`. It snapshots active app, per-app AX focused window, all on-screen windows, what sits under the cursor, and Capture's FD/thread/child counts. Three attempts at this bug (per-toggle panel churn, the `frontmostApplication` hand-back, activate-on-show) were all reasoned from mechanism and all failed — stop guessing and read the broken state. Healthy baseline for comparison: the active app shows `main=true` on its focused window, and Capture has exactly 0 or 1 on-screen windows.
  - Still unrun and free: when it happens, **relaunch only the affected app and leave Capture running.** If hover returns and stays, Capture is not holding anything and the damage is a one-time event.
  - Pre-registered next suspect: `setContent` builds a new `NSHostingView` per show and `removeFromSuperview()`s the old one. Gyors keeps ONE hosting controller for the process lifetime, re-arming per-show state via a `focusTick` counter plus a direct `makeFirstResponder` in an `NSViewRepresentable`. Ours is the last structural difference left.

- **No resign-key dismissal. The bar persists when focus is lost.** Charles tried click-away dismissal on 2026-08-23 and rejected it the same day. Dismiss only on Esc / Enter / hotkey toggle — all funnel through `hidePanel()`; keep that invariant.
  - If it is ever reintroduced: install it **once** in `ensurePanel`, never in `showPanel` (that accumulates one observer per show), scope it to `object: panel` (unscoped fires for the Settings window), and gate it on `!NSApp.isActive` checked one runloop hop later. Raw resign-key is not a focus-loss signal: `NSApp.activate` is async, and triage's `.loading` stage has no `TextField`, so nothing takes first responder and the panel drops key on its own.
  - Consequence to live with: a visible floating panel left up over another app swallows mouse events inside its own 720×N rectangle. That is local and expected — not the systemic hover bug, though it can look like it.
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
