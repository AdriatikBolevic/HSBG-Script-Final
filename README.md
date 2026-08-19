# HSBG — Hearthstone Battlegrounds Session Manager

An AutoHotkey v2 automation layer that manages a complete Hearthstone Battlegrounds session with a manageable features in the included config file: F1- Combat Skip without closing HSBG. F2- Cold launches Firestone & Hearthstone, as well as quick restarts you back into the game if used while HS is open., F3- Manages Firestone Mian and Firestone Battlegrounds, keeping them minimized and hidden away till you unlock and pull them back, F4 closes everything, overwolf, firestone, hearthstone and the script itself. F2 to open the game, and manage and hide all unwanted clutter that comes with programs like firestone and overwolf, F1 to skip the combat, F3 to pull up the Firestone programs when you want access to it, other wise keeping it away, the whole time the overlay is active and squared away, F2 to restart if you skipped combat but you died, and F4 to close it all up when it's time to sleep. A Full automated setup, that makes the game much more smooth and enjoyable. Also works if you do not have firestone, and just want a perfected combat skip. 

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
| **Battle.net** | Opens on your chosen monitor, presses Play, and minimises *before* the game window arrives. Its service surfaces — boot splash, auto-login shell, maintenance alerts, Update Agent — never appear. If Play can't start the game because an update or sign-in is pending, the launcher comes back and says so. |
| **Hearthstone** | Launched, and then left alone. Never hidden, muted or resized — fullscreen, borderless or windowed is entirely your in-game setting. The only thing the script decides is which monitor, and only if it landed on the wrong one. |
| **Overwolf** | Started immediately on F2, in parallel with Battle.net, so it is ready by the time the game is. |
| **Firestone** | Optional. Its in-game overlay stays visible and untouched at all times; its desktop windows stay out of sight until you ask for them; its notification popup is closed on sight and never painted. If it isn't installed, every Firestone subsystem stays dormant and the rest works normally. |

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
F2  ─┬─  Battle.net opens  →  presses Play  →  minimises
     │                                          ↓
     └─  Firestone starts                   Hearthstone opens and
         (immediately, in parallel)         takes the foreground
```

**Firestone starts before Hearthstone, and that order matters.** Firestone reads the game's memory to drive its overlay, so it goes up first and is in place and waiting as the game comes up. Starting it midway through Hearthstone's initialisation makes it attach to a process that isn't ready — which fails with *"CRITICAL ERROR: Could not read the game's memory"* and leaves you with no overlay for the whole session. `fsLaunchDelayMs` exists to delay it and is `0` for exactly that reason.

The launcher leaves *before* the game arrives. That ordering is deliberate: Hearthstone opens onto a clear screen and takes the foreground on its own, rather than having the launcher tidy itself away over the top of it. Hearthstone itself is never hidden, muted or resized — fullscreen, borderless or windowed is entirely your in-game setting.

Pressing F2 while Hearthstone is already running restarts it cleanly, closing the game and the Blizzard processes first.

**If the game doesn't start.** Pressing Play doesn't always launch anything — there may be a patch to download, or Battle.net may want you to sign in. Rather than sitting minimised while you wait for a game that isn't coming, the launcher restores itself after 25 seconds, tells you on screen, and keeps re-pressing Play in the background. A finished download is picked up automatically; once the game starts, the launcher minimises again. It waits up to 30 minutes, which is enough for a large patch.

A stalled launch is recovered rather than left hanging: the pipeline has a five-minute ceiling, time spent on the Battle.net login screen does not count against it, and a game that appears after the ceiling is still picked up.

### `F3` — Show or hide Firestone

Toggles the Firestone desktop windows (Main and Battlegrounds). They start hidden.

**F3 does nothing until Firestone Main has opened** — no toggle, no sound, no acknowledgement. Before that point there is nothing to show, and pressing it would disarm the concealment for the very window it was armed for, so Main would arrive on screen visible. An early press is silent and costs nothing: it is not queued and not remembered, so the first press after Main opens behaves as the first press.

These windows are **deliberately exempt from the monitor lock**. They are what you read while playing, so they belong wherever you put them — typically a second screen, beside the game rather than over it. Each window's exact position is remembered when it is concealed and restored when it returns, so move one wherever you like and F3 will keep it there.

**Two things F3 never touches.** The in-game overlay is always visible, whatever the lock state. And Firestone's notification popup — the "Your abilities are ready!" window — is not a toggle target at all.

That second one is enforced structurally rather than by rule-following. There are exactly two ways a concealed window gets back on screen — it is *released* (`_FSReleaseSurface`) or it is *shown* (`_FSShowIfNotPopup`) — and both refuse the popup and close it instead. Every path in the script funnels through those two, so no caller, present or future, can put the popup on screen. The popup closer also no longer stops when you press F3; the lock decides whether Firestone's own windows are visible and has no opinion about a notification.

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

There are two layers, and most people only ever need the first.

### `HSBG Config.ini` — the settings file

Sits next to the script. Created automatically on first run with every setting documented inside it as comments, so you never need to open the script or this file to change your mind. Delete it and it comes back with the defaults.

**To edit it: right-click the tray icon → "Open settings".** That route matters — the script runs elevated, so the editor it launches is elevated too. If the file happens to live somewhere only an administrator can write, opening it any other way lets you make changes and then refuses to save them.

| Setting | Default | Effect |
|---|---|---|
| `MonitorLock` | `1` | Put Battle.net, the Update Agent, Hearthstone and the status text on the monitor you started the script from. `0` leaves every window where it opens and moves nothing. No effect on a single monitor. |
| `HotkeyAudio` | `0` | Play a short, deep note when a hotkey fires, so a press is confirmed without looking away from the game. |
| `HotkeyAudioVolume` | `25` | `0`–`100`. Ignored while `HotkeyAudio=0`. |
| `HotkeySoundFile` | *(empty)* | Path to your own PCM `.wav`, played for every hotkey instead of the built-in note. Falls back to the built-in tone if the file is missing. |
| `HotkeyFreqMode` | `singular` | `singular` = every key sounds the same note. `varied` = each key gets its own pitch. |
| `HotkeyFreqSingular` | `110.0` | The pitch in Hz used by every key in `singular` mode. |
| `HotkeyFreqF1`–`F4` | `82.41`, `110.00`, `73.42`, `55.00` | Per-key pitches used in `varied` mode. Blank or `0` falls back to `HotkeyFreqSingular`. |

Changes are read once at start-up, so exit from the tray and start the script again — or use **"Reload settings"** in the tray, which applies these without a restart.

**About the built-in notes.** They are synthesised rather than beeped, because `SoundBeep` produces a square wave that at these frequencies sounds like a fault rather than a note. Each one is built as a plucked, overdriven bass string: five harmonics with the higher partials decaying faster (the falling brightness is what the ear reads as a *pluck*), a valve-style soft clip for weight, a pick attack, and a release taper so the note ends rather than being cut off. The default pitches sit between 55 Hz and 110 Hz — below anything in Hearthstone's own mix, so they cut through without competing with it. They are generated on first use and cached, so switching audio on costs about a second of one start-up and nothing afterwards.

### The script's `CFG` block

Everything else lives in `CFG` at the top of the script, documented in place with its trade-offs. Nothing there needs editing for normal use. The ones worth knowing about:

| Setting | Default | Effect |
|---|---|---|
| `forcefulHoldMs` | `2500` | How long F1 holds the connection block. The single knob controlling skip duration. |
| `f1Target` | `"smart"` | Which connection F1 blocks. `"all"` is a sledgehammer fallback if `"smart"` ever picks wrong. |
| `bnetLauncherMode` | `"visible"` | `"visible"` shows the launcher and minimises it after Play. `"minimized"` never shows it at all. |
| `bnetRevealDwellMs` | `600` | Minimum time the launcher stays on screen before Play may fire. |
| `bnetPostPlayLingerMs` | `1250` | Gap between Play firing and the launcher minimising. |
| `bnetStallRevealMs` | `25000` | How long to wait for the game before assuming an update or sign-in is blocking it. |
| `fsLaunchDelayMs` | `0` | Delay before Firestone is launched. `0` = immediately, before Hearthstone exists, which is the only ordering that lets it attach to the game reliably. Raising it risks the "could not read the game's memory" failure. |
| `fsPopupGraceMs` | `3000` | How long a bare-`Firestone` window may hold that title before it is judged a notification rather than a Main still forming. It is cloaked throughout, so this is time spent invisible. |
| `bnetReadyCeilingMs` | `12000` | How long Play waits for the launcher to look loaded before firing anyway. |
| `fsFollowMonitorLock` | `false` | Whether Firestone's windows are pinned to the launch monitor. |
| `fsHealthCheckMs` | `60000` | How long after launching Firestone to check whether it actually started. |
| `hkStuckModifierRepair` | `true` | Release a modifier key Windows reports as held when it isn't, which would otherwise make every hotkey inert. |
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
STARTUP v9.0 settings in force: MonitorLock=1 HotkeyAudio=1 vol=25 freqMode=singular from C:\...\HSBG Config.ini
BNET-TIMING launcher ready 340ms after its window appeared -- the fixed sequence starts now
BNET-TIMING Play fired 1200ms after ready; minimize scheduled in 1250ms (fixed)
BNET-SEQ minimize confirmed
BNET-STALL no Hearthstone 25000ms after Play -- restoring the launcher
FS-POPUP killed at namechange hwnd=... size=440x570 -- cloaked and closed on sight
FS-HEALTH Firestone is running
HOTKEY stuck modifier(s) Alt held with 10000ms of no physical input -- releasing
```

The `STARTUP` line is the one to check first for anything settings-related: it reports the values **this running script loaded** and the exact file it read them from — which is not always the file you edited.

---

## Troubleshooting

**A settings change seems to have no effect.** Check the `STARTUP` line in the log: it names the build, the settings in force, and the file they came from. If it reports the old value, either the running script is not the file you edited (AutoHotkey does not reload — exit from the tray and start it again), or you edited a different copy than the one it names. The build stamp on the tray tooltip tells you which script is actually running.

**The hotkeys stopped responding.** Almost always a stuck modifier: if Windows believes Alt, Ctrl or a Windows key is still held, every F-key is treated as part of a system chord and passed through. The script detects and repairs this within a couple of seconds and logs `HOTKEY stuck modifier(s)`. If you see that line repeatedly, something else on the machine is disrupting the keyboard hook chain — Overwolf crashing is one cause. Tapping and releasing Alt and Ctrl clears it manually.

**You turned the sound on and heard nothing.** Right-click the tray icon → **"Test hotkey sound"**. It reports on screen whether the script actually read `HotkeyAudio=1`, names the config file it read, and plays the note. If you set `HotkeySoundFile`, check the path points at a real PCM `.wav` — the script falls back to the built-in tone when it doesn't, which sounds like the setting being ignored.

**You don't have Firestone.** Nothing to do. The script detects the missing install at start-up, logs `STARTUP no Overwolf/Firestone install detected`, and leaves every Firestone subsystem dormant. F1, F2 and F4 work normally; F3 has nothing to toggle.

**A Firestone popup appeared anyway.** Check the log for `FS-POPUP killed` — if the line is there, it was closed and you saw it for the few milliseconds before the close landed. `FS-POPUP NOT killing` means the opposite and is deliberate: the popup and Firestone Main are indistinguishable by title and size (Main is titled just `Firestone` while it loads, at the same size), so nothing is ever closed unless a *separate* window titled `Firestone - Main` also exists at that moment. That structural check is the only thing standing between the fast kill and closing your Firestone, and it is applied in the one function every close path goes through.

If neither line appears, look for `FS-VISIBLE`, which records any Firestone window left visible with its title, size and styles — the evidence needed to identify a window shape the matcher doesn't know about yet.

**Clicks on Hearthstone do nothing — but work again after moving the cursor to another monitor and back.** That specific pattern is not an overlapping window (moving the cursor would not fix one). It is AutoHotkey's `#HotIf` mouse context: the expression guarding F1's click shield is evaluated by the input hook on *every click*, with a short deadline, and an expression that is too slow gets abandoned with the previous result reused. It used to enumerate every Hearthstone window and read each one's class and rectangle, per click. It is now one boolean and one process-ID comparison, and it cannot run at all unless an F1 firewall block is actually in place.

**Clicks on Hearthstone do nothing (general).** Right-click the tray icon → **"What is under my cursor?"**, then hold the cursor over the dead spot. It names the window that will receive the click, whether it is cloaked, whether it is topmost, and whether it has focus — which separates an invisible window over the game from the game not being foreground from the script's own shield. The same detail goes to the log as `CURSOR-PROBE`.

**Clicks blocked by a concealed window.** A DWM-cloaked window is invisible but still hit-tested, so anything the script conceals without also moving it off-screen sits over the game as an invisible sheet of glass. Every concealment path now moves the window off the virtual desktop rather than only cloaking it, including a notification popup waiting to be closed. If this recurs, check the log for `FS-POPUP cloaked and moved off-screen` — that line means the mechanism ran.

**Firestone's window comes back blank.** Check the log for `FS-PAINT`. If it reports the window never proved it painted, try `fsMainColdPolicy := "cloak"` instead of `"park"` — concealment behaves differently across Overwolf builds.

**The launcher does not minimise.** The log traces the whole sequence: revealed → armed → Play fired → minimize confirmed. Whichever line is missing identifies the stage that stalled. `BNET-SEQ minimize did NOT take` means the client is refusing or immediately restoring itself.

**A window is missing after a crash or reload.** Restart the script. It repairs stranded windows at start-up — anything left outside the virtual desktop, left cloaked, or left transparent by an earlier instance is recovered automatically.

**F1 does not skip.** Check the log line for the press: it records whether a game connection was identified at all. If none was found, set `f1Target := "all"`.

**F1 makes Battle.net pop up, or disconnects it.** Fixed: the firewall rule is scoped to Hearthstone's executable, so it no longer cuts the launcher's connection. If you see `F1 WARNING: Hearthstone's executable path is unknown`, the rule could not be scoped for that press and fell back to the old machine-wide behaviour.

**Changes to the script appear to have no effect.** AutoHotkey does not hot-reload. The previously launched instance keeps running until you exit it from the tray and start the new one. The build stamp on the tray tooltip confirms which one is live.

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
