HSBG — Hearthstone Battlegrounds Session Manager
One keypress. Clean lobby. Overlay ready. Combat skipped.

HSBG is an AutoHotkey v2 automation layer that manages a complete Hearthstone Battlegrounds session. It launches, restarts, and shuts down every application involved, keeps companion tools out of the way until you need them, and skips combat animations without closing the game.

No more scattered windows. No more manual restarts. No more waiting through combat. HSBG also works without Firestone, serving as a standalone combat skipper.

Why HSBG
One-key session control — F2 takes you from nothing running to a loaded game with your overlay attached.

Clean combat skip — F1 forces a fast reconnect that skips the combat animation while the match resolves server-side. Nothing is lost.

Invisible companion tools — Firestone and Overwolf stay hidden and healthy until you press F3 to reveal them.

Reliable startup — Battle.net, Hearthstone, Overwolf, and Firestone launch in the correct order, on the correct monitor, every time.

Optional Firestone support — No Firestone installed? HSBG works perfectly as a standalone combat skipper.

Clean shutdown — F4 closes everything and restores all system changes.

Applications Managed
Application	What HSBG does with it
Battle.net	Opens on your chosen monitor, presses Play, and minimizes before the game window arrives. If Play cannot start the game due to an update or sign-in, the launcher restores itself and keeps retrying.
Hearthstone	Launched cleanly and then left alone. Never hidden, muted, or resized. Fullscreen, borderless, or windowed — your in-game setting is respected.
Overwolf	Started immediately in parallel with Battle.net so it is ready when the game is.
Firestone	Optional. The in-game overlay remains visible and untouched. Desktop windows stay hidden until you press F3. Notification popups are closed on sight.
Hotkeys at a Glance
Key	Action
F1	Skip the current combat animation via a scoped connection block.
F2	Launch a full session, or restart Hearthstone if it is already running.
F3	Toggle Firestone desktop windows (Main and Battlegrounds) between hidden and visible.
F4	Close Overwolf, Battle.net, Hearthstone, Firestone, and exit the script.
Note: Only unmodified F-keys trigger HSBG. Alt+F4, Ctrl+F4, and Win+F4 are passed through to Windows untouched.

Quick Start
Requirements: Windows 10/11, AutoHotkey v2.0, Administrator privileges.

Install AutoHotkey v2.0.
v1 will not run this script.

Place HSBGScriptFinal.ahk anywhere convenient.

Run it from the monitor you want to play on.
HSBG resolves your intended monitor from its launch position and places everything accordingly.

Accept the UAC prompt.
Administrator rights are required for the firewall rules used by F1 and for pausing the Windows Search indexer.

The script elevates itself automatically and hands the launch monitor to the elevated instance, so your choice survives elevation.

Feature Details
F1 — Combat Animation Skip
Skips the Battlegrounds combat animation by forcing the client to reconnect past it.

Identifies Hearthstone's live game-server connection and blocks that address in both directions for a fixed interval.

The match continues resolving on Blizzard's servers throughout — you rejoin at the result, nothing is lost.

Blizzard's login and services connection (TCP 1119) is deliberately left alive, so there is no re-authentication and no risk to your seat in the lobby.

Hearthstone's audio is muted for the duration, and mouse input over the game window is swallowed, making the skip silent and impossible to disturb.

Cooldown: 2 seconds between presses.

F2 — Launch or Restart
Starts a full session, or restarts one already in progress.

text
F2  --->  Battle.net opens  ->  presses Play  ->  minimises
          Firestone starts                     Hearthstone opens and
          (immediately, in parallel)          takes the foreground
Firestone starts before Hearthstone — and that order matters. Firestone reads the game's memory to drive its overlay. Starting it first lets it attach cleanly. Starting it later often fails with "CRITICAL ERROR: Could not read the game's memory" and leaves you without an overlay for the whole session.

The launcher leaves before the game arrives, so Hearthstone opens onto a clear screen and takes the foreground naturally.

If the game doesn't start:

The launcher restores itself after 25 seconds, tells you on screen, and keeps re-pressing Play in the background.

A finished download is picked up automatically.

It waits up to 30 minutes — enough for a large patch.

The pipeline has a five-minute ceiling, but time spent on the Battle.net login screen does not count against it.

F3 — Show or Hide Firestone
Toggles the Firestone desktop windows (Main and Battlegrounds). They start hidden.

Does nothing until Firestone Main has opened. No toggle, no sound, no acknowledgement. An early press is silent and costs nothing.

Firestone windows are deliberately exempt from the monitor lock. They belong wherever you put them — typically a second screen.

Each window's exact position is remembered when concealed and restored when revealed.

The in-game overlay is always visible and is never touched.

The notification popup ("Your abilities are ready!") is not a toggle target. It is closed on sight and can never be shown by F3.

F4 — Shutdown
Closes Overwolf, Battle.net, Hearthstone, and Firestone, restores everything the script changed, and exits.

Also available as a held-key fallback, so it still works when a fullscreen game is swallowing window messages.

Design & Reliability
Three principles account for most of the design. They are what make the window handling reliable rather than lucky.

1. One owner per window per phase
Exactly one subsystem decides what happens to a given window at a given time. Where two could disagree, they are funnelled through a single shared primitive. Contended windows are the root of nearly every flicker and race.

2. Ask the window, not the ledger
The script keeps bookkeeping of what it has concealed, but that bookkeeping is never treated as evidence about a window's actual state. The owning application is editing that state concurrently. Anywhere the answer has to be correct, the code queries the OS rather than consulting its own notes.

3. Move, don't hide
Chromium-based windows — Firestone and the Battle.net client — treat ShowWindow(SW_HIDE) as you no longer exist and tear down their compositor. A window hidden before it has ever painted may never paint again: a correctly sized, correctly framed, completely blank rectangle.

So windows that must come back are moved off the virtual desktop rather than hidden. A move is synchronous and atomic; the window stays alive and fully rendered. Combined with a DWM cloak and taskbar-button removal, the result is indistinguishable from hidden — no pixels, no taskbar entry, no Alt-Tab entry — while the application remains perfectly healthy.

The script confirms a window can actually paint before using any stronger concealment on it.

Configuration
There are two layers. Most users only need the first.

HSBG Config.ini — User Settings
Created automatically on first run with every setting documented inside it as comments. Delete it and it comes back with the defaults.

To edit it: right-click the tray icon → "Open settings". That route matters because the script runs elevated, so the editor it launches is elevated too.

Setting	Default	Effect
MonitorLock	1	Put Battle.net, Update Agent, Hearthstone, and status text on the monitor you started the script from. 0 leaves everything where it opens.
HotkeyAudio	0	Play a short, deep note when a hotkey fires.
HotkeyAudioVolume	25	0–100. Ignored while HotkeyAudio=0.
HotkeySoundFile	(empty)	Path to your own PCM .wav, played instead of the built-in note.
HotkeyFreqMode	singular	singular = every key sounds the same note. varied = each key gets its own pitch.
HotkeyFreqSingular	110.0	The pitch in Hz used by every key in singular mode.
HotkeyFreqF1–F4	82.41, 110.00, 73.42, 55.00	Per-key pitches used in varied mode. Blank or 0 falls back to HotkeyFreqSingular.
Changes are read once at start-up. Exit from the tray and start again — or use "Reload settings" in the tray to apply them without a restart.

About the built-in notes: They are synthesised rather than beeped. Each one is a plucked, overdriven bass string with five harmonics, a soft clip, a pick attack, and a release taper. The default pitches sit between 55 Hz and 110 Hz, below anything in Hearthstone's mix, so they cut through without competing.

The Script's CFG Block — Advanced Settings
Located at the top of the script, documented in place. Nothing here needs editing for normal use.

Setting	Default	Effect
forcefulHoldMs	2500	How long F1 holds the connection block.
f1Target	"smart"	Which connection F1 blocks. "all" is a fallback if "smart" ever picks wrong.
bnetLauncherMode	"visible"	"visible" shows the launcher and minimises it after Play. "minimized" never shows it.
bnetRevealDwellMs	600	Minimum time the launcher stays on screen before Play may fire.
bnetPostPlayLingerMs	1250	Gap between Play firing and the launcher minimising.
bnetStallRevealMs	25000	How long to wait for the game before assuming an update or sign-in is blocking.
fsLaunchDelayMs	0	Delay before Firestone launch. 0 = immediately, before Hearthstone exists. Raising it risks the "could not read the game's memory" failure.
fsPopupGraceMs	3000	How long a bare-Firestone window may hold that title before it is judged a notification.
bnetReadyCeilingMs	12000	How long Play waits for the launcher to look loaded before firing anyway.
fsFollowMonitorLock	false	Whether Firestone's windows are pinned to the launch monitor.
fsHealthCheckMs	60000	How long after launching Firestone to check whether it actually started.
hkStuckModifierRepair	true	Release a modifier key Windows reports as held when it isn't.
scriptAboveNormalPriority	true	Raise the script's priority for steadier timing. Set false if you see game micro-stutter.
pauseWSearchDuringHS	true	Stop the Windows Search indexer while Hearthstone runs.
setHSGpuPreference	true	Register Hearthstone as high-performance GPU on hybrid graphics systems.
Reading the Source
The script is a single self-contained file of roughly 8,100 lines, about a third of which is documentation.

The comments are written to be sufficient to rebuild the script from scratch. Each subsystem states the constraint it exists to satisfy rather than merely what it does, because in nearly every case the obvious implementation is the one that fails — and the comment explains which failure.

The source is organised into numbered sections:

Section	Contents
S1	Configuration — every tunable, documented in place
S2	Runtime state — shared flags and caches
S3	HUD — on-screen status text
S4	Audio — per-application mute during F1
S5	Process manager — locate, launch, and query applications
S6	Path resolution — find Overwolf and Firestone on disk
S7	Settings patch — pre-configure Firestone's settings file
S8	Firewall manager — the scoped connection block used by F1
S9	Performance — timer resolution, priority, GPU preference
S10	Window manager — concealment, paint detection, reveal
S11	Overlay / reveal / monitor lock
S12	Timer helpers
S14	Launch pipeline — the F2 state machine
S15	Hotkeys — the four handlers
S16	Startup — boot checks, repairs, background tasks
Verifying a change
A cheap and strict check: strip every comment and blank line from the file before and after your edit, and diff the result. A documentation-only change should produce no difference at all.

bash
grep -v '^\s*;' HSBGScriptFinal.ahk | sed 's/\s\+;.*$//' | grep -v '^\s*$'
Safety & Cleanup
The script never modifies Hearthstone's process priority, game files, or memory.

It manages windows, one firewall rule scoped to a single address, and two Windows settings (per-application GPU preference and the Search indexer), all of which it reverses on exit.

Firewall rules created by F1 are removed on release, and swept at start-up and exit, so an interrupted press cannot leave a connection blocked.

Every concealment has a matching cleanup that works from an empty ledger, so a crash or forced reload cannot leave a window unreachable.

Contributing
Issues and pull requests are welcome. If you encounter a window shape the matcher does not recognize, please include the relevant window details — title, size, and styles — to help identify it.

License
Distributed under the license included in this repository. If no license file is present, all rights are reserved by the author.