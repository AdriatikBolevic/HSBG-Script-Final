# HSBG — Hearthstone Battlegrounds Session Manager

An AutoHotkey v2 automation layer that manages a complete Hearthstone Battlegrounds session: it sequences the four applications involved, keeps every window on the monitor you started it from, and shows you only the surfaces you actually want to see.

**Requirements:** Windows 10/11 · [AutoHotkey v2.0](https://www.autohotkey.com/) · Administrator privileges

---

## Contents

- [What it does](#what-it-does)
- [Installation](#installation)
- [Hotkeys](#hotkeys)
- [How it works](#how-it-works)
- [Configuration](#configuration)
- [Diagnostics](#diagnostics)
- [Troubleshooting](#troubleshooting)
- [Reading the source](#reading-the-source)

---

## What it does

Four applications are involved in a Battlegrounds session, and left alone they produce a cluttered, slow, multi-step start-up with windows scattered across monitors.

| Application | What HSBG does with it |
|---|---|
| **Battle.net** | Opens on your chosen monitor, launches Hearthstone, and minimises once the game is up. Its service surfaces — boot splash, auto-login shell, maintenance overlays, Update Agent — never appear. |
| **Hearthstone** | Launched, kept muted and off-screen while it loads, then revealed centred on your monitor. |
| **Overwolf** | Started after Hearthstone, so its windows are created into a quiet system. |
| **Firestone** | Its in-game overlay stays visible at all times. Its desktop windows stay out of sight until you ask for them. |

One keypress takes you from nothing running to a loaded game with the overlay attached.

---

## Installation

1. Install [AutoHotkey v2.0](https://www.autohotkey.com/) (v1 will not run this script).
2. Place `HSBGScriptFinal.ahk` anywhere convenient.
3. **Start it on the monitor you want to play on.** The script resolves your intended monitor from where it was launched, and everything it places afterwards follows that choice.
4. Accept the UAC prompt. Administrator rights are required for the firewall rules F1 uses and for pausing the Windows Search indexer.

The script elevates itself automatically, handing the launch monitor to the elevated instance so the choice survives.

---

## Hotkeys

### `F1` — Combat-animation skip

Skips the Battlegrounds combat animation by forcing the client to reconnect past it.

It identifies Hearthstone's live game-server connection and blocks that address in both directions for a fixed interval, then releases it. The match continues resolving on Blizzard's servers throughout, so nothing is lost — you rejoin at the result.

Blizzard's login and services connection (TCP 1119) is deliberately left alive, so there is no re-authentication and no risk to your seat in the lobby. Hearthstone's audio is muted for the duration and mouse input over the game window is swallowed, so the skip is silent and cannot be disturbed by a stray click.

Cooldown: 2 seconds between presses.

### `F2` — Launch or restart

Starts a full session, or restarts one already in progress.

```
Battle.net opens  →  launches Hearthstone  →  minimises once the game is up
                                           →  Firestone starts
                                           →  Hearthstone is revealed on your monitor
```

Pressing F2 while Hearthstone is already running restarts it cleanly, closing the game and the Blizzard processes first.

A stalled launch is recovered rather than left hanging: the pipeline has a five-minute ceiling, time spent on the Battle.net login screen does not count against it, and a game that appears after the ceiling is still picked up.

### `F3` — Show or hide Firestone

Toggles the Firestone desktop windows (Main and Battlegrounds). They start hidden.

These windows are **deliberately exempt from the monitor lock**. They are what you read while playing, so they belong wherever you put them — typically a second screen, beside the game rather than over it. Each window's exact position is remembered when it is concealed and restored when it returns, so move one wherever you like and F3 will keep it there.

The in-game overlay is never affected by F3. It is always visible.

### `F4` — Shutdown

Closes Overwolf, Battle.net and Hearthstone, restores everything the script changed, and exits.

Also available as a held-key fallback, so it still works when a fullscreen game is swallowing window messages.

> **Note:** `Alt+F4`, `Ctrl+F4` and `Win+F4` are passed through to Windows untouched. Only an unmodified F-key triggers HSBG.

---

## How it works

Three principles account for most of the design. They are what make the window handling reliable rather than lucky, and each exists because the obvious approach fails in a specific way.

### 1. One owner per window per phase

Exactly one subsystem decides what happens to a given window at a given time. Where two could disagree, they are funnelled through a single shared primitive instead.

Contended windows are the root of nearly every flicker and race this kind of automation suffers from. Two timers concealing the same window from different starting points do not average out — they fight, and which one wins varies by machine and by run.

### 2. Ask the window, not the ledger

The script keeps bookkeeping of what it has concealed, to avoid redundant work. That bookkeeping is never treated as evidence about a window's actual state.

The reason is simple: the owning application is editing that state concurrently. A cloak can be silently reset by an ordinary window operation; a window can be repositioned back on screen a millisecond after being moved off it. Anywhere the answer has to be correct, the code queries the OS rather than consulting its own notes.

### 3. Move, don't hide

Chromium-based windows — Firestone, and the Battle.net client — treat `ShowWindow(SW_HIDE)` as *you no longer exist* and tear down their compositor accordingly. A window hidden before it has ever painted may never paint again: you get a correctly sized, correctly framed, completely blank rectangle.

So windows that must come back are **moved off the virtual desktop** rather than hidden. A move is synchronous and atomic; the window stays alive and fully rendered, it simply is not over a monitor. Combined with a DWM cloak and taskbar-button removal, the result is indistinguishable from hidden — no pixels, no taskbar entry, no Alt-Tab entry, no thumbnail — while the application remains perfectly healthy.

The script confirms a window can actually paint (by sampling its composited content) before it will use any stronger concealment on it.

---

## Configuration

Every tunable value lives in the `CFG` object at the top of the script, documented in place with its trade-offs. Nothing outside `CFG` needs editing for normal use.

The settings most people will want:

| Setting | Default | Effect |
|---|---|---|
| `forcefulHoldMs` | `2500` | How long F1 holds the connection block. The single knob controlling skip duration. |
| `f1Target` | `"smart"` | Which connection F1 blocks. `"all"` is a sledgehammer fallback if `"smart"` ever picks wrong. |
| `bnetRevealDwellMs` | `3000` | Minimum time the launcher stays on screen before it may minimise. |
| `bnetPostPlayLingerMs` | `2000` | Pause between Hearthstone launching and the launcher minimising. |
| `fsLaunchAfterHS` | `true` | Start Firestone only once Hearthstone is running. |
| `fsFollowMonitorLock` | `false` | Whether Firestone's windows are pinned to the launch monitor. |
| `lockWindowsToChosenMonitor` | `true` | Keep Battle.net, the Agent, Hearthstone and the HUD on your monitor. |
| `scriptAboveNormalPriority` | `true` | Raise the script's own priority for steadier timing. Set false if you see game micro-stutter. |
| `pauseWSearchDuringHS` | `true` | Stop the Windows Search indexer while Hearthstone runs. |
| `setHSGpuPreference` | `true` | Register Hearthstone as high-performance GPU (hybrid graphics systems). |

---

## Diagnostics

With `f1DebugLog` enabled (the default), the script appends one line per significant event to:

```
%TEMP%\hs_bg_f1.log
```

A single launch is normally enough to explain any unexpected behaviour. The lines that matter most:

```
BNET-SEQ launcher revealed -- minimize sequence armed
BNET-SEQ Hearthstone launched -- launcher lingers 2000ms then minimizes
BNET-SEQ minimize confirmed
FS-DEFER Hearthstone up -- launching Firestone into a quiet system
FS-PAINT PROVEN AT REVEAL hwnd=... distinct=847 -- warm from now on
FS-REVEAL title="Firestone - Main" painted=yes visible=1
```

Each records a decision the script made and why, so a missing line localises a problem immediately.

---

## Troubleshooting

**Firestone's window comes back blank.** Check the log for `FS-PAINT`. If it reports the window never proved it painted, try `fsMainColdPolicy := "cloak"` instead of `"park"` — concealment behaves differently across Overwolf builds.

**The launcher does not minimise.** The log traces the whole sequence: revealed → armed → Hearthstone launched → minimize confirmed. Whichever line is missing identifies the stage that stalled. `BNET-SEQ minimize did NOT take` means the client is refusing or immediately restoring itself.

**A window is missing after a crash or reload.** Restart the script. It repairs stranded windows at start-up — anything left outside the virtual desktop, left cloaked, or left transparent by an earlier instance is recovered automatically.

**F1 does not skip.** Check the log line for the press: it records whether a game connection was identified at all. If none was found, set `f1Target := "all"`.

**Changes to the script appear to have no effect.** AutoHotkey does not hot-reload. The previously launched instance keeps running until you exit it from the tray and start the new one.

---

## Reading the source

The script is a single self-contained file of roughly 8,100 lines, about a third of which is documentation.

**The comments are written to be sufficient to rebuild the script from scratch.** Each subsystem states the constraint it exists to satisfy rather than merely what it does, because in nearly every case the obvious implementation is the one that fails — and the comment explains which failure. The file header contains a `REBUILDING THIS SCRIPT` section listing the load-bearing decisions in the order you will encounter them.

The source is organised into numbered sections, mapped in the header:

| | |
|---|---|
| **S1** Configuration | Every tunable, documented in place |
| **S2** Runtime state | Shared flags and caches |
| **S3** HUD | On-screen status text |
| **S4** Audio | Per-application mute during F1 |
| **S5** Process manager | Locate, launch and query the applications |
| **S6** Path resolution | Find Overwolf and Firestone on disk |
| **S7** Settings patch | Pre-configure Firestone's settings file |
| **S8** Firewall manager | The scoped connection block used by F1 |
| **S9** Performance | Timer resolution, priority, GPU preference |
| **S10** Window manager | Concealment, paint detection and reveal |
| **S11** Overlay / reveal / monitor lock | Overlay enforcement, F3, window placement |
| **S12** Timer helpers | Shared utilities |
| **S14** Launch pipeline | The F2 state machine |
| **S15** Hotkeys | The four handlers |
| **S16** Startup | Boot checks, repairs, background tasks |

### Verifying a change

A cheap and strict check: strip every comment and blank line from the file before and after your edit, and diff the result. A documentation-only change should produce **no difference at all**.

```bash
# extract code only, ignoring comments and blank lines
grep -v '^\s*;' HSBGScriptFinal.ahk | sed 's/\s\+;.*$//' | grep -v '^\s*$'
```

---

## Notes

- The script never modifies Hearthstone's process priority, game files, or memory. It manages windows, one firewall rule scoped to a single address, and two Windows settings (per-application GPU preference and the Search indexer), all of which it reverses on exit.
- Firewall rules created by F1 are removed on release, and swept at start-up and exit, so an interrupted press cannot leave a connection blocked.
- Every concealment has a matching cleanup that works from an empty ledger, so a crash or forced reload cannot leave a window unreachable.
