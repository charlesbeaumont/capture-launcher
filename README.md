<p align="center">
  <img src="docs/icon.png" alt="Capture" width="160" />
</p>

<h1 align="center">Capture</h1>

<p align="center">
  <a href="#install"><img src="https://img.shields.io/badge/platform-macOS%2026%2B-lightgrey" alt="Platform" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="License" /></a>
  <a href="https://github.com/charlesbeaumont/capture-launcher/releases"><img src="https://img.shields.io/github/v/release/charlesbeaumont/capture-launcher?include_prereleases&sort=semver" alt="Release" /></a>
</p>

A tiny macOS menu-bar launcher for a [Bear](https://bear.app)-based second brain. Press a global hotkey, type a thought, hit Enter — then a destination picker filters your projects, people, and personal areas as you type. Enter with nothing typed sends the thought to your Bear Inbox note; Enter on a destination files it into that project's note **immediately** (and a short-lived Claude agent moves it to the right section inside the note). A second hotkey processes the inbox backlog Tinder-style.

Built around three rules: every keystroke paints in under a millisecond (no I/O on the hot path), all Bear writes go through `bearcli` with compare-and-swap safety, and a capture is never lost — any failure parks it in the Inbox with a marker.

Single purpose. No history, no plugins, no main window, no Dock icon, no daemons.

## Install

### Download (recommended)

1. Grab the latest `Capture-vX.Y.Z.zip` from [Releases](https://github.com/charlesbeaumont/capture-launcher/releases).
2. Unzip and drag `Capture.app` to `/Applications`.
3. First launch: **right-click → Open**, then confirm. Capture is ad-hoc signed, so Gatekeeper asks once.

Requires Bear 2.8+ (Capture drives Bear through the `bearcli` binary inside Bear.app). The optional filing agent needs [Claude Code](https://claude.com/claude-code) (`claude` CLI).

### Build from source

Requirements: macOS 26 Tahoe, Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate
open Capture.xcodeproj
```

Then ⌘R. No Dock icon — look for the brain glyph in the menu bar. For tight iteration, `./scripts/dev.sh` rebuilds and relaunches on every save (needs `brew install fswatch`).

## Capture

| Action | Result |
|---|---|
| `⌃⌘Space` | Toggle the bar |
| `Enter` | Open the destination picker |
| `Enter` again (empty) | Send to the Bear Inbox note |
| type + `Enter` | File into the matched project / person / personal note |
| `Shift+Enter` | Newline |
| `↑` `↓` | Move the selection |
| `Esc` | Back to editing, then close |

The picker list is ranked by match quality, note recency, and your recent routings. Rows show the kind as a colored badge on the right — project, person, personal, reference — with badge colors drawn from the active theme's accent palette. A dim `ms` readout shows the filter latency.

Routed captures land at the end of the note's `## Captured` section (created if missing, above the tag line). If "Refine placement with Claude" is on, a detached `claude -p` run then moves the entry to the right spot per the note's own conventions — an append-at-top 1-on-1 log, a topical section, or a better-matching sub-note — and leaves it in `## Captured` when unsure.

## Process Inbox

`⌃⌘⇧Space` (or the menu item) triages existing inbox entries oldest-first, one at a time — prefilled and editable, with a `4/31` counter:

| Action | Result |
|---|---|
| `Enter` → type + `Enter` | File to the matched destination and remove from the Inbox |
| `Enter` → `Enter` (empty) | File to the general-reference note and remove from the Inbox |
| `⌘⌫` | Discard (remove from the Inbox) |
| `Tab` | Skip (leave in the Inbox) |
| `Esc` | Exit |

Every decision advances instantly; the Bear writes happen behind it.

## The Capture registry

A Bear note titled **Capture registry** (`#reference`) controls what the picker offers:

```
- project/q3-governance-guidance
- personal/build-cto-os !paused
- reference → <note-id>
general-reference: <note-id>
```

`!paused` hides a destination from the default list (it still matches when you type). `→ <note-id>` overrides which note a tag files into. `general-reference:` names the triage default target. Tags that exist in Bear but not in the registry still appear, marked `·new`. Without a registry note, the tag scan alone drives the picker.

## Configuration

Menu bar → **Settings…**: theme (Solarized Light default; Solarized Dark, Gruvbox Light/Dark, Catppuccin Latte/Mocha, Nord, Dracula, Tokyo Night, Mono Dark), both hotkeys, bearcli path, Inbox note id, registry note title, the filing agent (placement toggle / spelling-and-grammar tidy / `claude` path / model), and the fallback URI template — used only when bearcli fails, parking the capture in the Inbox with a `` → `#tag` `` marker so nothing is ever lost.

Logs live in `~/Library/Logs/Capture/`: `routings.jsonl` (every routing decision) and `filing.log` (agent transcripts).

## Project layout

```
project.yml                 XcodeGen spec — single source of truth
Sources/                    see CLAUDE.md for the per-file map
Resources/                  app icon
scripts/dev.sh              fswatch → rebuild → relaunch
scripts/release.sh          build Release zip for GitHub Releases
```

The `.xcodeproj` is generated and gitignored — run `xcodegen generate` after editing `project.yml` or adding source files.

## License

[MIT](LICENSE).
