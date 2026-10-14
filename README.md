<p align="center">
  <img src="docs/icon.png" alt="Capture" width="160" />
</p>

<h1 align="center">Capture</h1>

<p align="center">
  <a href="#install"><img src="https://img.shields.io/badge/platform-macOS%2026%2B-lightgrey" alt="Platform" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="License" /></a>
  <a href="https://github.com/charlesbeaumont/capture-launcher/releases"><img src="https://img.shields.io/github/v/release/charlesbeaumont/capture-launcher?include_prereleases&sort=semver" alt="Release" /></a>
</p>

A tiny macOS menu-bar launcher for a [Bear](https://bear.app)-based second brain. Press a global hotkey, type a thought, hit Enter, then pick a destination as you type: a Bear project, person, list or agenda note, or a [15Five](https://www.15five.com) 1-on-1. Enter with nothing typed sends the thought to your Bear Inbox note; Enter on a destination files it there **immediately**, verbatim. A second hotkey processes the inbox backlog Tinder-style.

Built around three rules: every keystroke paints in under a millisecond (no I/O on the hot path), all Bear writes go through `bearcli` with compare-and-swap safety, and a capture is never lost — any failure parks it in the Inbox with a marker.

Single purpose. No history, no plugins, no main window, no Dock icon, no daemons.

## Install

### Download (recommended)

1. Grab the latest `Capture-vX.Y.Z.zip` from [Releases](https://github.com/charlesbeaumont/capture-launcher/releases).
2. Unzip and drag `Capture.app` to `/Applications`.
3. First launch: **right-click → Open**, then confirm. Capture is ad-hoc signed, so Gatekeeper asks once.

Requires Bear 2.8+ (Capture drives Bear through the `bearcli` binary inside Bear.app). 15Five is optional and needs your company's 15Five MCP switched on (see below).

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
| type + `Enter` | File into the matched destination |
| `Shift+Enter` | Newline |
| `↑` `↓` | Move the selection |
| `Esc` | Back to editing, then close |

The picker list is ranked by match quality, recency, and your recent routings. Each row shows its kind as a colored chip on the right: project, personal, person, list, agenda, or 15Five. A dim `ms` readout shows the filter latency.

## Destinations

All destinations share one list. Each has its own section in Settings, where it can be switched on or off.

**Bear.** Every note tagged `#project`, `#personal`, `#person`, `#list` or `#agenda`, shown by title. A capture lands verbatim as one line, `- **YYYY-MM-DD HH:MM**: text`: at the top of `## Captures` for projects, personal notes and people, at the bottom of `## Captures` for lists, and at the bottom of `## Topics` for agendas. A missing section is created above the note's tag line.

**15Five.** One row per person you have 1-on-1s with, ranked by your next meeting. Enter adds the capture as a talking point on your current 1-on-1 with them; the other person sees it. Capture talks to 15Five's MCP server, the only 15Five interface that can add talking points. To set it up:

1. A 15Five HR or Company Admin switches on 15Five MCP **Access** and **Updates** under Agents Hub > Integrations.
2. In Capture's Settings, open the 15Five section and choose **Sign in…**. Your 15Five login opens in your browser.

Credentials stay in your macOS Keychain. An unused connection expires after 30 days; sign in again from Settings.

## Process Inbox

`⌃⌘⇧Space` (or the menu item) triages existing inbox entries oldest-first, one at a time — prefilled and editable, with a `4/31` counter:

| Action | Result |
|---|---|
| `Enter` → type + `Enter` | File to the matched destination and remove from the Inbox |
| `Enter` → `Enter` (empty) | Keep it in the Inbox and move on |
| `⌘⌫` | Discard (remove from the Inbox) |
| `Tab` | Skip (leave in the Inbox) |
| `Esc` | Exit |

Every decision advances instantly; the Bear writes happen behind it.

## Configuration

Menu bar → **Settings…**: theme (Ember default, Ember Light, and ten more, or follow the system's light/dark setting with a pair), both hotkeys, one section per destination (Bear: bearcli path and Inbox note id; 15Five: sign in and out), and the fallback URI template. The template is used only when a write fails: the capture is parked in the Inbox with ` → <destination>` so nothing is ever lost.

Logs live in `~/Library/Logs/Capture/`: `routings.jsonl` records every routing decision, and `15five-tools.json` holds 15Five's current tool definitions for diagnosis.

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
