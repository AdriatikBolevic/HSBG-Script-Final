# HSBG — Hearthstone Battlegrounds Session Manager

**Skip combat animations with one key. Launch your whole session with another.**

A single-file AutoHotkey v2 tool for Hearthstone Battlegrounds. Four keys, nothing to configure before you start.

| Key | What it does |
|:---:|---|
| **F1** | **Skip the combat animation.** The headline feature. Jump straight to the result of a fight instead of watching it play out. Nothing is lost — the match keeps resolving on Blizzard's servers and you rejoin at the outcome. |
| **F2** | **Start the session.** Battle.net opens, presses Play, and tidies itself away. Hearthstone opens and takes the screen. Your overlay comes up with it. One key, from nothing running to a loaded game. |
| **F3** | **Show or hide your overlay.** Firestone's desktop windows, or the HSReplay tracker's on-screen overlay — whichever you're using this session. |
| **F4** | **Shut it all down.** Closes the game, Battle.net, Overwolf and the tracker, puts back everything the script changed, and exits. |

### Why you'd want it

- **Combat skip.** Battlegrounds spends a large share of every game playing out fights you cannot influence. F1 gives that time back, one press at a time.
- **One-key launch.** No clicking through a launcher, waiting, then remembering to start your tracker.
- **Your tracker actually works.** HSBG runs as administrator, which means the Hearthstone it launches does too — and a tracker started any other way can't read an elevated game. That's the *"restart Hearthstone / run as administrator"* message. HSBG starts the tracker itself, at a matching level, and the message never appears.
- **Windows where you want them.** Everything opens on the monitor you started the script from, and the clutter you never asked for — Battle.net's splash and login shells, Firestone's nag popups — simply never appears.
- **Nothing to set up.** Sensible defaults, a settings file that writes itself, and a tray menu for the things worth changing.

### Quick start

1. Install [AutoHotkey v2.0](https://www.autohotkey.com/). (v1 will not run this.)
2. **Start the script on the monitor you want to play on** — that is how it knows where to put things.
3. Accept the UAC prompt, then press **F2**.

That is the whole of it. Everything below is detail for when you want it.

**Requirements** · Windows 10/11 · AutoHotkey v2.0 · Administrator rights (for F1's firewall rule and for pausing the Windows Search indexer) · An overlay is **optional** — HSBG supports [Firestone](https://www.firestoneapp.com/) and the [HSReplay deck tracker](https://hsreplay.net/downloads/), uses one at a time, and works normally with neither.

### What's on out of the box

Three things are **on by default**, and all three can be switched off in `HSBG Config.ini` — tray icon → *Open settings*. They are the only on/off switches in the file.

| Setting | What it does while it's on | Off |
|---|---|---|
| **`MonitorLock`** | Battle.net, the Blizzard Update Agent, Hearthstone and the on-screen status text all open on the monitor you started the script from. Start it on the screen you want to play on and the rest follows. Firestone's own windows are deliberately exempt, so they stay wherever you put them — usually a second screen. | `MonitorLock=0` — every window opens wherever Windows and the applications decide, and the script never moves anything. Makes no difference on a single monitor. |
| **`HotkeyAudio`** | A short, deep guitar note plays each time a hotkey fires, so you know the press registered without looking away from the game. | `HotkeyAudio=0` — silent. |
| **`UpdateCheck`** | Once per run, about ten seconds after start-up, HSBG asks GitHub whether a newer release exists. If one does it says so briefly and offers to download it — see [Updates](#updates). | `UpdateCheck=0` — the script never contacts the network for any reason. |

**The rest of the file is sound tuning and your overlay choice.** The sound settings:

- **`HotkeyAudioVolume`** — `0`–`100`, default `25`.
- **`HotkeySoundFile`** — path to your own PCM `.wav`, played for every hotkey in place of the built-in note. Empty by default; a missing file falls back to the built-in tone.
- **`HotkeyFreqMode`** — whether every key sounds the same note, or each key gets its own. This is a **word, not a number**: the file ships with the line `HotkeyFreqMode=singular`, and you change that single word so it reads `HotkeyFreqMode=varied`. Nothing else has to move.
  - `singular` — all four keys play **`HotkeyFreqSingular`**, `110.0` Hz by default. The `HotkeyFreqF1`–`F4` lines are sitting right there in the file but are ignored.
  - `varied` — each key plays its own line instead: **`HotkeyFreqF1`–`F4`**, `82.41`, `110.00`, `73.42` and `55.00` Hz by default, so F1 and F4 are two different presses to your ear. Leave one blank or set it to `0` and that key falls back to `HotkeyFreqSingular`.
  - Pitches are accepted between **20 and 2000 Hz**; anything outside that, or not a number, is ignored in favour of the default and noted in the log. Any spelling other than `singular` or `varied` is read as `singular`.

And the overlay settings — **`Tracker`** and **`HDTPath`** — which decide which overlay this session uses and where to find it. They are covered under [Only one overlay at a time](#only-one-overlay-at-a-time) and [Settings](#settings).

Every one of these is also documented in comments inside the file itself.

### The tray menu

HSBG has no window. It runs as an icon in the **system tray** — the small cluster at the right-hand end of the taskbar, next to the clock. Windows hides new tray icons by default, so click the **`^`** arrow there to reveal it: it is AutoHotkey's green **H**, and hovering it reads *Battle Grounds v4.0.0 — running*. Drag it down onto the taskbar to keep it permanently visible.

**Right-click** that icon for the menu:

| Menu item | What it does |
|---|---|
| **Open settings (HSBG Config.ini)** | Opens the settings file in Notepad. Use this rather than finding the file yourself — the script runs as administrator, so the editor it opens can actually save. |
| **Overlay for this session…** | Re-opens the overlay picker and applies the answer immediately, without restarting. Switching away from Firestone hands its windows back; switching away from HSReplay un-hides a tracker F3 had hidden. Neither overlay is launched or closed by this — the next F2 does that. Says so on screen if only one overlay is installed and there is nothing to choose. |
| **Reload settings** | Re-reads the file and applies what can be applied without a restart — the monitor lock starts and stops cleanly, and the hotkey tones rebuild. *Settings reloaded* flashes on screen when it lands. |
| **Test hotkey sound** | Plays the note, and says on screen whether the script really read `HotkeyAudio=1` and which file it read it from. |
| **What is under my cursor?**<br>**Log Firestone's windows** | Diagnostics for when clicks or windows misbehave — see [Troubleshooting](#troubleshooting). |
| **Get v5.0.0 …** | Appears only when a newer release exists, named for the version it found. Downloads it beside the current script — see [Updates](#updates). |
| **Exit** | Stops HSBG and puts back what it changed. It sits below the separator, among AutoHotkey's own items. |

So changing a setting is: right-click the tray icon → *Open settings* → edit the line → save and close Notepad → right-click again → *Reload settings*. That is the whole procedure.

> **Reload settings is honest about its limits.** The monitor lock and the hotkey tones re-apply live. Everything else in the file was consumed during start-up and is not revisited, so for those, exit from the tray and start the script again.

---

## Contents

- [What's on out of the box](#whats-on-out-of-the-box)
- [The tray menu](#the-tray-menu)
- [Hotkeys in detail](#hotkeys-in-detail)
- [What it does with each application](#what-it-does-with-each-application)
- [Settings](#settings)
- [Updates](#updates)
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

Blizzard's login and services connection (TCP 1119) is deliberately left alive, so there is no re-authentication and no risk to your seat in the lobby. Clicks on the game window are swallowed for the duration, so a stray click cannot disturb the skip.

**Finding the connection: two paths.** The Windows TCP table answers the common case in under a millisecond, and that is what a press normally uses. It cannot report connection creation times or interpret IPv6, so when the answer would be incomplete — two or more connections on the services port, or any IPv6 connection on the process — the press falls through to a fuller PowerShell enumeration that costs most of a second but sees everything. The log records which path each press took, as `F1 lookup=fast` or `F1 lookup=powershell`.

**A press that does nothing says why.** Four refusals, each with its own message, so a key that appears to have done nothing is never a mystery:

| On screen | Means |
|---|---|
| `F1 cooling down…` | Inside the 0.75 s cooldown from the previous press. |
| `No game connection found` | Neither path identified a game connection — see [Troubleshooting](#troubleshooting). |
| `F1 ignored — launch in progress` | An F2 pipeline is genuinely still running. If the flag is stale, F1 clears it and proceeds. |
| `HS not running` | There is no Hearthstone to skip in. |

Default hold: 2.5 seconds, then clicks stay swallowed for a further 1.5 seconds while the client reconnects — lifting the block is the *start* of the reconnect, not the end of the skip, and a click landing in that window goes into a board you cannot see yet. Cooldown: 0.75 seconds between presses.

The Battle.net launcher is held down for the hold and about six seconds after it, which is the window in which a disconnect would otherwise pop it back onto your screen. A failsafe timer removes the block even if the press dies part-way through, and it is re-armed rather than cancelled after a successful release — so an interrupted press cannot leave Hearthstone firewalled off its own game server.

Hearthstone's audio is left alone throughout. The game is never concealed during a skip or a launch, so there is no moment where you would be hearing a game you cannot see.

### `F2` — Launch or restart

Starts a full session, or restarts one already in progress.

```
F2  ─┬─  Battle.net opens  →  presses Play  →  minimises
     │                                           ↓
     └─  your overlay starts                 Hearthstone opens and
         (immediately, in parallel)          takes the foreground
```

**Your overlay starts before Hearthstone, and that order matters — for both of them, for different reasons.**

- **Firestone** reads the game's memory to drive its overlay, so it goes up first and is in place and waiting as the game arrives. Starting it midway through Hearthstone's initialisation makes it attach to a process that isn't ready — which fails with *"CRITICAL ERROR: Could not read the game's memory"* and leaves you with no overlay for the whole session. The `fsLaunchDelayMs` setting exists to delay it and is `0` for exactly that reason.
- **The HSReplay tracker** writes the log settings Hearthstone reads **once, at start-up**. Launch the game first and the tracker asks you to restart it, which costs a whole relaunch. So the Play press is held until the tracker is actually running — capped at 25 seconds, past which Play fires anyway and the log says so.

**The launcher leaves before the game arrives.** Hearthstone opens onto a clear screen and takes the foreground on its own, rather than having the launcher tidy itself away over the top of it. Hearthstone itself is never hidden, muted or resized — fullscreen, borderless or windowed stays entirely your in-game setting.

Pressing F2 while Hearthstone is already running restarts it cleanly, closing the game and the Blizzard processes first.

**If the game doesn't start.** Pressing Play does not always launch anything — there may be a patch to download, or Battle.net may want you to sign in. Rather than sitting minimised waiting for a game that isn't coming, the launcher restores itself after 25 seconds, says so on screen, and keeps re-pressing Play in the background. A finished download is picked up automatically and the launcher minimises again. It waits up to 30 minutes, which covers a large patch.

A stalled launch is recovered rather than left hanging: the pipeline has a five-minute ceiling, time spent on the Battle.net login screen does not count against it, and a game that appears after the ceiling is still picked up.

### `F3` — Show or hide your overlay

**What F3 toggles depends on which overlay this session is using.** Under Firestone it is the desktop windows; under HSReplay it is the tracker's on-screen overlay. Everything in the rest of this section describes the Firestone case; [the tracker case is below](#f3-under-the-hsreplay-tracker).

**F3 never opens the overlay picker.** It can arrive mid-match, and a dialog over a live board is not an acceptable answer to a keypress. If the choice is unambiguous — one overlay installed, or a `Tracker=` setting pinned — F3 uses it. If both are installed and no F2 has settled the question yet, F3 does nothing at all.

Toggles the Firestone desktop windows (Main and Battlegrounds). They start hidden.

**F3 does nothing until Firestone Main has opened** — no toggle, no sound, no acknowledgement. Before that point there is nothing to show, and pressing it would disarm the concealment for the very window it was armed for, so Main would arrive on screen visible. An early press is silent and costs nothing: it is not queued and not remembered, so the first press after Main opens behaves as the first press.

Presses inside 250 ms of each other are dropped. The note still plays — the tone fires before the debounce — but the toggle and its on-screen message do not, so you hear the key and nothing moves. Rapid re-toggling style-flaps the underlying Chromium window, which is the documented way to wedge a Firestone Main that is still forming.

These windows are **deliberately exempt from the monitor lock.** They are what you read while playing, so they belong wherever you put them — usually a second screen, beside the game rather than over it. Each window's exact position is remembered when it is concealed and restored when it comes back, so move one wherever you like and F3 will keep it there.

**Two things F3 never touches.** The in-game overlay is always visible, whatever the lock state. And Firestone's notification popup — the "Your abilities are ready!" window — is not a toggle target at all; it is closed on sight and never painted.

#### `F3` under the HSReplay tracker

Hides and un-hides the tracker's on-screen overlay. It **starts shown** — the opposite default to Firestone, because an overlay you just launched and cannot see is not a useful thing to hand someone.

Panels the tracker creates *while* F3 has it hidden — the Battlegrounds leaderboard at the start of a lobby, the combat simulator when a fight resolves — are caught and concealed too, so nothing leaks back onto the screen. So are windows the tracker shows again by itself: it re-displays its overlay on game-state changes, and those get put back under. That check runs about two and a half times a second (every 400 ms) rather than at event speed, so a disagreement between HSBG and the tracker reads as a slow blink instead of a strobe, and it gives up after 25 rounds on the same window and leaves it visible — a visible overlay is a cosmetic complaint, an overlay flickering for a whole session is not. The log says `HDT-HIDE ... standing down` if that ever happens.

**It always comes back.** On the next press, on F4, on a tray exit, and on any crash on the way out — HSBG hides those windows, so it is responsible for giving them back, and a concealment outlives the script that applied it. If HSBG is ever killed outright (Task Manager, a power cut) while the tracker is hidden, double-clicking the tracker's own system-tray icon brings its main window back, and the overlay returns on the next game-state change.

Nothing else about the tracker is touched: not moved, not resized, not monitor-locked, not restyled.

### `F4` — Shutdown

Closes Overwolf, Battle.net, Hearthstone and the HSReplay tracker, restores everything the script changed, and exits.

**The tracker is closed like everything else in the session, with no condition attached.** It is asked to close first — `taskkill` without `/F` — because it writes match statistics as it plays and a forced kill mid-write is how a stats file gets truncated. If it has not gone within two seconds it is forced. A tracker that F3 had hidden is always handed back before any of that, on every exit path including a crash.

Also available as a held-key fallback, so it still works when a fullscreen game is swallowing window messages. That fallback only arms while Hearthstone is running, and only responds to an unmodified F4.

> `Alt+F4`, `Ctrl+F4` and `Win+F4` are passed straight through to Windows. Only an unmodified F-key triggers HSBG.

---

## What it does with each application

Four applications are involved in a Battlegrounds session. Left alone they produce a cluttered, slow, multi-step start-up with windows scattered across monitors.

| Application | What HSBG does with it |
|---|---|
| **Battle.net** | Opens on your chosen monitor, presses Play, and minimises *before* the game window arrives. Its service surfaces — boot splash, auto-login shell, maintenance alerts, Update Agent — never appear. If Play cannot start the game because an update or sign-in is pending, the launcher comes back and says so. Held down during an F1 skip, so a disconnect cannot pop it onto your screen. |
| **Hearthstone** | Launched, then left alone. Never hidden, muted or resized. The only thing the script decides is which monitor, and only if the game landed on the wrong one. |
| **Overwolf** | Started immediately on F2, in parallel with Battle.net, so it is ready by the time the game is. |
| **Firestone** | Optional. Its in-game overlay stays visible and untouched at all times; its desktop windows stay out of sight until you ask for them; its notification popup is closed on sight. If Firestone is **not installed**, every Firestone subsystem stays dormant and the rest works normally. If it is installed but you picked the tracker instead, most of them stand down — with [one exception](#only-one-overlay-at-a-time). |
| **HSReplay tracker** | Optional. Started on F2, at administrator level so it matches the game, and then left alone: never moved, resized, monitor-locked or restyled. F3 cloaks and un-cloaks it. F4 closes it. |

### Only one overlay at a time

Firestone and the HSReplay tracker draw the same information in the same place. Two of them on one board is two sets of panels competing for the same pixels and two processes attached to the same game, so HSBG uses one per session.

- **Only one installed** — it is used, silently. Nothing to ask.
- **Both installed** — F2 asks, once, and remembers the answer **for that session only.** Restart HSBG and it asks again. Change your mind mid-session from the tray menu: *"Overlay for this session…"*.
- **Neither** — F2 launches Battle.net and Hearthstone and nothing else, and F3 does nothing.
- **Want to stop being asked** — set `Tracker=firestone` or `Tracker=hsreplay` in `HSBG Config.ini`.

**The picker cannot hang a launch.** It waits 30 seconds for an answer and then defaults to Firestone and gets on with it, which is also what closing it or pressing Escape does — closing the window is "leave it as it was", and for a script that has always launched Firestone, that is Firestone. A second F2 while it is open does not stack a second dialog.

**A pinned setting that names something you don't have falls back rather than launching nothing.** `Tracker=hsreplay` on a machine without the tracker reverts to ordinary detection and logs why, because silently starting no overlay at all is the failure that costs an evening.

The overlay you don't pick is **never launched, moved or closed by a hotkey**, and the tracker in particular is untouched in every respect when Firestone is the choice.

> **Known issue, in the other direction.** Choosing the HSReplay tracker does *not* currently stand every Firestone subsystem down. Most of them are mode-gated correctly — the loading suppressor and the settings patch both check first — but the start-up window sweep and the notification closer are gated only on *"is Firestone installed?"*. So if you pin `Tracker=hsreplay` while Firestone is installed **and you have it open for something else**, HSBG will still conceal its Main and Battlegrounds windows and close its notification popups. F3 will not give them back, because F3 belongs to the tracker that session. Closing Firestone before you start, or not pinning `hsreplay` on a machine where you use Firestone separately, avoids it.

---

## Settings

`HSBG Config.ini` sits next to the script. It is created on first run with every setting documented inside it as comments, so you never need to open the script — or this page — to change your mind. Delete it and it comes back with the defaults.

**To edit it: right-click the tray icon → "Open settings".** ([Where the tray icon is.](#the-tray-menu)) That route matters. The script runs elevated, so the editor it opens is elevated too; if the file happens to live somewhere only an administrator can write, opening it any other way lets you make changes and then refuses to save them.

**Where the file lives is decided by testing, not assumed.** An existing `HSBG Config.ini` beside the script always wins — that is portable mode, and whoever put it there meant it. Otherwise, the script's own folder if it is genuinely writable, and `%APPDATA%\HSBG\` if it is not. Whichever won is named in the start-up log line and reachable from the tray menu, so there is never a question about which file is being read.

| Setting | Default | Effect |
|---|---|---|
| `MonitorLock` | `1` | Put Battle.net, the Update Agent, Hearthstone and the status text on the monitor you started the script from. `0` leaves every window where it opens and moves nothing. No effect on a single monitor. |
| `HotkeyAudio` | `1` | Play a short, deep note when a hotkey fires, so a press is confirmed without looking away from the game. `0` for silence. |
| `HotkeyAudioVolume` | `25` | `0`–`100`. Ignored while `HotkeyAudio=0`. |
| `HotkeySoundFile` | *(empty)* | Path to your own PCM `.wav`, played for every hotkey instead of the built-in note. Falls back to the built-in tone if the file is missing. |
| `HotkeyFreqMode` | `singular` | A word, not a number. `singular` — every key sounds the same note. `varied` — each key gets its own pitch. Any other value is read as `singular`. |
| `HotkeyFreqSingular` | `110.0` | Pitch in Hz used by every key in `singular` mode, and the fallback for an unset key in `varied` mode. |
| `HotkeyFreqF1`–`F4` | `82.41`, `110.00`, `73.42`, `55.00` | Per-key pitches used in `varied` mode; ignored in `singular`. Blank or `0` falls back to `HotkeyFreqSingular`. |
| `Tracker` | `ask` | Which overlay to use. `ask` — if both are installed, F2 asks and remembers for that session only. `firestone` / `hsreplay` — always that one, never asks. `none` — neither; F2 launches only the game, F3 does nothing. |
| `HDTPath` | *(empty)* | Path to the HSReplay tracker, if the automatic lookup misses it. Point it at either `HearthstoneDeckTracker.exe` or the `Update.exe` beside it. A path that does not exist is ignored, with a log line, and the usual lookup runs instead. |
| `UpdateCheck` | `1` | Ask GitHub once per run whether a newer release exists — see [Updates](#updates). `0` means the script never contacts the network for any reason. |

Pitches must be between `20` and `2000` Hz. A value outside that range, or one that isn't a number, is discarded in favour of the default and logged as `CONFIG <key>=<value> is not a number` or `is out of range`.

`Tracker` accepts the names people actually reach for. `hdt`, `decktracker`, `deck tracker`, `hearthstonedecktracker`, `hs replay`, `hsreplay.net` and `replay` all mean `hsreplay`; `fs` and `overwolf` mean `firestone`; `off`, `neither` and an empty value mean `none`. Anything else is logged and read as `ask`.

Settings are read at start-up. Use **"Reload settings"** in the [tray menu](#the-tray-menu) to apply a change without restarting — with the limits noted there.

**Thirteen keys, and every one of them does something.** Anything that is engineering rather than preference lives in the script's `CFG` block instead — including the Play gate that waits for the tracker, which is the only ordering in which the tracker works at all and so is not offered as a choice. See [Advanced tuning](#advanced-tuning).

<details>
<summary><b>About the built-in notes</b></summary>

They are synthesised rather than beeped, because `SoundBeep` produces a square wave that at these frequencies sounds like a fault rather than a note. Each one is built as a plucked, overdriven bass string: five harmonics with the higher partials decaying faster (that falling brightness is what the ear reads as a *pluck*), a valve-style soft clip for weight, a pick attack, and a release taper so the note ends rather than being cut off. The default pitches sit between 55 Hz and 110 Hz — below anything in Hearthstone's own mix, so they cut through without competing with it. They are generated on first use and cached, so they cost about a second on one start-up and nothing afterwards.

</details>

---

## Updates

HSBG checks whether it is out of date, once per run, about ten seconds after start-up. If it is, it says so quietly and offers to fetch the new file. It never installs anything by itself.

**What you see.** A message on screen for a few seconds, the tray tooltip gains *· v5.0.0 available*, and a new tray item appears — **Get v5.0.0 …** — named for whatever version it found. That item stays for the rest of the session. There is no dialog and no second reminder: a version check that interrupts a match has made the script worse at the thing it exists to do.

**What the tray item does.** Downloads the new script **beside the current one**, named for its version — `HSBG Script Final v5.0.0.ahk` — and opens the folder with it selected. Then exit HSBG from the tray and run the new file.

> **It never overwrites the script you are running.** An elevated process rewriting its own source while AutoHotkey holds it open is how an install gets corrupted, and the failure would land on someone who had just been told the update was safe. Both files exist until you delete one, so a release you dislike is one deletion away from being undone.

If the release has no `.ahk` attached, or the download fails, the releases page opens in your browser instead.

**What it sends: nothing.** The request is a plain `GET` with a User-Agent naming the script, which GitHub requires. No identifier, no version, no machine information, no telemetry — HSBG asks what the newest version is and works out locally whether it is behind. `UpdateCheck=0` stops even that.

**What happens when it doesn't work.** Nothing visible, deliberately. Offline, behind a proxy, blocked by an ad-blocker, rate-limited, GitHub down, a tag someone typed as `final2` — every one of these ends in a log line and silence. A version check is a convenience; it has no business putting an error on screen for a machine that is working perfectly.

It reads two sources, in order, and stops at the first that answers:

1. **The GitHub Releases API** — the right answer when a release was published properly, and it carries the download URL for the attached file.
2. **`version.json` in the repository** — the fallback, covering the two cases the API can't: a tag that was never published as a formal Release, and an address that has used up its 60 unauthenticated API calls for the hour. A shared connection behind one NAT can reach that limit; a home connection will not.

**Versions are compared as numbers, not text.** `v4.10.0` is newer than `v4.9.0` — comparing those as strings says the opposite, which would tell everyone on 4.10 to downgrade and keep telling them. Two-part tags are accepted (`4.1` equals `v4.1.0`), and a `-beta` or `+build` suffix is trimmed rather than ordered. A tag that isn't a version number at all claims nothing in either direction.

**The check never blocks.** AutoHotkey interrupts a thread between lines, never inside one, so a synchronous HTTP call would freeze the whole script — hotkeys, watchdogs, F4 — for as long as the socket took to give up. The request is issued asynchronously and polled from a timer, and abandoned after 15 seconds whatever the socket is doing.

---

## Diagnostics

The script writes one line per significant event to:

```
HSBG.log        ← in the same folder as the script
```

Beside the script, where you can find it — a log in `%TEMP%` is one Windows may sweep before anyone reads it. (If the script is somewhere it cannot write to, such as Program Files, the log falls back to `%APPDATA%\HSBG\`, and to `%TEMP%` only if that folder cannot be created either — because a log somewhere beats no log at all. The start-up line says where it went.) It is capped at 2 MB, with the previous file kept as `HSBG.log.1`.

**Start-up says nothing on screen.** The settings in force go to the log and nowhere else — a message that appears at every launch to tell you nothing has gone wrong is noise. The tray menu reports them on demand instead.

A single launch is usually enough to explain any unexpected behaviour. The lines that matter most:

```
CONFIG read C:\...\HSBG Config.ini -- MonitorLock=1 HotkeyAudio=1 Volume=25 SoundFile= FreqMode=singular Tracker=ask HDTPath= UpdateCheck=1
STARTUP v4.0.0 settings in force: MonitorLock=1 HotkeyAudio=1 vol=25 freqMode=singular Tracker=ask from C:\...\HSBG Config.ini
STARTUP overlays detected: Firestone=yes HSReplay=yes -- Tracker=ask
TRACKER both overlays are installed and no choice has been made yet -- deferring to the next F2
TRACKER this session uses Firestone (chosen at the prompt)
HDT-PATH found at the default location: C:\Users\...\AppData\Local\HearthstoneDeckTracker
HDT-LAUNCH started, elevated (inherited from this script), so it matches the Hearthstone this script is about to launch
HDT-GATE tracker up after 2100ms -- releasing the Play press
HDT-SHUTDOWN tracker closed
SCOPE saw a window belonging to Discord.exe -- not a process this script manages, so it was ignored
BNET-TIMING launcher ready 156ms after its window appeared -- the fixed sequence starts now
BNET-TIMING Play fired 2359ms after ready; minimize scheduled in 1000ms (fixed)
BNET-SEQ minimize confirmed
BNET-STALL no Hearthstone 25000ms after Play -- restoring the launcher
FS-POPUP killed at namechange hwnd=... size=440x570 -- cloaked, parked off-screen and closed on sight
FS-PAINT PROVEN after 875ms title="Firestone - Main" distinct=360 policy=park
F1 lookup=fast fastIps=... fastSvcCnt=1 fastV6=0
F1 method=ipblock target=smart pid=... cnt=... svcCnt=... block=... hold=2500
F1 hold 2503ms (fixed 2500)
HOTKEY stuck modifier(s) Alt held with 10000ms of no physical input -- releasing
UPDATE v5.0.0 is available (this build is v4.0.0) -- asset: https://github.com/.../HSBG%20Script%20Final.ahk
UPDATE this build (v4.0.0) is current; newest published is v4.0.0
UPDATE downloaded v5.0.0 to C:\...\HSBG Script Final v5.0.0.ahk -- the running script was NOT modified
```

The `STARTUP` line is the one to check first for anything settings-related: it reports the values **this running script loaded**, and the exact file it read them from — which is not always the file you edited.

---

## Troubleshooting

**A settings change seems to have no effect.**
Check the `STARTUP` line in the log. It names the build, the settings in force, and the file they came from. If it reports the old value, either the running script is not the file you edited (AutoHotkey does not hot-reload — exit from the tray and start it again), or you edited a different copy than the one it names. The build stamp on the tray tooltip tells you which script is actually running.

**The hotkeys stopped responding.**
Almost always a stuck modifier: if Windows believes Alt, Ctrl or a Windows key is still held, every F-key is treated as part of a system chord and passed through. The script detects and repairs this within a couple of seconds and logs `HOTKEY stuck modifier(s)`. It catches this two ways — a modifier held through ten seconds of no typing at all, *and* a gate that has been refusing continuously for three seconds, which is the one that saves the user hammering a dead F2 (their own presses keep the idle timer at zero, so the first test alone would never fire). If you see that line repeatedly, something else on the machine is disrupting the keyboard hook chain — Overwolf crashing is one cause. Tapping and releasing Alt and Ctrl clears it by hand.

**The tracker says to restart Hearthstone, or to run it as administrator.**
This is what the tracker support in HSBG exists to prevent, so seeing it means one of two things. Either the tracker was **already running before you pressed F2** — HSBG cannot fix that in place, because the tracker is single-instance and starting it again does nothing, so close it completely and press F2 again and HSBG will start it itself. The log says `HDT-ELEVATION the tracker was ALREADY RUNNING without administrator rights` when this is the cause. Or the game beat the tracker to start-up, in which case the log says `HDT-GATE ceiling reached` — the tracker took more than 25 seconds to come up and Play fired without it. Press F2 again; the tracker is up now.

**F2 asks about overlays and I only want one of them.**
Set `Tracker=firestone` or `Tracker=hsreplay` in `HSBG Config.ini`. It only asks when both are installed and nothing has been pinned.

**Is HSBG interfering with my other overlay?**
No — and the log proves it rather than asserting it. HSBG only ever moves, hides, cloaks or closes windows belonging to Hearthstone, Battle.net, the Blizzard Agent and Overwolf. Anything else is declined at the window hook and recorded once as `SCOPE saw a window belonging to <program> -- not a process this script manages, so it was ignored`. Search the log for `SCOPE` to see everything it looked at and left alone. The start-up line states the same list before anything has happened.

**F1 does not skip.**
Check the log lines for the press. `F1 lookup=` says which path found the connection and what it saw; `F1 method=... block=` says what was actually blocked. If `block=` is empty and the HUD said *No game connection found*, neither path identified one — set `f1Target := "all"` in the script's `CFG` block.

**F1 seems to need two presses.**
It doesn't. The HUD names the refusal you hit — `F1 cooling down…` for a press inside the 0.75 s window, `F1 ignored — launch in progress` for one during an F2. A press that is refused is not a press that failed to skip, and reading the message saves you the second one.

**F1 makes Battle.net pop up, or disconnects it.**
It shouldn't. The firewall rules are scoped to Hearthstone's executable, so the launcher's own connection is never touched, and the launcher is held down for the hold plus six seconds on top of that. If you see `F1 WARNING: Hearthstone's executable path is unknown`, the rules could not be scoped for that one press and fell back to machine-wide — which is the case where the launcher can react.

**Clicks on Hearthstone do nothing — but work again after moving the cursor to another monitor and back.**
That specific pattern is not an overlapping window; moving the cursor would not fix one. It is AutoHotkey's `#HotIf` mouse context, which the input hook evaluates on *every click* against a short deadline — an expression too slow to finish is abandoned and the previous result reused, which is what makes the fault sticky and cursor-dependent. HSBG's context expression is one boolean and one process-ID comparison, and it cannot run at all unless an F1 block is actually in place, so it has no room to miss the deadline.

**Clicks on Hearthstone do nothing (general).**
Tray icon → **"What is under my cursor?"**, then hold the cursor over the dead spot. It names the window that will receive the click, whether it is cloaked, whether it is topmost, and whether it has focus — which separates an invisible window over the game from the game not being foreground from the script's own click shield. The same detail goes to the log as `CURSOR-PROBE`.

**The hotkeys are silent.**
The note is on by default, so hearing nothing means either the setting was turned off or the script did not read the file you think it did. Tray icon → **"Test hotkey sound"**: it reports on screen whether the script actually read `HotkeyAudio=1`, names the config file it read, and plays the note. If you set `HotkeySoundFile`, check the path points at a real PCM `.wav` — the script falls back to the built-in tone when it does not, which sounds exactly like the setting being ignored.

**You don't have Firestone.**
Nothing to do. The script detects the missing install at start-up, logs `STARTUP no Overwolf/Firestone install detected`, and leaves every Firestone subsystem dormant. F1, F2 and F4 work normally; F3 has nothing to toggle.

**A Firestone popup appeared anyway.**
Check the log for `FS-POPUP killed` — if the line is there, it was closed and you saw it for the few milliseconds before the close landed. `FS-POPUP cloaked and moved off-screen, not yet closed … cannot yet prove it is not Firestone Main` is the deliberate opposite: the popup and Firestone Main are indistinguishable by title and size (Main is titled just `Firestone` while it loads, at the same size), so nothing is *closed* unless a separate window titled `Firestone - Main` also exists at that moment. The window is concealed either way, so this is time spent invisible rather than time spent on your screen. That structural check is the only thing standing between the fast kill and closing your Firestone. If neither line appears, look for `FS-VISIBLE`, which records any Firestone window left visible along with its title, size and styles.

**Firestone's window comes back blank.**
Check the log for `FS-PAINT`. If it reports the window never proved it painted, try `fsMainColdPolicy := "cloak"` instead of `"park"` — concealment behaves differently across Overwolf builds.

**The launcher does not minimise.**
The log traces the whole sequence: revealed → armed → Play fired → minimize confirmed. Whichever line is missing identifies the stage that stalled. `BNET-SEQ minimize did NOT take` means the client is refusing, or immediately restoring itself.

**A window is missing after a crash or reload.**
Restart the script. It repairs stranded windows at start-up — anything left outside the virtual desktop, left cloaked, or left transparent by an earlier instance is recovered automatically.

**The update notice is wrong, or I want it to stop.**
Set `UpdateCheck=0` in `HSBG Config.ini`. If it is announcing a version you already have, check that the tray tooltip and the release tag are the same number — the comparison is numeric, so a tag like `4.0` and a build of `v4.0.0` are equal, but a tag like `release-4` is not a version and is ignored with a log line. Search the log for `UPDATE` to see exactly what it fetched and what it concluded.

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
| `cooldownTime` | `750` | Minimum gap between F1 presses. A press inside it is refused with a toast rather than silently. |
| `f1Target` | `"smart"` | Which connection F1 blocks. `"all"` is a sledgehammer fallback if `"smart"` ever picks wrong, and it deliberately skips the fast lookup path. |
| `f1Method` | `"ipblock"` | How the disconnect is forced. `"adapter"` drops the network adapter instead — cruder, and it takes the whole machine offline for the hold. |
| `f1DebugLog` | `true` | One line per F1 press in the log, including which lookup path ran and the measured hold. |
| `loginWaitCeilingMs` | `1800000` | How long the launch may wait for you to sign in to Battle.net before giving up and releasing F1/F2. |
| `bnetLauncherMode` | `"visible"` | `"visible"` shows the launcher and minimises it after Play. `"minimized"` never shows it at all. |
| `bnetRevealDwellMs` | `500` | Minimum time the launcher stays on screen before Play may fire. |
| `bnetPostPlayLingerMs` | `1000` | Gap between Play firing and the launcher minimising. |
| `bnetStallRevealMs` | `25000` | How long to wait for the game before assuming an update or sign-in is blocking it. |
| `bnetReadyCeilingMs` | `12000` | How long Play waits for the launcher to look loaded before firing anyway. |
| `hdtGatePlay` | `true` | Hold the Play press until the tracker is running, so Hearthstone reads the tracker's log settings at start-up rather than being told to restart. There is deliberately no settings-file key for this — see [Settings](#settings). |
| `hdtReadyCeilingMs` | `25000` | How long that gate waits before firing Play regardless. |
| `hdtHideWatchMs` | `400` | How often F3's tracker concealment re-checks for windows the tracker has shown again. |
| `hdtReHideMax` | `25` | How many times one tracker window may be re-concealed before HSBG stands down and leaves it visible. |
| `trackerPickTimeoutMs` | `30000` | How long the overlay picker waits before defaulting to Firestone. |
| `fsLaunchDelayMs` | `0` | Delay before Firestone is launched. `0` — immediately, before Hearthstone exists, which is the only ordering that lets it attach to the game reliably. Raising it risks the "could not read the game's memory" failure. |
| `fsPopupGraceMs` | `3000` | How long a bare-`Firestone` window may hold that title before it is judged a notification rather than a Main still forming. It is concealed throughout, so this is time spent invisible. |
| `fsBurstMs` / `fsCoastMs` / `fsSettledMs` | `10` / `50` / `250` | The three cadences of the Firestone window sweep: while windows are being created, while the launch settles, and once you are just playing. |
| `fsNudgeCeilingMs` | `10000` | The longest a run of new Overwolf windows may keep the sweep above its settled rate. Guards against a steady trickle of window creations pinning it there for a whole session. |
| `hsGuardFastMs` / `hsGuardIdleMs` | `50` / `1000` | How often Hearthstone's position is checked, while the game is still deciding where to open, and afterwards. |
| `fsFollowMonitorLock` | `false` | Whether Firestone's windows are pinned to the launch monitor. |
| `fsHealthCheckMs` | `60000` | How long after launching Firestone to check whether it actually started. |
| `hkStuckModifierRepair` | `true` | Release a modifier key Windows reports as held when it isn't, which would otherwise make every hotkey inert. |
| `hkStuckModifierMs` / `hkGateBlockedMs` | `10000` / `3000` | The two ways a modifier qualifies as stuck: held through that much idle time, or the hotkey gate refusing continuously for that long. |
| `scriptAboveNormalPriority` | `false` | Raise the script's own priority for steadier timing. Off by default — it competes with the game for CPU. |
| `pauseWSearchDuringHS` | `true` | Stop the Windows Search indexer while Hearthstone runs. |
| `setHSGpuPreference` | `true` | Register Hearthstone as high-performance GPU (hybrid graphics systems). |

---

## Reading the source

One self-contained file: **14,311 lines, of which 6,071 are comments and about 7,250 are code.**

**The comments are written to be sufficient to rebuild the script from scratch.** Each subsystem states the constraint it exists to satisfy rather than merely what it does, because in nearly every case the obvious implementation is the one that fails — and the comment explains which failure. The file header contains a `REBUILDING THIS SCRIPT` section listing the load-bearing decisions in the order you will meet them.

| | |
|---|---|
| **S1** Configuration | Every tunable, documented in place |
| **S2** Runtime state | Shared flags and caches |
| **S3** HUD | On-screen status text — and, sharing its span with no banner of their own, the per-process audio helpers and the synthesised hotkey notes |
| **S5** Process manager | Locate, launch and query the applications |
| **S6** Path resolution | Find Overwolf and Firestone on disk |
| **S7** Settings patch | Pre-configure Firestone's settings file |
| **S7B** Tracker layer | Which overlay owns the session, and the elevation fix |
| **S8** Firewall manager | The scoped connection block used by F1 |
| **S9** Performance | Timer resolution, priority, GPU preference |
| **S10** Window manager | Concealment, paint detection and reveal |
| **S11b** Overlay topmost | Keeping Firestone's in-game overlay on top |
| **S11d** Firestone-Main reveal | The F3 unlock path |
| **S11e** Monitor lock | Window placement on the launch monitor |
| **S12** Timer helpers | Shared utilities |
| **S13** Update check | Asks GitHub whether a newer release exists |
| **S14** Launch pipeline | The F2 state machine |
| **S15** Hotkeys | The four handlers |
| **S16** Startup | Boot checks, repairs, background tasks |

The numbering has gaps — there is no S4, S11, S11a or S11c. Sections were split and merged as the file grew and the surviving numbers were left alone, because renumbering would invalidate every cross-reference in the comments.

**Verifying a change.** A cheap and strict check: strip every comment and blank line from the file before and after your edit, then diff the result. A documentation-only change should produce no difference at all.

```bash
grep -v '^\s*;' "HSBG Script Final.ahk" | sed 's/\s\+;.*$//' | grep -v '^\s*$'
```

---

## What it touches on your system

- **Never** modifies Hearthstone's process priority, game files, or memory.
- **Two firewall rules per F1 press** — `HS_BG_IP_IN` and `HS_BG_IP_OUT`, one for each direction — scoped to Hearthstone's executable and to the specific remote address or addresses identified for that press, then deleted when the hold ends. Rules are swept at start-up and at exit, and a failsafe timer removes the block even if the F1 handler dies mid-press — an interrupted press cannot leave a connection blocked.
- **The Windows Search indexer** is stopped while Hearthstone runs and restarted on exit.
- **Two registry values are set and left**: Hearthstone's per-application GPU preference (high-performance), and Unity's saved display index when the monitor lock has to correct it — the latter only when the value actually differs from what is already stored. Both are settings for Hearthstone rather than for this script, so they persist deliberately; nothing else in the registry is touched.
- **Firestone's own settings file** is patched before launch, so its windows come up in the state HSBG expects. Skipped entirely once the session has settled on anything other than Firestone — editing the configuration of a program you were asked not to run is not a reasonable thing to do.
- **Window positions and visibility** for Battle.net, Overwolf and Firestone. Every concealment has a matching cleanup that works from an empty ledger, so a crash or a forced reload cannot leave a window unreachable.
- **The HSReplay tracker**, if that is the overlay you chose: started on F2, cloaked and un-cloaked by F3, and closed by F4 — asked first, forced only if it refuses. Never moved, resized, monitor-locked or restyled. Its own settings files are never touched.
- **Nothing else on the machine.** Every window the script acts on belongs to Hearthstone, Battle.net, the Blizzard Agent or Overwolf; any other program's windows are declined at the hook and logged once as `SCOPE`.
- **Two files beside the script**: `HSBG Config.ini` and `HSBG.log` (plus one rolled `HSBG.log.1`).
- **One outbound HTTPS request per run**, to `api.github.com` and, only if that fails, `raw.githubusercontent.com` — asking what the newest released version is, and sending nothing about you or the machine. `UpdateCheck=0` stops it entirely.
- **One file, only if you click "Get …"** in the tray menu: the new script, saved beside the current one under its version's name. The running script is never modified.
- **A handful of scratch files in `%TEMP%`**, none of which matter if you delete them: the four hotkey tones, cached as `hsbg_tone_*.wav` so they are synthesised once rather than every launch, and `hs_bg_find.ps1` / `hs_bg_find.txt`, rewritten by any F1 press that falls through to the PowerShell lookup.
