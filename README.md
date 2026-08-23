# HSBG — Hearthstone Battlegrounds Session Manager

**Skip combat animations with one key. Launch your whole session with another.**

A single-file AutoHotkey v2 tool for Hearthstone Battlegrounds. Four keys, nothing to configure before you start besides optional feature with on/off switches in the included config file. Obviously Requires AutoHotKey V2.

| Key | What it does |
|:---:|---|
| **F1** | **Skip the combat animation.** The headline feature. Jump straight to the result of a fight instead of watching it play out. Nothing is lost — the match keeps resolving on Blizzard's servers and you rejoin at the outcome. |
| **F2** | **Start the session.** Battle.net opens, presses Play, and tidies itself away. Hearthstone opens and takes the screen. Firestone comes up with it. One key, from nothing running to a loaded game. |
| **F3** | **Show or hide Firestone's windows.** They stay out of your way until you want them. The in-game overlay is never touched. |
| **F4** | **Shut it all down.** Closes the game, Battle.net and Overwolf, puts back everything the script changed, and exits. |

### Why you'd want it

- **Combat skip.** Battlegrounds spends a large share of every game playing out fights you cannot influence. F1 gives that time back, one press at a time.
- **One-key launch.** No clicking through a launcher, waiting, then remembering to start your tracker.
- **Windows where you want them.** Everything opens on the monitor you started the script from, and the clutter you never asked for — Battle.net's splash and login shells, Firestone's nag popups — simply never appears.
- **Nothing to set up.** Sensible defaults, a settings file that writes itself, and a tray menu for the two things worth changing.

### Quick start

1. Install [AutoHotkey v2.0](https://www.autohotkey.com/). (v1 will not run this.)
2. **Start the script on the monitor you want to play on** — that is how it knows where to put things.
3. Accept the UAC prompt, then press **F2**.

That is the whole of it. Everything below is detail for when you want it.

**Requirements** · Windows 10/11 · AutoHotkey v2.0 · Administrator rights (for F1's firewall rule and for pausing the Windows Search indexer) · Firestone is **optional** — without it, everything else works normally.

### What's on out of the box

Two things are **on by default**, and both can be switched off in `HSBG Config.ini` — tray icon → *Open settings*. They are the only on/off switches in the file.

| Setting | What it does while it's on | Off |
|---|---|---|
| **`MonitorLock`** | Battle.net, the Blizzard Update Agent, Hearthstone and the on-screen status text all open on the monitor you started the script from. Start it on the screen you want to play on and the rest follows. Firestone's own windows are deliberately exempt, so they stay wherever you put them — usually a second screen. | `MonitorLock=0` — every window opens wherever Windows and the applications decide, and the script never moves anything. Makes no difference on a single monitor. |
| **`HotkeyAudio`** | A short, deep guitar note plays each time a hotkey fires, so you know the press registered without looking away from the game. | `HotkeyAudio=0` — silent. |

**Everything else in the file is sound tuning** — that is the whole of it:

- **`HotkeyAudioVolume`** — `0`–`100`, default `25`.
- **`HotkeySoundFile`** — path to your own PCM `.wav`, played for every hotkey in place of the built-in note. Empty by default; a missing file falls back to the built-in tone.
- **`HotkeyFreqMode`** — whether every key sounds the same note, or each key gets its own. This is a **word, not a number**: the file ships with the line `HotkeyFreqMode=singular`, and you change that single word so it reads `HotkeyFreqMode=varied`. Nothing else has to move.
  - `singular` — all four keys play **`HotkeyFreqSingular`**, `110.0` Hz by default. The `HotkeyFreqF1`–`F4` lines are sitting right there in the file but are ignored.
  - `varied` — each key plays its own line instead: **`HotkeyFreqF1`–`F4`**, `82.41`, `110.00`, `73.42` and `55.00` Hz by default, so F1 and F4 are two different presses to your ear. Leave one blank or set it to `0` and that key falls back to `HotkeyFreqSingular`.
  - Pitches are accepted between **20 and 2000 Hz**; anything outside that, or not a number, is ignored in favour of the default and noted in the log. Any spelling other than `singular` or `varied` is read as `singular`.

Every one of these is also documented in comments inside the file itself, and again under [Settings](#settings).

### The tray menu

HSBG has no window. It runs as an icon in the **system tray** — the small cluster at the right-hand end of the taskbar, next to the clock. Windows hides new tray icons by default, so click the **`^`** arrow there to reveal it: it is AutoHotkey's green **H**, and hovering it reads *Battle Grounds v9.0 — running*. Drag it down onto the taskbar to keep it permanently visible.

**Right-click** that icon for the menu:

| Menu item | What it does |
|---|---|
| **Open settings (HSBG Config.ini)** | Opens the settings file in Notepad. Use this rather than finding the file yourself — the script runs as administrator, so the editor it opens can actually save. |
| **Reload settings** | Re-reads the file and applies your change straight away — everything in `HSBG Config.ini` is covered, so no restart. *Settings reloaded* flashes on screen when it lands. |
| **Test hotkey sound** | Plays the note, and says on screen whether the script really read `HotkeyAudio=1` and which file it read it from. |
| **What is under my cursor?**<br>**Log Firestone's windows** | Diagnostics for when clicks or windows misbehave — see [Troubleshooting](#troubleshooting). |
| **Exit** | Stops HSBG and puts back what it changed. It sits below the separator, among AutoHotkey's own items. |

So changing a setting is: right-click the tray icon → *Open settings* → edit the line → save and close Notepad → right-click again → *Reload settings*. That is the whole procedure.

---

## Contents

- [What's on out of the box](#whats-on-out-of-the-box)
- [The tray menu](#the-tray-menu)
- [Hotkeys in detail](#hotkeys-in-detail)
- [What it does with each application](#what-it-does-with-each-application)
- [Settings](#settings)
- [Diagnostics](#diagnostics)
- [Troubleshooting](#troubleshooting)
- [How it works](#how-it-works)
- [Advanced tuning](#advanced-tuning)
- [Reading the source](#reading-the-source)
- [What it touches on your system](#what-it-touches-on-your-system)

---

## Installation

1. Install [AutoHotkey v2.0](https://www.autohotkey.com/).
2. Put `HSBG Script Final.ahk` anywhere convenient. It creates two files beside itself on first run: `HSBG Config.ini` (settings) and `HSBG.log` (diagnostics).
3. **Start it on the monitor you want to play on.** The script takes the monitor it was launched from as your choice, and everything it places afterwards follows it.
4. Accept the UAC prompt.

The script elevates itself and hands the launch monitor to the elevated instance, so the choice survives.

---

## Hotkeys in detail

### `F1` — Combat-animation skip

Skips the Battlegrounds combat animation by forcing the client to reconnect past it.

The script identifies Hearthstone's live game-server connection and blocks that one address, in both directions, for a fixed interval — then releases it. The match continues resolving on Blizzard's servers the whole time, so nothing is lost: you rejoin at the result.

Blizzard's login and services connection (TCP 1119) is deliberately left alive, so there is no re-authentication and no risk to your seat in the lobby. Hearthstone's audio is muted for the duration and clicks on the game window are swallowed, so the skip is silent and cannot be disturbed by a stray click.

Default hold: 2.5 seconds, then clicks stay swallowed for a further 1.5 seconds while the client reconnects — lifting the block is the *start* of the reconnect, not the end of the skip, and a click landing in that window goes into a board you cannot see yet. Cooldown: 0.75 seconds between presses.

### `F2` — Launch or restart

Starts a full session, or restarts one already in progress.

```
F2  ─┬─  Battle.net opens  →  presses Play  →  minimises
     │                                           ↓
     └─  Firestone starts                    Hearthstone opens and
         (immediately, in parallel)          takes the foreground
```

**Firestone starts before Hearthstone, and that order matters.** Firestone reads the game's memory to drive its overlay, so it goes up first and is in place and waiting as the game arrives. Starting it midway through Hearthstone's initialisation makes it attach to a process that isn't ready — which fails with *"CRITICAL ERROR: Could not read the game's memory"* and leaves you with no overlay for the whole session. The `fsLaunchDelayMs` setting exists to delay it and is `0` for exactly that reason.

**The launcher leaves before the game arrives.** Hearthstone opens onto a clear screen and takes the foreground on its own, rather than having the launcher tidy itself away over the top of it. Hearthstone itself is never hidden, muted or resized — fullscreen, borderless or windowed stays entirely your in-game setting.

Pressing F2 while Hearthstone is already running restarts it cleanly, closing the game and the Blizzard processes first.

**If the game doesn't start.** Pressing Play does not always launch anything — there may be a patch to download, or Battle.net may want you to sign in. Rather than sitting minimised waiting for a game that isn't coming, the launcher restores itself after 25 seconds, says so on screen, and keeps re-pressing Play in the background. A finished download is picked up automatically and the launcher minimises again. It waits up to 30 minutes, which covers a large patch.

A stalled launch is recovered rather than left hanging: the pipeline has a five-minute ceiling, time spent on the Battle.net login screen does not count against it, and a game that appears after the ceiling is still picked up.

### `F3` — Show or hide Firestone

Toggles the Firestone desktop windows (Main and Battlegrounds). They start hidden.

**F3 does nothing until Firestone Main has opened** — no toggle, no sound, no acknowledgement. Before that point there is nothing to show, and pressing it would disarm the concealment for the very window it was armed for, so Main would arrive on screen visible. An early press is silent and costs nothing: it is not queued and not remembered, so the first press after Main opens behaves as the first press.

These windows are **deliberately exempt from the monitor lock.** They are what you read while playing, so they belong wherever you put them — usually a second screen, beside the game rather than over it. Each window's exact position is remembered when it is concealed and restored when it comes back, so move one wherever you like and F3 will keep it there.

**Two things F3 never touches.** The in-game overlay is always visible, whatever the lock state. And Firestone's notification popup — the "Your abilities are ready!" window — is not a toggle target at all; it is closed on sight and never painted.

### `F4` — Shutdown

Closes Overwolf, Battle.net and Hearthstone, restores everything the script changed, and exits.

Also available as a held-key fallback, so it still works when a fullscreen game is swallowing window messages.

> `Alt+F4`, `Ctrl+F4` and `Win+F4` are passed straight through to Windows. Only an unmodified F-key triggers HSBG.

---

## What it does with each application

Four applications are involved in a Battlegrounds session. Left alone they produce a cluttered, slow, multi-step start-up with windows scattered across monitors.

| Application | What HSBG does with it |
|---|---|
| **Battle.net** | Opens on your chosen monitor, presses Play, and minimises *before* the game window arrives. Its service surfaces — boot splash, auto-login shell, maintenance alerts, Update Agent — never appear. If Play cannot start the game because an update or sign-in is pending, the launcher comes back and says so. |
| **Hearthstone** | Launched, then left alone. Never hidden, muted or resized. The only thing the script decides is which monitor, and only if the game landed on the wrong one. |
| **Overwolf** | Started immediately on F2, in parallel with Battle.net, so it is ready by the time the game is. |
| **Firestone** | Optional. Its in-game overlay stays visible and untouched at all times; its desktop windows stay out of sight until you ask for them; its notification popup is closed on sight. If Firestone is not installed, every Firestone subsystem stays dormant and the rest works normally. |

---

## Settings

`HSBG Config.ini` sits next to the script. It is created on first run with every setting documented inside it as comments, so you never need to open the script — or this page — to change your mind. Delete it and it comes back with the defaults.

**To edit it: right-click the tray icon → "Open settings".** ([Where the tray icon is.](#the-tray-menu)) That route matters. The script runs elevated, so the editor it opens is elevated too; if the file happens to live somewhere only an administrator can write, opening it any other way lets you make changes and then refuses to save them.

| Setting | Default | Effect |
|---|---|---|
| `MonitorLock` | `1` | Put Battle.net, the Update Agent, Hearthstone and the status text on the monitor you started the script from. `0` leaves every window where it opens and moves nothing. No effect on a single monitor. |
| `HotkeyAudio` | `1` | Play a short, deep note when a hotkey fires, so a press is confirmed without looking away from the game. `0` for silence. |
| `HotkeyAudioVolume` | `25` | `0`–`100`. Ignored while `HotkeyAudio=0`. |
| `HotkeySoundFile` | *(empty)* | Path to your own PCM `.wav`, played for every hotkey instead of the built-in note. Falls back to the built-in tone if the file is missing. |
| `HotkeyFreqMode` | `singular` | A word, not a number. `singular` — every key sounds the same note. `varied` — each key gets its own pitch. Any other value is read as `singular`. |
| `HotkeyFreqSingular` | `110.0` | Pitch in Hz used by every key in `singular` mode, and the fallback for an unset key in `varied` mode. |
| `HotkeyFreqF1`–`F4` | `82.41`, `110.00`, `73.42`, `55.00` | Per-key pitches used in `varied` mode; ignored in `singular`. Blank or `0` falls back to `HotkeyFreqSingular`. |

Pitches must be between `20` and `2000` Hz. A value outside that range, or one that isn't a number, is discarded in favour of the default and logged as `CONFIG <key>=<value> is not a number` or `is out of range`.

Settings are read at start-up. Use **"Reload settings"** in the [tray menu](#the-tray-menu) to apply a change without restarting.

<details>
<summary><b>About the built-in notes</b></summary>

They are synthesised rather than beeped, because `SoundBeep` produces a square wave that at these frequencies sounds like a fault rather than a note. Each one is built as a plucked, overdriven bass string: five harmonics with the higher partials decaying faster (that falling brightness is what the ear reads as a *pluck*), a valve-style soft clip for weight, a pick attack, and a release taper so the note ends rather than being cut off. The default pitches sit between 55 Hz and 110 Hz — below anything in Hearthstone's own mix, so they cut through without competing with it. They are generated on first use and cached, so they cost about a second on one start-up and nothing afterwards.

</details>

---

## Diagnostics

The script writes one line per significant event to:

```
HSBG.log        ← in the same folder as the script
```

Not `%TEMP%`, not `%APPDATA%` — beside the script, where you can find it. (If the script is somewhere it cannot write to, such as Program Files, the log falls back to `%APPDATA%\HSBG\` and the start-up line says where it went.) It is capped at 2 MB, with the previous file kept as `HSBG.log.1`.

A single launch is usually enough to explain any unexpected behaviour. The lines that matter most:

```
STARTUP v9.0 settings in force: MonitorLock=1 HotkeyAudio=1 vol=25 freqMode=singular from C:\...\HSBG Config.ini
BNET-TIMING launcher ready 340ms after its window appeared -- the fixed sequence starts now
BNET-TIMING Play fired 1200ms after ready; minimize scheduled in 1000ms (fixed)
BNET-SEQ minimize confirmed
BNET-STALL no Hearthstone 25000ms after Play -- restoring the launcher
FS-POPUP killed at namechange hwnd=... size=440x570 -- cloaked and closed on sight
FS-HEALTH Firestone is running
F1 method=... target=... block=... hold=1500
HOTKEY stuck modifier(s) Alt held with 10000ms of no physical input -- releasing
```

The `STARTUP` line is the one to check first for anything settings-related: it reports the values **this running script loaded**, and the exact file it read them from — which is not always the file you edited.

---

## Troubleshooting

**A settings change seems to have no effect.**
Check the `STARTUP` line in the log. It names the build, the settings in force, and the file they came from. If it reports the old value, either the running script is not the file you edited (AutoHotkey does not hot-reload — exit from the tray and start it again), or you edited a different copy than the one it names. The build stamp on the tray tooltip tells you which script is actually running.

**The hotkeys stopped responding.**
Almost always a stuck modifier: if Windows believes Alt, Ctrl or a Windows key is still held, every F-key is treated as part of a system chord and passed through. The script detects and repairs this within a couple of seconds and logs `HOTKEY stuck modifier(s)`. If you see that line repeatedly, something else on the machine is disrupting the keyboard hook chain — Overwolf crashing is one cause. Tapping and releasing Alt and Ctrl clears it by hand.

**F1 does not skip.**
Check the log line for the press: it records whether a game connection was identified at all. If none was found, set `f1Target := "all"` in the script's `CFG` block.

**F1 makes Battle.net pop up, or disconnects it.**
Fixed — the firewall rule is scoped to Hearthstone's executable, so it no longer touches the launcher's connection. If you see `F1 WARNING: Hearthstone's executable path is unknown`, the rule could not be scoped for that one press and fell back to the old machine-wide behaviour.

**Clicks on Hearthstone do nothing — but work again after moving the cursor to another monitor and back.**
That specific pattern is not an overlapping window; moving the cursor would not fix one. It is AutoHotkey's `#HotIf` mouse context, which is evaluated by the input hook on *every click* with a short deadline — and an expression that is too slow gets abandoned, with the previous result reused. It used to enumerate every Hearthstone window and read each one's class and rectangle, per click. It is now one boolean and one process-ID comparison, and it cannot run at all unless an F1 block is actually in place.

**Clicks on Hearthstone do nothing (general).**
Tray icon → **"What is under my cursor?"**, then hold the cursor over the dead spot. It names the window that will receive the click, whether it is cloaked, whether it is topmost, and whether it has focus — which separates an invisible window over the game from the game not being foreground from the script's own click shield. The same detail goes to the log as `CURSOR-PROBE`.

**The hotkeys are silent.**
The note is on by default, so hearing nothing means either the setting was turned off or the script did not read the file you think it did. Tray icon → **"Test hotkey sound"**: it reports on screen whether the script actually read `HotkeyAudio=1`, names the config file it read, and plays the note. If you set `HotkeySoundFile`, check the path points at a real PCM `.wav` — the script falls back to the built-in tone when it does not, which sounds exactly like the setting being ignored.

**You don't have Firestone.**
Nothing to do. The script detects the missing install at start-up, logs `STARTUP no Overwolf/Firestone install detected`, and leaves every Firestone subsystem dormant. F1, F2 and F4 work normally; F3 has nothing to toggle.

**A Firestone popup appeared anyway.**
Check the log for `FS-POPUP killed` — if the line is there, it was closed and you saw it for the few milliseconds before the close landed. `FS-POPUP NOT killing` means the opposite, and is deliberate: the popup and Firestone Main are indistinguishable by title and size (Main is titled just `Firestone` while it loads, at the same size), so nothing is closed unless a *separate* window titled `Firestone - Main` also exists at that moment. That structural check is the only thing standing between the fast kill and closing your Firestone. If neither line appears, look for `FS-VISIBLE`, which records any Firestone window left visible along with its title, size and styles.

**Firestone's window comes back blank.**
Check the log for `FS-PAINT`. If it reports the window never proved it painted, try `fsMainColdPolicy := "cloak"` instead of `"park"` — concealment behaves differently across Overwolf builds.

**The launcher does not minimise.**
The log traces the whole sequence: revealed → armed → Play fired → minimize confirmed. Whichever line is missing identifies the stage that stalled. `BNET-SEQ minimize did NOT take` means the client is refusing, or immediately restoring itself.

**A window is missing after a crash or reload.**
Restart the script. It repairs stranded windows at start-up — anything left outside the virtual desktop, left cloaked, or left transparent by an earlier instance is recovered automatically.

**Changes to the script appear to have no effect.**
AutoHotkey does not hot-reload. The previously launched instance keeps running until you exit it from the tray and start the new one. The build stamp on the tray tooltip confirms which one is live.

---

## How it works

Three principles account for most of the design. They are what make the window handling reliable rather than lucky, and each exists because the obvious approach fails in a specific way.

**1 · One owner per window per phase.** Exactly one subsystem decides what happens to a given window at a given time; where two could disagree, they are funnelled through a single shared primitive instead. Contended windows are the root of nearly every flicker and race this kind of automation suffers from. Two timers concealing the same window from different starting points do not average out — they fight, and which one wins varies by machine and by run.

**2 · Ask the window, not the ledger.** The script keeps bookkeeping of what it has concealed, to avoid redundant work, but that bookkeeping is never treated as evidence about a window's actual state. The owning application is editing that state concurrently: a cloak can be silently reset by an ordinary window operation, and a window can be repositioned back on screen a millisecond after being moved off it. Anywhere the answer has to be correct, the code queries the OS rather than consulting its own notes.

**3 · Move, don't hide.** Chromium-based windows — Firestone, and the Battle.net client — treat `ShowWindow(SW_HIDE)` as *you no longer exist* and tear down their compositor accordingly. A window hidden before it has ever painted may never paint again: you get a correctly sized, correctly framed, completely blank rectangle. So windows that must come back are **moved off the virtual desktop** instead. A move is synchronous and atomic; the window stays alive and fully rendered, it simply is not over a monitor. Combined with a DWM cloak and taskbar-button removal, the result is indistinguishable from hidden — no pixels, no taskbar entry, no Alt-Tab entry, no thumbnail — while the application stays perfectly healthy.

---

## Advanced tuning

Everything not in `HSBG Config.ini` lives in the `CFG` block at the top of the script, documented in place with its trade-offs. Nothing there needs editing for normal use. The ones worth knowing about:

| Setting | Default | Effect |
|---|---|---|
| `forcefulHoldMs` | `2500` | How long F1 holds the connection block. **Do not shorten this to make F1 feel faster.** A firewall block drops packets silently, so the client only notices when its own timeout expires; mid-combat it shrugs off a short outage and no skip happens at all. A press that fails costs more time than the longer hold does. |
| `f1PostReleaseShieldMs` | `1500` | How long clicks stay swallowed *after* the block lifts, covering the reconnect. Raise if clicks still land early; `0` ends the shield with the block. |
| `loginWaitCeilingMs` | `1800000` | How long the launch may wait for you to sign in to Battle.net before giving up and releasing F1/F2. |
| `f1Target` | `"smart"` | Which connection F1 blocks. `"all"` is a sledgehammer fallback if `"smart"` ever picks wrong. |
| `bnetLauncherMode` | `"visible"` | `"visible"` shows the launcher and minimises it after Play. `"minimized"` never shows it at all. |
| `bnetRevealDwellMs` | `500` | Minimum time the launcher stays on screen before Play may fire. |
| `bnetPostPlayLingerMs` | `1000` | Gap between Play firing and the launcher minimising. |
| `bnetStallRevealMs` | `25000` | How long to wait for the game before assuming an update or sign-in is blocking it. |
| `bnetReadyCeilingMs` | `12000` | How long Play waits for the launcher to look loaded before firing anyway. |
| `fsLaunchDelayMs` | `0` | Delay before Firestone is launched. `0` — immediately, before Hearthstone exists, which is the only ordering that lets it attach to the game reliably. Raising it risks the "could not read the game's memory" failure. |
| `fsPopupGraceMs` | `3000` | How long a bare-`Firestone` window may hold that title before it is judged a notification rather than a Main still forming. It is concealed throughout, so this is time spent invisible. |
| `fsBurstMs` / `fsCoastMs` / `fsSettledMs` | `10` / `50` / `250` | The three cadences of the Firestone window sweep: while windows are being created, while the launch settles, and once you are just playing. |
| `fsNudgeCeilingMs` | `10000` | The longest a run of new Overwolf windows may keep the sweep above its settled rate. Guards against a steady trickle of window creations pinning it there for a whole session. |
| `hsGuardFastMs` / `hsGuardIdleMs` | `50` / `1000` | How often Hearthstone's position is checked, while the game is still deciding where to open, and afterwards. |
| `fsFollowMonitorLock` | `false` | Whether Firestone's windows are pinned to the launch monitor. |
| `fsHealthCheckMs` | `60000` | How long after launching Firestone to check whether it actually started. |
| `hkStuckModifierRepair` | `true` | Release a modifier key Windows reports as held when it isn't, which would otherwise make every hotkey inert. |
| `scriptAboveNormalPriority` | `false` | Raise the script's own priority for steadier timing. Off by default — it competes with the game for CPU. |
| `pauseWSearchDuringHS` | `true` | Stop the Windows Search indexer while Hearthstone runs. |
| `setHSGpuPreference` | `true` | Register Hearthstone as high-performance GPU (hybrid graphics systems). |

---

## Reading the source

One self-contained file: roughly 10,900 lines, of which about 4,200 are comments.

**The comments are written to be sufficient to rebuild the script from scratch.** Each subsystem states the constraint it exists to satisfy rather than merely what it does, because in nearly every case the obvious implementation is the one that fails — and the comment explains which failure. The file header contains a `REBUILDING THIS SCRIPT` section listing the load-bearing decisions in the order you will meet them.

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

**Verifying a change.** A cheap and strict check: strip every comment and blank line from the file before and after your edit, then diff the result. A documentation-only change should produce no difference at all.

```bash
grep -v '^\s*;' "HSBG Script Final.ahk" | sed 's/\s\+;.*$//' | grep -v '^\s*$'
```

---

## What it touches on your system

- **Never** modifies Hearthstone's process priority, game files, or memory.
- **One firewall rule**, scoped to Hearthstone's executable and to a single remote address, created and deleted per F1 press. Rules are swept at start-up and at exit, and a failsafe timer removes the block even if the F1 handler dies mid-press — an interrupted press cannot leave a connection blocked.
- **The Windows Search indexer** is stopped while Hearthstone runs and restarted on exit.
- **Two registry values are set and left**: Hearthstone's per-application GPU preference (high-performance), and Unity's saved display index when the monitor lock has to correct it — the latter only when the value actually differs from what is already stored. Both are settings for Hearthstone rather than for this script, so they persist deliberately; nothing else in the registry is touched.
- **Window positions and visibility** for Battle.net, Overwolf and Firestone. Every concealment has a matching cleanup that works from an empty ledger, so a crash or a forced reload cannot leave a window unreachable.
- **Two files**, both beside the script: `HSBG Config.ini` and `HSBG.log`.
