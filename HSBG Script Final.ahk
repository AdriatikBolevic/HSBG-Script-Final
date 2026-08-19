; ==============================================================================
;
;   HSBG  —  Hearthstone Battlegrounds Session Manager
;
;   Version 8.0
;   Requires AutoHotkey v2.0 · Windows 10/11 · Administrator privileges
;
; ==============================================================================
;
; OVERVIEW
; ------------------------------------------------------------------------------
; HSBG manages a Hearthstone Battlegrounds session end to end. It starts and
; sequences four applications, keeps every window on the monitor you chose, and
; shows you only the surfaces you actually want to see.
;
;   Hearthstone   The game (Unity engine).
;   Battle.net    Blizzard's launcher. Boots off-screen, navigates to the
;                 Hearthstone page, presses Play, then slides into view already
;                 launching and minimises once the game is up.
;   Overwolf      The framework hosting the Firestone add-on.
;   Firestone     The Battlegrounds helper. Its in-game overlay stays visible at
;                 all times; its desktop windows stay out of sight until F3.
;
;
; HOTKEYS
; ------------------------------------------------------------------------------
;   F1   Combat-animation skip. Forcibly resets only the live game-server
;        connection, leaving Blizzard's login/services connection (TCP 1119)
;        untouched, so the client reconnects past the animation while the match
;        continues resolving server-side. No re-authentication, no lost seat.
;
;   F2   Launch or restart the session. Battle.net starts, presses Play and
;        minimises BEFORE the game window arrives, so Hearthstone opens onto a
;        clear screen and takes the foreground on its own -- it is never
;        hidden, muted or resized by this script.
;
;        EVERYTHING STARTS AT ONCE. Firestone is launched on the F2 press
;        itself, in parallel with Battle.net, rather than waiting for
;        Hearthstone to appear first. It loads in the background while
;        Battle.net does its work, so the overlay is ready sooner -- usually
;        before the game has finished loading.
;
;        If Play does not produce a game -- a pending update, a sign-in --
;        the launcher comes back with an explanation instead of leaving the
;        user staring at nothing.
;
;        Windows are placed on the monitor this script was started from. That
;        is a setting, and it lives in HSBG Config.ini, not in this file.
;
;        Firestone is OPTIONAL. With no Overwolf/Firestone install, every
;        Firestone subsystem stays dormant and the rest works normally.
;
;   F3   Show or hide the Firestone desktop windows. Starts hidden. Firestone
;        windows are deliberately exempt from the monitor lock: they return to
;        wherever you last placed them, on whichever screen.
;
;        Two things F3 never touches: the in-game overlay, which is always
;        visible; and the notification popup, which is cloaked before it can
;        paint and closed within milliseconds of being created, so it never
;        becomes something F3 can summon back.
;
;   F4   Full shutdown. Closes Overwolf, Battle.net and Hearthstone, restores
;        anything the script changed, and exits.
;
;
; CONFIGURATION
; ------------------------------------------------------------------------------
; Two settings live OUTSIDE this file entirely, in HSBG Config.ini next to it:
; the monitor lock and the hotkey audio. They are ordinary preferences rather
; than engineering tunables, and asking someone to open an 8,000-line script to
; change one is not a real option. The file is created on first run, documents
; itself, and is reachable from the tray menu. See LoadUserConfig.
;
; SECTION 1 opens with a USER SETTINGS block -- the few choices most people
; want, chief among them whether windows are locked to the monitor the script
; was started on (on by default). Everything after it is internal tuning,
; documented in place with its trade-offs. Nothing outside CFG needs editing.
;
;
; DESIGN NOTES
; ------------------------------------------------------------------------------
; Three principles account for most of the code and are worth stating up front,
; because they are what make the window handling reliable rather than lucky.
;
;   ONE OWNER PER WINDOW PER PHASE
;       Exactly one subsystem decides what happens to a given window at a given
;       time. Where two owners could disagree, they are funnelled through a
;       single primitive instead. Contended windows are the root of nearly every
;       flicker, race and lost state this kind of automation suffers from.
;
;   ASK THE WINDOW, NOT THE LEDGER
;       The script keeps bookkeeping (which windows it cloaked, parked or hid)
;       to avoid redundant work. That bookkeeping is never treated as evidence
;       about a window's actual state, because the owning application is editing
;       that state concurrently. Anywhere the answer has to be correct, the code
;       queries the OS.
;
;   MOVE, DO NOT HIDE
;       Chromium-based windows (Firestone, and the Battle.net client) treat
;       ShowWindow(SW_HIDE) as "you no longer exist" and tear down their
;       compositor accordingly; a window hidden before its first frame may never
;       paint again. Windows that must come back are therefore moved off the
;       virtual desktop instead — invisible to the user, fully alive to the
;       application. See CFG.fsMainColdPolicy and CFG.fsWarmPolicy.
;
;
; REBUILDING THIS SCRIPT
; ------------------------------------------------------------------------------
; The comments throughout this file are written to be sufficient to rebuild it
; from scratch. Each subsystem states the constraint it exists to satisfy, not
; merely what it does, because in nearly every case the obvious implementation
; is the one that fails. If you are reimplementing, the load-bearing decisions
; are these, in the order you will meet them:
;
;   1. Concealment must not use ShowWindow on a Chromium window that has to come
;      back. Park it off the virtual desktop instead. (SECTION 10,
;      _FSColdSuppress / _FSWarmSuppress.)
;   2. Every concealment site must funnel through one primitive. Five sites
;      independently deciding what to do with one window is unfixable by tuning.
;      (_FSSuppressSurface.)
;   3. Window state must be read from the OS at every decision point. Cached
;      bookkeeping is for skipping redundant work, never for deciding whether a
;      window is visible. (_FSEnsureCloaked, _FSProbePaint, _FSParkWindow.)
;   4. Anything that conceals a window needs a janitor that works from an empty
;      ledger, so a crash or reload cannot strand a window. (FSRepairStuckAlpha,
;      FSRepairStrandedWindows, ExitCleanup.)
;   5. Sequencing must be anchored to observed events, not elapsed time. Two
;      timers measuring the same deadline from different starting points will
;      disagree, and which one wins will vary by machine.
;      (BNetMinimizeSequenceTick.)
;   6. Timers armed by one code path and cancelled by several will eventually
;      stay cancelled. Give such a sequence a single owner that starts and stops
;      itself. (Same.)
;
; A cheap way to verify a change: strip every comment and blank line from the
; file before and after, and diff the result. Documentation edits should produce
; no difference at all.
;
;
; GLOSSARY
; ------------------------------------------------------------------------------
;   HWND         A window's numeric handle. Windows re-uses these after a window
;                closes, so every ledger here is pruned of dead handles and
;                identity is re-verified before a remembered handle is trusted.
;   timer / tick "Every N milliseconds, run this." A faster tick reacts sooner
;                at the cost of more work per second.
;   hook         Windows calls us the instant something happens (a window is
;                created, shown, retitled) rather than us polling for it. Events
;                arrive a few milliseconds late, so hooks and timers are used
;                together.
;   compositor   The Windows component (DWM) that draws every window, one frame
;                at a time. Any visibility change takes effect on the NEXT frame,
;                and that gap is the source of most flicker.
;   cloak        A DWM feature: keep the window alive but draw nothing for it.
;                Reversible and invisible to the application. Removes the window
;                from Alt-Tab, Task View, Aero Peek and taskbar thumbnails.
;   park         Move a window entirely outside the virtual desktop. Synchronous
;                and atomic, unlike a cloak, and it never tells the application
;                anything. The primary concealment mechanism here.
;   minimise     Performed via SetWindowPlacement, which skips the shrink
;                animation. An animated minimise of a cloaked window composites
;                as a black rectangle collapsing into the taskbar.
;   blanket      A policy of suppressing everything from a process while its
;                windows cannot yet be told apart.
;   janitor      Code whose job is to undo a concealment. Iron rule: nothing is
;                ever cloaked, parked or hidden without a janitor guaranteed to
;                run, including on crash and reload.
;   guard        A condition that must hold before something irreversible
;                happens. The notification closer has six.
;
;
; DIAGNOSTICS
; ------------------------------------------------------------------------------
; With CFG.f1DebugLog enabled the script appends a single line per significant
; event to %TEMP%\hs_bg_f1.log — launch sequencing, Firestone paint detection,
; window classification decisions and every window it closes. One launch is
; normally enough to explain any unexpected behaviour.
;
;
; ARCHITECTURE
; ------------------------------------------------------------------------------
;   S1   CONFIGURATION      Every tunable, documented in place.
;   S2   RUNTIME STATE      Shared flags and caches.
;   S3   HUD                On-screen status text.
;   S4   AUDIO              Per-application unmute, kept as a repair only.
;   S5   PROCESS MANAGER    Locate, launch and query the four applications.
;   S6   PATH RESOLUTION    Find Overwolf and Firestone on disk.
;   S7   SETTINGS PATCH     Pre-configure Firestone's own settings file.
;   S8   FIREWALL MANAGER   The scoped connection block used by F1.
;   S9   PERFORMANCE        Timer resolution, process priority, GPU preference.
;   S10  WINDOW MANAGER     Concealment, paint detection and reveal.
;   S11b OVERLAY ENFORCER   Keeps the in-game overlay visible and on top.
;   S11d F3 REVEAL          The reveal watchdog.
;   S11e MONITOR LOCK       Keeps session windows on the chosen monitor.
;   S12  TIMER HELPERS      Shared utilities.
;   S14  LAUNCH PIPELINE    The F2 state machine.
;   S15  HOTKEYS            The four handlers.
;   S16  STARTUP            Boot checks, repairs and background tasks.
;
;
; PERFORMANCE
; ------------------------------------------------------------------------------
; CFG.scriptAboveNormalPriority raises this script's own process priority so its
; short-interval timers hold their cadence under load. On some machines that
; produces game micro-stutter; set it false to trade timer consistency for
; headroom. Hearthstone's own priority is never modified.
;
; ==============================================================================

#Requires AutoHotkey v2.0

; Build stamp. Shown on screen at start-up and on the tray tooltip.
;
; AutoHotkey does not reload an edited script, so "I updated the file" and "the
; running script is the updated file" are separate claims -- and telling them
; apart by behaviour alone has cost real time on this script. This makes the
; running build identifiable at a glance, without opening anything.
global HSBG_BUILD := "v9.0"
#SingleInstance Force

; ==============================================================================
; SECTION 1: CONFIGURATION
; ==============================================================================
;
; Every knob in one place. Each entry says what it does, why the default is
; what it is, and what changing it trades away. If a future request is "make
; X faster/slower/bigger", the answer usually starts here.
;
global CFG := {
    ; ╔══════════════════════════════════════════════════════════════════════╗
    ; ║  USER SETTINGS                                                       ║
    ; ║                                                                      ║
    ; ║  The handful of choices most people actually want to change. Edit a  ║
    ; ║  value, save, exit the script from the tray and start it again --    ║
    ; ║  AutoHotkey does not reload an edited file on its own.               ║
    ; ║                                                                      ║
    ; ║  Everything below this block is internal tuning. The defaults there  ║
    ; ║  are the tested ones; nothing needs changing for normal use.         ║
    ; ╚══════════════════════════════════════════════════════════════════════╝

    ; WHERE WINDOWS OPEN.
    ; true  = Battle.net, the Blizzard Update Agent, Hearthstone and the on-screen
    ;         status text are all put on the monitor you STARTED THE SCRIPT ON,
    ;         whatever monitor they would otherwise have chosen. Start the script
    ;         on the screen you want to play on and everything follows.
    ; false = every window opens wherever Windows and the applications decide,
    ;         and the script never moves anything.
    ;
    ; Harmless either way on a single-monitor machine: there is only one place
    ; for a window to be, so the lock has nothing to correct and does no work.
    ; Firestone's own windows are deliberately NOT covered -- see
    ; fsFollowMonitorLock, further down -- because they are what you read while
    ; playing and usually belong on a different screen from the game.
    lockWindowsToChosenMonitor: true,

    ; ── THESE TWO ARE DRIVEN BY HSBG.ini ────────────────────────────────────
    ; The values here are the FALLBACKS used when no settings file is present.
    ; HSBG Config.ini sits next to this script, is created automatically on first run,
    ; and overrides both at start-up. Edit the .ini, not this -- the whole point
    ; of the file is that you never have to open an 8,000-line script to change
    ; your mind about a monitor lock. See LoadUserConfig.
    hotkeyAudio:             false,    ; a deep guitar note when a hotkey fires.
                                       ; OFF by default.
    hotkeyAudioVolume:       25,       ; 0-100.
    hotkeyFreqMode:         "singular", ; "singular" or "varied" for built-in tones.
    hotkeyFreqSingular:     110.0,    ; frequency when mode is "singular".
    hotkeyFreqF1:           82.41,    ; individual frequencies when mode is "varied".
    hotkeyFreqF2:           110.0,
    hotkeyFreqF3:           73.42,
    hotkeyFreqF4:           55.0,
    hotkeySoundFile:        "",       ; optional custom .wav file path for all hotkeys.

    ; HOW THE BATTLE.NET LAUNCHER BEHAVES.
    ;
    ; "visible"   = the launcher opens on screen, is brought to the front, sits
    ;               there briefly, presses Play and then minimises. You see what
    ;               is happening, and if Battle.net wants something -- a patch,
    ;               a sign-in -- it is already in front of you.
    ;
    ; "minimized" = the launcher never appears at all. It is minimised the
    ;               instant its window exists, Play fires with no dwell, and
    ;               Hearthstone is the first thing you see. Fastest path from
    ;               F2 to the game, at the cost of never seeing the launcher --
    ;               so if it needs attention you find out when the stall watch
    ;               brings it back rather than immediately.
    ;
    ; Both modes end with the launcher minimised before the game window
    ; appears, and both use the same stall watch when Play produces no game.
    bnetLauncherMode:        "visible",

    ; Hearthstone's window is never hidden, muted or resized by this script.
    ; Fullscreen, borderless or windowed is entirely your in-game setting; the
    ; only thing the lock above changes is WHICH MONITOR it opens on, and even
    ; that is corrected only when it lands on the wrong one.

    ruleName:                "HS_BG",
    cooldownTime:            2000,   ; ms between F1 presses (anti‑stacking)

    ; ── F1 forceful combat‑skip (services‑preserving) settings ──────────────
    ; Mid‑combat HS's game socket is idle, so a passive whole‑app block is never
    ; "noticed" and nothing disconnects. This mode instead (1) forcibly RESETS
    ; only the live game‑SERVER connection so the drop registers instantly even
    ; mid‑combat, and (2) leaves the services/auth connection ALIVE so the
    ; client re‑syncs to the still‑held game WITHOUT re‑authenticating.
    servicesPorts:           [1119],   ; NEVER reset / never block connections on
                                       ; these remote ports — Blizzard services &
                                       ; auth (Battle.net = TCP 1119). Keeping this
                                       ; alive is the whole point. The in‑match HUD
                                       ; shows the server address actually targeted.
    gamePorts:               [],       ; Optional allow‑list of the live MATCH remote
                                       ; port(s). Empty = AUTO: target every ESTABLISHED
                                       ; HS connection to a PUBLIC address whose remote
                                       ; port is NOT a servicesPort. Fill only if auto
                                       ; ever grabs the wrong connection.
    f1DebugLog:              true,     ; true = append one line per F1 press to
                                       ; %TEMP%\hs_bg_f1.log (connections found, the
                                       ; IP(s) blocked, hold window). If a press ever
                                       ; fails to disconnect, this line says whether
                                       ; the game IP was even identified — the one
                                       ; question that matters for tuning gamePorts.
    forcefulHoldMs:          2500,     ; F1 blackout CEILING. The block is now
                                       ; ADAPTIVE: it lifts the moment HS has
                                       ; verifiably abandoned the connection
                                       ; (no ESTABLISHED socket to a blocked
                                       ; IP for f1DropConfirmMs), so an
                                       ; end-of-turn skip releases in ~2s --
                                       ; sooner than the old fixed 3s -- while
                                       ; mid-COMBAT, where the client shrugs
                                       ; off short outages (the old "needs a
                                       ; second click"), it holds up to this
                                       ; ceiling. The server holds your seat
                                       ; for minutes, so 6s is safely inside.
    f1Target:                "smart",  ; WHICH connection(s) get blocked.
                                       ;   "smart" (default) — block every non‑services
                                       ;             candidate PLUS the NEWEST
                                       ;             services‑port (1119) connection.
                                       ;             Why: on many setups the GAME
                                       ;             connection itself runs on 1119,
                                       ;             same port as auth. The two are told
                                       ;             apart by AGE: auth is created at
                                       ;             client start and lives for hours;
                                       ;             the game connection is created when
                                       ;             the match starts. Newest 1119 =
                                       ;             game. The old auth connection is
                                       ;             left alone, so no re‑login.
                                       ;   "all"   — block EVERY established public IP
                                       ;             Hearthstone has, auth included.
                                       ;             Sledgehammer: guaranteed to catch
                                       ;             the game connection; the auth blip
                                       ;             lasts only the hold and re‑syncs
                                       ;             on release. Use if "smart" ever
                                       ;             picks wrong on your machine.
                                       ; CFG.gamePorts (if set) overrides both: only
                                       ; those remote ports are ever considered.

    f1Method:                "ipblock", ; HOW F1 forces the disconnect.
                                       ;   "ipblock" (default) — the original, simple
                                       ;             design: find the game SERVER IP,
                                       ;             block THAT IP in + out (not tied
                                       ;             to the HS program), hold, unblock.
                                       ;             Address‑scoped both‑direction
                                       ;             blocks are enforced per‑packet, so
                                       ;             they sever the LIVE socket —
                                       ;             unlike a program‑scoped rule,
                                       ;             which is evaluated at connection‑
                                       ;             start and only inconsistently
                                       ;             touches an existing one (why the
                                       ;             old "full block" worked once and
                                       ;             then didn't). Handles IPv4 and
                                       ;             IPv6 targets identically.
                                       ;   "adapter" — GUARANTEED fallback: briefly
                                       ;             disable then re‑enable the active
                                       ;             network adapter (scripted "pull
                                       ;             the cable"). Always disconnects,
                                       ;             but drops EVERYTHING incl. auth —
                                       ;             use only if "ipblock" somehow
                                       ;             doesn't drop on your machine.
    f1AdapterHoldMs:         3000,     ; blackout for "adapter" mode -- matched to the
                                       ; 3-second F1 disconnect duration so both F1
                                       ; methods produce the same downtime.
    loginFallbackAfterMs:    50000,

    ; ── Battle.net launch hiding ─────────────────────────────────────────────
    bnetAggressiveHide:      true,     ; true = maximum-aggression hiding of
                                       ; every Battle.net-family surface that
                                       ; is not the REAL client window:
                                       ; cloak-at-birth + SW_HIDE for the
                                       ; auto-login shell ("Logging in" /
                                       ; Maintenance Alert), boot splash,
                                       ; update overlays, stray dialogs, and
                                       ; all Agent / Helper windows. Real
                                       ; login screens are hidden too until
                                       ; the pipeline's detector concludes a
                                       ; human must type (LOGIN_WAIT), which
                                       ; un-hides exactly those windows.
                                       ; false = hide nothing.
    fsBirthHide:             true,     ; Enabled: SW_HIDE every new Overwolf
                                       ; window AT CREATE (before it can paint
                                       ; a frame) while the F3 lock is on, and
                                       ; let the janitors un-hide the benign
                                       ; ones. This is the strongest anti‑flicker
                                       ; and has been tested for stability.
                                       ; Set false only if you see renderer
                                       ; issues after F3 reveal.
                                       ; (was) true = SW_HIDE every new Overwolf
                                       ; window AT CREATE (before it can paint
                                       ; a frame) while the F3 lock is on, and
                                       ; let the janitors un-hide the benign
                                       ; ones. Strongest anti-flicker there is.
                                       ; Set false to revert to cloak-only at
                                       ; birth if anything misbehaves.
    fsBirthHideMaxMs:        2000,     ; a birth-hidden window that never
                                       ; resolved to a KNOWN title is
                                       ; force-shown after this, so nothing can
                                       ; stay hidden by accident. See
                                       ; fsVisibleTitles -- "known" now means
                                       ; "on the must-be-visible allow-list",
                                       ; not "not on the suppress list".

    ; ── Overwolf surface classification (allow-list, not deny-list) ─────────
    ; The original design classified by EXCLUSION: suppress a short list of
    ; known-bad titles, reveal everything else. That is backwards for this job
    ; and is why stray Overwolf windows ("OverWolf Server", untitled CEF
    ; frames) appeared on screen -- they matched no suppression title, so three
    ; separate janitors treated them as benign and actively SHOWED them.
    ;
    ; Inverted here: while the F3 lock is on, an Overwolf-family window is
    ; suppressed unless its title is on fsVisibleTitles. That list is the only
    ; thing that is ever allowed to render.
    fsVisibleTitles: [
        "Firestone - Overlays",        ; the in-game overlay: MUST stay visible
    ],
    fsFamilyExes: [
        "Overwolf.exe",
        "OverwolfBrowser.exe",
        "OverwolfHelper.exe",          ; harmless if not present on your install
    ],
    ; Scope for the stuck-transparency repair ONLY (not for suppression).
    ; OverwolfLauncher.exe is included here and NOT in fsFamilyExes on purpose:
    ; its splash should still be suppressed by its own dedicated hider, but it
    ; is also the one process this script fades with WinSetTransparent(0) and
    ; then never un-fades -- so it must be inside the repair's reach.
    fsAlphaRepairExes: [
        "Overwolf.exe",
        "OverwolfBrowser.exe",
        "OverwolfHelper.exe",
        "OverwolfLauncher.exe",
    ],
    fsLogUnclassified:       true,     ; append one line per NEW (exe|class|
                                       ; title|size) Overwolf surface the
                                       ; script decides about, to
                                       ; %TEMP%\hs_bg_f1.log. One line per
                                       ; distinct signature per session, so it
                                       ; cannot spam. This is how we identify
                                       ; any window that still escapes: the log
                                       ; names the exact process and title.
    fsRevealForeground:      true,     ; true = F3 brings the revealed
                                       ; Firestone windows to the FOREGROUND,
                                       ; above Hearthstone (topmost + focus).
                                       ; Needed on a single monitor, where HS
                                       ; would otherwise cover them. The pin is
                                       ; dropped when the lock re-hides them.
    ; ── Alpha shield ────────────────────────────────────────────────────────
    ; DEFAULT OFF, deliberately. The shield makes a window fully transparent
    ; (WS_EX_LAYERED + alpha 0) as a SECOND invisibility layer on top of the
    ; DWM cloak and the SW_HIDE. With fsMainUseHide = true the window is taken
    ; off the screen entirely, so the shield buys nothing -- and it is the one
    ; mechanism in the script that can leave a window PERMANENTLY invisible:
    ; a transparent-but-shown window is the faint empty rectangle you get when
    ; F3 reveals something whose alpha never got restored.
    ;
    ; The shield also deliberately KEEPS WS_EX_LAYERED across an unlock, so
    ; after a script reload every previously-shielded window looks
    ; "already layered" to a fresh instance and gets misclassified as
    ; Overwolf's own (see _ApplyFSAlphaShield). That combination is what makes
    ; the failure survive restarts.
    ;
    ; Set true only if you ever see a real paint leak that the cloak misses.
    ; Suppression is unchanged either way: cloak + minimize + hide still run.
    fsUseAlphaShield:        false,

    ; ── Firestone - Loading: conceal, do not close ──────────────────────────
    ;
    ; Disabled by default, and it should stay that way.
    ;
    ; The loading popup can be sent WM_CLOSE, including via a PowerShell sweep
    ; matching MainWindowTitle. Two things make that dangerous, and both are
    ; specific to Main:
    ;
    ;   1. CloseMainWindow() posts WM_CLOSE to the PROCESS'S main window, not to a
    ;      window we identified. During launch that is the very HWND which becomes
    ;      Firestone - Main.
    ;   2. EnsureFirestoneSettings enables close-to-tray, which converts a stray
    ;      WM_CLOSE from "window destroyed" (obvious, and recoverable by relaunch)
    ;      into "window survives, web contents torn down" -- a live HWND with
    ;      nothing inside it.
    ;
    ; The popup is already concealed by the suppressors and Overwolf disposes of
    ; it once loading finishes, so closing it is tidiness with a real downside.
    ; Set true to restore the close behaviour.
    fsCloseLoadingPopup:     true,     ; CLOSE the loading popup as soon as a
                                       ; separate Firestone‑Main exists.
                                       ; The structural guard (Main must exist
                                       ; separately) is unchanged, so the
                                       ; popup is never confused with Main.

    fsMainUseHide:           true,     ; true = SW_HIDE FS-Main while locked
                                       ; (strongest exit -- a hidden window
                                       ; cannot flicker or be fought), ledgered
                                       ; so F3 reveals it. Now safe because
                                       ; FS-Main suppression is single-owner.
                                       ; false = the classic cloak+minimize.
                                       ; NOTE: this now applies only AFTER the
                                       ; window is paint-proven. Before that,
                                       ; fsMainColdPolicy below owns it.

    ; ── CONCEALMENT POLICY ────────────────────────────────────────────────
    ;
    ; Firestone is a Chromium (CEF) application, and that dictates the whole
    ; design of this section.
    ;
    ; A CEF window that receives ShowWindow(SW_HIDE) before it has produced its
    ; first frame never finishes bringing its compositor up. There is nothing on
    ; screen for it to draw to, so it does not draw, and it has no reason to
    ; revisit that decision. A later SW_SHOWNA is not a signal it acts on. The
    ; result is a correctly sized, correctly framed, never-painted rectangle with
    ; the desktop showing through -- indistinguishable, from the user's chair,
    ; from a transparency fault.
    ;
    ; Firestone - Loading and Firestone - Main are the same HWND: the loading
    ; window retitles into the main window in place. So anything done to the
    ; loading splash is done to the window that becomes Main, at the coldest
    ; moment of its life.
    ;
    ; The policy that follows from this: a Firestone window is never given a
    ; ShowWindow(SW_HIDE) until it has PROVEN it can paint. Until then it is kept
    ; invisible by means the renderer does not interpret as disappearing.
    ;
    ; fsMainColdPolicy -- how a window is concealed before it has painted:
    ;
    ;   "park"  (default) Moved entirely outside the virtual desktop, DWM-cloaked,
    ;           and removed from the taskbar via ITaskbarList::DeleteTab. No
    ;           pixels, no taskbar button, no Alt-Tab entry, no thumbnail --
    ;           visually identical to being hidden. But WS_VISIBLE is never
    ;           cleared, so the renderer keeps a live widget and paints normally.
    ;           ShowWindow is never called.
    ;   "cloak" Cloak only, in place. Invisible, but the taskbar button remains
    ;           for a few seconds. Use if parking upsets Overwolf's layout.
    ;   "hide"  SW_HIDE at birth. Provided for comparison; this is the setting
    ;           that produces the unpainted window described above.
    fsMainColdPolicy:        "park",

    ; What the F3 lock does to a window that has already proven it paints.
    ;
    ;   "park" (default) Move it off the virtual desktop and cloak it. No
    ;          ShowWindow in either direction, so the renderer never sees a
    ;          visibility transition and never tears its compositor down.
    ;          Each hide/show pair costs a Chromium window a frame-sink teardown
    ;          and rebuild; repeated toggling is what makes a renderer give up.
    ;   "hide" Cloak plus SW_HIDE. Lower overhead per cycle, but not durable
    ;          under repeated toggling.
    fsWarmPolicy:            "park",

    ; Whether Firestone's windows follow the monitor lock. They do not, by
    ; default: Main and Battlegrounds are the windows you read while playing, so
    ; they belong wherever you put them -- typically a second screen, beside the
    ; game rather than over it. Each window's exact rectangle is recorded when it
    ; is parked and restored when it returns, so F3 leaves a window precisely
    ; where you left it.
    ;
    ; lockWindowsToChosenMonitor is unaffected and still governs Battle.net, the
    ; Blizzard Agent, Hearthstone and the HUD.
    fsFollowMonitorLock:     false,

    ; PAINT DETECTION -- measured, not assumed.
    ;
    ; PrintWindow with PW_RENDERFULLCONTENT copies a window's real composited
    ; content; the flag exists specifically for DirectComposition and Chromium
    ; surfaces, which return black without it. A sparse pixel grid is sampled
    ; from the result and distinct colours counted: a drawn interface yields
    ; hundreds, a never-drawn window yields one.
    ;
    ; The probe runs only on the settled suppression sweep, never inside the
    ; window event hook, and stops as soon as it succeeds.
    fsPaintProbeMs:          250,      ; min ms between probes of one hwnd
    fsPaintMinDistinct:      8,        ; distinct sampled colours = "painted"
    fsPaintCeilingMs:        20000,    ; give up after this and hide anyway, so
                                       ; a window can never sit cold forever.
                                       ; Logged loudly when it happens.

    ; Overwolf answers our birth-suppression by calling SW_SHOW. Re-asserting
    ; at event speed is correct ONCE or twice; an unbounded fight is a storm.
    ; Capped, and the overflow is logged.
    fsBirthReassertMax:      3,

    ; ── Firestone launch point ──────────────────────────────────────────────
    ; false = LAUNCH FIRESTONE IMMEDIATELY on F2, alongside everything else.
    ; The old deferred behaviour (waiting for Hearthstone.exe) is removed.
    fsLaunchAfterHS:         false,    ; always immediate
    fsPopupGraceMs:          3000,     ; how long a bare-"Firestone" window may
                                       ; hold that title before it is judged a
                                       ; notification rather than a Firestone
                                       ; Main still forming. Main retitles to
                                       ; "Firestone - Main" within about a
                                       ; second; a notification never does. Only
                                       ; consulted when Main is not open to
                                       ; compare against -- with Main present the
                                       ; popup is closed at once. The window is
                                       ; cloaked throughout, so this is time
                                       ; spent invisible, not time on screen.
    fsLaunchDelayMs:         0,        ; how long after the F2 press before
                                       ; Firestone is launched. 0 = immediately,
                                       ; alongside everything else.
                                       ;
                                       ; THIS WAS 5000, AND IT BROKE FIRESTONE.
                                       ; The delay was meant to move Firestone's
                                       ; windows out of the busiest moment of the
                                       ; launch, so a birth-time concealment race
                                       ; had less to compete with. It did that --
                                       ; and it also moved Firestone's start INTO
                                       ; the window where Hearthstone is
                                       ; initialising, instead of safely before
                                       ; it. Firestone reads the game's memory to
                                       ; drive its overlay, and starting mid-load
                                       ; means it attaches to a process that is
                                       ; not ready: "CRITICAL ERROR: Could not
                                       ; read the game's memory", and no overlay
                                       ; for the whole session.
                                       ;
                                       ; Launching BEFORE Hearthstone exists lets
                                       ; Firestone be in place and waiting as the
                                       ; game comes up, which is the ordering that
                                       ; has always worked. A one-frame flash of a
                                       ; loading window is a cosmetic complaint;
                                       ; an overlay that cannot read the game is
                                       ; the entire product.
                                       ;
                                       ; The deferral mechanism is kept, and can
                                       ; be re-enabled by setting a value here --
                                       ; but anything non-zero risks this again.
    fsLaunchArmSettleMs:     50,       ; reduced from 250ms to arm suppressors faster
                                       ; the suppressors now have a very short
                                       ; settle before Firestone starts.
    ; ── Firestone suppression cadence (burst vs coast) ──────────────────────
    ; The suppression sweep enumerates every Overwolf / OverwolfBrowser window
    ; and reads each title. At 1 ms that is ~1000 full enumerations per second
    ; on a script running at HIGH process priority -- it saturates AutoHotkey's
    ; single thread, which is why hotkeys felt laggy, beeps went missing and
    ; the whole script read as "barely working". The 1 ms rate is only actually
    ; needed while windows are being BORN (a launch, or a fresh F3 lock); the
    ; rest of the time it is a pure watchdog. So the burst now DECAYS.
    fsBurstMs:               1,        ; sweep interval while bursting
    fsCoastMs:               50,       ; sweep interval once the burst decays.
                                       ; Still well under one frame at 60Hz, so
                                       ; steady-state suppression is unchanged.
    fsBurstMaxMs:            20000,    ; how long a burst lasts before it drops
                                       ; to the coast rate. Re-armed by every
                                       ; LockFirestoneMain / F2, so a launch
                                       ; always gets a fresh full-speed window.

    bnetMinimizeCeilingMs:   60000,

    ; SEQUENCE: launcher appears -> dwells -> Play -> minimize -> game opens.
    ; The launcher is gone BEFORE the game's window arrives, so the game takes
    ; the foreground with nothing else on screen to argue with.
    bnetReadyCeilingMs:      12000,    ; how long Play will wait for the launcher
                                       ; to look loaded before firing anyway. The
                                       ; readiness check is evidence, not a
                                       ; promise -- a minimized-mode launcher or
                                       ; an unusually small window can never
                                       ; satisfy it, and a launch that never
                                       ; happens is far worse than one that
                                       ; happens a moment early.
    bnetRevealDwellMs:       1200,      ; minimum on-screen time for the launcher
                                       ; before the Play command may fire. This
                                       ; is a floor, not a wait: it only stops
                                       ; the window flashing past. Raise it if
                                       ; you want a longer look at the launcher.
    bnetPostPlayLingerMs:    1250,     ; gap between Play firing and the launcher
                                       ; minimizing. Anchored to the COMMAND, not
                                       ; to Hearthstone's process, which is what
                                       ; lets the launcher leave first.
                                       ;
                                       ; 250ms was the minimum that let the client
                                       ; register the command; this is that plus a
                                       ; deliberate extra second on screen, so the
                                       ; launcher reads as finishing its job
                                       ; rather than blinking out of existence.
                                       ; Still well clear of the game window.

    ; Stalled launch: Play fired but no game appeared. Almost always a pending
    ; update or a sign-in. See BNetStallWatchTick.
    bnetStallRevealMs:       25000,    ; no Hearthstone this long after Play =
                                       ; bring the launcher back so the user can
                                       ; see what it is asking for. Generous, so
                                       ; a slow-but-healthy start-up is never
                                       ; interrupted.
    bnetRelaunchEveryMs:     30000,    ; while waiting, re-fire Play this often.
                                       ; A finished download leaves a client that
                                       ; would now work, and nothing else would
                                       ; ever press the button again.
    bnetStallWatchMaxMs:     1800000,  ; give up after 30 minutes. Long, because a
                                       ; multi-gigabyte patch is a legitimate
                                       ; reason to still be waiting.
    bnetRevealForeground:    true,     ; true = when the launcher comes up to launch
                                       ; Hearthstone it is pinned above every other
                                       ; window and given focus, the same treatment F3
                                       ; gives Firestone Main / Battlegrounds
                                       ; (fsRevealForeground). Without it the launcher
                                       ; opens wherever the z-order happens to put it,
                                       ; which on a busy desktop is behind whatever was
                                       ; already there. The pin is dropped again the
                                       ; moment the launcher minimizes or Hearthstone is
                                       ; revealed, so it never floats over the game.
                                       ; false = place it, but leave the z-order alone.
    loginDetectMinRetries:   25,       ; ticks before first BNet login‑screen check (~5s)
    loginFallbackMinRetries: 25,       ; ticks before entering LOGIN_WAIT fallback
    hammerFastMs:            200,      ; LaunchStateMachine tick interval (fast phase)
    hammerSlowMs:            500,      ; LaunchStateMachine tick interval (login‑wait phase)
    launchHudWatchMs:        400,      ; LaunchHudWatchdog poll interval

    fsHealthCheckMs:         60000,    ; after launching Firestone, wait this long
                                       ; and then check whether it is actually
                                       ; running. If it is not -- a failed start,
                                       ; a critical error -- every Firestone timer
                                       ; is stood down instead of polling for
                                       ; windows that will never appear. Generous,
                                       ; so a slow Overwolf start is never
                                       ; mistaken for a failure.

    ; ── Hotkey reliability ──────────────────────────────────────────────────
    ; The four F-keys are gated on "no system modifier is held" so Alt+F4 and
    ; friends pass through to Windows. If the OS ever reports a modifier held
    ; that is not, that gate turns every hotkey inert with no visible symptom.
    ; See HK_NoSysMods for the full mechanism.
    hkStuckModifierRepair:   true,     ; true = release a modifier the OS reports
                                       ; as held while no input is happening.
                                       ; This is what makes "the hotkeys stopped
                                       ; working" self-correcting instead of
                                       ; needing a script restart.
    hkStuckModifierMs:       10000,    ; required idle time before a held modifier
                                       ; is judged stuck. No human chord lasts
                                       ; this long: Alt-tab sends Tab presses,
                                       ; which reset the idle timer. Raise it if
                                       ; you ever see a legitimate chord broken.
    hkGateBlockedMs:         3000,     ; the OTHER way a modifier is judged stuck:
                                       ; the hotkey gate has been refusing every
                                       ; press continuously for this long. Needed
                                       ; because a user pressing dead F-keys keeps
                                       ; the idle timer above near zero, so the
                                       ; idle test alone would never fire for the
                                       ; person who needs it most.
    hkWatchdogPollMs:        2000,     ; how often that check runs.

    ; ── Performance / smoothness tweaks (set false to disable) ──────────────
    scriptAboveNormalPriority: true,    ; true = run this script itself at AboveNormal
                                       ; priority for more consistent F1/F3 timer
                                       ; response. Set false if you notice gameplay
                                       ; micro‑stutter (trades timer consistency for
                                       ; giving the game thread more headroom).
    setHSGpuPreference:      true,     ; write registry: HS = "High performance" GPU.
                                       ; Persists in HKCU; one‑time write per HS path.
                                       ; No admin needed (HKCU is per‑user).
    pauseWSearchDuringHS:    true,     ; stop "Windows Search" service while HS is
                                       ; running, restart on F3 / HS‑died / exit.
                                       ; Reduces background‑disk‑indexing hitches.
                                       ; Requires admin (script already runs elevated).
                                       ; System‑wide: indexing pauses for ALL users
                                       ; on this machine while HS is alive.

    ; ── Monitor lock (HUD / Battle.net / Agent; Hearthstone via its own guard) ─
    ; (lockWindowsToChosenMonitor lives in the USER SETTINGS block at the top
    ;  of CFG -- it is the one placement choice people actually change.)
    preShowPlaceBNet:        false,    ; DISABLED: redundant now that the
                                       ; reveal positions the launcher
                                       ; entirely while it is still hidden.
                                       ; It moved VISIBLE windows, which was a
                                       ; primary-monitor flicker source. Fewer
                                       ; movers = fewer races.
                                       ; (was) true = when a Battle.net / Agent
                                       ; top‑level window is CREATED and is not
                                       ; yet visible, move it to the chosen
                                       ; monitor BEFORE its first show. Nothing
                                       ; has painted yet, so there is no visible
                                       ; jump and nothing to corrupt — the first
                                       ; frame the user ever sees is already on
                                       ; the right screen. Windows born already
                                       ; visible still use the settled 400ms
                                       ; movers. Set false to fall back to
                                       ; settled‑mover‑only placement.
    monitorLockPollMs:       1000,     ; cadence of the steady‑state monitor‑lock
                                       ; watchdog. 1s is plenty — it only nudges a
                                       ; window that has drifted onto the WRONG
                                       ; monitor, so it's a no‑op almost every tick.

    setHSMonitorPref:        true,     ; true = before each launch (and once at
                                       ; startup), write Hearthstone's OWN saved
                                       ; display preference (Unity's
                                       ; UnitySelectMonitor registry value) to the
                                       ; chosen monitor. Unity re‑places its window
                                       ; onto whatever display it last remembered —
                                       ; usually the PRIMARY — shortly after boot,
                                       ; and that snap‑back versus the script's
                                       ; movers is the "HS bounces between primary
                                       ; and the locked monitor" fight. Making
                                       ; Unity's own memory point at the chosen
                                       ; monitor removes the fight at the source:
                                       ; HS opens on the right screen by itself and
                                       ; the movers become no‑ops. Registry‑only,
                                       ; HKCU, exactly what changing the display in
                                       ; HS's graphics options writes.

    ; ── Cold‑launch survivability ───────────────────────────────────────────
    launchCeilingMs:         300000,   ; hard ceiling of the F2 state machine.
                                       ; A cold boot -- cold-disk Battle.net,
                                       ; plus login, plus Hearthstone's first load -- routinely exceeds two minutes,
                                       ; and an abort mid-launch skips everything that hangs off
                                       ; CompleteHSLaunchSuccess. Five minutes covers a cold boot; time spent sitting
                                       ; on the Battle.net login screen does not count against it at all (see the
                                       ; LOGIN_WAIT bookkeeping), and LateHSWatch recovers even a post-ceiling launch.
}

; ══════════════════════════════════════════════════════════════════════════════
;  EXTERNAL SETTINGS FILE — HSBG.ini
; ══════════════════════════════════════════════════════════════════════════════
; Applied immediately after CFG is built and before anything reads it.
;
; WHY A SEPARATE FILE. CFG is the engineering surface: sixty-odd values, most of
; which have a paragraph explaining what they trade away. Two of them are
; ordinary preferences that a user should be able to change on a whim, and
; asking someone to open an 8,000-line script and find the right line to do it
; is not a real option. The .ini is those two, in a file you can read in ten
; seconds.
;
; The file lives next to the script and is created on first run with its
; defaults and comments, so there is nothing to install and nothing to copy from
; the documentation. Delete it and it comes back.
;
; Everything here is defensive: a missing file, an unreadable one, a value
; someone typed as "yes" instead of 1 -- none of it may stop the script
; starting. Anything unparseable falls back to the CFG default and says so in
; the log.
LoadUserConfig()

; Where HSBG.ini lives. Resolved once, then cached.
;
; THE SCRIPT'S OWN FOLDER IS NOT ALWAYS A PLACE THE USER CAN WRITE.
; This script runs ELEVATED. A file it creates next to itself inherits that
; folder's permissions, so if the script sits anywhere protected -- Program
; Files, a synced folder, a drive with restrictive ACLs -- the .ini ends up
; owned by an administrator and an ordinary Notepad cannot save over it. The
; user opens the file, edits it, presses save, and is refused. Nothing about
; that is visible from the outside; it just looks like the settings file is
; broken.
;
; So the folder is CHOSEN by testing it, not assumed:
;
;   1. An HSBG.ini already sitting next to the script wins. That is portable
;      mode -- a USB stick, a git checkout -- and whoever put it there meant it.
;   2. Otherwise, if the script's own folder is genuinely writable, use it.
;      That is the friendliest place: the settings sit with the thing they
;      configure.
;   3. Otherwise %APPDATA%\HSBG\HSBG.ini, which a user can always write to
;      without elevation, by definition.
;
; Whichever wins is logged at start-up and shown in the tray menu, so there is
; never a question about which file is actually being read.
;
; THE CACHE IS A `static`, NOT A FILE-SCOPE GLOBAL, AND THAT IS LOAD-BEARING.
;
; It was a global, declared `global _cfgPathResolved := ""` a couple of dozen
; lines BELOW the LoadUserConfig() call that starts all of this. A file-scope
; initializer runs when the auto-execute thread reaches THAT LINE -- so at the
; moment this function first ran, the variable did not exist yet. Reading an
; unset variable throws in AutoHotkey v2, the throw was caught by the blanket
; try in LoadUserConfig, and the entire settings file was silently ignored.
; Edit HSBG.ini, restart, nothing changes, no error, no log line.
;
; A static initializes on first call, so it cannot be outrun by the order of
; statements in the file. Nothing here may depend on where in the script it
; happens to sit.
_ConfigPath() {
    static cached := ""
    if (cached != "")
        return cached

    beside := A_ScriptDir . "\HSBG Config.ini"
    if (FileExist(beside) || _DirIsWritable(A_ScriptDir)) {
        cached := beside
        return cached
    }

    dir := A_AppData . "\HSBG"
    try {
        if !DirExist(dir)
            DirCreate(dir)
    }
    cached := (DirExist(dir) ? dir : A_AppData) . "\HSBG Config.ini"
    return cached
}

; Can a file actually be created here? Asked, not assumed -- the entire bug
; this guards against is a folder that looks fine and refuses the write.
_DirIsWritable(dir) {
    probe := dir . "\hsbg_write_test.tmp"
    try {
        f := FileOpen(probe, "w")
        if !f
            return false
        f.Close()
        FileDelete(probe)
        return true
    }
    return false
}

; Make sure the user can edit the file after we write it.
;
; Clears the read-only attribute, which a copy out of a downloads folder, a
; restored backup or an extracted archive can all set. Cheap, and it removes
; one more way for "I went to edit the config and it would not let me" to
; happen.
_MakeConfigEditable(path) {
    try FileSetAttrib("-R", path)
}

; Write the default settings file. Called only when it does not exist.
_WriteDefaultConfig(path) {
    txt := ""
    txt .= "; ============================================================================`r`n"
    txt .= ";  HSBG -- settings`r`n"
    txt .= "; ============================================================================`r`n"
    txt .= ";  Edit a value, save, then exit HSBG from the tray icon and start it again.`r`n"
    txt .= ";  AutoHotkey does not reload a running script, and this file is read once`r`n"
    txt .= ";  at start-up.`r`n"
    txt .= ";`r`n"
    txt .= ";  Every setting is 1 for on, 0 for off. Delete this file to get it back`r`n"
    txt .= ";  with the defaults.`r`n"
    txt .= "; ----------------------------------------------------------------------------`r`n"
    txt .= "`r`n"
    txt .= "[Settings]`r`n"
    txt .= "`r`n"
    txt .= "; MonitorLock -- default 1 (on)`r`n"
    txt .= ";`r`n"
    txt .= ";   1 = Battle.net, the Blizzard Update Agent, Hearthstone and the on-screen`r`n"
    txt .= ";       status text all open on the monitor you STARTED THIS SCRIPT ON.`r`n"
    txt .= ";       Start it on the screen you want to play on and everything follows.`r`n"
    txt .= ";   0 = every window opens wherever Windows and the applications decide,`r`n"
    txt .= ";       and the script never moves anything.`r`n"
    txt .= ";`r`n"
    txt .= ";   Makes no difference on a single-monitor machine: there is only one place`r`n"
    txt .= ";   for a window to be. Firestone's own windows are never covered by this --`r`n"
    txt .= ";   they stay wherever you put them, which is usually a second screen.`r`n"
    txt .= "MonitorLock=1`r`n"
    txt .= "`r`n"
    txt .= "; HotkeyAudio -- default 0 (off)`r`n"
    txt .= ";`r`n"
    txt .= ";   1 = play a short, deep guitar note when a hotkey fires, so you know a`r`n"
    txt .= ";       press registered without looking away from the game. All keys now`r`n"
    txt .= ";       sound the same unless you customise frequencies below.`r`n"
    txt .= ";   0 = silent.`r`n"
    txt .= ";`r`n"
    txt .= ";   The notes are generated on first use and cached, so enabling this adds`r`n"
    txt .= ";   about a second to one start-up and nothing afterwards.`r`n"
    txt .= "HotkeyAudio=0`r`n"
    txt .= "`r`n"
    txt .= "; HotkeyAudioVolume -- 0 to 100, default 25`r`n"
    txt .= ";   Ignored while HotkeyAudio=0.`r`n"
    txt .= "HotkeyAudioVolume=25`r`n"
    txt .= "`r`n"
    txt .= "; HotkeySoundFile -- optional custom .wav file to play for all hotkeys.`r`n"
    txt .= ";   If left empty, the built-in synthesised note is used (with frequencies`r`n"
    txt .= ";   configured below). The path must point to an existing PCM WAV file.`r`n"
    txt .= ";   If the file is missing, the script falls back to the default tone.`r`n"
    txt .= "HotkeySoundFile=`r`n"
    txt .= "`r`n"
    txt .= "; HotkeyFreqMode -- how frequencies are chosen for the built-in tones.`r`n"
    txt .= ";   `"singular`" = all hotkeys use the same frequency (set by HotkeyFreqSingular).`r`n"
    txt .= ";   `"varied`"   = each key uses its own frequency (HotkeyFreqF1..F4).`r`n"
    txt .= ";   Default: singular.`r`n"
    txt .= "HotkeyFreqMode=singular`r`n"
    txt .= "`r`n"
    txt .= "; HotkeyFreqSingular -- frequency in Hz for all keys when mode is `"singular`".`r`n"
    txt .= ";   Default: 110.0 (the F2 note). Must be a positive number.`r`n"
    txt .= "HotkeyFreqSingular=110.0`r`n"
    txt .= "`r`n"
    txt .= "; HotkeyFreqF1..F4 -- individual frequencies when mode is `"varied`".`r`n"
    txt .= ";   If left blank or set to 0, that key falls back to HotkeyFreqSingular.`r`n"
    txt .= ";   Defaults: F1=82.41, F2=110.00, F3=73.42, F4=55.00 (the original notes).`r`n"
    txt .= "HotkeyFreqF1=82.41`r`n"
    txt .= "HotkeyFreqF2=110.00`r`n"
    txt .= "HotkeyFreqF3=73.42`r`n"
    txt .= "HotkeyFreqF4=55.00`r`n"
    try FileAppend(txt, path, "UTF-8-RAW")
    _MakeConfigEditable(path)
}

; Read one integer setting. Returns the fallback for anything unparseable.
_CfgInt(path, key, fallback, lo, hi) {
    raw := ""
    try raw := IniRead(path, "Settings", key, "")
    raw := Trim(raw)
    if (raw = "")
        return fallback
    if !IsInteger(raw) {
        _FSLog("CONFIG " . key . "=" . raw . " is not a number -- using "
             . fallback)
        return fallback
    }
    v := Integer(raw)
    if (v < lo || v > hi) {
        _FSLog("CONFIG " . key . "=" . v . " is out of range " . lo . "-" . hi
             . " -- using " . fallback)
        return fallback
    }
    return v
}

; Read a floating-point setting with bounds.
_CfgFloat(path, key, fallback, lo, hi) {
    raw := ""
    try raw := IniRead(path, "Settings", key, "")
    raw := Trim(raw)
    if (raw = "")
        return fallback
    if !IsNumber(raw) {
        _FSLog("CONFIG " . key . "=" . raw . " is not a number -- using " . fallback)
        return fallback
    }
    v := Float(raw)
    if (v < lo || v > hi) {
        _FSLog("CONFIG " . key . "=" . v . " is out of range " . lo . "-" . hi
             . " -- using " . fallback)
        return fallback
    }
    return v
}

LoadUserConfig() {
    global CFG
    try {
        path := _ConfigPath()
        if !FileExist(path)
            _WriteDefaultConfig(path)
        if !FileExist(path)
            return

        CFG.lockWindowsToChosenMonitor := (_CfgInt(path, "MonitorLock", 1, 0, 1) = 1)
        CFG.hotkeyAudio                := (_CfgInt(path, "HotkeyAudio",  0, 0, 1) = 1)
        CFG.hotkeyAudioVolume          :=  _CfgInt(path, "HotkeyAudioVolume", 25, 0, 100)
        ; custom sound file
        try {
            CFG.hotkeySoundFile := Trim(IniRead(path, "Settings", "HotkeySoundFile", ""))
        } catch {
            CFG.hotkeySoundFile := ""
        }
        ; frequency mode
        try {
            CFG.hotkeyFreqMode := Trim(IniRead(path, "Settings", "HotkeyFreqMode", "singular"))
        } catch {
            CFG.hotkeyFreqMode := "singular"
        }
        if (CFG.hotkeyFreqMode != "singular" && CFG.hotkeyFreqMode != "varied")
            CFG.hotkeyFreqMode := "singular"
        ; frequency values
        try {
            CFG.hotkeyFreqSingular := _CfgFloat(path, "HotkeyFreqSingular", 110.0, 20.0, 2000.0)
        } catch {
            CFG.hotkeyFreqSingular := 110.0
        }
        try {
            CFG.hotkeyFreqF1 := _CfgFloat(path, "HotkeyFreqF1", 82.41, 20.0, 2000.0)
        } catch {
            CFG.hotkeyFreqF1 := 82.41
        }
        try {
            CFG.hotkeyFreqF2 := _CfgFloat(path, "HotkeyFreqF2", 110.0, 20.0, 2000.0)
        } catch {
            CFG.hotkeyFreqF2 := 110.0
        }
        try {
            CFG.hotkeyFreqF3 := _CfgFloat(path, "HotkeyFreqF3", 73.42, 20.0, 2000.0)
        } catch {
            CFG.hotkeyFreqF3 := 73.42
        }
        try {
            CFG.hotkeyFreqF4 := _CfgFloat(path, "HotkeyFreqF4", 55.0, 20.0, 2000.0)
        } catch {
            CFG.hotkeyFreqF4 := 55.0
        }

        _FSLog("CONFIG read " . path
             . " -- MonitorLock=" . (CFG.lockWindowsToChosenMonitor ? 1 : 0)
             . " HotkeyAudio="    . (CFG.hotkeyAudio ? 1 : 0)
             . " Volume="         .  CFG.hotkeyAudioVolume
             . " SoundFile="      .  CFG.hotkeySoundFile
             . " FreqMode="       .  CFG.hotkeyFreqMode)
    } catch as e {
        try _FSLog("CONFIG FAILED to load: " . e.Message
                 . " -- the settings file was NOT applied and the built-in"
                 . " defaults are in force. This line existing at all means"
                 . " something is wrong with the file or its folder.")
    }
}

; ==============================================================================
; SECTION 2: RUNTIME STATE
; ==============================================================================
;
; The script's shared memory: flags describing what is currently happening
; (is a launch in flight? is the Firestone lock on?), plus caches of things
; that are expensive to look up twice. Functions everywhere read and write
; these — when debugging "why did it think X?", the answer is one of these.
;

; Primary script state flags.
global State := {
    startupDone:             false,   ; true = startup cleanup ran; safe to prewarm rules
    lastF1End:               0,       ; TickCount when the last F1 cycle completed
    launcherHideActive:      false,   ; true = HideOverwolfLauncher timer is running
    f2Active:                false,   ; true = F2 launch pipeline is in progress
    fsMainLocked:            true,    ; true = force Firestone‑Main suppressed at all times
    hsHiddenLaunchActive:    false,   ; true = the post-launch placement watch is running
    hsHiddenLaunchUntil:     0,       ; TickCount ceiling for that watch
    fsLoadingSeen:           false,
    wsearchPaused:           false,   ; true = we stopped WSearch and owe it a restart
}

; State for the F1 cursor shield. While active (mode "F1") the #HotIf
; mouse‑swallower block below eats clicks/wheel over real HS windows only.
global InputShield := {
    active:  false,
    endTime: 0,
    mode:    "",   ; "F1" — for diagnostics only
}

; Resolved path/ID cache — populated lazily, cleared on HS restart.
global Cache := {
    hsPath:               "",
    owPath:               "",
    fsCmd:                "",
    fsAppId:              "",
    firestoneLookupDone:  false,
}

; Launch pipeline state machine.
global Launch := {
    state:              "IDLE",   ; IDLE | HAMMERING | LOGIN_WAIT | DONE
    retries:            0,
    lastAttempt:        0,
    sessionStart:       0,
    loginFallbackDone:  false,
    loginTitleCount:    0,
    skipLoginDetect:    false,    ; true on restart — BNet already authenticated
    bnetWasRunning:     false,
    loginEnteredAt:     0,        ; TickCount when LOGIN_WAIT was entered. Time the
                                  ; user spends typing credentials is credited back
                                  ; to sessionStart on exit from LOGIN_WAIT, so the
                                  ; launch ceiling never expires while the pipeline
                                  ; is simply waiting on a human.
}

; ── Launch‑monitor selection ────────────────────────────────────────────────
; The monitor the user launched the script on, resolved ONCE at startup by
; ResolveChosenMonitor() and then treated as authoritative for the HUD and for
; every window the script places. It survives the admin relaunch because the
; first (non‑elevated) instance hands the launch point to the elevated instance
; on the command line (/mon:x,y) — otherwise the elevated process would re‑detect
; its OWN window's monitor, which Windows drops on the PRIMARY screen.
global ChosenMonPt  := ""   ; "x,y" launch point in virtual‑screen coordinates
global ChosenMonIdx := 0    ; resolved 1‑based monitor index (0 = not yet resolved)

; ==============================================================================
; SECTION 3: HUD
; ==============================================================================
;
; The small on‑screen status text ("Launching...", "FS Unlocked", server
; addresses during F1). Built to update without flickering itself.
;

class BgHUD {
    static _gui  := 0
    static _text := 0

    static Hide(*) {
        BgHUD._text := 0
        if IsObject(BgHUD._gui) {
            try BgHUD._gui.Destroy()
            BgHUD._gui := 0
        }
        try SetTimer(BgHUD_AutoHide, 0)
    }

    static Show(msg, duration := 0) {
        if IsObject(BgHUD._gui) && IsObject(BgHUD._text) {
            try {
                if (BgHUD._text.Text != msg)
                    BgHUD._text.Text := msg
                try SetTimer(BgHUD_AutoHide, 0)
                ; Failsafe: duration 0 means "persist until Hide()" — but cap
                ; at 310s so a stuck launch toast never lingers forever.
                SetTimer(BgHUD_AutoHide, -(duration > 0 ? duration : 310000))
                return
            } catch {
            }
        }
        BgHUD._Create(msg, duration)
    }

    static _Create(msg, duration) {
        BgHUD.Hide()

        ; Pin the HUD to the launch monitor (ChosenMonIdx) if the config
        ; says so; otherwise follow Hearthstone's current monitor.
        global CFG
        if CFG.lockWindowsToChosenMonitor
            GetChosenMonitorBounds(&l, &t, &monW, &monH)
        else
            GetHSMonitorBounds(&l, &t, &monW, &monH)

        fs := Max(12, monH // 48)
        textW := fs * 25

        g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20", "BgHUD")
        ; -DPIScale: EVERY number below is already a physical pixel value,
        ; derived from the real monitor bounds via MonitorGet/SysGet, which
        ; AutoHotkey does not scale. A Gui scales what it is given by the
        ; monitor's DPI factor unless told not to, so leaving this off scaled
        ; the font, margins, width and the x/y position a SECOND time. At 100%
        ; scaling the factor is 1.0 and nothing was visibly wrong -- which is
        ; why it survived; at 125/150/200%, the settings most laptops and most
        ; single-monitor machines ship with, the HUD rendered oversized and
        ; well off its intended position, and at higher factors partly off the
        ; edge of the screen.
        g.Opt("-DPIScale")
        g.BackColor := "111111"
        g.MarginX   := fs // 2
        g.MarginY   := fs // 2
        g.SetFont("s" . fs . " cWhite Bold", "Arial")
        BgHUD._text := g.Add("Text", "w" . textW . " Center", msg)
        BgHUD._gui  := g

        g.Show("Hide")
        WinGetPos(, , &ww, , g)
        g.Show("x" . (l + (monW - ww) // 2) . " y" . (t + monH // 20) . " NoActivate")
        try WinSetTransColor("000000 180", g)

        ; Failsafe: duration 0 means "persist until Hide()" — but if a launch
        ; path aborts without hiding, the toast must not sit on screen forever.
        ; Cap at 310s (just past CFG.launchCeilingMs = 5 min, so it never cuts
        ; off a legitimate in‑progress launch toast — LOGIN_WAIT time is also
        ; credited back to the ceiling, but a toast surviving a marathon login
        ; is harmless, whereas one vanishing mid‑launch reads as a hang).
        SetTimer(BgHUD_AutoHide, -(duration > 0 ? duration : 310000))
    }
}

; One‑shot timer callback that hides the HUD after a duration expires.
BgHUD_AutoHide(*) => BgHUD.Hide()

; Helper: Returns the monitor index containing a given point (x, y).
GetMonitorIndexForPoint(x, y) {
    count := MonitorGetCount()
    loop count {
        i := A_Index
        MonitorGet(i, &left, &top, &right, &bottom)
        if (x >= left && x <= right && y >= top && y <= bottom)
            return i
    }
    return MonitorGetPrimary()
}

; Resolves the monitor bounds to use for the HUD when not locked to the
; launch monitor. Prefers Hearthstone's real window, falling back to the
; launch monitor if HS is not yet visible.
GetHSMonitorBounds(&l, &t, &monW, &monH) {
    l := 0, t := 0
    monIdx := 0
    try {
        prevDHW := A_DetectHiddenWindows
        DetectHiddenWindows true
        for hwnd in WinGetList("ahk_exe Hearthstone.exe") {
            try {
                if IsIMEWindow(hwnd)
                    continue
                if (WinGetTitle("ahk_id " . hwnd) != "Hearthstone")
                    continue
                if (WinGetMinMax("ahk_id " . hwnd) = -1)
                    continue
                WinGetPos(&hx, &hy, &hw, &hh, "ahk_id " . hwnd)
                if (hw > 100 && hh > 100) {
                    monIdx := GetMonitorIndexForPoint(hx + hw // 2, hy + hh // 2)
                    break
                }
            }
        }
        DetectHiddenWindows prevDHW
    }
    if !monIdx
        monIdx := GetScriptMonitor()
    try {
        MonitorGet(monIdx, &mL, &mT, &mR, &mB)
        l := mL, t := mT, monW := mR - mL, monH := mB - mT
    } catch {
        monW := SysGet(78)
        monH := SysGet(79)
    }
}

; Returns the monitor the user launched the script on (cached from
; ResolveChosenMonitor). Used as the anchor for all window placement.
GetScriptMonitor() {
    global ChosenMonIdx
    return ChosenMonIdx ? ChosenMonIdx : MonitorGetPrimary()
}

; Monitor of the current foreground window, or 0 if none is usable. Shell /
; desktop surfaces (Progman, WorkerW, taskbars) span monitors or sit on fixed
; ones and say nothing about where the user is working, so they're excluded,
; as are minimized windows and tiny helpers.
_ForegroundWindowMonitor() {
    fg := DllCall("user32\GetForegroundWindow", "Ptr")
    if !fg
        return 0
    try {
        cls := WinGetClass("ahk_id " . fg)
        if (cls = "Progman" || cls = "WorkerW"
         || cls = "Shell_TrayWnd" || cls = "Shell_SecondaryTrayWnd")
            return 0
        if (WinGetMinMax("ahk_id " . fg) = -1)
            return 0
        WinGetPos(&x, &y, &w, &h, "ahk_id " . fg)
        if (w < 50 || h < 50)
            return 0
        return GetMonitorIndexForPoint(x + w // 2, y + h // 2)
    } catch {
    }
    return 0
}

; Resolve — once — the monitor the user launched on and cache it in ChosenMonPt
; / ChosenMonIdx. Everything monitor‑aware reads those, so the whole session
; agrees on one screen no matter where the elevated process's own window lands.
;
; Anchor priority:
;   1. /mon:x,y command‑line arg — the pre‑elevation instance hands its
;      resolved point to the elevated relaunch. Always authoritative.
;   2. The FOREGROUND WINDOW's monitor — the Explorer window / terminal /
;      whatever the user launched the script from. This is the real "where I
;      opened the script" signal, and it survives elevation: after the UAC
;      consent, Windows re‑activates the window that was foreground before
;      the prompt. A short settle loop covers the moment right after UAC when
;      focus is still being handed back.
;   3. The cursor position — last resort only.
;   4. The primary monitor.
ResolveChosenMonitor() {
    global ChosenMonPt, ChosenMonIdx

    ; (1) Elevated relaunch hands us the original launch point.
    for a in A_Args {
        if (SubStr(a, 1, 5) = "/mon:") {
            p := StrSplit(SubStr(a, 6), ",")
            if (p.Length = 2) {
                ChosenMonPt  := SubStr(a, 6)
                ChosenMonIdx := GetMonitorIndexForPoint(p[1] + 0, p[2] + 0)
                return
            }
        }
    }

    ; (2) Foreground‑window monitor, with a short settle loop for the
    ;     just‑after‑UAC focus handback.
    deadline := A_TickCount + 1200
    loop {
        idx := _ForegroundWindowMonitor()
        if idx {
            ChosenMonIdx := idx
            try {
                MonitorGet(idx, &mL, &mT, &mR, &mB)
                ChosenMonPt := (mL + (mR - mL) // 2) . "," . (mT + (mB - mT) // 2)
            }
            return
        }
        if (A_TickCount >= deadline)
            break
        Sleep(50)
    }

    ; (3) Cursor — last resort. Save/restore CoordMode so we never disturb the
    ;     rest of the script's mouse math.
    try {
        oldCM := CoordMode("Mouse", "Screen")
        MouseGetPos(&mx, &my)
        CoordMode("Mouse", oldCM)
        ChosenMonPt := mx . "," . my
    }

    p := StrSplit(ChosenMonPt, ",")
    if (p.Length = 2)
        ChosenMonIdx := GetMonitorIndexForPoint(p[1] + 0, p[2] + 0)
    else
        ChosenMonIdx := MonitorGetPrimary()   ; (4) final fallback
}

; Full‑monitor bounds of the launch‑chosen monitor — used to pin the HUD there.
GetChosenMonitorBounds(&l, &t, &w, &h) {
    global ChosenMonIdx
    idx := ChosenMonIdx ? ChosenMonIdx : MonitorGetPrimary()
    try {
        MonitorGet(idx, &mL, &mT, &mR, &mB)
        l := mL, t := mT, w := mR - mL, h := mB - mT
    } catch {
        l := 0, t := 0, w := SysGet(78), h := SysGet(79)
    }
}

; ------------------------------------------------------------------------------
; Per‑process mute/unmute for Hearthstone via Windows Core Audio session control.
; This targets the audio session owned by Hearthstone.exe specifically.
; It does NOT mute system audio globally, and — critically — it NEVER touches
; any HS window, so it cannot trigger Windows IME/TSF helper‑window popups.
; ------------------------------------------------------------------------------
; NOTE: there is no MuteHearthstone. The game is no longer concealed during the
; launch, so there is no longer a window of time in which the user can hear a
; game they cannot see. Only the UNMUTE survives, as a repair for a mute left
; behind by an earlier build of this script.
; ══════════════════════════════════════════════════════════════════════════════
;  HOTKEY TONES — a deep guitar note per key
; ══════════════════════════════════════════════════════════════════════════════
; Off by default; switched on with HotkeyAudio=1 in HSBG.ini.
;
; WHY THESE ARE SYNTHESISED RATHER THAN BEEPED. SoundBeep drives the system beep
; with a square wave: it is thin, piercing, and at the low frequencies wanted
; here it sounds like a fault rather than a note. An earlier build used it and
; the verdict was that the beeps "suck" -- which was fair, and was about the
; waveform, not the idea.
;
; A plucked, overdriven bass string is a specific and reproducible shape, so it
; is built rather than approximated:
;
;   * Harmonics 1-5, amplitude 1/n, each decaying FASTER than the one below it.
;     That falling-brightness-over-time is what the ear reads as a plucked
;     string rather than an organ.
;   * Soft clipping (s - s^3/3, hard-limited past unity). This is the classic
;     valve-overdrive curve: it adds odd harmonics and compresses the peak, so
;     the note reads as "heavy" without turning into buzz.
;   * A 5ms attack, so the note starts with a pick edge instead of a click, and
;     a slow overall decay so it rings rather than blips.
;
; Frequencies are the bottom of a guitar in drop tuning -- 55Hz to 110Hz, all
; below the range of anything in Hearthstone's own mix, which is the point: the
; note has to be audible over the game without competing with it.
;
; Generated once into %TEMP% and cached on disk, so the cost is about a second
; on ONE start-up and nothing thereafter. Nothing here ever runs when the
; feature is off, and every part of it is wrapped -- an audio failure must never
; be able to stop a hotkey doing its actual job.
global _toneFiles := Map()

_ToneFreq(which) {
    global CFG
    if (CFG.hotkeyFreqMode = "varied") {
        ; map which to the corresponding config key
        static map := Map("F1", "hotkeyFreqF1"
                        , "F2", "hotkeyFreqF2"
                        , "F3", "hotkeyFreqF3"
                        , "F4", "hotkeyFreqF4")
        key := map.Get(which, "")
        if (key != "" && CFG.%key% > 0)
            return CFG.%key%
        ; fall through to singular if individual is 0 or missing
    }
    ; singular mode or fallback
    return CFG.hotkeyFreqSingular ? CFG.hotkeyFreqSingular : 110.0
}

; Build one 16-bit mono WAV of a plucked, overdriven low string.
_WriteGuitarWav(path, freq, durMs, vol) {
    static SR := 22050          ; twice the highest harmonic we generate, and
                                ; half the samples of CD rate -- for a 110Hz
                                ; note with 5 harmonics that is ample.
    n     := Round(SR * durMs / 1000)
    bytes := n * 2
    buf   := Buffer(44 + bytes, 0)

    NumPut("UInt",   0x46464952, buf,  0)   ; "RIFF"
    NumPut("UInt",   36 + bytes, buf,  4)
    NumPut("UInt",   0x45564157, buf,  8)   ; "WAVE"
    NumPut("UInt",   0x20746D66, buf, 12)   ; "fmt "
    NumPut("UInt",   16,         buf, 16)   ; PCM header size
    NumPut("UShort", 1,          buf, 20)   ; format = PCM
    NumPut("UShort", 1,          buf, 22)   ; channels = mono
    NumPut("UInt",   SR,         buf, 24)   ; sample rate
    NumPut("UInt",   SR * 2,     buf, 28)   ; byte rate
    NumPut("UShort", 2,          buf, 32)   ; block align
    NumPut("UShort", 16,         buf, 34)   ; bits per sample
    NumPut("UInt",   0x61746164, buf, 36)   ; "data"
    NumPut("UInt",   bytes,      buf, 40)

    twoPi := 6.283185307179586
    Loop n {
        ; The outer index is CAPTURED, not read twice.
        ;
        ; A_Index belongs to the innermost enclosing loop, so every read of it
        ; after the harmonic loop below is a read of a value that loop was also
        ; writing. AutoHotkey does restore it -- but a sample buffer whose write
        ; offset depends on that restore working is a buffer that is silently
        ; wrong if it ever does not. One local removes the question.
        i := A_Index
        t := (i - 1) / SR

        ; Harmonic stack. Higher partials decay faster -- a real string loses
        ; its brightness long before it loses its fundamental.
        s := 0.0
        Loop 5 {
            k    := A_Index
            amp  := (1.0 / k) * Exp(-t * 2.2 * k)
            s    += amp * Sin(twoPi * freq * k * t)
        }

        ; Valve-style soft clip: drive it, then round the peaks off.
        s *= 1.9
        if (s > 1.0)
            s := 1.0
        else if (s < -1.0)
            s := -1.0
        else
            s := s - (s * s * s) / 3.0

        ; 5ms pick attack, then a slow ring-out.
        env := (t < 0.005) ? (t / 0.005) : Exp(-t * 3.0)

        ; RELEASE TAPER over the final 80ms.
        ; The exponential decay above is still at roughly a fifth of full
        ; amplitude when the buffer runs out, and a waveform that stops at a
        ; non-zero value is a step change -- which is a click. The taper walks
        ; the last 80ms to true zero so the note ends instead of being cut off.
        rel := (durMs / 1000.0) - t
        if (rel < 0.08)
            env *= (rel > 0) ? (rel / 0.08) : 0

        v := Round(s * env * 30000 * vol)
        if (v >  32767)
            v :=  32767
        else if (v < -32768)
            v := -32768
        NumPut("Short", v, buf, 44 + (i - 1) * 2)
    }

    f := FileOpen(path, "w")
    if !f {
        _FSLog("AUDIO could not open " . path . " for writing")
        return false
    }
    f.RawWrite(buf, buf.Size)
    f.Close()
    return FileExist(path) ? true : false
}

; Build all four notes if they are not already on disk. Safe to call twice.
; All notes are generated with the frequency returned by _ToneFreq(which),
; which is now configurable. The volume is controlled by CFG.hotkeyAudioVolume.
;
; Logs what it did rather than only that it finished. "Nothing happened when I
; turned the sound on" is impossible to diagnose from a line that says
; everything is fine, so this records the file, its size, and any step that
; failed -- and reports a count of what actually exists rather than a count of
; what it attempted.
EnsureHotkeyTones() {
    global CFG, _toneFiles
    if !CFG.hotkeyAudio {
        _FSLog("AUDIO EnsureHotkeyTones called with hotkeyAudio OFF -- nothing"
             . " to build. If you set HotkeyAudio=1, the script did not read"
             . " the file you edited: check the CONFIG line above for the path"
             . " it actually used.")
        return
    }
    vol   := CFG.hotkeyAudioVolume / 100.0
    built := 0
    for which in ["F1", "F2", "F3", "F4"] {
        try {
            freq := _ToneFreq(which)
            ; The volume and frequency are in the filename so a changed setting
            ; regenerates instead of silently playing the old tone.
            path := A_Temp . "\hsbg_tone_" . which . "_"
                  . Round(freq * 100) . "_" . CFG.hotkeyAudioVolume . ".wav"
            if !FileExist(path)
                _WriteGuitarWav(path, freq, 550, vol)
            if FileExist(path) {
                _toneFiles[which] := path
                built += 1
            } else {
                _FSLog("AUDIO " . which . " could not be built at " . path)
            }
        } catch as e {
            _FSLog("AUDIO " . which . " generation threw: " . e.Message)
        }
    }
    _FSLog("AUDIO " . built . " of 4 hotkey notes ready, volume "
         . CFG.hotkeyAudioVolume . " (files in " . A_Temp . ")")
}

; Play the note for a hotkey.
;
; NEVER BLOCKS THE KEY. Everything is pushed onto its own thread by the -1
; timer: building a waveform takes a moment and even SoundPlay touches the
; audio engine, and F1's job is to skip a combat animation, not to wait for a
; sound card. A press whose note is late is fine; a press that is late is not.
_HotkeyTone(which) {
    global CFG
    if !CFG.hotkeyAudio
        return
    try SetTimer(_PlayHotkeyTone.Bind(which), -1)
}

_PlayHotkeyTone(which) {
    global CFG, _toneFiles
    ; If a custom sound file is specified and exists, play it for any hotkey.
    if (CFG.hotkeySoundFile != "" && FileExist(CFG.hotkeySoundFile)) {
        try {
            SoundPlay(CFG.hotkeySoundFile)
            return
        } catch {
            ; fall through to default if custom file fails
        }
    }

    if _toneFiles.Has(which) {
        try SoundPlay(_toneFiles[which])
        return
    }
    ; Not built yet -- the start-up build may not have run, or may have failed.
    ; Build now, and if that still produces nothing, fall back to the system
    ; beep at the same pitch. A thin beep is a poor note but it is unambiguous
    ; evidence that the setting is on and the script is trying, which is far
    ; more useful than silence.
    try EnsureHotkeyTones()
    if _toneFiles.Has(which) {
        try SoundPlay(_toneFiles[which])
        return
    }
    try SoundBeep(Round(_ToneFreq(which)), 150)
}

; Tray-menu diagnostic. Answers "I turned it on and nothing happened" in one
; click, on screen, without asking anyone to read a log file.
; ── "WHAT IS UNDER MY CURSOR?" ──────────────────────────────────────────────
; Hold the cursor over the spot where clicks are being lost and pick this from
; the tray. It names the window that will actually receive the click.
;
; This exists because "clicks do not register" has several possible causes that
; look identical from the outside -- an invisible cloaked window sitting over
; the game, the game not being foreground, or the script's own F1 mouse shield
; being active -- and guessing between them from a description has cost several
; rounds. This reports all three at once, from the same call, in the state they
; are in at the moment of the complaint.
;
; A five-second countdown first, so there is time to move the cursor onto the
; game after picking the menu item.
WhatIsUnderCursor() {
    BgHUD.Show("Move the cursor over the spot that will not click — reading in 5s", 5000)
    SetTimer(_WhatIsUnderCursorNow, -5000)
}

_WhatIsUnderCursorNow() {
    global InputShield, _ipBlockOn
    try {
        MouseGetPos(&mx, &my, &hwnd)
        if !hwnd {
            BgHUD.Show("No window under the cursor", 6000)
            return
        }
        title := "", cls := "", exe := "", ex := 0, st := 0
        try title := WinGetTitle("ahk_id " . hwnd)
        try cls   := WinGetClass("ahk_id " . hwnd)
        try exe   := WinGetProcessName("ahk_id " . hwnd)
        try ex    := WinGetExStyle("ahk_id " . hwnd)
        try st    := WinGetStyle("ahk_id " . hwnd)
        cloaked := IsWindowCloakedDWM(hwnd) ? "YES" : "no"
        topmost := (ex & 0x8) ? "YES" : "no"
        thru    := (ex & 0x20) ? "YES" : "no"
        fg      := DllCall("user32\GetForegroundWindow", "Ptr")

        msg := exe . "  |  cloaked=" . cloaked . "  topmost=" . topmost
             . "  |  " . (hwnd = fg ? "has focus" : "NOT the foreground window")
        BgHUD.Show(msg, 10000)

        _FSLog("CURSOR-PROBE at " . mx . "," . my
             . " hwnd=" . hwnd
             . " exe=" . exe
             . " title=`"" . title . "`""
             . " class=" . cls
             . " ex=" . Format("0x{:X}", ex)
             . " style=" . Format("0x{:X}", st)
             . " cloaked=" . cloaked
             . " topmost=" . topmost
             . " clickthrough=" . thru
             . " isForeground=" . (hwnd = fg ? 1 : 0)
             . " | shield.active=" . (InputShield.active ? 1 : 0)
             . " shield.mode=" . InputShield.mode
             . " ipBlockOn=" . (_ipBlockOn ? 1 : 0))
    }
}

TestHotkeySound() {
    global CFG, _toneFiles
    if !CFG.hotkeyAudio {
        BgHUD.Show("Sound is OFF in " . _ConfigPath(), 6000)
        _FSLog("AUDIO test: hotkeyAudio is FALSE. Config read from "
             . _ConfigPath())
        return
    }
    EnsureHotkeyTones()
    if !_toneFiles.Has("F2") {
        BgHUD.Show("Sound ON but the note could not be built — see the log", 6000)
        return
    }
    BgHUD.Show("Playing F2 note — volume " . CFG.hotkeyAudioVolume, 2500)
    try SoundPlay(_toneFiles["F2"])
}

UnmuteHearthstone() {
    pid := GetHSPID()
    if !pid
        return false
    return SetAppMuteByPID(pid, false)
}

SetAppMuteByPID(targetPID, mute := true) {
    static CLSID_MMDeviceEnumerator  := "{BCDE0395-E52F-467C-8E3D-C4579291692E}"
    static IID_IMMDeviceEnumerator   := "{A95664D2-9614-4F35-A746-DE8DB63617E6}"
    static IID_IAudioSessionManager2 := "{77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F}"
    static IID_IAudioSessionControl2 := "{bfb7ff88-7239-4fc9-8fa2-07c950be9c6d}"
    static IID_ISimpleAudioVolume    := "{87CE5498-68D6-44E5-9215-6DA47EF883D8}"

    deviceEnumerator := 0
    defaultDevice    := 0
    sessionManager2  := 0
    sessionEnum      := 0
    count            := 0
    matched          := false

    try {
        deviceEnumerator := ComObject(CLSID_MMDeviceEnumerator, IID_IMMDeviceEnumerator)
        if !deviceEnumerator
            return false

        ; IMMDeviceEnumerator::GetDefaultAudioEndpoint(eRender=0, eMultimedia=1)
        ComCall(4, deviceEnumerator, "Int", 0, "Int", 1, "Ptr*", &defaultDevice := 0)
        if !defaultDevice
            return false

        ; IMMDevice::Activate(IID_IAudioSessionManager2, CLSCTX_ALL=23)
        ComCall(3, defaultDevice, "Ptr", _FwGUID(IID_IAudioSessionManager2), "UInt", 23, "Ptr", 0, "Ptr*", &sessionManager2 := 0)
        if !sessionManager2
            return false

        ; IAudioSessionManager2::GetSessionEnumerator
        ComCall(5, sessionManager2, "Ptr*", &sessionEnum := 0)
        if !sessionEnum
            return false

        ; IAudioSessionEnumerator::GetCount
        ComCall(3, sessionEnum, "Int*", &count := 0)

        loop count {
            idx             := A_Index - 1
            sessionControl  := 0
            sessionControl2 := 0
            simpleVolume    := 0
            pid             := 0

            try {
                ComCall(4, sessionEnum, "Int", idx, "Ptr*", &sessionControl := 0)
                if !sessionControl
                    continue

                sessionControl2 := ComObjQuery(sessionControl, IID_IAudioSessionControl2)
                if !sessionControl2
                    continue

                ; IAudioSessionControl2::GetProcessId
                ComCall(14, sessionControl2, "UInt*", &pid := 0)
                if (pid != targetPID)
                    continue

                simpleVolume := ComObjQuery(sessionControl2, IID_ISimpleAudioVolume)
                if !simpleVolume
                    continue

                ; ISimpleAudioVolume::SetMute(BOOL, LPCGUID)
                ComCall(5, simpleVolume, "Int", mute ? 1 : 0, "Ptr", 0)
                matched := true
            } catch {
            }

            if simpleVolume
                ObjRelease(simpleVolume)
            if sessionControl2
                ObjRelease(sessionControl2)
            if sessionControl
                ObjRelease(sessionControl)
        }
    } catch {
        matched := false
    }

    if sessionEnum
        ObjRelease(sessionEnum)
    if sessionManager2
        ObjRelease(sessionManager2)
    if defaultDevice
        ObjRelease(defaultDevice)

    return matched
}

; Helper — converts a GUID string to a 16‑byte buffer for COM calls.
_FwGUID(str) {
    buf := Buffer(16, 0)
    DllCall("Ole32\CLSIDFromString", "WStr", str, "Ptr", buf.Ptr)
    return buf
}

; ==============================================================================
; SECTION 5: PROCESS MANAGER — HS / BNet / Overwolf queries
; ==============================================================================
;
; "Is it running? Where is its .exe? What windows does it own? Kill it."
; Everything above the window layer asks these questions here, so path
; lookups and process checks live in exactly one place.
;

GetHSPID() => ProcessExist("Hearthstone.exe")

; Returns true if any real Hearthstone window exists (including hidden ones).
HSWindowExists() {
    return GetHSRealWindows().Length > 0
}

; Returns real HS top‑level windows only.
; Filters out IME/TSF helper windows and tiny utility windows so the shield
; follows the actual HS game window.
GetHSRealWindows() {
    windows := []
    prev := A_DetectHiddenWindows
    DetectHiddenWindows true

    for hwnd in WinGetList("ahk_exe Hearthstone.exe") {
        if IsIMEWindow(hwnd)
            continue

        try {
            cls := WinGetClass("ahk_id " . hwnd)
        } catch {
            cls := ""
        }

        if (cls = "IME" || cls = "MSCTFIME UI")
            continue

        try {
            WinGetPos(&x, &y, &w, &h, "ahk_id " . hwnd)
        } catch {
            continue
        }

        if (w <= 2 || h <= 2)
            continue

        windows.Push(hwnd)
    }

    DetectHiddenWindows prev
    return windows
}


; ── THE #HotIf FOR THE MOUSE SHIELD. IT MUST BE CHEAP AND IT MUST BE EXACT. ──
;
; This expression is evaluated by AutoHotkey's INPUT HOOK on every single mouse
; click, before the click is delivered. The hook has a short deadline: an
; expression that takes too long is abandoned and the PREVIOUS result is reused,
; and while it is running no input is processed at all. The symptom of getting
; that wrong is unmistakable and was reported -- clicks stop registering, and
; come back only when the cursor crosses into a different window and forces the
; criterion to be re-evaluated.
;
; Two rules follow, and both are load-bearing:
;
;   1. THE CHEAPEST TEST FIRST. _ipBlockOn is a plain boolean and is the real
;      precondition: the shield exists to stop a stray click during an F1
;      firewall block, so with no block in place there is nothing to shield.
;      With this first, the expensive part below is unreachable except during
;      the two seconds of an actual F1 press.
;
;   2. NO WINDOW ENUMERATION. MouseIsOverRealHSWindow used to call
;      GetHSRealWindows, which enumerates every Hearthstone window and queries
;      the class and rectangle of each -- inside the hook, per click. It is
;      replaced by a single process-ID comparison on the window under the
;      cursor, which is one call and answers the same question.
HS_MouseShieldActive() {
    global InputShield, _ipBlockOn
    if !(_ipBlockOn && InputShield.active && InputShield.mode = "F1")
        return false
    return _MouseIsOverHSProcess()
}

; Is the cursor over a window belonging to Hearthstone? One WindowFromPoint plus
; one GetWindowThreadProcessId -- no enumeration, no title reads, no
; DetectHiddenWindows toggling. Safe to run inside the input hook.
_MouseIsOverHSProcess() {
    try {
        pid := GetHSPID()
        if !pid
            return false
        MouseGetPos(, , &hwnd)
        if !hwnd
            return false
        wpid := 0
        DllCall("user32\GetWindowThreadProcessId", "Ptr", hwnd, "UInt*", &wpid)
        return (wpid = pid)
    }
    return false
}

; F1 cursor shield: swallow clicks/wheel only while the cursor is over a real
; HS window. Deliberately NOT implemented via WinSetEnabled — disabling a
; focused window makes Windows strip its focus and hand the foreground to the
; next top‑level window (often on the other monitor), which is exactly the
; "F1 steals focus" behavior an earlier build exhibited.
#HotIf HS_MouseShieldActive()
*LButton::return
*RButton::return
*MButton::return
*WheelUp::return
*WheelDown::return
*WheelLeft::return
*WheelRight::return
#HotIf

; Returns the path of the running Hearthstone.exe, or "" if unavailable.
; Result is cached in Cache.hsPath and cleared on HS restart.
GetHSPath(hsPID := 0) {
    global Cache
    if (Cache.hsPath != "")
        return Cache.hsPath
    if !hsPID
        hsPID := GetHSPID()
    if !hsPID
        return ""
    try Cache.hsPath := ProcessGetPath(hsPID)
    catch
        return ""
    return Cache.hsPath
}

; Returns true only if the FIRESTONE APP is actually up: Overwolf is running
; AND at least one Overwolf‑family window whose title starts with "Firestone"
; exists (Main, Loading, Overlays, Battlegrounds, or the bare‑"Firestone"
; decorations — any of them proves the extension is loaded).
FirestoneAppRunning() {
    if !ProcessExist("Overwolf.exe")
        return false
    found := false
    prev     := A_DetectHiddenWindows
    prevMode := A_TitleMatchMode
    DetectHiddenWindows true
    SetTitleMatchMode(1)   ; prefix match: "Firestone", "Firestone - Main", ...
    try {
        for exe in ["Overwolf.exe", "OverwolfBrowser.exe"] {
            for h in WinGetList("ahk_exe " . exe) {
                try {
                    if (SubStr(WinGetTitle("ahk_id " . h), 1, 9) = "Firestone") {
                        found := true
                        break
                    }
                }
            }
            if found
                break
        }
    }
    DetectHiddenWindows prev
    SetTitleMatchMode prevMode
    return found
}

; Resolve Battle.net Launcher.exe path via registry, then hard‑coded fallback.
GetBNetExec() {
    static exe := ""
    if (exe != "")
        return exe
    for regPath in [
        "HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Battle.net",
        "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Battle.net",
    ] {
        try {
            ico  := RegRead(regPath, "DisplayIcon")
            cand := StrReplace(ico, "Battle.net.exe", "Battle.net Launcher.exe")
            if FileExist(cand) {
                exe := cand
                return exe
            }
        }
    }
    fallback := "C:\Program Files (x86)\Battle.net\Battle.net Launcher.exe"
    if FileExist(fallback)
        exe := fallback
    return exe
}

; Resolve Battle.net Launcher.exe from common install paths (no registry).
GetBattleNetPath() {
    for path in [
        "C:\Program Files (x86)\Battle.net\Battle.net Launcher.exe",
        "C:\Program Files\Battle.net\Battle.net Launcher.exe",
    ] {
        if FileExist(path)
            return path
    }
    return ""
}

; Launch Hearthstone (WTCG) via the Battle.net protocol handler.
;
; Resolves the Battle.net Launcher.exe path through multiple mechanisms so
; installs outside the default Program Files locations work automatically.
LaunchWTCG() {
    exe := ""

    ; (1) Live‑process derivation — works for any install location.
    bnetPID := ProcessExist("Battle.net.exe")
    if bnetPID {
        try {
            runningPath := ProcessGetPath(bnetPID)
            if (runningPath != "") {
                cand := StrReplace(runningPath, "Battle.net.exe", "Battle.net Launcher.exe")
                if FileExist(cand)
                    exe := cand
            }
        }
    }

    ; (2) Registry‑aware lookup.
    if (exe = "")
        exe := GetBNetExec()

    ; (3) Hardcoded Program Files fallbacks.
    if (exe = "")
        exe := GetBattleNetPath()

    if (exe != "" && FileExist(exe)) {
        ; Only ever reached through TryLaunchWTCG's gate: by now the REAL
        ; Battle.net client window has been VISIBLE for CFG.bnetRevealDwellMs
        ; -- so this behaves like a human pressing Play in a fully drawn
        ; launcher. (Service surfaces stay hidden throughout; see the
        ; Battle.net window policy.)
        try Run('"' . exe . '" --exec="launch WTCG"')
    } else {
        ; Last resort: no launcher executable could be resolved. The battlenet://
        ; protocol reaches any registered installation, so the pipeline still makes
        ; progress rather than retrying a no-op until the ceiling.
        try Run("battlenet://WTCG")
    }
}

; ── Battle.net-first launch sequencing ────────────────────────────────────────
; The F2 pipeline no longer fires the WTCG launch blindly. The order is:
;   1. the bare Battle.net CLIENT is started (no game command); the services
;      blanket hides its splash / auto-login / maintenance surfaces, while
;      the REAL client window appears normally on the chosen monitor;
;   2. the gate waits until that real window is present AND VISIBLE (hidden
;      look-alikes such as the auto-login shell do not count); it renders
;      UNFOCUSED -- no focus steal, no active-window highlight;
;   3. it renders on screen for CFG.bnetRevealDwellMs -- the user watches
;      the launcher come up fully;
;   4. only THEN is the "launch WTCG" command fired — the visible launcher
;      launches Hearthstone exactly like a human press of Play;
;   5. the launcher is minimized animation-free the INSTANT the command
;      fires -- the navigation to the game page and its Play-press outline
;      render off-screen; HS-PID minimize + watchdog remain as backstops.
; TryLaunchWTCG() is the single gate every pipeline call site goes through; it
; returns true only when the real launch command actually fired.

; Start the bare Battle.net client (no game command). Returns true if the
; client is running or a start was initiated.
StartBNetClient() {
    if ProcessExist("Battle.net.exe")
        return true
    exe := GetBNetExec()
    if (exe = "")
        exe := GetBattleNetPath()
    if (exe != "" && FileExist(exe)) {
        ; Plain boot (the deep-link arg is ignored by this client build --
        ; field-confirmed: it lands on HOME regardless). There is no longer a
        ; hidden pre-navigate stage: TryLaunchWTCG boots the client, waits for
        ; the real launcher window, lets it render for bnetRevealDwellMs, and
        ; only then fires the WTCG launch command. The client's navigation to
        ; the game page is covered by bnetPostPlayLingerMs (0 = minimize the
        ; instant the command fires, so it renders off-screen).
        ; Pass the deep link anyway. On client builds that honour it, the
        ; launcher boots straight onto the Hearthstone page and the navigation
        ; settle below has nothing to hide. On builds that ignore it (this one,
        ; per the note above) it is harmless, and the cloak-through-navigation
        ; in TryLaunchWTCG covers the case regardless.
        try Run('"' . exe . '" --exec="launch WTCG"')
        return true
    }
    return false
}

; "Launcher READY" gate check: true only when the REAL Battle.net client
; window (_IsProtectedBNetMain) is present AND VISIBLE. The hidden auto-login
; shell shares the "Battle.net" title; anchoring the render dwell to it made
; the dwell expire during the invisible auto-login, so the real launcher got
; zero on-screen time before the WTCG launch and the minimize.
; Starvation fallback: if a VISIBLE launcher-titled window has been on screen
; for 8s straight without qualifying (a client build without a resize
; frame), accept it anyway -- the pipeline can never stall at this gate.
BNetMainWindowExists() {
    static firstTitledSeen := 0
    if !ProcessExist("Battle.net.exe") {
        firstTitledSeen := 0
        return false
    }
    found := false
    sawTitledVisible := false
    ; This function's contract is "the real client window exists, hidden or not",
    ; and it is called from the state-machine timer thread where
    ; DetectHiddenWindows defaults to OFF. Without setting it explicitly,
    ; WinGetList silently skips every hidden window and the contract is not
    ; honoured: while the services blanket has the launcher concealed this would
    ; return false indefinitely and the launch command would never fire.
    prevDHW := A_DetectHiddenWindows
    DetectHiddenWindows true
    try {
        for hwnd in WinGetList("ahk_exe Battle.net.exe") {
            try {
                if IsHelperWindow(hwnd)
                    continue
                ; Do NOT require visibility: the launcher now boots hidden
                ; by design, so "ready" means the real client WINDOW exists
                ; (hidden or not). The reveal will show it.
                if _IsProtectedBNetMain(hwnd) {
                    found := true
                    break
                }
                if !DllCall("user32\IsWindowVisible", "Ptr", hwnd)
                    continue
                title := WinGetTitle("ahk_id " . hwnd)
                if (title = "Battle.net" || title = "Blizzard Battle.net")
                    sawTitledVisible := true
            }
        }
    }
    DetectHiddenWindows prevDHW
    if found {
        firstTitledSeen := 0
        return true
    }
    if sawTitledVisible {
        if !firstTitledSeen
            firstTitledSeen := A_TickCount
        else if (A_TickCount - firstTitledSeen > 8000)
            return true
    } else {
        firstTitledSeen := 0
    }
    return false
}

; The launch gate (see the sequencing note above): steps the pipeline through
; client-start -> reveal -> render dwell, and fires LaunchWTCG only at the end.
; Cheap when its stage is already satisfied, so it is safe to call every tick.
TryLaunchWTCG() {
    global CFG, _bnetRevealedAt, _bnetLaunchFiredAt, _bnetPlayFiredAt, _bnetPostMinDone
    global _bnetReadyAt
    global _bnetLauncherHwnd
    if !ProcessExist("Battle.net.exe") {
        if StartBNetClient()
            return false          ; client booting — step again next tick
        LaunchWTCG()              ; no client path found: legacy protocol boot
        return true
    }

    ; ══════════════════════════════════════════════════════════════════════
    ; The launcher itself is never concealed
    ; ══════════════════════════════════════════════════════════════════════
    ; Only Battle.net's SERVICE surfaces are kept off the screen -- the boot
    ; splash, the auto-login shell, maintenance overlays and every Update Agent
    ; window -- and that is handled by the services blanket in _HideBlizzWindow,
    ; not here.
    ;
    ; The client window itself opens normally, on the chosen monitor, navigates
    ; to the Hearthstone page and presses Play in full view, and minimises with
    ; the shell's own animation once the game has launched. There is nothing to
    ; hide about a launcher that is doing exactly what the user asked it to.
    ;
    ; Stages: exists -> place -> fire launch -> (minimise, owned elsewhere).

    ; --- Stage 1: wait for the real client window to exist ---
    if !BNetMainWindowExists()
        return false

    ; --- Stage 2: place it, and hand its lifetime to its single owner ---
    ; _bnetRevealedAt is the moment the launcher became the user's to look at.
    ; BNetMinimizeSequenceTick measures its on-screen floor from it and owns
    ; every question about when the window goes away; this function's job ends
    ; once the launcher is placed and the launch command has been fired.
    if (_bnetRevealedAt = 0) {
        RevealBNetForRender()          ; position on the chosen monitor
        _bnetRevealedAt := A_TickCount
        StartBNetMinimizeSequence()
        return false
    }

    ; --- Stage 3: fire the launch command, UNFOCUSED, exactly once ---
    if (_bnetLaunchFiredAt = 0) {
        ; ── THE LAUNCHER MUST HAVE FINISHED ARRIVING ───────────────────────
        ; Stage 1 proves a client window EXISTS. That is not the same as a
        ; client that has finished LOADING, and on a machine already busy -- a
        ; game running in the background was the reported case -- the gap
        ; between the two stretches. Firing Play into a half-built client and
        ; then minimising it 1250ms later is how the launcher ended up
        ; minimised before it had loaded.
        ;
        ; So the launcher has to look like a window someone could actually use:
        ; on screen, not minimised, and at a real size rather than the small
        ; placeholder rect a CEF window is born with. The dwell floor runs
        ; alongside it, so a slow machine and a fast one wait for the same
        ; EVIDENCE rather than for the same stopwatch.
        ; WAIT FOR READINESS, BUT NEVER FOREVER.
        ;
        ; The readiness test is evidence, not a guarantee it will ever be
        ; satisfied. It cannot be, in two real configurations: with
        ; bnetLauncherMode="minimized" the launcher is minimised ON PURPOSE and
        ; the not-minimised check can never pass; and a user whose Battle.net
        ; window is remembered smaller than the size floor, on a single monitor
        ; where the reveal never resizes it, would fail it every time.
        ;
        ; Either would mean Play is never pressed and Hearthstone never starts
        ; -- a hang, not a race fix. So the wait is BOUNDED: past the ceiling
        ; the command fires regardless, and the launch proceeds as it did
        ; before this gate existed. A launcher that minimises a little early is
        ; a cosmetic complaint; a launcher that never launches is not.
        ; ── THE DWELL IS MEASURED FROM "READY", NOT FROM "EXISTS" ──────────
        ; This is what makes the sequence take the same time every launch.
        ;
        ; _bnetRevealedAt is stamped when a client WINDOW EXISTS. The wait for
        ; that window to be usable is Battle.net's business and varies wildly --
        ; near zero when the client was already running, several seconds on a
        ; cold start or a busy machine. Measuring the dwell from that stamp
        ; meant the launcher's time on screen was (variable readiness wait) plus
        ; the dwell, so no two launches looked alike.
        ;
        ; Anchoring to the moment it becomes READY makes the part this script
        ; controls a constant: from "the launcher is up and usable" to "the
        ; launcher is gone" is always bnetRevealDwellMs + bnetPostPlayLingerMs.
        ; How long Battle.net took to get there still varies, but that is time
        ; the user spends watching a launcher boot, not time the script added.
        if (CFG.bnetLauncherMode != "minimized" && !_bnetReadyAt) {
            if _BNetLauncherLooksReady() {
                _bnetReadyAt := A_TickCount
                _FSLog("BNET-TIMING launcher ready "
                     . (_bnetReadyAt - _bnetRevealedAt) . "ms after its window"
                     . " appeared -- the fixed sequence starts now")
            } else if ((A_TickCount - _bnetRevealedAt) >= CFG.bnetReadyCeilingMs) {
                _bnetReadyAt := A_TickCount
                _FSLog("BNET-TIMING readiness ceiling reached -- proceeding anyway")
            } else {
                return false
            }
        }
        if !_bnetReadyAt
            _bnetReadyAt := A_TickCount      ; "minimized" mode: ready by fiat
        if (A_TickCount - _bnetReadyAt < CFG.bnetRevealDwellMs)
            return false

        ; Hand the foreground away first. Battle.net takes the foreground when
        ; it boots, so if the launch command lands while it still holds it, the
        ; Play button is the focused control of the focused window and Windows
        ; draws its focus ring -- which then stays drawn on the "Launching"
        ; state. The command is IPC rather than a synthetic click, so it does
        ; not care whether the client is foreground.
        ;
        ; This does NOT undo the foreground pin from stage 2, and the two are
        ; not in conflict: TOPMOST is z-order, focus is input routing. The
        ; launcher stays visually in front of everything -- a topmost window
        ; outranks non-topmost windows whether or not it is active -- it simply
        ; stops being the KEYBOARD-focused window, which is the only thing the
        ; focus ring depends on. Do not "simplify" this by dropping the pin
        ; instead; that trades a cosmetic ring for a launcher that disappears
        ; behind whatever else is open.
        try {
            fg := DllCall("user32\GetForegroundWindow", "Ptr")
            if (fg && _bnetLauncherHwnd && fg = _bnetLauncherHwnd) {
                shell := DllCall("user32\GetShellWindow", "Ptr")
                if shell
                    try WinActivate("ahk_id " . shell)
            }
        }
        LaunchWTCG()
        _bnetLaunchFiredAt := A_TickCount
        _bnetPlayFiredAt   := A_TickCount

        ; ── THE MINIMIZE IS SCHEDULED, NOT POLLED ──────────────────────────
        ; BNetMinimizeSequenceTick still owns the decision and still runs as a
        ; backstop, but it polls at 200ms -- so the launcher's disappearance
        ; landed anywhere in a 200ms band even when everything else was
        ; identical. A one-shot timer fires at the interval itself, which is
        ; the difference between "about a second and a bit" and the same
        ; interval every time. _bnetPostMinDone makes the duplicate a no-op.
        SetTimer(_BNetSequenceMinimizeNow, -CFG.bnetPostPlayLingerMs)
        _FSLog("BNET-TIMING Play fired " . (A_TickCount - _bnetReadyAt)
             . "ms after ready; minimize scheduled in "
             . CFG.bnetPostPlayLingerMs . "ms (fixed)")
        return false
    }

    ; --- Stage 4: nothing left to gate on ---
    ; The minimise has exactly one owner, anchored to Hearthstone having
    ; launched rather than to a stopwatch. See BNetMinimizeSequenceTick.
    return true
}

; Returns true if Battle.net has a login / auth window by title.
; Enumerates HIDDEN windows too: the launch blanket SW_HIDEs the client, so a
; login screen would otherwise be invisible to a visible-only scan and never be
; revealed for the user. Minimized windows are ALSO counted (FIX): the launch
; blanket minimizes BEFORE it hides, so a minimized-skip made the login screen
; structurally undetectable and LOGIN_WAIT unreachable. Title-only, so it
; will not trip on the transient auto-login ("Logging in...") whose window title
; stays "Battle.net".
BNetLoginOrAuthScreen() {
    if !ProcessExist("Battle.net.exe")
        return false
    prev  := A_DetectHiddenWindows
    DetectHiddenWindows true
    found := false
    try {
        for hwnd in WinGetList("ahk_exe Battle.net.exe") {
            try {
                title := StrLower(WinGetTitle("ahk_id " . hwnd))
                if (StrLen(title) > 50 || StrLen(title) < 3)
                    continue
                if (InStr(title, "log in") || InStr(title, "sign in") || InStr(title, "battle.net login"))
                    found := true
            }
        }
    }
    DetectHiddenWindows prev
    return found
}

; ==============================================================================
; SECTION 6: OVERWOLF / FIRESTONE — PATH RESOLUTION
; ==============================================================================
;
; Finds where Overwolf and the Firestone app actually live on disk (live
; process first, then the registry, then known folders) so F2 can launch
; them without hard‑coded paths.
;

; Resolve Overwolf.exe path: live process → registry → fallback directories.
GetOverwolfPath() {
    global Cache
    if (Cache.owPath != "")
        return Cache.owPath
    pid := ProcessExist("Overwolf.exe")
    if pid {
        try {
            p := ProcessGetPath(pid)
            if (p != "") {
                Cache.owPath := p
                return Cache.owPath
            }
        }
    }
    for key in [
        "HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Overwolf_is1",
        "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Overwolf_is1",
    ] {
        try {
            val := RegRead(key, "DisplayIcon")
            if (val != "" && FileExist(val)) {
                Cache.owPath := val
                return Cache.owPath
            }
        }
        try {
            val := RegRead(key, "InstallLocation")
            if (val != "") {
                testPath := RTrim(val, "\/") . "\Overwolf.exe"
                if FileExist(testPath) {
                    Cache.owPath := testPath
                    return Cache.owPath
                }
            }
        }
    }
    localApp := EnvGet("LOCALAPPDATA")
    for path in [
        localApp . "\Overwolf\Overwolf.exe",
        "C:\Program Files (x86)\Overwolf\Overwolf.exe",
        "C:\Program Files\Overwolf\Overwolf.exe",
    ] {
        if FileExist(path) {
            Cache.owPath := path
            return Cache.owPath
        }
    }
    return ""
}

; Resolve the OverwolfLauncher -launchapp command for Firestone by scanning
; extension manifests for the string "Firestone". Result cached after first hit.
GetFirestoneCmd() {
    global Cache
    if (Cache.firestoneLookupDone) {
        ; Validate the cached launcher path still exists.
        if (Cache.fsCmd != "") {
            cachedLauncher := RegExReplace(Cache.fsCmd, '^"([^"]+)".*', "$1")
            if FileExist(cachedLauncher)
                return Cache.fsCmd
            ; Cached launcher no longer exists — drop and re‑resolve below.
            Cache.firestoneLookupDone := false
            Cache.fsCmd               := ""
            Cache.fsAppId             := ""
        } else {
            return Cache.fsCmd
        }
    }
    Cache.fsCmd := ""
    localApp := EnvGet("LOCALAPPDATA")
    extDir   := localApp . "\Overwolf\Extensions"
    if DirExist(extDir) {
        loop files extDir . "\*", "D" {
            appId   := A_LoopFileName
            appPath := A_LoopFileFullPath
            try {
                loop files appPath . "\manifest.json", "R" {
                    content := FileRead(A_LoopFileFullPath)
                    if InStr(content, '"Firestone"') {
                        owPath   := GetOverwolfPath()
                        launcher := (owPath != "")
                            ? RegExReplace(owPath, "[^\\]+$", "OverwolfLauncher.exe")
                            : "C:\Program Files (x86)\Overwolf\OverwolfLauncher.exe"
                        if FileExist(launcher) {
                            Cache.fsCmd               := '"' . launcher . '" -launchapp ' . appId
                            Cache.fsAppId             := appId
                            Cache.firestoneLookupDone := true
                            return Cache.fsCmd
                        }
                    }
                    break
                }
            }
        }
    }
    Cache.firestoneLookupDone := true
    return Cache.fsCmd
}

; Returns the cached Firestone extension App ID, resolving it if needed.
GetFirestoneAppId() {
    global Cache
    if (Cache.fsAppId != "")
        return Cache.fsAppId
    GetFirestoneCmd()
    return Cache.fsAppId
}

; ==============================================================================
; SECTION 7: FIRESTONE SETTINGS PATCH
; Patches Firestone JSON settings files to enable close‑to‑tray, advanced‑settings
; visibility, and auto‑launch keys. Must be called only when Overwolf is NOT
; running (files are commonly write‑locked when open).
; ==============================================================================
EnsureFirestoneSettings() {
    appId := GetFirestoneAppId()
    if (appId = "")
        return
    localApp  := EnvGet("LOCALAPPDATA")
    basePaths := [
        localApp . "\Overwolf\" . appId,
        localApp . "\Overwolf\Extensions\" . appId,
        localApp . "\Overwolf\" . appId . "\storage",
    ]
    settingsKeys := [
        ["closeToTray",                   '"closeToTray"\s*:\s*false',                   '"closeToTray": true'],
        ["close-to-tray",                 '"close-to-tray"\s*:\s*false',                 '"close-to-tray": true'],
        ["close_to_tray",                 '"close_to_tray"\s*:\s*false',                 '"close_to_tray": true'],
        ["showAdvancedSettings",          '"showAdvancedSettings"\s*:\s*false',           '"showAdvancedSettings": true'],
        ["advanced-settings",             '"advanced-settings"\s*:\s*false',              '"advanced-settings": true'],
        ["launchFirestoneWhenGameStarts", '"launchFirestoneWhenGameStarts"\s*:\s*false',  '"launchFirestoneWhenGameStarts": true'],
        ["launchFirestoneOnGameStart",    '"launchFirestoneOnGameStart"\s*:\s*false',     '"launchFirestoneOnGameStart": true'],
        ["launchOnGameStart",             '"launchOnGameStart"\s*:\s*false',              '"launchOnGameStart": true'],
    ]
    for basePath in basePaths {
        if !DirExist(basePath)
            continue
        loop files basePath . "\*.json" {
            try {
                content := FileRead(A_LoopFileFullPath)
                changed := false
                for entry in settingsKeys {
                    if InStr(content, entry[1]) {
                        newContent := RegExReplace(content, entry[2], entry[3])
                        if (newContent != content) {
                            content := newContent
                            changed := true
                        }
                    }
                }
                if changed {
                    tmp := A_LoopFileFullPath . ".tmp"
                    FileAppend(content, tmp, "UTF-8-RAW")   ; no BOM: JSON parsers reject it
                    if FileExist(tmp) {
                        FileDelete(A_LoopFileFullPath)
                        FileMove(tmp, A_LoopFileFullPath)
                    }
                }
            }
        }
    }
}

; ==============================================================================
; SECTION 8: FIREWALL MANAGER — the F1 disconnect (pure IP‑block design)
; ------------------------------------------------------------------------------
; F1's disconnect is exactly the original concept, implemented correctly:
;
;   1) enumerate Hearthstone's ESTABLISHED connections and identify the game
;      SERVER's remote IP(s) — services/auth (CFG.servicesPorts, TCP 1119) and
;      private/loopback addresses are excluded, so auth is never a target;
;   2) add TWO firewall rules blocking that IP: "<ruleName>_IP_OUT" (dir=out)
;      and "<ruleName>_IP_IN" (dir=in), NOT tied to any program;
;   3) hold CFG.forcefulHoldMs, then delete both rules → HS reconnects to the
;      still‑held game, past the combat animation, without re‑authenticating.
;
; WHY address‑scoped + both directions + no program filter: Windows evaluates
; PROGRAM‑scoped rules at connection‑start (ALE layer), so applying one
; mid‑match only inconsistently affects an already‑established socket — the
; observed "worked once, not the next time". A plain address block with no
; program condition is enforced per‑packet in both directions: the live socket
; goes dark the instant the rules land, HS's client notices the dead
; connection within seconds, drops, and reconnects on release. This works
; identically for IPv4 and IPv6 game servers.
;
; Rules are created per press and deleted on release; janitors run at
; startup, exit, and F2‑restart so a crash mid‑hold can never leave the
; machine blocked. Older builds' rule names ("_GAME_OUT", "_V6_OUT",
; "_FULL_OUT", "_IN"/"_OUT") are also swept by the janitors below.
; ==============================================================================

; Join an AHK array of ports into a bare comma list, e.g. [1119] -> "1119".
PortsToCsv(arr) {
    s := ""
    for p in arr
        s .= (s = "" ? "" : ",") . p
    return s
}

; Find the live game‑server connection(s). Enumeration ONLY — nothing is reset
; or blocked here; the caller applies CFG.f1Target to the result.
; Returns a stats object:
;   {nonSvcIps, svcNewestIp, svcIps, svcCnt, cnt, detail}
;   nonSvcIps   — unique remote address(es) on NON‑services ports (comma list,
;                 "" if none). IPv4 and IPv6 both included.
;   svcNewestIp — remote address of the MOST RECENTLY CREATED services‑port
;                 connection ("" if none). Field evidence: on setups where the
;                 game runs over 1119, auth is the OLD 1119 connection (created
;                 at client start) and the game is the NEW one (created when
;                 the match began) — connection CreationTime tells them apart.
;   svcIps      — unique remote address(es) of ALL services‑port connections.
;   svcCnt      — how many established services‑port connections exist.
;   cnt         — number of non‑services candidates.
;   detail      — per‑connection log lines (ip:port, and age for svc conns).
; If CFG.gamePorts is set, ONLY those ports are considered and they populate
; nonSvcIps; the svc fields stay empty (explicit override, no heuristics).
; Hidden PowerShell via a temp .ps1 so stdout can be captured cleanly.
FindGameServerIPs(hsPID) {
    global CFG
    if (!hsPID)
        return {nonSvcIps: "", svcNewestIp: "", svcIps: "", svcCnt: 0, cnt: 0, detail: "no pid"}
    svc := PortsToCsv(CFG.servicesPorts)
    gp  := PortsToCsv(CFG.gamePorts)
    if (svc = "")
        svc := "0"
    if (gp != "")
        portFilter := "@(" . gp . ") -contains $_.RemotePort"
    else
        portFilter := "@(" . svc . ") -notcontains $_.RemotePort"

    ; Private / loopback / link‑local exclusion — the game server is a public
    ; address; anything matching this pattern is never a block candidate.
    priv := "'^(10\.|127\.|169\.254\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.|0\.0\.0\.0|::1|fe80)'"

    ; One snapshot, two sections:
    ;   GAME|addr|port          — non‑services candidates
    ;   SVC|addr|port|ageSec    — services‑port conns, NEWEST FIRST (sorted by
    ;                             CreationTime desc), public addresses only
    ps1 := A_Temp . "\hs_bg_find.ps1"
    out := A_Temp . "\hs_bg_find.txt"

    ; The script writes its own output file (last line) instead of relying on a
    ; cmd.exe ">" redirect, so PowerShell can be launched directly -- one less
    ; process spawn per F1 press. Results are accumulated into $o so a single
    ; Set-Content call does the write.
    ;
    ; On the final line: -join (rather than passing the array straight to
    ; -Value) keeps the command valid when there are ZERO matching
    ; connections -- an empty array can fail parameter binding, an empty
    ; string cannot.
    psCode := "$ErrorActionPreference='SilentlyContinue'`r`n"
            . "$o=@()`r`n"
            . "$a=Get-NetTCPConnection -OwningProcess " . hsPID . " -State Established`r`n"
            . "$pub=$a | Where-Object { $_.RemoteAddress -notmatch " . priv . " }`r`n"
            . "$c=$pub | Where-Object { " . portFilter . " }`r`n"
            . "$o+=@($c | ForEach-Object { `"GAME|$($_.RemoteAddress)|$($_.RemotePort)`" })`r`n"
            . "$s=$pub | Where-Object { @(" . svc . ") -contains $_.RemotePort } | Sort-Object CreationTime -Descending`r`n"
            . "$now=Get-Date`r`n"
            . "$o+=@($s | ForEach-Object { $age=[int](New-TimeSpan -Start $_.CreationTime -End $now).TotalSeconds; `"SVC|$($_.RemoteAddress)|$($_.RemotePort)|$age`" })`r`n"
            . "Set-Content -LiteralPath '" . out . "' -Value ($o -join [Environment]::NewLine) -Encoding ASCII`r`n"

    try FileDelete(out)
    try {
        f := FileOpen(ps1, "w")
        f.Write(psCode)
        f.Close()
    } catch {
        return {nonSvcIps: "", svcNewestIp: "", svcIps: "", svcCnt: 0, cnt: 0, detail: "ps1 write failed"}
    }
    ; Run PowerShell DIRECTLY -- the redirection is done inside the .ps1 (see
    ; the Out-File line appended to psCode above). The old form wrapped this in
    ; cmd.exe purely to get a "> file" redirect, costing an extra process spawn
    ; (~100-200 ms) on the critical path of every F1 press: this RunWait blocks
    ; the hotkey thread before the firewall block is even applied, so it is
    ; pure added latency between the keypress and the skip.
    RunWait('powershell.exe -NoLogo -NonInteractive -NoProfile -ExecutionPolicy Bypass'
        . ' -File "' . ps1 . '"', , "Hide")

    raw := ""
    try raw := FileRead(out)
    seenNon := Map(), seenSvc := Map()
    nonIps := "", svcIps := "", svcNewest := ""
    cnt := 0, svcCnt := 0
    detail := ""
    Loop Parse, raw, "`n", "`r" {
        line := Trim(A_LoopField, " `t")
        if (line = "")
            continue
        flds := StrSplit(line, "|")
        if (flds.Length < 3)
            continue
        kind := flds[1], ra := Trim(flds[2]), rp := Trim(flds[3])
        if (ra = "")
            continue
        if (kind = "GAME") {
            cnt++
            detail .= "GAME " . ra . ":" . rp . "`n"
            if !seenNon.Has(ra) {
                seenNon[ra] := true
                nonIps .= (nonIps = "" ? "" : ",") . ra
            }
        } else if (kind = "SVC") {
            svcCnt++
            age := (flds.Length >= 4) ? Trim(flds[4]) : "?"
            detail .= "SVC  " . ra . ":" . rp . " age=" . age . "s`n"
            if (svcNewest = "")
                svcNewest := ra          ; PS emitted newest‑first
            if !seenSvc.Has(ra) {
                seenSvc[ra] := true
                svcIps .= (svcIps = "" ? "" : ",") . ra
            }
        }
    }
    return {nonSvcIps: nonIps, svcNewestIp: svcNewest, svcIps: svcIps, svcCnt: svcCnt, cnt: cnt, detail: detail}
}

; ── The IP block itself ──────────────────────────────────────────────────────
; Two plain address‑scoped rules, no program filter, protocol=any:
;   "<ruleName>_IP_OUT"  dir=out  action=block  remoteip=<game ip(s)>
;   "<ruleName>_IP_IN"   dir=in   action=block  remoteip=<game ip(s)>
; netsh accepts a comma‑separated remoteip list and IPv6 literals, so one call
; per direction covers every identified game address. Created enabled, deleted
; on release. _ipBlockOn tracks state purely so the janitors know whether a
; cleanup is a repair or a no‑op.
global _ipBlockOn := false

; Scope the block to Hearthstone's executable.
;
; THIS IS THE FIX FOR "F1 PULLED UP BATTLE.NET".
;
; A netsh rule written as `remoteip=<addr>` with nothing else applies to EVERY
; PROCESS ON THE MACHINE. Blizzard's game and services addresses are shared
; infrastructure -- the Battle.net client talks to the same hosts Hearthstone
; does -- so blocking one by address cut the launcher's connection too. The
; client reacts to a lost connection the way it is designed to: it surfaces
; itself, un-minimizing over whatever you were doing, and shows a reconnect or
; disconnected state that sometimes needs a restart to clear. Nothing in this
; script was "pulling up" Battle.net; the firewall rule was disconnecting it,
; and it came up on its own.
;
; `program=` restricts the rule to one executable's traffic. With it, F1 drops
; exactly the connection it means to drop and no other process on the machine
; notices anything -- which is also what makes CFG.f1Target="smart" safe: it
; deliberately includes Hearthstone's newest SERVICES connection, and without
; this scoping that meant blocking an address Battle.net was actively using.
;
; Returns "" when the path is unknown. An unscoped block is still better than
; no skip at all, so this degrades rather than refusing -- but it logs, because
; an unscoped block is the condition that produced the bug.
_HSProgramScope() {
    p := GetHSPath()
    if (p = "") {
        _FSLog("F1 WARNING: Hearthstone's executable path is unknown, so the"
             . " firewall rule cannot be scoped to it. The block will apply"
             . " machine-wide for its duration, which can disconnect the"
             . " Battle.net client and make it restore itself.")
        return ""
    }
    return ' program="' . p . '"'
}

ApplyIPBlock(ipsCsv) {
    global CFG, _ipBlockOn
    if (ipsCsv = "")
        return false
    RemoveIPBlock()   ; idempotence — never stack duplicate rules
    n     := CFG.ruleName
    scope := _HSProgramScope()
    ec1 := RunWait('netsh advfirewall firewall add rule name="' . n . '_IP_OUT" dir=out action=block remoteip=' . ipsCsv . scope . ' enable=yes profile=any', , "Hide")
    ec2 := RunWait('netsh advfirewall firewall add rule name="' . n . '_IP_IN" dir=in action=block remoteip=' . ipsCsv . scope . ' enable=yes profile=any', , "Hide")
    _ipBlockOn := (ec1 == 0 && ec2 == 0)
    if !_ipBlockOn
        RemoveIPBlock()   ; half‑applied is worse than not applied
    return _ipBlockOn
}

RemoveIPBlock() {
    global CFG, _ipBlockOn
    n := CFG.ruleName
    RunWait('netsh advfirewall firewall delete rule name="' . n . '_IP_OUT"', , "Hide")
    RunWait('netsh advfirewall firewall delete rule name="' . n . '_IP_IN"',  , "Hide")
    _ipBlockOn := false
}

; ── Adapter reset — the guaranteed disconnect (scripted "pull the cable") ─────
; The one method that ALWAYS severs an established connection regardless of
; IPv4/IPv6, port, or firewall behaviour: briefly take the active network
; adapter(s) down and back up — exactly the known‑good manual skip (unplug
; ethernet / toggle Wi‑Fi, reconnect), automated. Drops EVERYTHING including
; auth, so it is opt‑in (CFG.f1Method := "adapter").
;
; The disable → sleep → enable all happens inside ONE elevated PowerShell
; process, launched fire‑and‑forget, so the adapter is ALWAYS brought back even
; if this script is killed mid‑blackout. Only adapters currently 'Up' are
; touched, and they are re‑enabled by the same $a reference, so nothing is left
; disabled. Physical adapters only (virtual/loopback/VPN taps are left alone).
_F1AdapterReset(holdMs) {
    ms := Round(holdMs)
    ps := "$a=Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object {$_.Status -eq 'Up'};"
        . "if($a){Disable-NetAdapter -InputObject $a -Confirm:$false -ErrorAction SilentlyContinue;"
        . "Start-Sleep -Milliseconds " . ms . ";"
        . "Enable-NetAdapter -InputObject $a -Confirm:$false -ErrorAction SilentlyContinue}"
    cmd := 'powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command "' . ps . '"'
    try Run(cmd, , "Hide")
}

; Janitor for every firewall rule this script (or an older build of it) can
; have created — run at startup and exit so nothing outlives the session:
; the live IP block, plus the retired "_GAME_OUT" / "_V6_OUT" / "_FULL_OUT"
; names from previous F1 designs.
DeleteGameRule() {
    global CFG
    RemoveIPBlock()
    for suffix in ["_GAME_OUT", "_V6_OUT", "_FULL_OUT"]
        RunWait('netsh advfirewall firewall delete rule name="' . CFG.ruleName . suffix . '"', , "Hide")
}

; Legacy cleanup: remove the whole‑app "<ruleName>_IN"/"_OUT" rules an OLDER
; build may have created (called at startup and on ExitApp). Current builds
; never create these; safe no‑op when the rules don't exist.
DeleteRules() {
    global CFG
    n := CFG.ruleName
    RunWait('netsh advfirewall firewall delete rule name="' . n . '_IN"',  , "Hide")
    RunWait('netsh advfirewall firewall delete rule name="' . n . '_OUT"', , "Hide")
}

StartHSInputShield(mode, durationMs) {
    global InputShield
    InputShield.active  := true
    InputShield.mode    := mode
    InputShield.endTime := A_TickCount + durationMs
    SetTimer(HSInputShield_Tick, 50)
}

StopHSInputShield() {
    global InputShield
    InputShield.active  := false
    InputShield.mode    := ""
    InputShield.endTime := 0
    SetTimer(HSInputShield_Tick, 0)
}

HSInputShield_Tick() {
    global InputShield
    if (!GetHSPID() || A_TickCount >= InputShield.endTime)
        StopHSInputShield()
}

; ------------------------------------------------------------------------------
; HS Hide‑on‑Launch watchdog
; ------------------------------------------------------------------------------
; ══════════════════════════════════════════════════════════════════════════════
;  HEARTHSTONE IS NOT CONCEALED
; ══════════════════════════════════════════════════════════════════════════════
; This subsystem used to cloak Hearthstone the instant it appeared, minimize it
; animation-free, mute it, hold it that way for ten seconds, and then restore,
; move and uncloak it in one carefully ordered reveal. All of that is gone.
;
; WHY IT IS GONE. Every part of it fought the game for control of its own
; window, and the game is better at that than we are. Unity re-runs its
; display-mode setup whenever the window is restored, moved or loses the
; foreground, so the sequence needed a cloak to hide the churn, a bounded
; verification loop to catch the snap-back, and a mute to hide the audio of a
; game the user could not yet see. Each of those was a fix for a problem the
; concealment itself created -- and none of it survives contact with a machine
; whose display, DPI or fullscreen mode differs from the one it was written on.
; Whether Hearthstone opens fullscreen, borderless or windowed, and where, is a
; setting the user already made inside the game.
;
; WHAT REPLACES IT. Nothing, on the concealment side: Hearthstone launches and
; takes the foreground exactly as it would with this script not running. The
; monitor preference is still honoured, but through the mechanism the game
; itself respects -- SetHSMonitorPref writes Unity's own display index before
; the launch -- with a single corrective move afterwards only if the window
; actually landed on the wrong screen. See RevealHSAfterLaunch.
;
; The function names are unchanged because roughly a dozen call sites, timers
; and cleanup paths reference them; only the behaviour is different. The watch
; is now purely a TRIGGER: it waits for the real game window to exist, then
; hands off to placement once and stops.
HideHSOnLaunch(durationMs := 10000) {
    StopHSHiddenLaunchWatch()
    StartHSHiddenLaunchWatch(durationMs)
}

StartHSHiddenLaunchWatch(durationMs := 10000) {
    global State
    State.hsHiddenLaunchActive := true
    State.hsHiddenLaunchUntil  := A_TickCount + durationMs
    SetTimer(HSHiddenLaunchWatch, 50)
    HSHiddenLaunchWatch()   ; immediate pass
}

StopHSHiddenLaunchWatch() {
    global State
    State.hsHiddenLaunchActive := false
    SetTimer(HSHiddenLaunchWatch, 0)
}

; Waits for the game window, then places it. Touches nothing else.
;
; The old version ran for a fixed ten seconds no matter what, because it was
; holding the window hidden for that long. With nothing to hold, waiting out a
; timer is just latency: the moment a real game window exists there is nothing
; left to wait for. The deadline survives only as a ceiling, so a launch that
; never produces a window still releases the timer instead of ticking forever.
HSHiddenLaunchWatch() {
    global State

    if !State.hsHiddenLaunchActive {
        SetTimer(HSHiddenLaunchWatch, 0)
        return
    }

    seen := false
    prev := A_DetectHiddenWindows
    DetectHiddenWindows true
    for hwnd in WinGetList("ahk_exe Hearthstone.exe") {
        try {
            if (IsIMEWindow(hwnd) || IsHelperWindow(hwnd))
                continue
            if (WinGetTitle("ahk_id " . hwnd) != "Hearthstone")
                continue
            WinGetPos(, , &w, &h, "ahk_id " . hwnd)
            if (w >= 600 && h >= 400)
                seen := true
        }
    }
    DetectHiddenWindows prev

    if (seen || A_TickCount >= State.hsHiddenLaunchUntil) {
        StopHSHiddenLaunchWatch()
        RevealHSAfterLaunch()
    }
}

; RevealHSAfterLaunch -- reveals the Hearthstone window and, when
; CFG.lockWindowsToChosenMonitor is set, places it on the launch monitor,
; centred in that monitor's work area. With the flag off it is centred within
; whatever monitor it restored onto.
;
; ── Monitor-index safety ─────────────────────────────────────────────────────
; ChosenMonIdx is resolved once, at start-up, and never revalidated. Monitor
; counts change underneath a running script -- a laptop is undocked, a cable is
; pulled, a display sleeps -- and MonitorGetWorkArea THROWS on an index that is
; no longer in range. Several call sites cloak or park a window before that
; call and uncloak it after, so the throw stranded the window invisible with no
; path back.
;
; _ValidMonIdx is the one place that decides whether an index is still real.
; _SafeWorkArea and _SafeMonitorRect never throw: they fall back to the primary
; monitor, and to the virtual desktop if even that fails. A wrong-but-visible
; monitor is always better than an exception in the middle of a window
; transition.
_ValidMonIdx(idx) {
    try {
        n := MonitorGetCount()
        if (idx >= 1 && idx <= n)
            return idx
        return MonitorGetPrimary()
    }
    return 1
}

_SafeWorkArea(idx, &l, &t, &r, &b) {
    try {
        MonitorGetWorkArea(_ValidMonIdx(idx), &l, &t, &r, &b)
        return true
    }
    try {
        MonitorGetWorkArea(MonitorGetPrimary(), &l, &t, &r, &b)
        return true
    }
    l := SysGet(76), t := SysGet(77)
    r := l + SysGet(78), b := t + SysGet(79)
    return true
}

_SafeMonitorRect(idx, &l, &t, &r, &b) {
    try {
        MonitorGet(_ValidMonIdx(idx), &l, &t, &r, &b)
        return true
    }
    return _SafeWorkArea(idx, &l, &t, &r, &b)
}

; Put the game on the monitor the user launched the script from -- and nothing
; else.
;
; Deliberately narrow. It moves the window only when the window is on the WRONG
; monitor; a window already on the right screen is left exactly where the game
; put it, because at that point its position is the user's business.
;
; A fullscreen-shaped window (its rect matches a whole monitor, work area
; ignored) is relocated to the target monitor's FULL bounds rather than centred
; in the work area, so a fullscreen game stays fullscreen instead of being
; shrunk to sit above the taskbar.
_PlaceHSOnChosenMonitor(hwnd) {
    global CFG, ChosenMonIdx
    if (!CFG.lockWindowsToChosenMonitor || !ChosenMonIdx)
        return false
    ; Single monitor: there is no wrong screen. Every correction below would be
    ; a no-op, and the verification loop after it would be pure latency.
    try {
        if (MonitorGetCount() <= 1)
            return false
    }
    idx := _ValidMonIdx(ChosenMonIdx)
    try {
        WinGetPos(&x, &y, &w, &h, "ahk_id " . hwnd)
        if (w < 600 || h < 400)
            return false
        if (GetMonitorIndexForPoint(x + w // 2, y + h // 2) = idx)
            return false            ; already right: hands off

        ; Is it covering a whole monitor? Then keep it covering a whole one.
        srcIdx := GetMonitorIndexForPoint(x + w // 2, y + h // 2)
        _SafeMonitorRect(srcIdx, &sl, &st, &sr, &sb)
        fullscreen := (x <= sl && y <= st && (x + w) >= sr && (y + h) >= sb)

        if fullscreen {
            _SafeMonitorRect(idx, &dl, &dt, &dr, &db)
            WinMove(dl, dt, dr - dl, db - dt, "ahk_id " . hwnd)
        } else {
            _SafeWorkArea(idx, &waL, &waT, &waR, &waB)
            waW := waR - waL, waH := waB - waT
            nx := (w <= waW) ? waL + (waW - w) // 2 : waL
            ny := (h <= waH) ? waT + (waH - h) // 2 : waT
            WinMove(nx, ny, , , "ahk_id " . hwnd)
        }
        _FSLog("HS-PLACE moved to monitor " . idx
             . (fullscreen ? " (fullscreen-shaped)" : " (windowed)"))
        return true
    }
    return false
}

; NOTHING HERE SHOWS THE WINDOW -- the game did that itself. This is placement
; and cleanup only.
;
; Design rules, which prevent cross-monitor side effects:
;   * No MouseMove, no WinActivate, no WinSetAlwaysOnTop, no cloak. Every one
;     of those pokes a borderless DXGI window into re-running its display-mode
;     setup, which is the flicker they were each added to hide.
;   * MOVE ONLY IF WRONG. The window is corrected when it landed on a monitor
;     the user did not ask for, and otherwise left exactly where the game put
;     it. Re-centring a window that is already on the right screen would
;     override a position the user chose.
;   * A fullscreen-exclusive window is never moved. It cannot be, meaningfully,
;     and trying makes Unity renegotiate the display for no benefit.
;
; The uncloak/enable calls remain as REPAIRS, not as part of a reveal: an
; earlier build of this script, or an instance killed mid-launch, can leave a
; Hearthstone window cloaked, and something has to be willing to undo that.
; They are no-ops on a window nobody concealed.
RevealHSAfterLaunch() {
    global CFG, ChosenMonIdx, _hsRevealed
    StopHSHiddenLaunchWatch()
    StopHSCloaker()
    try UnmuteHearthstone()   ; repair: undo a mute left by an older build

    ; Release the launcher's foreground pin. The minimize normally does this
    ; first, but "normally" is not a guarantee -- a slow client, a retry, or a
    ; minimize that does not take would leave a TOPMOST launcher floating over
    ; the game. The game is about to become the thing on screen; nothing else
    ; may be pinned above it.
    try _BNetDropTopmost()

    _hsRevealed := Map()   ; fresh release‑ledger for this launch

    prev := A_DetectHiddenWindows
    DetectHiddenWindows true

    for hwnd in WinGetList("ahk_exe Hearthstone.exe") {
        try {
            if IsIMEWindow(hwnd)
                continue
            if (WinGetTitle("ahk_id " . hwnd) != "Hearthstone") {
                ; Non‑game HS window: just make sure it isn't left cloaked,
                ; and mark it released so the placement guard skips it.
                UncloakWindow(hwnd)
                _hsRevealed[hwnd] := true
                continue
            }

            ; ---- Repair, not reveal ----
            ; The game shows its own window. These only undo concealment left
            ; behind by an earlier build or a killed instance.
            UncloakWindow(hwnd)

            ; ---- Correct the monitor, and only that ----
            _PlaceHSOnChosenMonitor(hwnd)
            _hsRevealed[hwnd] := true

        } catch {
            continue
        }
    }
    DetectHiddenWindows prev

    ; Arm the post-reveal placement guard almost immediately: its drift
    ; branch is a no-op while HS sits on the right monitor, so there is
    ; nothing to fight -- and a late Unity snap-back to the primary now gets
    ; corrected within ~150ms instead of sitting there for up to a second.
    SetTimer(() => StartHSPlacementGuard(60000), -150)

    SetHSGpuPreferenceHigh()
    PauseWSearch()
}

; Re‑enables all HS windows that may have been locked via WinSetEnabled.
; Defensive utility — called from ExitCleanup and recovery paths.
; Skips IME/TSF windows — EnableWindow on those can trigger composition popups.
ForceEnableHSWindow() {
    prev := A_DetectHiddenWindows
    DetectHiddenWindows true
    for hwnd in WinGetList("ahk_exe Hearthstone.exe") {
        if IsIMEWindow(hwnd)
            continue
        try DllCall("EnableWindow", "Ptr", hwnd, "Int", true)
    }
    DetectHiddenWindows prev
}

; ==============================================================================
; SECTION 9: PERFORMANCE / SMOOTHNESS TWEAKS
; ------------------------------------------------------------------------------
; Two optional system‑level tweaks that improve HS frame consistency without
; touching the script's hot paths. Both are gated by CFG flags so they can be
; turned off without code changes.
;
;   1. SetHSGpuPreferenceHigh — writes the per‑app GPU preference to HKCU so
;      Windows picks the discrete/high‑performance GPU for HS on hybrid systems.
;      Same effect as Windows Settings → System → Display → Graphics → Browse
;      → pick Hearthstone.exe → Options → High performance.
;
;   2. PauseWSearch / ResumeWSearch — stop the Windows Search indexer service
;      for the lifetime of an HS session. Search indexing is a common source
;      of background disk activity that surfaces as random hitches during
;      gameplay. State.wsearchPaused tracks whether we owe a Resume so we
;      never restart a service we didn't stop, and we only stop once even
;      across F2 cycles.
; ==============================================================================

; Write HS's per‑app GPU preference to HKCU so Windows always picks the high‑
; performance GPU for it.
SetHSGpuPreferenceHigh() {
    global CFG
    if !CFG.setHSGpuPreference
        return false

    hsPath := GetHSPath()
    if (hsPath = "" || !FileExist(hsPath))
        return false

    try {
        RegWrite("GpuPreference=2;", "REG_SZ",
                 "HKCU\Software\Microsoft\DirectX\UserGpuPreferences",
                 hsPath)
        return true
    } catch {
        return false
    }
}

; Stop the "WSearch" service if it's currently running. Sets
; State.wsearchPaused := true so ResumeWSearch knows to start it back up.
; Also arms WSearchHSWatch so the service auto‑resumes on any HS‑death path.
PauseWSearch() {
    global CFG, State
    if !CFG.pauseWSearchDuringHS
        return
    if State.wsearchPaused
        return   ; already paused by us — don't redundant‑stop

    exitCode := -1
    try exitCode := RunWait('"' . A_ComSpec . '" /c sc stop WSearch', , "Hide")
    if (exitCode = 0) {
        State.wsearchPaused := true
        SetTimer(WSearchHSWatch, 5000)
    }
}

; Restart the "WSearch" service IF and ONLY IF this script is the one that
; stopped it. State.wsearchPaused = true means "we owe a Resume."
ResumeWSearch() {
    global State
    if !State.wsearchPaused
        return
    try RunWait('"' . A_ComSpec . '" /c sc start WSearch', , "Hide")
    State.wsearchPaused := false
    SetTimer(WSearchHSWatch, 0)
}

; Watcher that resumes WSearch when HS dies, regardless of HOW it dies.
WSearchHSWatch() {
    global State
    if !State.wsearchPaused {
        SetTimer(WSearchHSWatch, 0)
        return
    }
    if !ProcessExist("Hearthstone.exe")
        ResumeWSearch()
}

; ==============================================================================
; SECTION 10: WINDOW MANAGER — Firestone / Overwolf surface suppression
; ==============================================================================
;
; THE INVISIBILITY SYSTEM — the largest and most safety‑critical section.
; Read the header glossary first; then, in the order they appear here:
;   • the OverwolfLauncher splash hider (simple: cloak + hide + fade);
;   • the five‑event window hook (created/shown/un‑minimized/un‑cloaked/
;     retitled → instant re‑suppression, Battle.net birth stamps, and the
;     event‑speed janitors);
;   • the Firestone‑Loading popup pipeline (pre‑hide, then close);
;   • the notification sweeper and its SIX guards (the code most capable of
;     doing harm, therefore the most defended);
;   • the launch "blanket" (3 ms pre‑title cloak + pre‑title alpha shield)
;     and its carefully decoupled lifetime;
;   • the Firestone‑Main suppression core: cloak + alpha shield + throttled
;     animation‑free minimize, plus the burst/coast timer machinery and the
;     120 s post‑launch guard.
; Golden thread: every hide has a janitor, every ledger is pruned, and the
; ABSOLUTE guards are never given exceptions.
;

; ── OverwolfLauncher splash hider ────────────────────────────────────────────
; Polls at 10ms to suppress the transient OverwolfLauncher (Firestone loader)
; splash during F2. OWCreateHookProc already pre‑hides the splash at window
; CREATION, so this poll is only the fallback for frames the hook misses.
global _launcherHideHasRef := false

StartLauncherHide() {
    global State, _launcherHideHasRef
    State.launcherHideActive := true
    StartOWCreateHook()             ; pre‑hide the launcher splash AT CREATION
                                    ; (the 10ms poll below stays as a fallback)
    if !_launcherHideHasRef {       ; own high‑res ref — idempotent Start/Stop
        _AcquireHighResTimer()
        _launcherHideHasRef := true
    }
    SetTimer(HideOverwolfLauncher, 10)
}

StopLauncherHide() {
    global State, _launcherHideHasRef
    State.launcherHideActive := false
    SetTimer(HideOverwolfLauncher, 0)
    if _launcherHideHasRef {
        _ReleaseHighResTimer()
        _launcherHideHasRef := false
    }
    ; UN-FADE. HideOverwolfLauncher applies WinSetTransparent(0) -- i.e.
    ; WS_EX_LAYERED at alpha 0 -- to every OverwolfLauncher.exe window, at
    ; 10 ms, for the whole launch. NOTHING anywhere in the script ever undid
    ; it: the startup repair pass only uncloaks Overwolf windows, and the
    ; WinSetTransparent("Off") calls elsewhere are scoped to the Battle.net
    ; family and to Hearthstone. So any window still owned by that process
    ; when the launch ended was left permanently transparent -- shown, sized,
    ; focusable, invisible. This fires on BOTH F2 paths, which matches a
    ; symptom that appears after F2 and has nothing to do with reloading.
    ; The repair uses the layered-mechanism probe, so a per-pixel window is
    ; still never touched, and it does NOT un-hide anything -- a suppressed
    ; splash stays suppressed, it just stops being stranded transparent.
    try FSRepairStuckAlpha()
    prev := A_DetectHiddenWindows
    DetectHiddenWindows true
    try {
        for hwnd in WinGetList("ahk_exe OverwolfLauncher.exe")
            try UncloakWindow(hwnd)
    }
    DetectHiddenWindows prev
}

; Called at 10ms while launcherHideActive is true. Self‑cancels if flag cleared.
HideOverwolfLauncher() {
    global State
    if !State.launcherHideActive {
        SetTimer(HideOverwolfLauncher, 0)
        return
    }
    prev := A_DetectHiddenWindows
    DetectHiddenWindows true
    try {
        ; Suppress ONLY the OverwolfLauncher (Firestone loader) splash.
        for hwnd in WinGetList("ahk_exe OverwolfLauncher.exe") {
            try {
                CloakWindow(hwnd)
                if DllCall("user32\IsWindowVisible", "Ptr", hwnd)
                    DllCall("ShowWindow", "Ptr", hwnd, "Int", 0)
                WinSetTransparent(0, "ahk_id " . hwnd)
            }
        }
    }
    DetectHiddenWindows prev
}

; ── Window event hook (first‑frame suppression + steady‑state enforcement) ────
; SESSION‑PERMANENT: armed once at startup and torn down only in ExitCleanup.
; This hook listens for five events and enforces suppression immediately.
global _OWCreateHook_Show := 0
global _OWCreateHook_Create := 0
global _OWCreateHook_MinEnd := 0
global _OWCreateHook_Uncloak := 0
global _OWCreateHook_Name := 0
global _OWCreateCB := 0

StartOWCreateHook() {
    global _OWCreateHook_Show, _OWCreateHook_Create, _OWCreateCB
    global _OWCreateHook_MinEnd, _OWCreateHook_Uncloak, _OWCreateHook_Name

    if !_OWCreateCB
        _OWCreateCB := CallbackCreate(OWCreateHookProc, "Fast")

    ; EVENT_OBJECT_CREATE = 0x8000
    if !_OWCreateHook_Create
        _OWCreateHook_Create := DllCall(
            "user32\SetWinEventHook"
            , "UInt", 0x8000
            , "UInt", 0x8000
            , "Ptr", 0
            , "Ptr", _OWCreateCB
            , "UInt", 0
            , "UInt", 0
            , "UInt", 0x0000 | 0x0002
            , "Ptr"
        )

    ; EVENT_OBJECT_SHOW = 0x8002
    if !_OWCreateHook_Show
        _OWCreateHook_Show := DllCall(
            "user32\SetWinEventHook"
            , "UInt", 0x8002
            , "UInt", 0x8002
            , "Ptr", 0
            , "Ptr", _OWCreateCB
            , "UInt", 0
            , "UInt", 0
            , "UInt", 0x0000 | 0x0002
            , "Ptr"
        )

    ; EVENT_SYSTEM_MINIMIZEEND = 0x0017 — fires when a window is RESTORED from
    ; minimized. This is how Overwolf raises a suppressed FS‑Main in steady
    ; state, and it produces NO create/show event.
    if !_OWCreateHook_MinEnd
        _OWCreateHook_MinEnd := DllCall(
            "user32\SetWinEventHook"
            , "UInt", 0x0017
            , "UInt", 0x0017
            , "Ptr", 0
            , "Ptr", _OWCreateCB
            , "UInt", 0
            , "UInt", 0
            , "UInt", 0x0000 | 0x0002
            , "Ptr"
        )

    ; EVENT_OBJECT_UNCLOAKED = 0x8018 — fires when a window's DWM cloak is
    ; cleared. If anything external drops the cloak on a locked FS‑Main, this
    ; tells us the instant it happens so we re‑cloak pre‑frame.
    if !_OWCreateHook_Uncloak
        _OWCreateHook_Uncloak := DllCall(
            "user32\SetWinEventHook"
            , "UInt", 0x8018
            , "UInt", 0x8018
            , "Ptr", 0
            , "Ptr", _OWCreateCB
            , "UInt", 0
            , "UInt", 0
            , "UInt", 0x0000 | 0x0002
            , "Ptr"
        )

    ; EVENT_OBJECT_NAMECHANGE = 0x800C — fires when a window's TITLE changes.
    ; The title‑settle instant triggers suppression (cloak + alpha shield) at
    ; event speed, and also releases the shield from windows that settled to
    ; non‑suppression titles (e.g. "Firestone - Overlays").
    if !_OWCreateHook_Name
        _OWCreateHook_Name := DllCall(
            "user32\SetWinEventHook"
            , "UInt", 0x800C
            , "UInt", 0x800C
            , "Ptr", 0
            , "Ptr", _OWCreateCB
            , "UInt", 0
            , "UInt", 0
            , "UInt", 0x0000 | 0x0002
            , "Ptr"
        )
}

StopOWCreateHook() {
    global _OWCreateHook_Show, _OWCreateHook_Create, _OWCreateCB
    global _OWCreateHook_MinEnd, _OWCreateHook_Uncloak, _OWCreateHook_Name

    if (_OWCreateHook_Create) {
        DllCall("user32\UnhookWinEvent", "Ptr", _OWCreateHook_Create)
        _OWCreateHook_Create := 0
    }
    if (_OWCreateHook_Show) {
        DllCall("user32\UnhookWinEvent", "Ptr", _OWCreateHook_Show)
        _OWCreateHook_Show := 0
    }
    if (_OWCreateHook_MinEnd) {
        DllCall("user32\UnhookWinEvent", "Ptr", _OWCreateHook_MinEnd)
        _OWCreateHook_MinEnd := 0
    }
    if (_OWCreateHook_Uncloak) {
        DllCall("user32\UnhookWinEvent", "Ptr", _OWCreateHook_Uncloak)
        _OWCreateHook_Uncloak := 0
    }
    if (_OWCreateHook_Name) {
        DllCall("user32\UnhookWinEvent", "Ptr", _OWCreateHook_Name)
        _OWCreateHook_Name := 0
    }
    if (_OWCreateCB) {
        CallbackFree(_OWCreateCB)
        _OWCreateCB := 0
    }
}

; Exact matcher for the Firestone loading popup.
; Close a window WITHOUT waiting for it to go.
;
; AutoHotkey's WinClose sends WM_CLOSE and then BLOCKS until the window is gone
; or its timeout expires. Every call site here targets an Overwolf/Firestone
; window, and the whole point of these closers is that they run when Firestone
; is misbehaving -- so the moment WinClose is called is the moment the target
; is most likely to be hung. AutoHotkey is single-threaded: that block freezes
; the ENTIRE script, hotkeys included, and every watchdog that would recover it
; is a timer, so nothing runs to save it. A user reported exactly this after a
; Firestone crash -- no F-keys at all for the rest of the session.
;
; PostMessage puts WM_CLOSE on the window's queue and returns immediately. A
; healthy window closes exactly as before; a hung one stops being our problem.
; Nothing downstream needed the close to have completed on return -- every
; caller re-checks on its next tick.
_CloseWindowAsync(hwnd) {
    static WM_CLOSE := 0x0010
    try return PostMessage(WM_CLOSE, 0, 0, , "ahk_id " . hwnd)
    return false
}

IsLikelyFirestoneLoadingPopupHwnd(hwnd) {
    try {
        exe := WinGetProcessName("ahk_id " . hwnd)
        if (exe != "Overwolf.exe" && exe != "OverwolfBrowser.exe")
            return false
        title := WinGetTitle("ahk_id " . hwnd)
        if (title = "Firestone - Loading")
            return true

        ; BARE "Firestone" IN THE POPUP SIZE ENVELOPE COUNTS TOO.
        ;
        ; Firestone's start-up window ("Getting ready", with the spinner) is
        ; titled just "Firestone" -- not "Firestone - Loading". Matching only
        ; the hyphenated title meant this dedicated suppressor, the one armed
        ; at 10ms BEFORE the process even exists, never saw the window that is
        ; actually on screen during start-up. It fell through to the general
        ; sweep, which runs later and had more ways to decline.
        ;
        ; Widening it here only ever adds CONCEALMENT -- this path cloaks, it
        ; does not close -- so the cost of a false match is a window that is
        ; hidden a moment earlier than it would have been anyway.
        if (title != "Firestone")
            return false
        if _CoversMostOfItsMonitor(hwnd)      ; the overlay: never
            return false
        ex := 0
        try ex := WinGetExStyle("ahk_id " . hwnd)
        if (ex & 0x20)                        ; WS_EX_TRANSPARENT: click-through
            return false
        w := 0, h := 0
        try WinGetPos(, , &w, &h, "ahk_id " . hwnd)
        return (w >= 300 && h >= 300 && w <= 800 && h <= 800)
    } catch {
    }
    return false
}
; Does this window cover most of the monitor it is sitting on?
;
; THIS REPLACES A FIXED 1600x1000 PIXEL CAP, which was the script's way of
; saying "too big to be a popup, therefore it is the in-game overlay". That
; test is only correct on a monitor bigger than the cap. On a 1366x768 or
; 1600x900 display -- ordinary single-monitor and laptop resolutions -- the
; overlay is SMALLER than the cap, so the check that existed to protect it
; instead waved it through: the overlay could be classified as the loading
; splash and concealed, or judged parkable and moved off screen. Neither can
; happen on the 1440p+ monitor the script was written on, which is exactly why
; it was never seen.
;
; Expressed as a FRACTION of the monitor, the same rule holds at every
; resolution and every DPI: the overlay is game-screen sized by definition, and
; no popup is. The script uses aspect-ratio reasoning elsewhere for the same
; reason -- see _IsProtectedBNetMain, which notes that pixel sizes are not
; DPI-proof.
_CoversMostOfItsMonitor(hwnd, w := 0, h := 0) {
    try {
        if (!w || !h)
            WinGetPos(, , &w, &h, "ahk_id " . hwnd)
        if (w <= 0 || h <= 0)
            return false
        WinGetPos(&x, &y, , , "ahk_id " . hwnd)
        _SafeMonitorRect(GetMonitorIndexForPoint(x + w // 2, y + h // 2)
            , &ml, &mt, &mr, &mb)
        mw := mr - ml, mh := mb - mt
        if (mw <= 0 || mh <= 0)
            return false
        return (w * 100 >= mw * 70) && (h * 100 >= mh * 70)
    }
    return false
}

; Early visual matcher for the Firestone loading popup ONLY.
; Used only by the earliest anti‑flicker paths (create hook + early cloak).
IsLikelyFirestoneLoadingEarlyHwnd(hwnd) {
    try {
        exe := WinGetProcessName("ahk_id " . hwnd)
        if (exe != "Overwolf.exe" && exe != "OverwolfBrowser.exe")
            return false
        title := WinGetTitle("ahk_id " . hwnd)
        if (title = "Firestone - Loading")
            return true
        if (title = "Firestone - Main" || title = "Firestone - Overlays")
            return false
        if (title != "" && title != "Firestone")
            return false
        WinGetPos(, , &w, &h, "ahk_id " . hwnd)
        ; Bounds widened: the pre-title Main is CREATEd tiny (CEF windows are
        ; often born near 0x0 and resized before show) and a remembered size
        ; can exceed the old 1100x900 cap -- either way it escaped this
        ; matcher, showed untitled, and was only minimized once it titled.
        ; The in-game overlay (the reason an upper cap exists at all) is
        ; game-screen sized and still excluded -- by proportion of its monitor
        ; rather than by a pixel count, so the exclusion holds on a small
        ; display too. See _CoversMostOfItsMonitor.
        if (w < 60 || h < 40)
            return false
        if _CoversMostOfItsMonitor(hwnd, w, h)
            return false
        return true
    } catch {
    }
    return false
}

OWCreateHookProc(hWinEventHook, event, hwnd, idObject, idChild, dwEventThread, dwmsEventTime) {
    global _HSCloakActive, _EarlyOWCloakActive, State, _hsGuardActive, _hsRevealed
    global CFG, ChosenMonIdx, _placeCreateSeen, _placeFirstSeen
    global _earlyCloakSawFSMainAt, _bnetFirstMoved, _fsAlphaApplied, _fsHiddenByUs, _fsEverPainted, _fsBirthHidden
    global _bnetPostMinUntil, _bnetPostMinCount, _bnetCloakActive, _bnetHiddenByUs, _fsRevealActive
    global _fsBirthReassert, _fsPaintState, _fsParked
    static EV_CREATE := 0x8000, EV_SHOW := 0x8002
    static EV_MINEND := 0x0017, EV_UNCLOAKED := 0x8018
    static EV_NAMECHANGE := 0x800C

    ; ---- HIDDEN-WINDOW VISIBILITY ----
    ; This proc is a CallbackCreate(..., "Fast") callback, so it does not get a
    ; fresh AutoHotkey thread: it inherits the settings of whatever thread it
    ; interrupts, which when the script is idle means DetectHiddenWindows OFF.
    ; Every WinGet* call below addresses a window by "ahk_id", and with that
    ; setting off AutoHotkey will not find a window that is not visible.
    ;
    ; That matters here more than anywhere else in the script, because
    ; EVENT_OBJECT_CREATE always describes an invisible window -- windows are
    ; created hidden and shown afterwards -- and because a window this script has
    ; concealed must remain addressable.
    ;
    ; Fast mode has no thread of its own, so the setting must be restored on every
    ; exit path; hence the finally block at the bottom rather than a plain
    ; assignment.
    prevDHW := A_DetectHiddenWindows
    DetectHiddenWindows true
    try {
        if (idObject != 0 || idChild != 0 || !hwnd)
            return

        ; Cheap global gate — only resolve the exe when at least one consumer
        ; below could act on the event. HS conditions (_HSCloakActive,
        ; _hsGuardActive) are intentionally NOT here: HS is owned by its own
        ; dedicated timers, not this hook, so this hook need not wake for an
        ; HS-only phase. Firestone (fsMainLocked / lock), the Overwolf
        ; launcher splash (launcherHideActive), early cloak, and Battle.net
        ; placement (lock) remain.
        if !(State.launcherHideActive || _EarlyOWCloakActive
          || State.fsMainLocked || CFG.lockWindowsToChosenMonitor)
            return

        exe := ""
        try exe := WinGetProcessName("ahk_id " . hwnd)
        if (exe = "")
            return

        ; ---- EARLIEST-POSSIBLE FS BIRTH CLOAK ----
        ; While LOCKED, cloak a newly CREATED Overwolf window RIGHT NOW,
        ; before title resolution and before any other branch below. Every
        ; WinGet* call between here and the titled-suppression branch is a
        ; round-trip during which a fresh CEF window can paint its first
        ; (black) frame -- that gap was the residual flicker. Cloaking at
        ; the very top closes it to the minimum. DWM cloak works on a
        ; still-invisible window and is idempotent, so re-cloaking below is
        ; harmless. Non-FS Overwolf windows (e.g. the overlay) are uncloaked
        ; microseconds later by their janitors. Only CREATE (not SHOW), only
        ; Overwolf processes, only while locked.
        if (event = EV_CREATE && State.fsMainLocked
         && (exe = "Overwolf.exe" || exe = "OverwolfBrowser.exe")) {
            {
                ; NO IsHelperWindow GATE HERE. That gate is why the "Getting
                ; ready" window is painted before anything conceals it:
                ; Overwolf builds its surfaces OWNED or WS_EX_TOOLWINDOW, so
                ; the gate was true for exactly the windows this branch exists
                ; to catch, and they were skipped at the one moment concealment
                ; is free -- before the window has ever been shown. The funnel
                ; itself now decides what an unnamed newborn deserves (a cloak),
                ; which is the right place for that judgement.
                ;
                ; BIRTH SUPPRESSION -- routed through the single funnel.
                ; This used to be an unconditional ShowWindow(SW_HIDE) at
                ; CREATE. That is the earliest and most damaging of the five
                ; hides: it lands before the window has a title, before it has
                ; ever been shown, and before Chromium has had any chance to
                ; stand up a compositor for it. See CFG.fsMainColdPolicy.
                ; The funnel now applies the COLD policy instead, which keeps
                ; the window equally invisible without clearing WS_VISIBLE.
                if (CFG.fsBirthHide && !_fsBirthHidden.Has(hwnd))
                    _fsBirthHidden[hwnd] := A_TickCount
                try _FSSuppressSurface(hwnd, "", false)
            }
        }
        ; ---- BIRTH SUPPRESSION RE-ASSERT ----
        ; Overwolf answers our birth-time concealment by calling SW_SHOW a moment
        ; later. Under the park policy there is nothing to undo -- the window was
        ; never hidden -- so this branch has work to do only under the legacy "hide"
        ; policy.
        ;
        ; The re-assert is COUNTED. Re-asserting once or twice is correct; an
        ; unbounded hide/show duel at event speed is a storm, and a storm on a cold
        ; Chromium window destroys it. Past the cap this stands down and lets the
        ; settled sweep own the window.
        if (event = EV_SHOW && State.fsMainLocked && CFG.fsBirthHide
         && _fsBirthHidden.Has(hwnd)
         && (exe = "Overwolf.exe" || exe = "OverwolfBrowser.exe")) {
            if !IsHelperWindow(hwnd) {
                n := _fsBirthReassert.Get(hwnd, 0)
                if (n < CFG.fsBirthReassertMax) {
                    _fsBirthReassert[hwnd] := n + 1
                    try _FSSuppressSurface(hwnd, "", false)
                } else if (n = CFG.fsBirthReassertMax) {
                    _fsBirthReassert[hwnd] := n + 1
                    _FSLog("FS-COLD re-assert cap reached hwnd=" . hwnd
                         . " -- standing down at event speed, settled sweep owns it")
                }
            }
        }

        ; ---- Firestone popup: killed the instant it names itself ----------
        ; A CEF window is created without a caption and titled a few
        ; milliseconds later, so this event -- not CREATE -- is the first moment
        ; the popup can be told apart from anything else Overwolf makes. Acting
        ; here is the earliest possible correct kill, and it is why the popup no
        ; longer survives long enough to be seen.
        ;
        ; Not gated on the F3 lock, by design: a notification is never something
        ; the user asked to see, whatever state their overlay is in.
        if (event = EV_NAMECHANGE
         && (exe = "Overwolf.exe" || exe = "OverwolfBrowser.exe")) {
            try {
                t := WinGetTitle("ahk_id " . hwnd)
                if IsFirestoneNotificationPopup(hwnd, t)
                    _FSKillNotificationPopup(hwnd, "namechange")
            }
        }

        ; ---- Battle.net NAMECHANGE enforcement (bidirectional) ----
        ; A title change can flip a window's classification either way, so
        ; both directions are enforced at event speed: a hidden window whose
        ; settled identity is the REAL client is un-hidden immediately; a
        ; live window whose title exposes it as a service surface is hidden.
        if (event = EV_NAMECHANGE && exe = "Battle.net.exe") {
            if _bnetHiddenByUs.Has(hwnd) {
                if _IsProtectedBNetMain(hwnd) {
                    _bnetHiddenByUs.Delete(hwnd)
                    try UncloakWindow(hwnd)
                    DllCall("ShowWindow", "Ptr", hwnd, "Int", 8)   ; SW_SHOWNA
                }
            } else if (_bnetCloakActive && CFG.bnetAggressiveHide
                    && !_IsBlizzInfrastructureWindow(hwnd)) {
                try _HideBlizzWindow(hwnd, exe)
            }
            return
        }

        ; ---- Battle.net / Agent placement (no popup suppression) ----
        if ((event = EV_CREATE || event = EV_SHOW)
         && (exe = "Battle.net.exe" || exe = "Agent.exe")) {

            ; Services blanket, event speed: everything except the REAL
            ; client window is cloaked+hidden the instant it appears -- the
            ; auto-login shell included. The real client passes through and
            ; continues into the placement logic below, so its very first
            ; frame already lands on the chosen monitor.
            if (_bnetCloakActive && CFG.bnetAggressiveHide) {
                if !_IsBlizzInfrastructureWindow(hwnd)
                    try _HideBlizzWindow(hwnd, exe)
                if _bnetHiddenByUs.Has(hwnd)
                    return          ; a hidden SERVICE surface: nothing to place.
                                    ; The launcher (never hidden) falls through
                                    ; even while INVISIBLE at CREATE, so the
                                    ; Layer-1 pre-show move below still lands
                                    ; its very first frame on the chosen monitor.
            }

            ; --- First: placement / minimize for the main launcher ---
            if (CFG.lockWindowsToChosenMonitor) {
                if (DllCall("user32\GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr") = hwnd) {
                    if (event = EV_CREATE) {
                        _placeCreateSeen[hwnd] := A_TickCount
                        if _placeFirstSeen.Has(hwnd)
                            _placeFirstSeen.Delete(hwnd)

                        ; Layer 1: pre‑show move while still invisible.
                        if (CFG.preShowPlaceBNet && ChosenMonIdx
                         && !DllCall("user32\IsWindowVisible", "Ptr", hwnd)) {
                            try {
                                rc := Buffer(16, 0)
                                if DllCall("user32\GetWindowRect", "Ptr", hwnd, "Ptr", rc) {
                                    bx := NumGet(rc, 0, "Int"), by := NumGet(rc, 4, "Int")
                                    bw := NumGet(rc,  8, "Int") - bx
                                    bh := NumGet(rc, 12, "Int") - by
                                    if (GetMonitorIndexForPoint(bx + bw // 2, by + bh // 2) != ChosenMonIdx) {
                                        _SafeWorkArea(ChosenMonIdx, &waL, &waT, &waR, &waB)
                                        waW := waR - waL
                                        waH := waB - waT
                                        nx := (bw > 0 && bw <= waW) ? waL + (waW - bw) // 2 : waL
                                        ny := (bh > 0 && bh <= waH) ? waT + (waH - bh) // 2 : waT
                                        DllCall("user32\SetWindowPos", "Ptr", hwnd, "Ptr", 0
                                            , "Int", nx, "Int", ny, "Int", 0, "Int", 0
                                            , "UInt", 0x0001 | 0x0004 | 0x0010)
                                    }
                                }
                            }
                        }
                    } else {
                        if !_placeCreateSeen.Has(hwnd)
                            _placeCreateSeen[hwnd] := A_TickCount
                        ; Layer 2: first‑frame placement at first visibility.
                        _BNetFirstShowPlace(hwnd)

                        ; Event‑speed re‑minimize during the post‑launch window.
                        if (_bnetPostMinUntil > A_TickCount
                         && DllCall("user32\IsWindowVisible", "Ptr", hwnd)
                         && !IsHelperWindow(hwnd)
                         && WinGetMinMax("ahk_id " . hwnd) != -1) {
                            WinGetPos(, , &pbW, &pbH, "ahk_id " . hwnd)
                            if (pbW >= 200 && pbH >= 150
                             && (!_placeCreateSeen.Has(hwnd)
                              || A_TickCount - _placeCreateSeen[hwnd] >= 4000)
                             && _bnetPostMinCount.Get(hwnd, 0) < 3) {
                                _bnetPostMinCount[hwnd] := _bnetPostMinCount.Get(hwnd, 0) + 1
                                _MinimizeWindowNoAnim(hwnd)
                            }
                        }
                    }
                    ; Layer 3: one‑shot settled pass just past the 400ms margin.
                    SetTimer(_HookedPlacementPass, -460)
                }
            }
            return
        }

        ; ---- Hearthstone: NOT handled here ----
        ; HS placement/cloaking is owned exclusively by StartHSCloaker (launch
        ; phase, 10ms) and HSPlacementGuardTick (post-reveal, 150ms), which
        ; run sequentially (RevealHSAfterLaunch stops the cloaker before
        ; arming the guard). Handling HS in this shared hook too made it a
        ; multi-owner window and coupled its timing to FS/BNet events. It is
        ; now fully independent of this hook -- if the event is for HS, the
        ; per-exe branches below simply don't match it and it falls through
        ; harmlessly. (The dedicated owners see every HS window via their own
        ; WinGetList enumeration, so nothing is missed.)
        if (exe = "Hearthstone.exe")
            return

        ; ---- OverwolfLauncher splash (CREATE/SHOW only) ----
        if ((event = EV_CREATE || event = EV_SHOW)
         && State.launcherHideActive && exe = "OverwolfLauncher.exe") {
            CloakWindow(hwnd)
            DllCall("ShowWindow", "Ptr", hwnd, "Int", 0)  ; SW_HIDE
            return
        }

        ; ---- Overwolf / OverwolfBrowser ----
        if (exe != "Overwolf.exe" && exe != "OverwolfBrowser.exe")
            return

        title := ""
        try title := WinGetTitle("ahk_id " . hwnd)

        ; Firestone - Main and Firestone - Battlegrounds while the F3 lock is on.
        ; Routed through the single suppression primitive, which applies the cold
        ; policy until the window has proven it paints and the standard concealment
        ; afterwards. The alpha shield is applied by that primitive, not here: two
        ; owners performing opposite-layer operations on one Chromium window in the
        ; same millisecond is precisely what this design exists to prevent.
        if (IsFirestoneSuppressionTitle(title) && State.fsMainLocked) {
            _ApplyFSAlphaShield(hwnd)     ; ledger-only while fsUseAlphaShield=false
            try _FSSuppressSurface(hwnd, title, false)
            ; Stamp the first sighting for early‑cloak self‑stop.
            if (!_earlyCloakSawFSMainAt && _EarlyOWCloakActive
             && IsFirestoneMainTitle(title))
                _earlyCloakSawFSMainAt := A_TickCount
            return
        }

        ; ---- Unlocked SHOW release ----
        ; While UNLOCKED, a suppression-titled window being shown by
        ; Overwolf must actually appear. Its cloak may deliberately still
        ; be armed from the locked era (kept on hidden windows so the NEXT
        ; locked-era show is born invisible -- the BG match-start flicker
        ; fix); release cloak and shield here at event speed. Worst case
        ; under event lag is a one-frame LATE appearance (invisible ->
        ; visible), imperceptible -- unlike the old wrong-visible frame.
        if (IsFirestoneSuppressionTitle(title) && !State.fsMainLocked) {
            if _fsAlphaApplied.Has(hwnd)
                _ClearFSAlphaShield(hwnd)
            _FSReleaseSurface(hwnd)       ; unpark first, then uncloak
            return
        }

        ; ---- Overlay janitor (ANY event, incl. NAMECHANGE) ----
        ; The in‑game overlay must be visible. Release cloak, shield AND PARK.
        ; The park matters: the overlay is born untitled like everything else,
        ; so the birth suppression parks it off-screen. Without the unpark here
        ; the in-game overlay would live outside the virtual desktop for the
        ; whole session -- the same class of unrecoverable state the birth-hide
        ; used to create, which is why this janitor exists at all.
        if (title = "Firestone - Overlays") {
            if _fsAlphaApplied.Has(hwnd)
                _RemoveFSAlphaShield(hwnd)
            _FSReleaseSurface(hwnd)
            ; If the birth-hide took it off screen, put it back NOW: the
            ; in-game overlay must be visible.
            if _fsBirthHidden.Has(hwnd) {
                _MapDrop(_fsBirthHidden, hwnd)
                _FSShowIfNotPopup(hwnd)
            }
            return
        }

        ; ---- Title-settle janitor (NAMECHANGE only) ----
        ; A window whose title settles to something we do NOT suppress gets
        ; its shield unwound AND its birth cloak released, the moment it
        ; proves benign. "Firestone - Loading" is deliberately excluded:
        ; its own suppressors keep it cloaked+hidden through the launch.
        if (event = EV_NAMECHANGE) {
            if (title != "" && title != "Firestone") {
                ; ALLOW-LIST. The old test was "not a suppression title and not
                ; Firestone - Loading => benign => uncloak and SHOW it". That
                ; is the event-speed twin of the birth-hide sweep's bug: any
                ; Overwolf window that settled to an unrecognised title -- e.g.
                ; "OverWolf Server" -- was classified benign and deliberately
                ; put on screen. Only titles on CFG.fsVisibleTitles are
                ; released now; everything else stays suppressed while locked.
                if (!FSShouldSuppress(title) || title = "Firestone - Overlays") {
                    if _fsAlphaApplied.Has(hwnd)
                        _RemoveFSAlphaShield(hwnd)
                    _FSReleaseSurface(hwnd)     ; unpark, then uncloak
                    if _fsBirthHidden.Has(hwnd) {
                        _MapDrop(_fsBirthHidden, hwnd)
                        _FSShowIfNotPopup(hwnd)
                    }
                } else {
                    ; Suppressed. This branch fires the INSTANT the window
                    ; titles itself "Firestone - Main" -- which for CEF is
                    ; before first paint, not after it. It used to SW_HIDE
                    ; unconditionally right there, which is hide number four
                    ; of five and the one that lands at the worst possible
                    ; moment. Funnelled now: cold policy until proven, the
                    ; Battlegrounds exit afterwards.
                    _MapDrop(_fsBirthHidden, hwnd)
                    try _FSSuppressSurface(hwnd, title, false)
                }
            }
            return
        }

        ; Everything below is CREATE/SHOW policy only.

        ; ---- Firestone - Loading ----
        ; THIS IS FIRESTONE-MAIN'S OWN HWND. The Loading window retitles into
        ; Main in place -- the same-HWND retitle case documented throughout
        ; this script. So every "harmless" suppression aimed at the loading
        ; popup was in fact being applied to the window that becomes Main,
        ; during the coldest seconds of its life. Funnelled.
        if (title = "Firestone - Loading") {
            try _FSSuppressSurface(hwnd, title, false)
            return
        }

        if (title = "" || title = "Firestone") {
            ; Pre-title. Also Main's HWND, earlier still. Same treatment.
            if (_EarlyOWCloakActive || State.fsMainLocked) {
                if !_fsBirthHidden.Has(hwnd)
                    _fsBirthHidden[hwnd] := A_TickCount
                try _FSSuppressSurface(hwnd, title, false)
                return
            }
        }

        ; ---- Fallback: early loading‑popup shape matcher (launch phases only) ─
        if !(_EarlyOWCloakActive || State.f2Active)
            return
        if !IsLikelyFirestoneLoadingEarlyHwnd(hwnd)
            return

        ; Concealment is delegated to the single primitive. Note that
        ; ShowWindow(SW_MINIMIZE) on a hidden window RE-SHOWS it, minimised, so a
        ; hide/minimise pair is a visibility flip rather than a concealment -- and a
        ; sustained flip on a cold Chromium window prevents it ever painting.
        try _FSSuppressSurface(hwnd, "", false)
    } catch {
    } finally {
        DetectHiddenWindows prevDHW   ; Fast callback: never leak the setting
    }
}

; ── Firestone loading popup suppression ───────────────────────────────────────
; Handles the startup/loading popup in four stages:
;   • StartOWCreateHook / OWCreateHookProc — at EVENT_OBJECT_CREATE / SHOW,
;     cloaks early popup candidates; SW_HIDEs only the exact‑titled popup.
;   • EarlyOverwolfCloakTick — same policy on a 10ms poll.
;   • SuppressFirestoneLoadingTick — keeps only the exact titled loading popup
;     invisible once it has settled.
;   • KillFirestoneLoading — closes only the exact titled loading popup hwnd.

KillFirestoneLoading() {
    global State, _fsHiddenByUs
    prev     := A_DetectHiddenWindows
    prevMode := A_TitleMatchMode
    DetectHiddenWindows true
    SetTitleMatchMode(3)   ; exact match only

    popupStillExists := false
    fsMainTitled     := false   ; structural guard for the PS closer (below)

    try {
        for exe in ["Overwolf.exe", "OverwolfBrowser.exe"] {
            for h in WinGetList("ahk_exe " . exe) {
                try {
                    tK := WinGetTitle("ahk_id " . h)
                    if (tK = "Firestone - Main")
                        fsMainTitled := true
                    if (tK != "Firestone - Loading")
                        continue

                    popupStillExists    := true
                    State.fsLoadingSeen := true

                    ; SUPPRESSION REMOVED FROM THIS FUNCTION ENTIRELY.
                    ;
                    ; This was one half of the storm. KillFirestoneLoading and
                    ; SuppressFirestoneLoadingTick were TWO IDENTICAL 10 ms
                    ; timers, both doing cloak -> SW_HIDE -> SW_MINIMIZE on the
                    ; same HWND -- and SW_MINIMIZE on a hidden window re-shows
                    ; it. Two hundred visibility flips per second, for up to
                    ; sixty seconds, on the exact HWND that becomes
                    ; Firestone - Main, while Chromium is trying to bring up
                    ; its compositor for the first time.
                    ;
                    ; SuppressFirestoneLoadingTick is now the sole suppressor
                    ; and it funnels through _FSSuppressSurface. This function
                    ; keeps only its bookkeeping and its self-stop, and its
                    ; timer has been dropped from 10 ms to 250 ms to match.
                } catch {
                }
            }
        }

        ; COLD‑LAUNCH GUARD (same structure as the notif sweeper's guard 2):
        ; the ASYNC PowerShell closer may only fire while a window titled
        ; exactly "Firestone - Main" exists SIMULTANEOUSLY. On a slow cold
        ; launch the loading window can retitle itself INTO the forming Main
        ; inside the closer's Get‑Process→CloseMainWindow gap (hundreds of
        ; ms), and the deferred WM_CLOSE then lands on the Main — the rare
        ; "Firestone Main didn't survive the cold launch". With a Main
        ; already present the loading hwnd can no longer BECOME the Main, so
        ; the close is structurally safe; until then the popup stays hidden
        ; by the suppression above, which is all the user could see anyway.
        if (popupStillExists && fsMainTitled)
            _FireFirestoneLoadingPSClose()

        if (State.fsLoadingSeen && !popupStillExists)
            StopKillFirestoneLoading()
    }
    DetectHiddenWindows prev
    SetTitleMatchMode prevMode
}

; Closes any already‑open Firestone - Loading popup immediately.
KillFirestoneLoadingExisting() {
    global CFG
    prevDHW := A_DetectHiddenWindows
    DetectHiddenWindows true
    try {
        ; Structural guard: a bare "Firestone - Loading" window may only be closed
        ; while a window titled exactly "Firestone - Main" exists simultaneously. Until
        ; then the Loading window could still retitle into the forming Main, so it is
        ; only concealed -- which is all the user could perceive either way.
        fsMainTitled := false
        for exe in ["Overwolf.exe", "OverwolfBrowser.exe"] {
            for h in WinGetList("ahk_exe " . exe) {
                try {
                    if (WinGetTitle("ahk_id " . h) == "Firestone - Main")
                        fsMainTitled := true
                }
            }
        }
        for exe in ["Overwolf.exe", "OverwolfBrowser.exe"] {
            for h in WinGetList("ahk_exe " . exe) {
                try {
                    if (WinGetTitle("ahk_id " . h) == "Firestone - Loading") {
                        ; Suppress, don't close (see CFG.fsCloseLoadingPopup).
                        ; On the same-HWND Loading->Main retitle this close
                        ; lands on Firestone - Main, and with close-to-tray on
                        ; that leaves the window alive but gutted.
                        CloakWindow(h)
                        if (CFG.fsCloseLoadingPopup && fsMainTitled)
                            _CloseWindowAsync(h)
                    }
                }
            }
        }
    }
    DetectHiddenWindows prevDHW
}

; ── PowerShell‑based Firestone - Loading closer ──────────────────────────────
; Debounced to at most once per 100ms to close the popup faster.
; Powershell.exe startup latency is ~300ms, but the debounce is now shorter
; to allow more frequent attempts while still avoiding a flood.
global _LastFSLoadingPSCloseTick := 0
_FireFirestoneLoadingPSClose() {
    global _LastFSLoadingPSCloseTick, CFG
    ; See CFG.fsCloseLoadingPopup. CloseMainWindow() targets the PROCESS's main
    ; window, which during launch is the HWND that becomes Firestone - Main;
    ; with close-to-tray enabled a stray hit leaves a live but gutted window.
    if !CFG.fsCloseLoadingPopup
        return
    if (A_TickCount - _LastFSLoadingPSCloseTick < 100)   ; reduced debounce
        return
    _LastFSLoadingPSCloseTick := A_TickCount

    ; Second layer of the cold‑launch guard: the title is re‑verified INSIDE
    ; PowerShell (Process.Refresh) immediately before CloseMainWindow, so the
    ; check‑to‑close race shrinks from hundreds of ms to ~1ms.
    psCmd :=
        "Get-Process "
      . "| ForEach-Object { $_.Refresh(); "
      . "if ($_.MainWindowTitle -eq 'Firestone - Loading') "
      . "{ $_.CloseMainWindow() | Out-Null } }"

    cmd := 'powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command "' . psCmd . '"'
    try Run(cmd, , "Hide")
}

; First sighting of every Overwolf top-level window, used only by the
; diagnostic below. See the FS-LOADING log line for what it answers.
global _fsOWFirstSeen := Map()

; ── "Why is that window still on screen?" ────────────────────────────────────
; Records any Firestone-family window that is VISIBLE while the lock is on and
; nothing has concealed it. That combination should not occur, so a line here
; is always a bug -- and it carries the four facts needed to identify which
; one: the title, the size, the extended styles, and whether the lock was
; actually on at the time.
;
; This exists because the last three reports of "it was not hidden" each had
; several plausible explanations and no way to choose between them. Once per
; window, so a 10ms sweep cannot flood the log.
global _fsVisibleLogged := Map()
_FSLogVisibleSurface(hwnd) {
    global _fsVisibleLogged, State
    try {
        if _fsVisibleLogged.Has(hwnd)
            return
        if !DllCall("user32\IsWindowVisible", "Ptr", hwnd)
            return
        title := WinGetTitle("ahk_id " . hwnd)
        if (title = "" || !InStr(title, "Firestone"))
            return
        if (title = "Firestone - Overlays")      ; supposed to be visible
            return
        if IsWindowCloakedDWM(hwnd)              ; concealed after all
            return
        _fsVisibleLogged[hwnd] := true
        w := 0, h := 0, ex := 0, st := 0
        try WinGetPos(, , &w, &h, "ahk_id " . hwnd)
        try ex := WinGetExStyle("ahk_id " . hwnd)
        try st := WinGetStyle("ahk_id " . hwnd)
        _FSLog("FS-VISIBLE unconcealed Firestone window hwnd=" . hwnd
             . " title=`"" . title . "`" size=" . w . "x" . h
             . " ex=" . Format("0x{:X}", ex) . " style=" . Format("0x{:X}", st)
             . " locked=" . (State.fsMainLocked ? 1 : 0)
             . " -- this window should have been concealed and was not")
    }
}

SuppressFirestoneLoadingTick() {
    global State, _fsHiddenByUs, _fsOWFirstSeen
    prev     := A_DetectHiddenWindows
    prevMode := A_TitleMatchMode
    DetectHiddenWindows true
    SetTitleMatchMode(3)

    try {
        for exe in ["Overwolf.exe", "OverwolfBrowser.exe"] {
            for h in WinGetList("ahk_exe " . exe) {
                try {
                    ; Stamp every Overwolf window the first time this sweep
                    ; sees it, titled or not. Costs one Map lookup per window
                    ; per tick and answers the one question the log could not:
                    ; how long the loading window existed BEFORE it was
                    ; identifiable.
                    if !_fsOWFirstSeen.Has(h)
                        _fsOWFirstSeen[h] := A_TickCount

                    isPopup := IsLikelyFirestoneLoadingPopupHwnd(h)
                    if !isPopup {
                        _FSLogVisibleSurface(h)   ; diagnostic only
                        continue
                    }

                    ; ---- WHY THIS LINE EXISTS ----
                    ; This sweep can only match "Firestone - Loading" by exact
                    ; title, so it is blind to the window for as long as the
                    ; window is untitled. If the splash is ever visible before
                    ; suppression, there are exactly two possible causes and
                    ; they need opposite fixes: either the funnel declined to
                    ; act on it (FS-EXEMPT names that), or it was on screen
                    ; with no title for long enough to be seen (this names
                    ; that). A large untitled= value here is the second.
                    ; Logged once per launch, on the first identification.
                    if !State.fsLoadingSeen
                        _FSLog("FS-LOADING identified hwnd=" . h
                             . " untitled=" . (A_TickCount - _fsOWFirstSeen.Get(h, A_TickCount)) . "ms"
                             . " visible=" . (DllCall("user32\IsWindowVisible", "Ptr", h) ? 1 : 0)
                             . " cloaked=" . (IsWindowCloakedDWM(h) ? 1 : 0))

                    State.fsLoadingSeen := true

                    ; SOLE OWNER of loading-window suppression, and funnelled.
                    ; The old body was cloak -> SW_HIDE -> SW_MINIMIZE every
                    ; tick, unconditionally, with an identical copy of itself
                    ; running in KillFirestoneLoading at the same rate. The
                    ; SW_MINIMIZE re-showed what the SW_HIDE had just hidden,
                    ; so the pair was a visibility flip rather than a hide, and
                    ; this HWND is the one that becomes Firestone - Main.
                    ;
                    ; The funnel is idempotent: the cloak is arbitrated through
                    ; _cloakState, the park is gated on _fsParked, and the warm
                    ; hide is skipped outright when the window is already
                    ; invisible. Running it at 10 ms is now free.
                    _FSSuppressSurface(h, "Firestone - Loading", true)
                } catch {
                }
            }
        }
    }

    DetectHiddenWindows prev
    SetTitleMatchMode prevMode
}

; Run the exact‑title popup suppression/close loop at 10ms intervals for up to
; 60s, while simultaneously keeping the popup suppression burst active.
StartKillFirestoneLoading() {
    global State, _fsPopupWatchDone, _fsOWFirstSeen, _fsExemptLogged, _fsVisibleLogged
    State.fsLoadingSeen := false
    ; Fresh measurement per launch. Both maps are diagnostic ledgers scoped to
    ; one Firestone start-up; carrying entries over from a previous F2 would
    ; report an untitled= age measured from the wrong process.
    _fsOWFirstSeen       := Map()
    _fsExemptLogged      := Map()
    _fsVisibleLogged     := Map()
    _fsPopupWatchDone := false   ; popup lifecycle open — early cloak waits on it
    SuppressFirestoneLoadingTick()
    KillFirestoneLoading()
    SetTimer(SuppressFirestoneLoadingTick, 10)
    ; KillFirestoneLoading now runs at 50 ms to close the loading popup faster.
    ; It no longer suppresses anything -- it only does bookkeeping and the
    ; PowerShell close (now enabled by default via fsCloseLoadingPopup=true).
    SetTimer(KillFirestoneLoading, 50)
    SetTimer(StopKillFirestoneLoading, -60000)
}

StopKillFirestoneLoading(*) {
    global State, _fsPopupWatchDone, _EarlyOWCloakActive
    SetTimer(SuppressFirestoneLoadingTick, 0)
    SetTimer(KillFirestoneLoading, 0)
    State.fsLoadingSeen := false
    _fsPopupWatchDone := true
    ; NOTE: early Overwolf cloak is NOT stopped here; it owns its own lifetime.
}

; ── Title helpers ─────────────────────────────────────────────────────────────

; Matches the standalone Firestone desktop app window.
IsFirestoneMainTitle(title) {
    if (title = "")
        return false
    return (title = "Firestone - Main")
}

; Matches any Firestone window that should be suppressed at all times.
; "Firestone - Loading" is deliberately NOT included – it is closed,
; not toggled with F3.
IsFirestoneSuppressionTitle(title) {
    return (title = "Firestone - Main" || title = "Firestone - Battlegrounds")
}

; ── Allow-list classification (see CFG.fsVisibleTitles) ──────────────────────
; TRUE only for a title that must be allowed to render while the lock is on.
; Everything else in the Overwolf family is suppressed by default.
IsFSVisibleTitle(title) {
    global CFG
    if (title = "")
        return false
    for t in CFG.fsVisibleTitles {
        if (title = t)
            return true
    }
    return false
}

; TRUE when this Overwolf-family window should be kept off the screen right
; now. The single decision point -- every janitor asks this instead of
; open-coding its own "is this one of ours?" test, which is how the three
; reveal paths ended up disagreeing with each other.

FSShouldSuppress(title) {
    global State
    if !State.fsMainLocked
        return false
    ; ALLOW-LIST, NOT DENY-LIST. DO NOT INVERT THIS AGAIN.
    ;
    ; "Should this stay concealed?" is answered by exclusion from a very short
    ; list of titles that are allowed to be seen -- currently just the in-game
    ; overlay. Everything else stays concealed while the lock is on.
    ;
    ; It was briefly changed to "only suppress windows whose title says
    ; Firestone", to stop the script managing other Overwolf apps' windows.
    ; That reasoning was right and the change was in the wrong place: the
    ; CALLER treats "not suppressed" as "actively show it" and calls
    ; ShowWindow. So the inversion did not merely stop concealing Overwolf's
    ; own infrastructure -- "OverWolf Server", untitled CEF frames, windows
    ; Overwolf itself keeps hidden -- it dragged them onto the desktop as blank
    ; white rectangles.
    ;
    ; The problem it was aimed at is solved where it belongs instead: _FSMayPark
    ; refuses to park anything it cannot name as Firestone's, so no other app's
    ; window ever enters the ledger F3 restores from.
    return !IsFSVisibleTitle(title)
}

; Diagnostic: one log line per distinct Overwolf surface signature per session.
; Purpose is identification, not debugging noise -- if a window still gets
; through, this names its exe, class, title and size so it can be added to a
; list by fact instead of by guess.
global _fsSurfaceLogged := Map()
_LogFSSurface(hwnd, title, decision) {
    global CFG, _fsSurfaceLogged
    if !CFG.fsLogUnclassified
        return
    try {
        exe := "", cls := "", w := 0, h := 0
        try exe := WinGetProcessName("ahk_id " . hwnd)
        try cls := WinGetClass("ahk_id " . hwnd)
        try WinGetPos(, , &w, &h, "ahk_id " . hwnd)
        sig := exe . "|" . cls . "|" . title . "|" . decision
        if _fsSurfaceLogged.Has(sig)
            return
        _fsSurfaceLogged[sig] := true
        FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss")
            . " FS-SURFACE " . decision
            . " exe=" . exe . " class=" . cls
            . " title=`"" . title . "`" size=" . w . "x" . h . "`n"
            , A_Temp . "\hs_bg_f1.log")
    }
}

; Matches the Firestone - Battlegrounds window (standalone stats/board view).
IsFirestoneBattlegroundsTitle(title) {
    if (title = "")
        return false
    return (title = "Firestone - Battlegrounds")
}

; Matches the "Firestone" notification popup (e.g. "Your abilities are ready!")
; ══════════════════════════════════════════════════════════════════════════════
;  THE NOTIFICATION POPUP IS KILLED, NOT MANAGED
; ══════════════════════════════════════════════════════════════════════════════
; One function, called from every site that can identify the popup, so there is
; exactly one answer to "what happens to it": it is cloaked so it never paints,
; and closed immediately.
;
; NO STABILITY WAIT, and that is the change. The sweeper deliberately waited for
; a window to hold a matching title and size for a stretch before closing it,
; because a sweep sees windows at arbitrary moments and a half-built window can
; briefly resemble anything. That caution is unnecessary here: this is reached
; from the CREATE and NAMECHANGE events, which fire ON the transition, and from
; the funnel, which has already established identity. The window is killed at
; its beginning rather than a second and a half into its life.
;
; INDEPENDENT OF F3. The lock decides whether Firestone's real windows are on
; screen. It has no opinion about a notification, and wiring one to the other
; produced the worst of both: a popup that appeared and disappeared as the user
; toggled their overlay. Nothing here reads State.fsMainLocked.
;
; The identity ledger remains absolute -- a window that has ever carried the
; Main or Loading title is never closed here, whatever it is titled now.
; Is a window titled exactly "Firestone - Main" open RIGHT NOW, other than this
; one? Hidden windows count -- Main is concealed on purpose and is still open.
;
; This is the structural guarantee that the thing being closed is not Firestone
; Main, and it is not a heuristic: if Main exists as its own separate window,
; then whatever else is sitting there titled bare "Firestone" is, by
; definition, not Main.
_FSMainWindowPresent(excludeHwnd := 0) {
    prev  := A_DetectHiddenWindows
    DetectHiddenWindows true
    found := false
    try {
        for exe in ["Overwolf.exe", "OverwolfBrowser.exe"] {
            for h in WinGetList("ahk_exe " . exe) {
                try {
                    if (h != excludeHwnd && IsFirestoneMainTitle(WinGetTitle("ahk_id " . h))) {
                        found := true
                        break
                    }
                }
            }
            if found
                break
        }
    }
    DetectHiddenWindows prev
    return found
}

global _fsPopupKilled    := Map()
global _fsPopupFirstSeen := Map()   ; hwnd -> first sighting, for the grace
_FSKillNotificationPopup(hwnd, why) {
    global _fsPopupKilled, _fsPopupFirstSeen, _fsMainCandidate
    global _fsMainEverOpened, CFG
    try {
        if _fsMainCandidate.Has(hwnd)      ; it is, or becomes, Main: never
            return false
        if _fsPopupKilled.Has(hwnd)        ; asked once is enough
            return false

        ; ── THE STRUCTURAL GUARD. DO NOT REMOVE IT AGAIN. ──────────────────
        ; A bare-"Firestone" window may only be closed while a SEPARATE window
        ; titled exactly "Firestone - Main" also exists.
        ;
        ; The reason is that the title and size cannot tell the notification
        ; apart from Firestone Main. Main is titled just "Firestone" in some
        ; states -- while it is loading, showing "Getting ready" -- and at a
        ; size squarely inside the envelope the popup matcher accepts. They are
        ; the same window to every static test available.
        ;
        ; This guard was in the original sweeper and the fast kill paths added
        ; later bypassed it. The result was exactly what it sounds like: one F3
        ; press revealed Main, Main's title changed, the NAMECHANGE handler saw
        ; a bare-"Firestone" window of popup size, and closed the user's
        ; Firestone. Speed is worth nothing if it is occasionally aimed at the
        ; wrong window.
        ;
        ; Checked here, in the one function every kill path calls, so no future
        ; caller can route around it.
        ;
        ; TWO WAYS TO SATISFY IT, because requiring (a) alone was too strict: a
        ; notification arriving while Main is closed could then never be closed
        ; at all, which is the "popup was not closed" report.
        ;
        ;   (a) A separate "Firestone - Main" window exists right now, so this
        ;       window is provably not Main. Acted on immediately.
        ;
        ;   (b) Main has opened at some point this session, this HWND has never
        ;       carried a Main or Loading title, and it has sat there titled
        ;       bare "Firestone" for longer than CFG.fsPopupGraceMs. A Main that
        ;       is still forming retitles within a second or so; a notification
        ;       keeps that bare title for its whole life. Waiting out that
        ;       window is the only honest way to separate them when Main is not
        ;       present to compare against.
        ;
        ; EITHER WAY THE WINDOW IS CLOAKED ON FIRST SIGHTING, BEFORE ANY OF THIS.
        ; Concealment is reversible and costs nothing if the judgement is wrong;
        ; closing is neither. So it never paints while its identity is settled.
        CloakWindow(hwnd)
        _DisableDWMTransitions(hwnd)
        if !_fsPopupFirstSeen.Has(hwnd)
            _fsPopupFirstSeen[hwnd] := A_TickCount

        safeToClose := _FSMainWindowPresent(hwnd)
        if (!safeToClose
         && (A_TickCount - _fsPopupFirstSeen[hwnd]) >= CFG.fsPopupGraceMs)
            safeToClose := true

        ; The _fsMainEverOpened precondition that used to sit on that second
        ; branch is GONE. It was meant as extra caution and acted as a third
        ; way for the close to be blocked forever -- if the flag never got set,
        ; a popup that appeared while Main was closed could never be closed at
        ; all, which is precisely the recurring complaint.
        ;
        ; Nothing is lost by removing it. The protection that matters is
        ; _fsMainCandidate, checked at the top of this function: an HWND that
        ; has ever carried the Main or Loading title can never be closed here,
        ; whatever it is titled now and whatever any flag says. That is a
        ; property of the window itself rather than of a flag somebody has to
        ; remember to set.

        if !safeToClose {
            ; ── INVISIBLE IS NOT ENOUGH. GET IT OUT OF THE WAY. ─────────────
            ; A DWM-cloaked window is not drawn, but it is still THERE: it
            ; still hit-tests, so it still swallows every mouse click that
            ; lands on it. A popup left cloaked in the middle of the screen
            ; over Hearthstone is an invisible sheet of glass over the board --
            ; the user clicks the game and nothing happens, with nothing on
            ; screen to explain why.
            ;
            ; So it is also moved off the virtual desktop. Deliberately a bare
            ; SetWindowPos rather than _FSParkWindow: parking RECORDS the
            ; window so it can be restored, and this window must never be
            ; restored -- it is waiting to be closed. No ledger entry, nothing
            ; to bring it back, and no clicks intercepted while it waits.
            try {
                vx := SysGet(76), vy := SysGet(77)
                vw := SysGet(78), vh := SysGet(79)
                DllCall("user32\SetWindowPos", "Ptr", hwnd, "Ptr", 0
                    , "Int", vx + vw + 2000, "Int", vy + vh + 2000
                    , "Int", 0, "Int", 0
                    , "UInt", 0x0001 | 0x0004 | 0x0010)  ; NOSIZE|NOZORDER|NOACTIVATE
            }
            _FSLog("FS-POPUP cloaked and moved off-screen, not yet closed,"
                 . " hwnd=" . hwnd . " at " . why . " -- cannot yet prove it is"
                 . " not Firestone Main. It is invisible AND cannot intercept"
                 . " clicks; it will be closed the moment it can be told apart.")
            return false
        }

        _fsPopupKilled[hwnd] := A_TickCount
        _CloseWindowAsync(hwnd)
        w := 0, h := 0
        try WinGetPos(, , &w, &h, "ahk_id " . hwnd)
        _FSLog("FS-POPUP killed at " . why . " hwnd=" . hwnd
             . " size=" . w . "x" . h . " -- cloaked and closed on sight")
        return true
    }
    return false
}

IsFirestoneNotificationPopup(hwnd, title) {
    if (title != "Firestone")
        return false
    w := 0, h := 0
    try WinGetPos(, , &w, &h, "ahk_id " . hwnd)
    if (w < 300 || h < 300 || w > 800 || h > 800)
        return false
    exStyle := 0
    try exStyle := WinGetExStyle("ahk_id " . hwnd)
    if (exStyle & 0x20)   ; WS_EX_TRANSPARENT — click‑through overlay, never close
        return false
    ; NO WS_EX_TOPMOST EXCLUSION HERE -- and this comment exists so it is not
    ; added back.
    ;
    ; It was, on the theory that Overwolf draws its in-game surfaces topmost so
    ; a pinned comp panel would be excluded by that bit. The theory was wrong in
    ; the way that mattered: the "Your abilities are ready!" notification is
    ; topmost too, so the exclusion did not protect pins, it simply stopped this
    ; function ever identifying anything, and the popup the closer exists to
    ; remove was never removed. It sat on screen being cloaked and un-cloaked by
    ; the F3 lock instead of being closed.
    ;
    ; Pins are protected by the mechanism that was actually broken -- see
    ; UncloakWindow's _MapDrop note, where an exception was aborting the overlay
    ; topmost enforcer on nearly every tick. If a pinned panel is ever closed
    ; anyway, the FS-POPUP log line below names the exact window and size, which
    ; is the evidence needed to write a discriminator that is not a guess.
    return true
}

;  Per-hwnd tick of the first time a window matched the popup shape while
;  titled exactly "Firestone". Retained as evidence that the window's size has
;  settled, and for the log; it no longer gates whether the window is closed.
global _fsNotifFirstMatch := Map()
global _fsDeferredPopupCloak := Map()   ; hwnd -> tick handed over by the
                                        ; blanket's stop-release

; BACKSTOP sweep for the Firestone notification popup.
;
; The popup is normally dead before this ever sees it: the NAMECHANGE handler
; in the window event hook kills it within milliseconds of it being titled, and
; the suppression funnel kills any that reaches it. This sweep exists for the
; cases an event cannot cover -- a popup that already existed when the script
; started, or one created while the hook was being re-armed.
;
; The guards that remain are the ones that protect Firestone's REAL windows,
; and they are structural rather than timing-based:
;   * ABSOLUTE: an HWND that has ever carried the "Firestone - Main" or
;     "Firestone - Loading" title is never closed, whatever it is titled now
;     (_fsMainCandidate). This is the guarantee; everything else is secondary.
;   * ABSOLUTE: never close a window flagged by the pre-title alpha shield
;     (the >=600x400 formation profile of a Main still being built).
;   * Never close a minimized window.
;
; The old ten-second, then 1.2-second, "hold the match before acting" timer is
; gone. It was a proxy for the identity question above, which is now answered
; directly and cannot be fooled by timing -- and every millisecond it bought in
; safety was a millisecond of nag popup on screen, which is the complaint.
_HSIsForeground() {
    try return WinActive("ahk_exe Hearthstone.exe") != 0
    return false
}

CloseFirestoneNotificationPopups() {
    global _EarlyOWCloakActive, State, _fsNotifFirstMatch
    global _fsDeferredPopupCloak, _fsAlphaApplied, _fsMainCandidate

    ; guard 1 -- kept for the early pre-title blanket, where windows genuinely
    ; have no identity yet.
    if _EarlyOWCloakActive
        return

    ; GUARD 1b REMOVED: the popup closer now runs regardless of F3 lock state.
    ; The popup must be terminated on creation, not toggled by F3.

    ; NO "STAND DOWN DURING A MATCH" GUARD HERE, deliberately.
    ;
    ; One was added, suppressing the close whenever the overlay was visible and
    ; Hearthstone had the foreground. That is the state a Battlegrounds player
    ; is in for essentially the whole session -- and it is also exactly when the
    ; "Your abilities are ready!" notification appears. The guard therefore
    ; disabled the closer at the only time it was ever needed.

    prev     := A_DetectHiddenWindows
    prevMode := A_TitleMatchMode
    DetectHiddenWindows true
    SetTitleMatchMode(3)   ; exact match only

    matched := Map()
    try {
        ; Guard 2 precondition: locate a titled Firestone - Main first.
        fsMainPresent := false
        for exe in ["Overwolf.exe", "OverwolfBrowser.exe"] {
            for h in WinGetList("ahk_exe " . exe) {
                try {
                    if IsFirestoneMainTitle(WinGetTitle("ahk_id " . h))
                        fsMainPresent := true
                } catch {
                }
            }
        }

        for exe in ["Overwolf.exe", "OverwolfBrowser.exe"] {
            for h in WinGetList("ahk_exe " . exe) {
                try {
                    title := WinGetTitle("ahk_id " . h)
                    if !IsFirestoneNotificationPopup(h, title)
                        continue
                    if !fsMainPresent                       ; guard 2
                        continue
                    ; guard 3 -- identity. An HWND that has ever carried the "Firestone - Loading"
                    ; or "Firestone - Main" title can never be closed here, whatever it is titled
                    ; now.
                    ;
                    ; This is the guarantee directly; testing whether the window is currently
                    ; DWM-cloaked is only a proxy for it, and one that collapses as soon as
                    ; concealment cloaks every suppressed surface.
                    if _fsMainCandidate.Has(h)              ; guard 3
                        continue
                    if (WinGetMinMax("ahk_id " . h) = -1)   ; guard 4
                        continue
                    if _fsAlphaApplied.Has(h)               ; guard 3b
                        continue

                    wNow := 0, hNow := 0
                    try WinGetPos(, , &wNow, &hNow, "ahk_id " . h)
                    matched[h] := true
                    if (!_fsNotifFirstMatch.Has(h)
                     || _fsNotifFirstMatch[h].w != wNow
                     || _fsNotifFirstMatch[h].h != hNow) {
                        _fsNotifFirstMatch[h] := {t: A_TickCount, w: wNow, h: hNow}
                        continue
                    }
                    ; NO STABILITY WAIT. This sweep is now a BACKSTOP: the
                    ; popup is normally killed by the NAMECHANGE handler within
                    ; milliseconds of being titled, and only reaches here if
                    ; that event was missed -- a hook that was not armed yet, a
                    ; window that existed before the script started. Having
                    ; identified it, waiting a further settling period before
                    ; acting would only extend the time it is on screen, which
                    ; is the entire complaint.
                    ;
                    ; The stability ledger is still maintained above, because it
                    ; is what proves the window's size settled -- but it no
                    ; longer gates the kill.
                    _FSKillNotificationPopup(h, "sweeper backstop")
                } catch {
                }
            }
        }

        ; Prune ledger entries that did not match this pass.
        stale := []
        for h in _fsNotifFirstMatch {
            if !matched.Has(h)
                stale.Push(h)
        }
        for h in stale
            _fsNotifFirstMatch.Delete(h)

        ; Deferred‑set hygiene.
        staleDef := []
        for h in _fsDeferredPopupCloak {
            keep := false
            try {
                if DllCall("user32\IsWindow", "Ptr", h) {
                    tD := WinGetTitle("ahk_id " . h)
                    keep := (tD = "Firestone" || tD = "")
                }
            }
            if !keep
                staleDef.Push(h)
        }
        for h in staleDef {
            _fsDeferredPopupCloak.Delete(h)
            try {
                if !DllCall("user32\IsWindow", "Ptr", h)
                    continue
                t := WinGetTitle("ahk_id " . h)
                if (IsFirestoneSuppressionTitle(t) && State.fsMainLocked)
                    continue
                if _fsAlphaApplied.Has(h)
                    _RemoveFSAlphaShield(h)
                _FSReleaseSurface(h)   ; unpark, then uncloak
            }
        }
    }
    DetectHiddenWindows prev
    SetTitleMatchMode prevMode
}

; ── Firestone notification‑popup sweeper (F2 launch window) ──────────────────
; The bare‑"Firestone" nag popup is the ONE Firestone window we deliberately
; CLOSE rather than hide. The sweeper runs on a gentle cadence for 90s.
global _fsNotifSweepUntil := 0

StartFSNotifSweeper() {
    global _fsNotifSweepUntil, _fsNotifFirstMatch
    _fsNotifSweepUntil := 0   ; no expiry – runs forever
    _fsNotifFirstMatch := Map()
    SetTimer(FSNotifSweepTick, 750)
    CloseFirestoneNotificationPopups()   ; immediate pass
}

StopFSNotifSweeper() {
    global _fsNotifSweepUntil
    _fsNotifSweepUntil := 0
    SetTimer(FSNotifSweepTick, 0)
    _ReleaseDeferredPopupCloaks()
}

FSNotifSweepTick() {
    ; The sweeper runs indefinitely at a gentle cadence, closing the
    ; notification popup whenever it appears. It is not tied to F3 lock state.
    CloseFirestoneNotificationPopups()
}

; Janitor of last resort for the deferred‑popup set.
_ReleaseDeferredPopupCloaks() {
    global _fsDeferredPopupCloak, _fsAlphaApplied, State, _fsMainCandidate

    fsMainPresent := false
    prevDHW := A_DetectHiddenWindows
    DetectHiddenWindows true
    try {
        for exe in ["Overwolf.exe", "OverwolfBrowser.exe"] {
            for hh in WinGetList("ahk_exe " . exe) {
                try {
                    if IsFirestoneMainTitle(WinGetTitle("ahk_id " . hh))
                        fsMainPresent := true
                }
            }
        }
    }
    DetectHiddenWindows prevDHW

    for h, tickIn in _fsDeferredPopupCloak.Clone() {
        try {
            if !DllCall("user32\IsWindow", "Ptr", h)
                continue
            t := WinGetTitle("ahk_id " . h)
            if (IsFirestoneSuppressionTitle(t) && State.fsMainLocked)
                continue

            ; TOAST PROOF — HARDENED. A member is now closable only when ALL
            ; of these hold:
            ;   • never flagged by the pre‑title alpha shield,
            ;   • its RESTORED size is inside the popup envelope,
            ;   • a titled Firestone - Main exists RIGHT NOW,
            ;   • it has held the bare title for >=45s.
            ; Same rule as the sweeper: never close anything while the lock
            ; is off and the user is looking at Firestone's windows.
            closable := false
            if (State.fsMainLocked
             && t = "Firestone"
             && IsFirestoneNotificationPopup(h, t)
             && !_fsAlphaApplied.Has(h)
             && !_fsMainCandidate.Has(h)      ; same identity guard as the closer
             && fsMainPresent
             && (A_TickCount - tickIn >= 45000)) {
                _GetRestoredSize(h, &dw, &dh)
                if (dw >= 300 && dh >= 300 && dw <= 800 && dh <= 800)
                    closable := true
            }
            if closable {
                try _CloseWindowAsync(h)
                continue
            }

            if _fsAlphaApplied.Has(h)
                _RemoveFSAlphaShield(h)
            _FSReleaseSurface(h)   ; unpark, then uncloak
        }
    }
    _fsDeferredPopupCloak := Map()
}

; ──────────────────────────────────────────────────────────────────────────────
; Firestone‑Main suppression model
; ──────────────────────────────────────────────────────────────────────────────
;
; While the F3 lock is ON (State.fsMainLocked), every FSMainMonitor tick:
;   • DWM‑cloaks FS‑Main (async compositor‑level invisibility),
;   • applies the ALPHA SHIELD (WS_EX_LAYERED, alpha 0) to windows that were
;     not already layered — Overwolf‑layered ones are recorded, never touched,
;   • re‑minimizes it animation‑free (SetWindowPlacement) if it isn't
;     minimized, throttled to one attempt per 250ms per hwnd.
;
; Cadence:
;   Burst (1ms)   → during F2 pipeline and Firestone‑Loading suppression window
;   Coast (200ms) → after CompleteHSLaunchSuccess (safety net only)
;   Off           → F3 unlocked

LockFirestoneMain() {
    global State, _fsMinLastAttempt, Launch, CFG
    StopFSReveal()               ; a re‑lock must cancel any in‑flight F3 reveal
    State.fsMainLocked := true
    _fsMinLastAttempt := Map()   ; fresh lock ⇒ first minimize fires immediately

    ; ── Burst only while windows are actually being created ──────────────────────
    ; StartFSBurst pins the suppression sweep at CFG.fsBurstMs for twenty seconds,
    ; and that sweep enumerates every Overwolf window and reads every title --
    ; roughly a thousand full enumerations per second on a script running at high
    ; process priority, which saturates AutoHotkey's single thread.
    ;
    ; The burst is only needed while windows are being created: a launch, or the
    ; deferred Firestone start, which arms it explicitly. A re-lock creates nothing
    ; -- the windows already exist, the event hook catches any that appear, and
    ; concealment is idempotent -- so a re-lock coasts.
    launching := State.f2Active
              || (Launch.state != "IDLE" && Launch.state != "DONE")
    if launching
        StartFSBurst()           ; 1 ms while newborn windows are likely
    else
        SetTimer(FSMainMonitor, CFG.fsCoastMs)   ; steady state: 50 ms watchdog
    SuppressFirestoneMainTick()  ; immediate enforcement pass
    ; STRESS HARDENING: a second synchronous pass in the SAME thread turn.
    ; Under rapid F3, a re-lock landing microseconds after an unlock must
    ; re-hide both FS windows NOW, not one burst tick later -- otherwise a
    ; just-revealed window can sit visible for a frame before the burst
    ; catches it. Two back-to-back passes close that gap deterministically.
    SuppressFirestoneMainTick()
}

; ── Burst controls ────────────────────────────────────────────────────────────
; Ref‑count for timeBeginPeriod(1). Multiple subsystems may all need high‑res
; resolution simultaneously.
global _highResRefCount := 0

_AcquireHighResTimer() {
    global _highResRefCount
    if (_highResRefCount = 0)
        try DllCall("winmm\timeBeginPeriod", "UInt", 1)
    _highResRefCount++
}

_ReleaseHighResTimer() {
    global _highResRefCount
    if (_highResRefCount <= 0) {
        _highResRefCount := 0
        return
    }
    _highResRefCount--
    if (_highResRefCount = 0)
        try DllCall("winmm\timeEndPeriod", "UInt", 1)
}

_ForceReleaseHighResTimer() {
    global _highResRefCount, _fsBurstHasRef, _HSCloakerHasRef, _EarlyOWCloakHasRef, _launcherHideHasRef
    if (_highResRefCount > 0)
        try DllCall("winmm\timeEndPeriod", "UInt", 1)
    _highResRefCount     := 0
    _fsBurstHasRef       := false
    _HSCloakerHasRef     := false
    _EarlyOWCloakHasRef  := false
    _launcherHideHasRef  := false
}

; ── Normal burst (FSMainMonitor at 1ms + timeBeginPeriod) ────────────────────
; Each subsystem owns exactly one boolean tracking whether it currently holds
; a high‑res ref.
global _fsBurstHasRef := false

StartFSBurst() {
    global State, _fsBurstHasRef, CFG
    if !State.fsMainLocked
        return

    if !_fsBurstHasRef {
        _AcquireHighResTimer()
        _fsBurstHasRef := true
    }

    SetTimer(FSMainMonitor, CFG.fsBurstMs)
    ; Re-arm the decay on every call: a burst is a fixed-length window that
    ; restarts whenever something worth bursting for happens (a lock, an F2).
    ; Without this the 1 ms rate ran for the ENTIRE locked period -- and since
    ; the lock is armed at startup and only ever cleared by F3, that meant
    ; permanently, from boot.
    SetTimer(_FSBurstDecay, -CFG.fsBurstMaxMs)
}

; Drop the suppression sweep from the burst rate to the coast rate and give up
; the high-resolution timer period. Suppression itself is unchanged -- only how
; often it re-checks. Safe to call at any time, including twice.
_FSBurstDecay(*) {
    global State, _fsBurstHasRef, CFG
    if _fsBurstHasRef {
        _ReleaseHighResTimer()
        _fsBurstHasRef := false
    }
    if !State.fsMainLocked {
        SetTimer(FSMainMonitor, 0)
        return
    }
    SetTimer(FSMainMonitor, CFG.fsCoastMs)
}

StopFSBurst() {
    global State, _fsBurstHasRef, CFG

    SetTimer(_FSBurstDecay, 0)          ; no decay can fire after an explicit stop

    if _fsBurstHasRef {
        _ReleaseHighResTimer()
        _fsBurstHasRef := false
    }

    if !State.fsMainLocked {
        SetTimer(FSMainMonitor, 0)
        return
    }

    ; Previously this re-armed the 1 ms rate whenever ANY other subsystem still
    ; held a high-res timer ref -- so stopping the burst could leave the sweep
    ; running at full speed indefinitely. Coast unconditionally instead.
    SetTimer(FSMainMonitor, CFG.fsCoastMs)
}

; Suppression tick. Cloaks FS‑Main / FS‑Loading so DWM refuses to render them.
SuppressFirestoneMainTick() {
    global State, CFG, _fsBirthHidden, _fsHiddenByUs, _fsAlphaApplied

    ; ---- birth-hide timeout sweep (safety net) ----
    ; Guarantees no window stays hidden by accident: anything birth-hidden
    ; that never resolved to one of our titles is force-shown once it is
    ; older than CFG.fsBirthHideMaxMs. Usually iterates an empty map.
    if _fsBirthHidden.Count {
        for bhwnd, bat in _fsBirthHidden.Clone() {
            try {
                if !DllCall("user32\IsWindow", "Ptr", bhwnd) {
                    _MapDrop(_fsBirthHidden, bhwnd)
                    continue
                }
                if (A_TickCount - bat < CFG.fsBirthHideMaxMs)
                    continue
                btitle := ""
                try btitle := WinGetTitle("ahk_id " . bhwnd)
                ; _MapDrop: this iterates a Clone, so a hotkey thread can have
                ; removed the key already. A throw here would skip the
                ; reveal/keep-hidden decision below entirely.
                _MapDrop(_fsBirthHidden, bhwnd)
                ; Allow-list, not deny-list. Classifying by exclusion -- suppress a short list
                ; of known titles and reveal everything else -- means any Overwolf window with
                ; an unrecognised title ("OverWolf Server", untitled CEF frames) is treated as
                ; benign and actively shown. Only titles on CFG.fsVisibleTitles are released;
                ; everything else stays concealed while the lock is on.
                if FSShouldSuppress(btitle) {
                    _fsHiddenByUs[bhwnd] := true      ; ours: stays hidden
                    _LogFSSurface(bhwnd, btitle, "kept-hidden")
                } else {
                    ; RELEASE, BUT ONLY SHOW WHAT WE HID.
                    ;
                    ; Releasing our own concealment (unpark, uncloak) is always
                    ; correct -- it undoes something this script did. Calling
                    ; ShowWindow is not: a window can be invisible because
                    ; OVERWOLF wants it invisible, and forcing it on screen puts
                    ; a blank internal frame on the user's desktop.
                    ;
                    ; The ledger is the difference. _fsHiddenByUs records the
                    ; windows this script took off the screen, and those are the
                    ; only ones it has any business putting back.
                    _LogFSSurface(bhwnd, btitle, "released")
                    _FSReleaseSurface(bhwnd)    ; unpark, then uncloak
                    if _fsHiddenByUs.Has(bhwnd) {
                        _FSShowIfNotPopup(bhwnd)
                        _MapDrop(_fsHiddenByUs, bhwnd)
                    }
                }
            }
        }
    }

    if !State.fsMainLocked
        return

    try {
        prev     := A_DetectHiddenWindows
        prevMode := A_TitleMatchMode
        DetectHiddenWindows true
        SetTitleMatchMode(2)

        for exe in CFG.fsFamilyExes {
            for h in WinGetList("ahk_exe " . exe) {
                try {
                    if !DllCall("IsWindow", "Ptr", h)
                        continue
                    title := WinGetTitle("ahk_id " . h)

                    ; ---- MUST-BE-VISIBLE: actively enforce, every tick ----
                    ; The in-game overlay is the one surface that has to
                    ; render. Nothing in the always-on path used to guarantee
                    ; that: the only un-hide paths were the event hook (which
                    ; was blind to hidden windows) and OverlayTopmostTick
                    ; (which only runs AFTER a successful launch). So an
                    ; overlay that got caught by the birth-hide simply stayed
                    ; hidden for the whole session with nothing to rescue it
                    ; -- the "overlay failed" symptom. Enforcing visibility
                    ; here, on the same 50 ms sweep that does the hiding,
                    ; makes that unrecoverable state impossible.
                    if IsFSVisibleTitle(title) {
                        ; Unconditional, NOT gated on a ledger entry: an
                        ; overlay stranded transparent by a previous instance
                        ; has no ledger entry, and it is precisely the case
                        ; that needs rescuing. Same reasoning now covers the
                        ; PARK: an overlay parked off the virtual desktop by
                        ; the birth suppression is just as unrecoverable as one
                        ; stranded transparent, so this sweep un-parks it too.
                        _RemoveFSAlphaShield(h)
                        _FSReleaseSurface(h)      ; unpark, then uncloak
                        if !DllCall("user32\IsWindowVisible", "Ptr", h) {
                            ; _MapDrop, not .Delete: an absent key throws in
                            ; v2, and a throw here would skip the ShowWindow
                            ; below -- leaving the overlay hidden, which is the
                            ; exact failure this branch exists to prevent.
                            _MapDrop(_fsHiddenByUs, h)
                            _MapDrop(_fsBirthHidden, h)
                            DllCall("ShowWindow", "Ptr", h, "Int", 8)  ; SW_SHOWNA
                        }
                        continue
                    }

                    if IsFirestoneSuppressionTitle(title) {
                        _SuppressFSHwnd(h, title)
                        continue
                    }

                    ; ---- EVERYTHING ELSE: suppressed while locked ----
                    ; Previously this only CLOAKED untitled / bare-"Firestone"
                    ; windows and ignored every other title outright, so a
                    ; window that settled to something like "OverWolf Server"
                    ; was never suppressed by this sweep at all -- and a cloak
                    ; alone is fragile: DWM clears it on some window
                    ; operations, and a window that gets uncloaked mid-paint
                    ; is exactly the black-rectangle-with-a-titlebar in the
                    ; screenshot. Cloak AND take it off the screen, ledgered
                    ; so F3 can bring it back.
                    if IsHelperWindow(h)
                        continue
                    ; UNTITLED AND UNRECOGNISED SURFACES. Firestone - Main is
                    ; born untitled, so this branch used to be hide number
                    ; three of five on Main's own HWND -- an unconditional
                    ; SW_HIDE at the 1 ms burst rate, before the window had a
                    ; name, let alone a frame. Funnelled, with probing enabled:
                    ; this is the settled sweep, so this is where measurement
                    ; belongs.
                    _LogFSSurface(h, title, "suppressed")
                    _FSSuppressSurface(h, title, true)
                } catch {
                }
            }
        }

        DetectHiddenWindows prev
        SetTitleMatchMode prevMode
    } catch {
        ; Swallow and let the next tick retry.
    }
}

; Per‑hwnd tick of last minimize ATTEMPT (not success) — throttles re‑minimize.
global _fsMinLastAttempt := Map()

; Per-hwnd tick of the FIRST time we saw this window carrying a suppression
; title. Powers the first-paint grace below.
global _fsFirstTitledAt := Map()

_SuppressFSHwnd(h, title := "") {
    global State, CFG, _fsFirstTitledAt

    ; Mid-pass unlock guard: hotkey threads interleave with timer threads,
    ; so an unlock can land between two windows of one suppression sweep.
    ; Without this, the tail of that sweep re-suppresses exactly what the
    ; reveal is about to show -- one avoidable flicker per stress cycle.
    if !State.fsMainLocked
        return

    ; The shield is ledger-only while CFG.fsUseAlphaShield is false, which it
    ; is. Kept because the notification sweeper's guard 3b reads the ledger.
    _ApplyFSAlphaShield(h)

    if !_fsFirstTitledAt.Has(h)
        _fsFirstTitledAt[h] := A_TickCount

    ; Concealment is delegated to _FSSuppressSurface, which is the single
    ; primitive every suppression site in this script funnels through.
    ;
    ; A per-function paint grace was tried here and cannot work: this function is
    ; the LAST of five owners to touch a Firestone window, so by the time a window
    ; arrives carrying the title Firestone - Main it has already been concealed by
    ; the event hook (at CREATE, at SHOW and at NAMECHANGE) and by the untitled
    ; branch of the settled sweep. A gate here guards a door the others have
    ; already walked through.
    ;
    ; allowProbe is true because this is a settled timer thread, which is the only
    ; context where the PrintWindow capture may run.
    _FSSuppressSurface(h, title, true)
}

; ──────────────────────────────────────────────────────────────────────────────
; Fresh‑launch early Overwolf cloaker
; ──────────────────────────────────────────────────────────────────────────────
; Runs during the startup popup phase. Cloaks only windows that match the
; likely Firestone‑loading popup so the real Overwolf overlay is not suppressed.
; Stopped only after the popup has disappeared and FS‑Main has been titled
; (plus a grace period).
global _EarlyOWCloakActive := false
global _EarlyOWCloakHasRef := false   ; tracks ownership of the high‑res ref
global _earlyCloakSawFSMainAt := 0    ; tick when a suppression‑titled window
                                      ; (FS‑Main / FS‑Battlegrounds) was first
                                      ; observed during THIS cloak session
global _fsPopupWatchDone := true      ; loading‑popup watchdog concluded

StartEarlyOverwolfCloak() {
    global _EarlyOWCloakActive, _EarlyOWCloakHasRef, _earlyCloakSawFSMainAt
    _EarlyOWCloakActive := true
    _earlyCloakSawFSMainAt := 0
    if !_EarlyOWCloakHasRef {
        _AcquireHighResTimer()
        _EarlyOWCloakHasRef := true
    }
    SetTimer(_EarlyCloakFailsafeStop, -120000)
    SetTimer(EarlyOverwolfCloakTick, 3)
    EarlyOverwolfCloakTick()
}

_EarlyCloakFailsafeStop(*) => StopEarlyOverwolfCloak()

StopEarlyOverwolfCloak(*) {
    global _EarlyOWCloakActive, _EarlyOWCloakHasRef, State, _fsAlphaApplied
    global _fsDeferredPopupCloak, _fsNotifSweepUntil
    _EarlyOWCloakActive := false
    SetTimer(EarlyOverwolfCloakTick, 0)
    SetTimer(_EarlyCloakFailsafeStop, 0)
    if _EarlyOWCloakHasRef {
        _ReleaseHighResTimer()
        _EarlyOWCloakHasRef := false
    }

    ; Release every non‑Firestone‑Main OW window.
    prev     := A_DetectHiddenWindows
    prevMode := A_TitleMatchMode
    DetectHiddenWindows true
    SetTitleMatchMode(2)
    try {
        for exe in ["Overwolf.exe", "OverwolfBrowser.exe"] {
            for h in WinGetList("ahk_exe " . exe) {
                try {
                    title := WinGetTitle("ahk_id " . h)

                    ; Leave anything the lock still owns alone. Was
                    ; `IsFirestoneSuppressionTitle(title) && State.fsMainLocked`
                    ; -- the same deny-list mistake, so ending the early cloak
                    ; UNCLOAKED every unrecognised Overwolf surface, which is a
                    ; third independent way the stray windows reached the
                    ; screen. FSShouldSuppress already folds in the lock state.
                    if FSShouldSuppress(title)
                        continue

                    ; A NOTIFICATION POPUP IS KILLED HERE, NEVER RELEASED.
                    ;
                    ; This used to hand the popup to the notification sweeper if
                    ; the sweeper was alive, and otherwise fall through to
                    ; _FSReleaseSurface -- which UNCLOAKS it. That fall-through
                    ; is how F3 painted the popup: the unlock path stopped the
                    ; sweeper one line earlier, so "is the sweeper alive" was
                    ; false and the release ran.
                    ;
                    ; There is no version of this where showing a notification
                    ; is the right outcome, so the sweeper's state no longer has
                    ; a vote. _FSKillNotificationPopup keeps it cloaked and
                    ; closes it, and its own guards still make closing Firestone
                    ; Main impossible.
                    if IsFirestoneNotificationPopup(h, title) {
                        _fsDeferredPopupCloak[h] := A_TickCount
                        _FSKillNotificationPopup(h, "early-cloak stop")
                        continue
                    }

                    if _fsAlphaApplied.Has(h)
                        _RemoveFSAlphaShield(h)
                    _FSReleaseSurface(h)      ; unpark, then uncloak
                } catch {
                }
            }
        }
    }
    DetectHiddenWindows prev
    SetTitleMatchMode prevMode
}

EarlyOverwolfCloakTick() {
    global _EarlyOWCloakActive, _earlyCloakSawFSMainAt, _fsPopupWatchDone, State, _fsHiddenByUs
    if !_EarlyOWCloakActive {
        SetTimer(EarlyOverwolfCloakTick, 0)
        return
    }

    prev := A_DetectHiddenWindows
    DetectHiddenWindows true
    try {
        for exe in ["Overwolf.exe", "OverwolfBrowser.exe"] {
            for h in WinGetList("ahk_exe " . exe) {
                try {
                    title := ""
                    try title := WinGetTitle("ahk_id " . h)

                    ; PROACTIVE UNCLOAK: if a window has settled to a known
                    ; "must be visible" title, ensure it's not still cloaked
                    ; -- and not still parked off the virtual desktop.
                    if (title = "Firestone - Overlays") {
                        _FSReleaseSurface(h)
                        continue
                    }

                    ; FS‑MAIN OBSERVED: stamp the sighting. CLOAK ONLY -- the
                    ; 1ms burst is the SOLE owner of the shield and the
                    ; minimize. The early-cloak applying the shield too was
                    ; half of the "Firestone fighting itself" cold-launch
                    ; crash (two timers, opposite-layer ops on one CEF
                    ; window). Cloak alone gives full invisibility here.
                    if IsFirestoneSuppressionTitle(title) {
                        if (!_earlyCloakSawFSMainAt && IsFirestoneMainTitle(title))
                            _earlyCloakSawFSMainAt := A_TickCount
                        if State.fsMainLocked
                            _FSSuppressSurface(h, title, false)
                        continue
                    }

                    ; PRE‑TITLE BLANKET: cloak every untitled or bare‑"Firestone"
                    ; Overwolf window. CLOAK ONLY -- no shield here either; the
                    ; burst owns the shield once the window is painted. Cloak
                    ; is complete invisibility on its own for a pre-title
                    ; window, so nothing shows.
                    if (title = "" || title = "Firestone") {
                        _FSSuppressSurface(h, title, false)
                        continue
                    }

                    if !IsLikelyFirestoneLoadingEarlyHwnd(h)
                        continue

                    ; Was an unconditional SW_HIDE on "Firestone - Loading"
                    ; AT A 3 ms CADENCE -- i.e. a third suppressor on the very
                    ; HWND that becomes Firestone - Main, running faster than
                    ; the other two. Funnelled. No probing here: 3 ms is far
                    ; too hot for a PrintWindow capture, and the settled sweep
                    ; already owns the measurement.
                    _FSSuppressSurface(h, title, false)
                } catch {
                }
            }
        }
    }
    DetectHiddenWindows prev

    ; SELF‑STOP: end the blanket only when ALL THREE are true —
    ;   • FS‑Main has been titled for the 3s grace,
    ;   • the loading‑popup watchdog has concluded,
    ;   • the F2 pipeline itself is over (!f2Active).
    if (_earlyCloakSawFSMainAt && _fsPopupWatchDone && !State.f2Active
     && (A_TickCount - _earlyCloakSawFSMainAt >= 3000))
        StopEarlyOverwolfCloak()
}

; ──────────────────────────────────────────────────────────────────────────────
; Battle.net / Agent launch blanket
; ──────────────────────────────────────────────────────────────────────────────
; Runs from the F2 press through RevealHSAfterLaunch. It no longer touches
; Hearthstone at all -- the game is never concealed; see the note at the top of
; HSHiddenLaunchWatch for why that was removed. What remains is the Battle.net
; side: while _bnetCloakActive is true (armed by StartHSCloaker, cleared by
; StopHSCloaker) each tick blankets every Battle.net.exe / Agent.exe SERVICE
; window, which genuinely does need a 10ms cadence to catch them at birth.
;
; The two flags survive as a pair because the timer's lifetime is still tied to
; the launch, and because Battle.net must be revealable EARLY (login screen)
; independently of when the launch finishes.
global _HSCloakActive   := false
global _bnetCloakActive := false   ; true = HSCloakTick also blankets BNet/Agent
global _HSCloakerHasRef := false

StartHSCloaker() {
    global _HSCloakActive, _HSCloakerHasRef, _hsGuardActive, _hsRevealed
    global _bnetCloakActive, _bnetRevealedAt, _bnetHiddenByUs, _bnetPostMinDone, _bnetLoginAllowed, _bnetLauncherStaged, _bnetLaunchFiredAt, _bnetHideDone, _bnetLauncherHwnd
    _hsGuardActive := false
    SetTimer(HSPlacementGuardTick, 0)
    _hsRevealed := Map()
    _HSCloakActive   := true
    _bnetCloakActive := true   ; arm the Battle.net/Agent launch blanket
    _bnetRevealedAt  := 0      ; fresh launch: launcher-ready not stamped yet
    _bnetHiddenByUs  := Map()  ; fresh ledger of SERVICE windows we SW_HIDE
    _bnetLoginAllowed := false ; the blanket owns Battle.net.exe again
    _bnetLauncherStaged := false ; launcher boots hidden; reveal will stage it
    _bnetHideDone    := Map()  ; fresh hide-once ledger
    _bnetLauncherHwnd := 0     ; no launcher revealed yet this launch
    _bnetLaunchFiredAt := 0    ; launch command not fired yet this launch
    _bnetPostMinDone := false  ; post-launch minimize not performed yet
    StartOWCreateHook()
    if !_HSCloakerHasRef {
        _AcquireHighResTimer()
        _HSCloakerHasRef := true
    }
    SetTimer(HSCloakTick, 10)
    HSCloakTick()
}

StopHSCloaker() {
    global _HSCloakActive, _HSCloakerHasRef, _bnetCloakActive, _bnetLoginAllowed
    _HSCloakActive    := false
    _bnetCloakActive  := false  ; the blanket may never outlive its tick
    _bnetLoginAllowed := false
    SetTimer(HSCloakTick, 0)
    if _HSCloakerHasRef {
        _ReleaseHighResTimer()
        _HSCloakerHasRef := false
    }
    ; De-ghost sweep: uncloak every Battle.net-family window (SW_HIDDEN ones
    ; stay hidden, so nothing pops). A cloak leaking past the session would
    ; make any window the client re-shows later invisible-but-"visible".
    try {
        prev := A_DetectHiddenWindows
        DetectHiddenWindows true
        for exe in ["Battle.net.exe", "Agent.exe", "Battle.net Helper.exe"] {
            for hwnd in WinGetList("ahk_exe " . exe) {
                try UncloakWindow(hwnd)
            }
        }
        DetectHiddenWindows prev
    }
}

HSCloakTick() {
    global _HSCloakActive, _bnetCloakActive, CFG, _bnetHiddenByUs, _bnetLauncherStaged
    global _bnetHideDone, _bnetLauncherHwnd, _bnetPostMinDone
    if !_HSCloakActive {
        SetTimer(HSCloakTick, 0)
        return
    }
    prev := A_DetectHiddenWindows
    DetectHiddenWindows true
    try {
        ; HEARTHSTONE IS NOT TOUCHED HERE ANY MORE.
        ; This tick used to cloak every Hearthstone window the instant it
        ; appeared. That is gone -- the game shows itself, on the user's own
        ; fullscreen and monitor settings. The timer survives because it also
        ; owns the Battle.net services blanket below, which is a separate job
        ; that genuinely does need a 10ms cadence during the launch.
        ;
        ; Battle.net SERVICES blanket -- active for the whole launch (until
        ; StopHSCloaker), maximum aggression: cloak+hide everything in the
        ; family except the REAL client window. The auto-login shell, splash,
        ; maintenance overlays and all Agent / Helper windows never appear.
        if (_bnetCloakActive && CFG.bnetAggressiveHide) {
            for exe in ["Battle.net.exe", "Agent.exe", "Battle.net Helper.exe"] {
                for hwnd in WinGetList("ahk_exe " . exe) {
                    try {
                        if _IsBlizzInfrastructureWindow(hwnd)
                            continue
                        ; ---- PROMOTE-AND-UNHIDE (birth-race recovery) -------
                        ; A window hidden by the blanket BEFORE it could be
                        ; identified may since have settled into the real
                        ; client. _HideBlizzWindow will not re-hide it (it
                        ; respects _IsProtectedBNetMain), but nothing UN-hides
                        ; it either: the only un-hide path was the NAMECHANGE
                        ; branch, which fires solely if the window is already
                        ; identifiable at the instant its title changes. When
                        ; the style settles without a title change -- or after
                        ; it -- that path never runs and the launcher stays
                        ; hidden for the whole session. This reclaims it at
                        ; 10ms instead of relying on that one event.
                        ;
                        ; Gated to BEFORE the post-launch minimize so it can
                        ; never fight _BNetDwellMinimize, and to genuinely
                        ; invisible windows so a minimized launcher (which is
                        ; still WS_VISIBLE) is never restored.
                        if (exe = "Battle.net.exe" && !_bnetPostMinDone
                         && _IsProtectedBNetMain(hwnd)) {
                            if _bnetHiddenByUs.Has(hwnd)
                                _bnetHiddenByUs.Delete(hwnd)
                            if _bnetHideDone.Has(hwnd)
                                _bnetHideDone.Delete(hwnd)
                            if !DllCall("user32\IsWindowVisible", "Ptr", hwnd) {
                                try UncloakWindow(hwnd)
                                DllCall("ShowWindow", "Ptr", hwnd, "Int", 8)  ; SW_SHOWNA
                            }
                            if !_bnetLauncherHwnd
                                _bnetLauncherHwnd := hwnd
                            continue
                        }
                        _HideBlizzWindow(hwnd, exe)
                    }
                }
            }
            ; (The old 10ms "enforcement pass" lived here. It un-hid any
            ; ledgered window it judged to be the real client -- but the
            ; launcher now BOOTS HIDDEN BY DESIGN and is revealed
            ; deliberately, so that pass fought the intentional hide and the
            ; two halves ping-ponged at 100Hz: the Battle.net fade. The
            ; reveal already un-hides and centres the real client, so the
            ; pass had no remaining job. Removed.)
            ; Dead-hwnd upkeep only:
            for hwnd in _bnetHiddenByUs.Clone() {
                try {
                    if !DllCall("user32\IsWindow", "Ptr", hwnd)
                        _bnetHiddenByUs.Delete(hwnd)
                }
            }
        }
    }
    DetectHiddenWindows prev
}

; ── HS post‑reveal placement guard ────────────────────────────────────────────
; Two jobs, both scoped to 60s after the reveal:
;   1. NEW windows: cloak → place → uncloak on the chosen monitor.
;   2. REVEALED windows: correct drift caused by Unity's display‑mode setup.
global _hsGuardActive := false
global _hsGuardUntil  := 0
global _hsRevealed    := Map()   ; hwnd -> true once placed + uncloaked

StartHSPlacementGuard(durationMs := 60000) {
    global _hsGuardActive, _hsGuardUntil
    _hsGuardActive := true
    _hsGuardUntil  := A_TickCount + durationMs
    SetTimer(HSPlacementGuardTick, 50)    ; was 150: a faster tick means
                                          ; Unity's snap-to-primary is
                                          ; corrected sooner, so HS is visibly
                                          ; off-monitor for less time
    HSPlacementGuardTick()
}

StopHSPlacementGuard() {
    global _hsGuardActive, _hsRevealed
    _hsGuardActive := false
    SetTimer(HSPlacementGuardTick, 0)
    prev := A_DetectHiddenWindows
    DetectHiddenWindows true
    try {
        for hwnd in WinGetList("ahk_exe Hearthstone.exe") {
            try {
                if !_hsRevealed.Has(hwnd)
                    UncloakWindow(hwnd)
            }
        }
    }
    DetectHiddenWindows prev
}

HSPlacementGuardTick() {
    global _hsGuardActive, _hsRevealed, CFG, ChosenMonIdx

    if !_hsGuardActive {
        SetTimer(HSPlacementGuardTick, 0)
        return
    }
    ; Permanent while HS exists: the guard is HS's SOLE monitor-keeper now
    ; (the lock no longer touches HS), so it must not time out and leave HS
    ; unowned. It self-stops only when Hearthstone is gone.
    if !ProcessExist("Hearthstone.exe") {
        StopHSPlacementGuard()
        return
    }

    prev := A_DetectHiddenWindows
    DetectHiddenWindows true
    try {
        for hwnd in WinGetList("ahk_exe Hearthstone.exe") {
            try {
                if IsIMEWindow(hwnd)
                    continue

                ; ---- Already‑revealed windows: drift correction ────────────
                if _hsRevealed.Has(hwnd) {
                    if !(CFG.lockWindowsToChosenMonitor && ChosenMonIdx)
                        continue
                    if (WinGetTitle("ahk_id " . hwnd) != "Hearthstone")
                        continue
                    if (WinGetMinMax("ahk_id " . hwnd) = -1)
                        continue
                    WinGetPos(&x, &y, &w, &h, "ahk_id " . hwnd)
                    if (w < 600 || h < 400)
                        continue
                    if (GetMonitorIndexForPoint(x + w // 2, y + h // 2) = ChosenMonIdx) {
                        _MoveBudgetReset(hwnd)
                        continue
                    }
                    if !_MoveBudgetAllows(hwnd)
                        continue
                    ; NO CLOAK AROUND THE MOVE.
                    ; This used to cloak, move, sleep 15ms and uncloak, to hide
                    ; the correction. Two problems. The cloak/uncloak pair is
                    ; itself a display-mode event for a borderless DXGI window,
                    ; so it provoked the churn it was hiding; and the
                    ; MonitorGetWorkArea between the two THROWS on a stale
                    ; monitor index -- the catch below swallowed it, and the
                    ; window was left cloaked with no path back. On a machine
                    ; whose monitor count changed, that is a permanently
                    ; invisible game. A bare move cannot strand anything.
                    _MoveBudgetNote(hwnd)
                    _PlaceHSOnChosenMonitor(hwnd)
                    continue
                }

                ; ---- Unreleased windows: place, and mark released ----------
                if (WinGetTitle("ahk_id " . hwnd) != "Hearthstone")
                    continue
                if (WinGetMinMax("ahk_id " . hwnd) = -1)
                    continue
                UncloakWindow(hwnd)      ; repair only (see RevealHSAfterLaunch)
                _PlaceHSOnChosenMonitor(hwnd)
                _hsRevealed[hwnd] := true
            } catch {
            }
        }
    }
    DetectHiddenWindows prev
}

; Timer entry point — delegates to the tick.
FSMainMonitor() {
    SuppressFirestoneMainTick()
}

; ── DWM cloak helpers (state-arbitrated) ──────────────────────────────────────
; All three attributes are set together so cloaked windows stay invisible
; everywhere: Alt‑Tab thumbnail, Win+Tab view, Aero Peek, and taskbar live
; preview. ARBITRATION (option B): a per-hwnd cloak-state map makes both
; primitives IDEMPOTENT -- the 3 DwmSetWindowAttribute calls fire ONLY when the
; state actually changes. 22 cloak + 27 uncloak sites across Firestone,
; Battle.net and Hearthstone previously hammered DWM with no coordination; a
; window already cloaked by one subsystem was re-cloaked by another every tick,
; and uncloak/re-cloak races between subsystems churned the compositor -- a
; flicker source. With this, redundant calls are no-ops and only genuine
; transitions touch DWM, so the subsystems no longer contend for the primitive.
global _cloakState := Map()   ; hwnd -> true when WE currently have it cloaked

; ── Cloak enforcement: ask DWM, not the ledger ────────────────────────────────
; CloakWindow is arbitrated -- it skips the DWM call when _cloakState already
; records the window as cloaked. That arbitration prevents several subsystems
; hammering DWM every tick, but it has one blind spot: a DWM cloak is
; asynchronous, and some window operations silently reset it.
;
; When that happens the ledger still reads "cloaked", so the arbitration
; returns early and nothing re-applies it. Since those operations are exactly
; the ones an application performs while showing, resizing or restoring a
; window, the concealment can switch itself off at precisely the moment it is
; needed, with no way back on.
;
; DwmGetWindowAttribute answers the question directly for the cost of one
; call, so the suppression path asks it rather than trusting bookkeeping
; another process can invalidate.
_FSEnsureCloaked(hwnd) {
    global _cloakState
    if IsWindowCloakedDWM(hwnd) {
        ; Genuinely cloaked. Keep the ledger honest so the reveal knows it has
        ; something to undo, even when the cloak was applied by an earlier pass
        ; whose bookkeeping has since been pruned.
        if !_cloakState.Has(hwnd)
            _cloakState[hwnd] := true
        return true
    }
    ; DWM says it is NOT cloaked, whatever the ledger believes. Force past the
    ; arbitration -- this is the one caller that has actually checked.
    CloakWindow(hwnd, true)
    _cloakState[hwnd] := true
    return false
}

CloakWindow(hwnd, force := false) {
    global _cloakState
    static DWMWA_CLOAK              := 13
    static DWMWA_EXCLUDED_FROM_PEEK := 12
    static DWMWA_DISALLOW_PEEK      := 11
    if (!force && _cloakState.Has(hwnd))   ; already cloaked by us: no DWM churn
        return
    _cloakState[hwnd] := true
    v := 1
    try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", DWMWA_CLOAK,              "Int*", v, "UInt", 4)
    try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", DWMWA_EXCLUDED_FROM_PEEK, "Int*", v, "UInt", 4)
    try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", DWMWA_DISALLOW_PEEK,      "Int*", v, "UInt", 4)
}

UncloakWindow(hwnd, force := false) {
    global _cloakState
    static DWMWA_CLOAK              := 13
    static DWMWA_EXCLUDED_FROM_PEEK := 12
    static DWMWA_DISALLOW_PEEK      := 11
    if (!force && !_cloakState.Has(hwnd))  ; not cloaked by us: no DWM churn
        return
    ; Map.Delete THROWS on a key that is not there, and the force path reaches
    ; this line precisely when the key is usually absent -- force exists to
    ; uncloak a window we have no ledger entry for. The throw propagated into
    ; whatever called us, and the biggest victim was OverlayTopmostTick: it
    ; calls _FSReleaseSurface (force uncloak) on the in-game overlay every two
    ; seconds, BEFORE re-asserting the overlay's topmost flag. The exception
    ; aborted the rest of that window's body every single tick, so the topmost
    ; re-assert -- the enforcer's entire job -- almost never ran. An overlay
    ; that loses its z-order and is never put back is an overlay whose pinned
    ; panels appear and disappear at random.
    _MapDrop(_cloakState, hwnd)
    v := 0
    try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", DWMWA_CLOAK,              "Int*", v, "UInt", 4)
    try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", DWMWA_EXCLUDED_FROM_PEEK, "Int*", v, "UInt", 4)
    try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", DWMWA_DISALLOW_PEEK,      "Int*", v, "UInt", 4)
}

; ══════════════════════════════════════════════════════════════════════════════
; FIRESTONE COLD-WINDOW SUBSYSTEM — the Firestone-Main fix
; ══════════════════════════════════════════════════════════════════════════════
;
; Read CFG.fsMainColdPolicy for the full diagnosis. In short:
;
;   COLD  = the window has not yet proven it painted a frame.
;           It is kept 100% invisible WITHOUT ShowWindow(SW_HIDE), because that
;           call is what stops a CEF window ever building its compositor.
;   WARM  = the window has been measured to have painted.
;           From this instant it takes EXACTLY the Battlegrounds exit --
;           cloak + one ledgered SW_HIDE -- and behaves identically to the
;           window that has always worked.
;
; Every suppression site in the script funnels through _FSSuppressSurface()
; so the five owners that used to disagree now cannot. The hook calls it too,
; but the hook never probes (a "Fast" callback must stay cheap); probing is
; owned solely by the settled sweep.
;
global _fsPaintState     := Map()   ; hwnd -> 1 painted, -1 gave up (absent = cold)
global _fsPaintProbeAt   := Map()   ; hwnd -> tick of last probe (throttle)
global _fsPaintHits      := Map()   ; hwnd -> consecutive passing probes
global _fsColdSince      := Map()   ; hwnd -> tick we first suppressed it cold
global _fsParked         := Map()   ; hwnd -> true: currently parked off-screen
global _fsParkedRect     := Map()   ; hwnd -> {x,y,w,h} where it was before
global _fsParkCycles     := Map()   ; hwnd -> park/unpark cycles performed
global _fsProbeGaveUp    := Map()   ; hwnd -> probing stopped (stays COLD)
global _fsMainCandidate  := Map()   ; hwnd -> ever carried a Loading/Main title.
                                    ; Identity guard for the popup closer: an
                                    ; HWND that has ever been Loading or Main
                                    ; may NEVER be closed, whatever it is
                                    ; titled now. Replaces the old "never close
                                    ; a cloaked window" proxy, which v8 broke by
                                    ; cloaking everything.
global _fsBirthReassert  := Map()   ; hwnd -> count of event-speed re-asserts
global _fsMainLogged     := Map()   ; hwnd -> lifecycle lines already written

; One-line diagnostic to %TEMP%\hs_bg_f1.log. This is the log that ends the
; guessing: one launch tells you whether Main painted, how long it took, and
; which policy was in force when it did or did not.
_FSLog(msg) {
    global CFG
    if !CFG.f1DebugLog
        return
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") . " " . msg . "`n"
        , A_Temp . "\hs_bg_f1.log")
}

; ── Taskbar button suppression (style-free) ───────────────────────────────────
; ITaskbarList::DeleteTab removes a window's taskbar button without touching any
; window style. That matters: the alternative, toggling WS_EX_TOOLWINDOW, needs
; SWP_FRAMECHANGED, which sends WM_NCCALCSIZE to a window that may still be
; forming.
;
; The shell API takes an HWND and is happy to be called cross-process. This
; script runs elevated and Overwolf does not, and a higher integrity level may
; act on a lower one, so the direction is legal.
;
; Falls back to the ex-style toggle only if the COM object cannot be created.
global _fsTbl       := 0
global _fsTblReady  := false
global _fsTblBroken := false

_FSTaskbarInit() {
    global _fsTbl, _fsTblReady, _fsTblBroken
    if (_fsTblReady || _fsTblBroken)
        return
    try {
        _fsTbl := ComObject("{56FDF344-FD6D-11d0-958A-006097C9A090}"   ; CLSID_TaskbarList
                          , "{56FDF342-FD6D-11d0-958A-006097C9A090}")  ; IID_ITaskbarList
        ComCall(3, _fsTbl)                       ; ITaskbarList::HrInit
        _fsTblReady := true
    } catch {
        _fsTbl       := 0
        _fsTblReady  := false
        _fsTblBroken := true
        _FSLog("FS-COLD ITaskbarList unavailable -- falling back to WS_EX_TOOLWINDOW")
    }
}

; Ledgered wrappers. The raw call is fire-and-forget; these remember that WE
; took a button away, so exactly one janitor puts it back and nothing tries to
; restore a button on a window that never had one.
; True only while the F4 full-shutdown path is running. It tells ExitCleanup
; that the Overwolf / Battle.net / Hearthstone processes have just been killed,
; so its restore janitors have nothing left to make reachable and should stay
; out of the way. Cleared again if the kill turns out to have failed.
global _f4Shutdown := false

global _fsTabRemoved := Map()

_FSTabOff(hwnd) {
    global _fsTabRemoved
    if _fsTabRemoved.Has(hwnd)
        return
    _fsTabRemoved[hwnd] := true
    _FSTaskbarTab(hwnd, false)
}

_FSTabOn(hwnd) {
    global _fsTabRemoved
    if !_fsTabRemoved.Has(hwnd)
        return
    _MapDrop(_fsTabRemoved, hwnd)
    _FSTaskbarTab(hwnd, true)
}

_FSTaskbarTab(hwnd, show) {
    global _fsTbl, _fsTblReady, _fsTblBroken
    if (_fsTblReady && !_fsTblBroken) {
        try {
            ComCall(show ? 4 : 5, _fsTbl, "Ptr", hwnd)   ; AddTab / DeleteTab
            return true
        } catch {
            _fsTblBroken := true
            _fsTblReady  := false
            _fsTbl       := 0
            _FSLog("FS-COLD ITaskbarList call failed -- falling back to WS_EX_TOOLWINDOW")
        }
    }
    ; Fallback: ex-style toggle. Deliberately WITHOUT SWP_FRAMECHANGED -- the
    ; taskbar reads the style on the next show/hide transition, and skipping
    ; the frame recalculation keeps this safe on a forming window.
    try {
        static GWL_EXSTYLE := -20, WS_EX_TOOLWINDOW := 0x80, WS_EX_APPWINDOW := 0x40000
        fnGet := (A_PtrSize = 8) ? "user32\GetWindowLongPtrW" : "user32\GetWindowLongW"
        fnSet := (A_PtrSize = 8) ? "user32\SetWindowLongPtrW" : "user32\SetWindowLongW"
        ex := DllCall(fnGet, "Ptr", hwnd, "Int", GWL_EXSTYLE, "Ptr")
        ex := show ? ((ex & ~WS_EX_TOOLWINDOW) | WS_EX_APPWINDOW)
                   : ((ex | WS_EX_TOOLWINDOW) & ~WS_EX_APPWINDOW)
        DllCall(fnSet, "Ptr", hwnd, "Int", GWL_EXSTYLE, "Ptr", ex)
        return true
    }
    return false
}

; ── Is this window eligible to be parked? ─────────────────────────────────────
; Deliberately narrow, and the restriction is load-bearing.
;
; Parking moves a window, and moving the wrong one is worse than any flicker:
; the in-game OVERLAY is positioned by Overwolf relative to the Hearthstone
; window and is not necessarily re-placed afterwards. Park the overlay and the
; one surface that must work has been silently broken.
;
; So only windows positively identified as the Firestone desktop application are
; parked, plus -- before a window has ever been shown -- any Overwolf window
; small enough not to be the overlay, since the park records its exact rectangle
; and the unpark restores it. Click-through windows (WS_EX_TRANSPARENT) and
; anything on CFG.fsVisibleTitles are excluded outright.
_FSMayPark(hwnd, title) {
    if IsFSVisibleTitle(title)
        return false
    try {
        ex := WinGetExStyle("ahk_id " . hwnd)
        if (ex & 0x20)              ; WS_EX_TRANSPARENT: click-through overlay
            return false
    }

    ; Positively-identified Firestone app windows: always parkable.
    if (title = "Firestone - Main" || title = "Firestone - Loading"
     || title = "Firestone - Battlegrounds" || title = "Firestone")
        return true

    ; ── NOTHING UNNAMED IS EVER PARKED. ────────────────────────────────────
    ; There used to be a "pre-show allowance" here: any not-yet-visible Overwolf
    ; window of reasonable size could be parked off the virtual desktop before
    ; it was ever shown, on the theory that a synchronous move beats a DWM cloak
    ; by up to one frame.
    ;
    ; OVERWOLF IS A PLATFORM, NOT AN APP. It hosts League overlays, TFT
    ; overlays, and whatever else the user has installed, all inside the same
    ; two executables this script enumerates. An untitled newborn is therefore
    ; as likely to belong to somebody else's app as to Firestone -- and parking
    ; RECORDS the window in _fsParked, which F3's unlock sweep restores and
    ; shows. That is exactly how pressing F3 opened a TFT app: the script had
    ; parked a window it could not name, then dutifully handed it back.
    ;
    ; A cloak has no ledger and no restore, so an unnamed newborn is cloaked
    ; instead (see _FSSuppressSurface) and released as soon as its title shows
    ; it belongs to somebody else. The theoretical one frame is worth far less
    ; than reaching into another application's windows.
    return false
}

; ── Off-screen park ───────────────────────────────────────────────────────────
; Moves the window entirely outside the virtual desktop. SetWindowPos does not
; clamp to the desktop, so this is exact. SWP_NOSIZE|SWP_NOZORDER|SWP_NOACTIVATE
; means nothing changes except the origin -- no resize, no z-order churn, no
; focus theft, and above all no ShowWindow.
_FSParkWindow(hwnd) {
    global _fsParked, _fsParkedRect, CFG
    try {
        vx := SysGet(76), vy := SysGet(77), vw := SysGet(78), vh := SysGet(79)

        ; Re-assert rather than set and forget. The ledger entry means "this window is
        ; ours", not "this window is done": Overwolt-style applications re-centre their
        ; own windows shortly after showing them. Every call re-reads where the window
        ; actually is and moves it back if it has drifted onto the virtual desktop.
        ; Idempotent when it has not -- the common path is one GetWindowRect.
        rc := Buffer(16, 0)
        if !DllCall("user32\GetWindowRect", "Ptr", hwnd, "Ptr", rc)
            return false
        cx := NumGet(rc, 0, "Int"), cy := NumGet(rc, 4, "Int")
        cw := NumGet(rc, 8, "Int") - cx, ch := NumGet(rc, 12, "Int") - cy
        offscreen := !(cx + cw > vx && cx < vx + vw && cy + ch > vy && cy < vy + vh)

        if (_fsParked.Has(hwnd) && offscreen)
            return true                 ; still parked where we put it

        if !_fsParked.Has(hwnd) {
            ; First park of this hwnd. Remember where it was, so the unpark can
            ; put it back rather than imposing a centred position.
            if (cw >= 200 && ch >= 200)
                _fsParkedRect[hwnd] := {x: cx, y: cy, w: cw, h: ch}

            ; No cycle cap here. Park and unpark are geometry changes, which a browser
            ; window handles thousands of times without complaint; the expensive operation
            ; was never this one. Capping it would also be unsafe now that parking is the
            ; steady-state concealment mechanism, since refusing to park would simply leave
            ; the window on screen.
        }

        ; Park at the window's existing vertical offset, just past the right edge of the
        ; desktop, so the unpark is a pure horizontal restore -- one less axis for the
        ; compositor to reconcile in the frame the window reappears.
        px := vx + vw + 64
        py := (cy >= vy && cy < vy + vh) ? cy : vy
        DllCall("user32\SetWindowPos", "Ptr", hwnd, "Ptr", 0
            , "Int", px, "Int", py, "Int", 0, "Int", 0
            , "UInt", 0x0001 | 0x0004 | 0x0010)   ; NOSIZE|NOZORDER|NOACTIVATE
        _FSTabOff(hwnd)
        _fsParked[hwnd] := true
        return true
    }
    return false
}

; Bring a parked window back. Prefers the remembered position; falls back to
; centring on the chosen monitor when there is none, or when the remembered
; one no longer lands on a monitor (display layout changed while parked).
; Never activates, never resizes.
_FSUnparkWindow(hwnd) {
    global _fsParked, _fsParkedRect, CFG, ChosenMonIdx
    if !_fsParked.Has(hwnd)
        return false
    _MapDrop(_fsParked, hwnd)
    try {
        _FSTabOn(hwnd)
        rc := Buffer(16, 0)
        if !DllCall("user32\GetWindowRect", "Ptr", hwnd, "Ptr", rc)
            return false
        w := NumGet(rc, 8, "Int") - NumGet(rc, 0, "Int")
        h := NumGet(rc, 12, "Int") - NumGet(rc, 4, "Int")

        nx := "", ny := ""

        ; ── A window returns to where it was ────────────────────────────────
        ; Firestone's windows are not pinned to the launch monitor. They are the ones
        ; read while playing, so they belong wherever the user put them -- typically a
        ; second screen, beside the game rather than over it. The park records each
        ; window's exact rectangle and the unpark restores it, so moving Main to
        ; another monitor and toggling F3 leaves it exactly where it was.
        ;
        ; CFG.fsFollowMonitorLock := true pins them with everything else.
        ; lockWindowsToChosenMonitor deliberately does not govern this; it still
        ; governs Battle.net, the Agent, Hearthstone and the HUD.
        if !CFG.fsFollowMonitorLock {
            if _fsParkedRect.Has(hwnd) {
                o := _fsParkedRect[hwnd]
                _MapDrop(_fsParkedRect, hwnd)
                vx := SysGet(76), vy := SysGet(77), vw := SysGet(78), vh := SysGet(79)
                ; Only reject it if the layout changed underneath us and the
                ; remembered spot is no longer on any monitor at all.
                if (o.x + o.w > vx && o.x < vx + vw
                 && o.y + o.h > vy && o.y < vy + vh) {
                    nx := o.x, ny := o.y
                }
            }
        } else {
            _MapDrop(_fsParkedRect, hwnd)
        }
        if (nx = "") {
            idx := (CFG.fsFollowMonitorLock && CFG.lockWindowsToChosenMonitor
                 && ChosenMonIdx)
                 ? ChosenMonIdx : MonitorGetPrimary()
            _SafeWorkArea(idx, &waL, &waT, &waR, &waB)
            waW := waR - waL, waH := waB - waT
            nx := (w > 0 && w <= waW) ? waL + (waW - w) // 2 : waL
            ny := (h > 0 && h <= waH) ? waT + (waH - h) // 2 : waT
        }
        DllCall("user32\SetWindowPos", "Ptr", hwnd, "Ptr", 0
            , "Int", nx, "Int", ny, "Int", 0, "Int", 0
            , "UInt", 0x0001 | 0x0004 | 0x0010)   ; NOSIZE|NOZORDER|NOACTIVATE
        return true
    }
    return false
}

; Unpark EVERYTHING. Janitor of last resort -- exit, F4, abort. A window left
; parked by a crashed instance is off-screen with no taskbar button, i.e.
; unreachable, so this must run on every teardown path.
_FSUnparkAll() {
    global _fsParked, _fsTabRemoved
    for h in _fsParked.Clone() {
        try {
            if DllCall("user32\IsWindow", "Ptr", h)
                _FSUnparkWindow(h)
            else
                _MapDrop(_fsParked, h)
        }
    }
    ; And give every window its taskbar button back, including ones that were
    ; never movable and so were never in _fsParked.
    for h in _fsTabRemoved.Clone() {
        try {
            if DllCall("user32\IsWindow", "Ptr", h)
                _FSTabOn(h)
            else
                _MapDrop(_fsTabRemoved, h)
        }
    }
}

; ── Stranded-park repair ──────────────────────────────────────────────────────
; Every concealment in this script has a janitor, and the park needs one that
; works from a COLD LEDGER. If the script is reloaded, killed or crashes while a
; window is parked, the next instance starts with no bookkeeping and would never
; know to bring it back: the window would sit outside the virtual desktop, with
; no taskbar button, unreachable for the rest of the Overwolf session.
;
; A window is judged stranded when its rectangle does not intersect the virtual
; desktop at all. Nothing legitimate lives there.
FSRepairStrandedWindows() {
    global CFG, _fsTabRemoved, _fsParked, _fsParkedRect, ChosenMonIdx
    static lastRun := 0

    ; THROTTLE. This enumerates four processes and does a GetWindowRect on every
    ; window. StartFSReveal calls it on EVERY F3 unlock, so under a stress test
    ; it was running several times a second for no reason -- a window cannot
    ; become stranded between two key presses.
    if (lastRun && A_TickCount - lastRun < 3000)
        return
    lastRun := A_TickCount

    prev := A_DetectHiddenWindows
    DetectHiddenWindows true
    try {
        vx := SysGet(76), vy := SysGet(77), vw := SysGet(78), vh := SysGet(79)
        for exe in CFG.fsAlphaRepairExes {
            for h in WinGetList("ahk_exe " . exe) {
                try {
                    rc := Buffer(16, 0)
                    if !DllCall("user32\GetWindowRect", "Ptr", h, "Ptr", rc)
                        continue
                    l := NumGet(rc, 0, "Int"), t := NumGet(rc, 4, "Int")
                    r := NumGet(rc, 8, "Int"), b := NumGet(rc, 12, "Int")
                    if (r - l < 100 || b - t < 60)
                        continue
                    ; Intersects the virtual desktop? Then it is not stranded.
                    if (r > vx && l < vx + vw && b > vy && t < vy + vh)
                        continue
                    ; OURS, ON PURPOSE. A window this instance has parked is
                    ; off the virtual desktop BY DESIGN and is not stranded.
                    ; Without this the repair could not tell "abandoned by a
                    ; dead instance" from "deliberately parked one second ago"
                    ; -- and since CompleteHSLaunchSuccess schedules a repair
                    ; 1.5 s out, and the deferred launch starts Firestone right
                    ; around then, it was dragging freshly-parked Firestone
                    ; windows back onto the screen and handing them their
                    ; taskbar buttons. That is the "Getting ready" window in
                    ; the screenshot.
                    if _fsParked.Has(h)
                        continue
                    _fsTabRemoved[h] := true      ; force the restore below
                    _FSTabOn(h)
                    ; Rescued windows go to the chosen monitor, not the primary. This function
                    ; recovers exactly the windows this script parks -- which is every time the
                    ; park ledger has been lost to a reload -- so depositing them on the primary
                    ; would place them off the session's monitor and they would be revealed there.
                    if _fsParkedRect.Has(h) {
                        _o := _fsParkedRect[h]
                        _MapDrop(_fsParkedRect, h)
                        if (_o.x + _o.w > vx && _o.x < vx + vw
                         && _o.y + _o.h > vy && _o.y < vy + vh) {
                            DllCall("user32\SetWindowPos", "Ptr", h, "Ptr", 0
                                , "Int", _o.x, "Int", _o.y, "Int", 0, "Int", 0
                                , "UInt", 0x0001 | 0x0004 | 0x0010)
                            _MapDrop(_fsParked, h)
                            _FSLog("FS-PARK repaired stranded window exe=" . exe
                                 . " hwnd=" . h . " -- restored to its own last position")
                            continue
                        }
                    }
                    _rIdx := (CFG.lockWindowsToChosenMonitor && ChosenMonIdx)
                           ? ChosenMonIdx : MonitorGetPrimary()
                    _SafeWorkArea(_rIdx, &waL, &waT, &waR, &waB)
                    DllCall("user32\SetWindowPos", "Ptr", h, "Ptr", 0
                        , "Int", waL + 80, "Int", waT + 80, "Int", 0, "Int", 0
                        , "UInt", 0x0001 | 0x0004 | 0x0010)
                    _FSLog("FS-PARK repaired stranded window exe=" . exe
                         . " hwnd=" . h . " -- was outside the virtual desktop")
                }
            }
        }
    }
    DetectHiddenWindows prev
}

; ── PAINT PROOF ───────────────────────────────────────────────────────────────
; Does this window have real composited content?
;
; PrintWindow with PW_RENDERFULLCONTENT (0x2) copies what DWM actually holds for
; the window, including DirectComposition/Chromium surfaces -- without that flag
; a Chromium window prints black, which is why a naive probe would report every
; window as unpainted. The result is sampled on a sparse grid and the number of
; DISTINCT colours is counted: a drawn Firestone dashboard yields hundreds, a
; never-drawn window yields one (usually pure black).
;
; Returns true/false; `distinct` receives the count for the log.
_FSWindowHasPainted(hwnd, &distinct) {
    static PW_RENDERFULLCONTENT := 0x2
    distinct := 0
    hdcScreen := 0, hdcMem := 0, hbm := 0, oldBm := 0
    try {
        ; A window with no WS_VISIBLE prints black no matter what, so do not
        ; waste the capture -- and never report a hidden window as painted.
        if !DllCall("user32\IsWindowVisible", "Ptr", hwnd)
            return false
        rc := Buffer(16, 0)
        if !DllCall("user32\GetWindowRect", "Ptr", hwnd, "Ptr", rc)
            return false
        w := NumGet(rc, 8, "Int") - NumGet(rc, 0, "Int")
        h := NumGet(rc, 12, "Int") - NumGet(rc, 4, "Int")
        if (w < 200 || h < 200)
            return false
        if (w > 1024)
            w := 1024                 ; cap the capture; PrintWindow just clips
        if (h > 1024)
            h := 1024

        hdcScreen := DllCall("user32\GetDC", "Ptr", 0, "Ptr")
        if !hdcScreen
            return false
        hdcMem := DllCall("gdi32\CreateCompatibleDC", "Ptr", hdcScreen, "Ptr")
        if !hdcMem
            return false

        bi := Buffer(40, 0)
        NumPut("UInt",   40, bi,  0)          ; biSize
        NumPut("Int",     w, bi,  4)          ; biWidth
        NumPut("Int",    -h, bi,  8)          ; biHeight, negative = top-down
        NumPut("UShort",  1, bi, 12)          ; biPlanes
        NumPut("UShort", 32, bi, 14)          ; biBitCount
        NumPut("UInt",    0, bi, 16)          ; BI_RGB

        pBits := 0
        hbm := DllCall("gdi32\CreateDIBSection", "Ptr", hdcMem, "Ptr", bi
             , "UInt", 0, "Ptr*", &pBits, "Ptr", 0, "UInt", 0, "Ptr")
        if (!hbm || !pBits)
            return false
        oldBm := DllCall("gdi32\SelectObject", "Ptr", hdcMem, "Ptr", hbm, "Ptr")

        if !DllCall("user32\PrintWindow", "Ptr", hwnd, "Ptr", hdcMem
                  , "UInt", PW_RENDERFULLCONTENT)
            return false

        seen := Map()
        step := 17                    ; prime-ish stride: never aligns with a
                                      ; repeating UI grid and misses variation
        y := 3
        while (y < h) {
            x := 3
            while (x < w) {
                px := NumGet(pBits + 0, (y * w + x) * 4, "UInt") & 0x00FFFFFF
                seen[px] := true
                x += step
            }
            y += step
        }
        distinct := seen.Count
        return true
    } catch {
        return false
    } finally {
        try {
            if (hdcMem && oldBm)
                DllCall("gdi32\SelectObject", "Ptr", hdcMem, "Ptr", oldBm, "Ptr")
            if hbm
                DllCall("gdi32\DeleteObject", "Ptr", hbm)
            if hdcMem
                DllCall("gdi32\DeleteDC", "Ptr", hdcMem)
            if hdcScreen
                DllCall("user32\ReleaseDC", "Ptr", 0, "Ptr", hdcScreen)
        }
    }
}

; Cheap read: has this hwnd been proven (or given up on)? Safe in the hook.
_FSIsWarm(hwnd) {
    global _fsPaintState
    return _fsPaintState.Has(hwnd)
}

; Throttled probe. Called ONLY from the settled suppression sweep -- never from
; the event hook. Promotes the window to WARM on two consecutive passes, or
; gives up (and says so, loudly) at the ceiling.
_FSProbePaint(hwnd, title) {
    global CFG, _fsPaintState, _fsPaintProbeAt, _fsPaintHits, _fsColdSince
    global _cloakState, _fsParked, _fsProbeGaveUp

    if _fsPaintState.Has(hwnd)
        return _fsPaintState[hwnd]

    if !_fsColdSince.Has(hwnd)
        _fsColdSince[hwnd] := A_TickCount

    ; Ceiling: stop probing, but stay cold.
    ;
    ; Being cold is not a failure state that needs escaping -- under the park
    ; policy a cold window is already completely concealed and can remain so
    ; indefinitely at no cost. Forcing a concealment change at the ceiling would
    ; only guarantee the unpainted window this subsystem exists to prevent, on any
    ; machine where the probe could not get a reading.
    ;
    ; So the ceiling stops the PrintWindow captures, which are the only expensive
    ; part, and leaves the window as it is. The verdict is deferred to the reveal,
    ; where the window is on a real screen and the answer is trustworthy.
    if (A_TickCount - _fsColdSince[hwnd] > CFG.fsPaintCeilingMs) {
        if !_fsProbeGaveUp.Has(hwnd) {
            _fsProbeGaveUp[hwnd] := true
            _FSLog("FS-PAINT no reading after " . (A_TickCount - _fsColdSince[hwnd])
                 . "ms title=`"" . title . "`" policy=" . CFG.fsMainColdPolicy
                 . " -- probing stopped, window STAYS parked and invisible;"
                 . " the verdict is deferred to the next F3 reveal")
        }
        return 0
    }
    if _fsProbeGaveUp.Has(hwnd)
        return 0

    if (A_TickCount - _fsPaintProbeAt.Get(hwnd, 0) < CFG.fsPaintProbeMs)
        return 0
    _fsPaintProbeAt[hwnd] := A_TickCount

    ; ── Uncloak for the capture, but only when that is free ───────────────
    ; A cloaked window may not have a current DWM redirection surface, and
    ; PrintWindow reads exactly that, so probing through the cloak risks a black
    ; capture and a false "never painted". Dropping the cloak for one capture is
    ; therefore worth it -- but only while the window is off the virtual desktop,
    ; where it cannot put a pixel on screen.
    ;
    ; The ledger is not evidence of that. Overwolf repositions its own windows
    ; during start-up (layout, fade-in, restoring a remembered position), any of
    ; which returns the window to the desktop while our bookkeeping still says
    ; parked. So ask the window where it is.
    ;
    ; On the desktop: do not uncloak, do not capture, re-assert the park and try
    ; again. A missed probe costs nothing -- the window simply stays in the cold
    ; state, which is already fully concealed.
    offDesktop := false
    try {
        prc := Buffer(16, 0)
        if DllCall("user32\GetWindowRect", "Ptr", hwnd, "Ptr", prc) {
            pl := NumGet(prc, 0, "Int"), pt := NumGet(prc, 4, "Int")
            pr := NumGet(prc, 8, "Int"), pb := NumGet(prc, 12, "Int")
            pvx := SysGet(76), pvy := SysGet(77)
            pvw := SysGet(78), pvh := SysGet(79)
            offDesktop := !(pr > pvx && pl < pvx + pvw
                         && pb > pvy && pt < pvy + pvh)
        }
    }
    if (!offDesktop) {
        ; On screen and still cold: the cloak is the only thing hiding it, so
        ; it does not come off. Put it back where it belongs and wait.
        if (CFG.fsMainColdPolicy = "park" && _FSMayPark(hwnd, title)) {
            _FSEnsureCloaked(hwnd)
            _FSParkWindow(hwnd)
        }
        return 0
    }

    reCloak := false
    if _cloakState.Has(hwnd) {
        UncloakWindow(hwnd)
        reCloak := true
    }

    d := 0
    ok := _FSWindowHasPainted(hwnd, &d)

    if reCloak
        CloakWindow(hwnd)
    if (!ok || d < CFG.fsPaintMinDistinct) {
        _fsPaintHits[hwnd] := 0
        return 0
    }
    n := _fsPaintHits.Get(hwnd, 0) + 1
    _fsPaintHits[hwnd] := n
    if (n < 2)
        return 0                      ; two consecutive passes required

    _fsPaintState[hwnd] := 1
    _FSLog("FS-PAINT PROVEN after " . (A_TickCount - _fsColdSince[hwnd])
         . "ms title=`"" . title . "`" distinct=" . d
         . " policy=" . CFG.fsMainColdPolicy . " -- switching to the "
         . "Battlegrounds exit (cloak + single SW_HIDE)")
    return 1
}

; ── The single suppression primitive ──────────────────────────────────────────
; COLD path. Keeps the window 100% invisible without ever clearing WS_VISIBLE.
_FSColdSuppress(hwnd, title) {
    global CFG, _fsHiddenByUs, _fsColdSince, _fsMainLogged

    if !_fsColdSince.Has(hwnd)
        _fsColdSince[hwnd] := A_TickCount

    if (!_fsMainLogged.Has(hwnd) && title != "") {
        _fsMainLogged[hwnd] := true
        _FSLog("FS-COLD born title=`"" . title . "`" policy=" . CFG.fsMainColdPolicy)
    }

    ; Cloak in every policy: it is the one operation that removes the window
    ; from Alt-Tab, Win+Tab, Aero Peek and taskbar thumbnails, and it does not
    ; clear WS_VISIBLE. VERIFIED against DWM rather than assumed -- see
    ; _FSEnsureCloaked for why the ledger alone is not enough.
    _FSEnsureCloaked(hwnd)
    _DisableDWMTransitions(hwnd)

    if (CFG.fsMainColdPolicy = "park") {
        ; The taskbar button goes regardless of whether the window is movable:
        ; "100% invisible" has to include the taskbar, and DeleteTab touches no
        ; style and no geometry, so it is safe on any window.
        _FSTabOff(hwnd)
        ; Only positively-identified Firestone app windows are ever MOVED --
        ; see _FSMayPark. Everything else (untitled frames in particular) is
        ; left exactly where it is and carried by the cloak alone, which is
        ; invisible and touches no geometry. This is what keeps the in-game
        ; overlay safe: it is never relocated, only ever cloaked.
        if _FSMayPark(hwnd, title)
            _FSParkWindow(hwnd)
        return
    }
    if (CFG.fsMainColdPolicy = "cloak")
        return

    ; "hide" -- the OLD behaviour, kept only so the whole fix can be A/B'd with
    ; one config word. This is the setting that produces the blank window.
    if DllCall("user32\IsWindowVisible", "Ptr", hwnd) {
        _fsHiddenByUs[hwnd] := true
        DllCall("ShowWindow", "Ptr", hwnd, "Int", 0)   ; SW_HIDE
    }
}

; WARM path. Byte-for-byte the exit Firestone - Battlegrounds has always taken
; and which has always worked: cloak, then ONE ledgered SW_HIDE, and never
; touch it again while it stays hidden.
_FSWarmSuppress(hwnd, title) {
    global _fsHiddenByUs, _fsRevealActive, State, CFG, _fsMinLastAttempt

    ; Yield to an active reveal (an unlock in flight): never hide while the
    ; reveal is showing it -- that is the taskbar-strobe war.
    if (_fsRevealActive || !State.fsMainLocked)
        return

    _FSEnsureCloaked(hwnd)            ; verified against DWM, not assumed
    _DisableDWMTransitions(hwnd)

    ; ══════════════════════════════════════════════════════════════════════
    ; CONCEALMENT WITHOUT A VISIBILITY TRANSITION
    ; ══════════════════════════════════════════════════════════════════════
    ; To Chromium a visibility transition is not a cheap flag: WM_SHOWWINDOW
    ; drives the widget's visibility, which tears down and rebuilds the
    ; compositor's frame sink. A hide/show pair per F3 press accumulates, and a
    ; renderer subjected to enough of them stops coming back.
    ;
    ; The cold path already solved this by keeping the window WS_VISIBLE and
    ; moving it out of sight instead, and there is no reason the warm path should
    ; not do the same. A SetWindowPos is a geometry change, which a browser window
    ; handles thousands of times without complaint. So the lock becomes:
    ;
    ;     lock   -> move off the virtual desktop + cloak
    ;     unlock -> move back + uncloak
    ;
    ; No ShowWindow in either direction. The renderer is never told the window
    ; went away, so there is nothing to rebuild. Concealment is unchanged: off
    ; every monitor, out of Alt-Tab and Peek, and no taskbar button.
    ;
    ; CFG.fsWarmPolicy := "hide" selects the SW_HIDE exit instead.
    if (CFG.fsWarmPolicy = "park" && _FSMayPark(hwnd, title)) {
        ; Drop the F3 topmost pin before parking. The reveal pins the window
        ; HWND_TOPMOST so it sits above a borderless fullscreen Hearthstone; that pin
        ; must be released symmetrically or the window stays always-on-top for the rest
        ; of the session, above every other application, the next time anything shows it.
        try DllCall("user32\SetWindowPos", "Ptr", hwnd, "Ptr", -2   ; HWND_NOTOPMOST
            , "Int", 0, "Int", 0, "Int", 0, "Int", 0
            , "UInt", 0x0001 | 0x0002 | 0x0010)
        _FSTabOff(hwnd)
        _FSParkWindow(hwnd)
        return
    }

    if !DllCall("user32\IsWindowVisible", "Ptr", hwnd)
        return                        ; already off screen: NOTHING to do.
                                      ; Re-issuing a hide here is the storm.

    ; Legacy path, preserved: with CFG.fsMainUseHide := false, FS-Main takes
    ; the classic cloak+minimize exit rather than SW_HIDE. Battlegrounds always
    ; hides. Throttled exactly as before so a minimize can never be hammered.
    if (!CFG.fsMainUseHide && IsFirestoneMainTitle(title)) {
        if (WinGetMinMax("ahk_id " . hwnd) = -1)
            return
        now := A_TickCount
        if (now - _fsMinLastAttempt.Get(hwnd, 0) < 250)
            return
        _fsMinLastAttempt[hwnd] := now
        _MinimizeWindowNoAnim(hwnd)
        return
    }

    _fsHiddenByUs[hwnd] := true
    ; Drop any F3 topmost pin before hiding.
    try DllCall("user32\SetWindowPos", "Ptr", hwnd, "Ptr", -2   ; HWND_NOTOPMOST
        , "Int", 0, "Int", 0, "Int", 0, "Int", 0
        , "UInt", 0x0001 | 0x0002 | 0x0010)
    DllCall("ShowWindow", "Ptr", hwnd, "Int", 0)      ; SW_HIDE -- exactly once
}

; Diagnostic: record a window the funnel declined to touch because it is
; helper-shaped and carries no title we recognise.
;
; ONCE PER HWND, and only for titled windows. The funnel runs at 10 ms and the
; window event hook calls it with an empty title for every newborn Overwolf
; window, so an ungated log line here would be both a flood and a hot-path
; FileAppend from a "Fast" callback. What it buys: if a Firestone surface is
; ever visible when it should not be, this line names the window that was
; skipped and why -- instead of leaving a silent early return to be found by
; reading the source.
global _fsExemptLogged := Map()
_FSLogExemptOnce(hwnd, title) {
    global _fsExemptLogged
    if (title = "" || _fsExemptLogged.Has(hwnd))
        return
    _fsExemptLogged[hwnd] := true
    ex := 0
    try ex := WinGetExStyle("ahk_id " . hwnd)
    _FSLog("FS-EXEMPT declined (helper-shaped, unrecognised title) hwnd=" . hwnd
         . " title=`"" . title . "`" exstyle=" . Format("0x{:X}", ex))
}

; The single suppression primitive. Every concealment site in this script calls
; this and nothing else, so the owners that act on one window cannot disagree
; about it.
;
; allowProbe is false for the window event hook: that is a CallbackCreate
; "Fast" callback with no thread of its own, so a PrintWindow capture there
; would run on whatever thread it interrupted. The hook reads the already
; decided state; the settled sweep owns the measurement.
_FSSuppressSurface(hwnd, title, allowProbe := false) {
    global State, CFG, _fsMainCandidate, _fsMainEverOpened
    if !State.fsMainLocked
        return

    ; Identity ledger, FIRST. Once an HWND has carried the Loading or Main title
    ; it is permanently off-limits to the notification-popup closer, whatever it is
    ; titled later. A title-and-size heuristic cannot safely distinguish a settled
    ; notification from a Firestone window that happens to match, and the
    ; consequence of getting it wrong is a WM_CLOSE.
    ;
    ; This runs BEFORE the helper-window branch below, which returns early. A
    ; Loading window that took that early return was never recorded here, so the
    ; one window guaranteed to become Firestone - Main was also the one window
    ; the closer considered fair game. Recording identity is free and must not
    ; be conditional on whether we go on to act.
    if (title = "Firestone - Loading" || title = "Firestone - Main")
        _fsMainCandidate[hwnd] := true

    ; Latch "Main has existed this session" HERE, where Main is actually seen.
    ;
    ; It used to be set only inside FSMainHasOpened(), which is called only from
    ; Hotkey_F3 -- so a user who never pressed F3 never set it, and every rule
    ; depending on it was silently inert for the whole session. A fact about the
    ; world belongs where the world is observed, not where somebody asks.
    if IsFirestoneMainTitle(title)
        _fsMainEverOpened := true

    ; HELPER-WINDOW EXEMPTION, NARROWED.
    ; IsHelperWindow returns true for anything OWNED by another window or
    ; carrying WS_EX_TOOLWINDOW. Overwolf builds most of its chrome-less
    ; surfaces that way -- the notification popup ("Your abilities are ready!")
    ; AND the "Firestone - Loading" splash -- so this early return skipped the
    ; loading window entirely. Nothing else hides it: the 10 ms sweep funnels
    ; through here, so it declined too, and the window simply sat on screen in
    ; full view until KillFirestoneLoading's 250 ms timer WM_CLOSEd it. That is
    ; the "flickered for a second and wasn't completely hidden before it
    ; disappeared" report -- it was never hidden at all, it was closed.
    ;
    ; The exemption exists to protect INFRASTRUCTURE (Qt tray helper,
    ; message-only sinks) from being managed at all. A titled Firestone surface
    ; is not that, whatever its window styles say. Any surface we can name is
    ; suppressed -- CLOAK ONLY, never moved, since a tool window's position is
    ; Overwolf's business and a park would fight its owner.
    ;
    ; Titles are matched EXACTLY (IsFirestoneMainTitle and friends), so the
    ; in-game overlay ("Firestone - Overlays") does not match any of them and
    ; keeps its complete immunity. That is deliberate and load-bearing: the
    ; overlay is the one Firestone surface that must never be touched.
    ; ── NOTIFICATION POPUP: CLOAK, NEVER PARK, AND KILL IT ──────────────────
    ; Handled before everything below, and deliberately never parked.
    ;
    ; Parking moves a window off the virtual desktop and RECORDS ITS RECTANGLE
    ; so it can be put back. That bookkeeping is what ties a window to F3: the
    ; unlock sweep restores everything it finds parked. A popup that is going
    ; to be closed must never enter that ledger, or F3 becomes a way to summon
    ; a window whose whole purpose is to not exist. Cloaking has no such
    ; bookkeeping -- it is a property of the window, cleared when the window
    ; dies, which for this window is imminent.
    if IsFirestoneNotificationPopup(hwnd, title) {
        ; The kill is ASKED FOR, not assumed. _FSKillNotificationPopup applies
        ; the structural guard and refuses when this window might be Firestone
        ; Main -- and if it refuses, this window is not a popup after all, so
        ; it must fall through to normal suppression rather than being cloaked
        ; here and abandoned. Cloaking first and asking afterwards left a
        ; declined window cloaked, outside the ledgers, and reachable only by
        ; the reveal path.
        if _FSKillNotificationPopup(hwnd, "funnel") {
            _DisableDWMTransitions(hwnd)
            return
        }
        ; Declined: treat it as the real Firestone window it may well be.
    }

    if IsHelperWindow(hwnd) {
        ; AN UNNAMED NEWBORN IS CLOAKED, NOT WAVED THROUGH.
        ;
        ; This is the birth gap. The window event hook calls this funnel at
        ; CREATE with an EMPTY title -- a CEF window has no caption yet -- and
        ; every test below matches on a TITLE, so at CREATE none of them could
        ; match and this branch returned having done nothing at all. By the
        ; time the window had a name to recognise, it had already painted.
        ;
        ; Cloaking an unidentified newborn is the safe direction to be wrong
        ; in. A cloak is reversible, costs nothing, and works on a window that
        ; has never been shown; if it turns out to be the in-game overlay,
        ; OverlayTopmostTick uncloaks it on its next pass -- the same contract
        ; this hook already relies on for every non-helper Overwolf window.
        ; Being invisible for one tick is recoverable. Being painted is not.
        if (title = "") {
            CloakWindow(hwnd)
            _DisableDWMTransitions(hwnd)
            return
        }
        if !(IsFirestoneMainTitle(title)
          || IsFirestoneBattlegroundsTitle(title)
          || title = "Firestone - Loading"
          || title = "Firestone") {
            _FSLogExemptOnce(hwnd, title)
            return
        }
        ; A NAMED FIRESTONE SURFACE FALLS THROUGH to the normal policy below,
        ; which MOVES it off the virtual desktop rather than only cloaking it.
        ;
        ; This branch used to stop here with a cloak and nothing else, on the
        ; reasoning that a tool window's position is Overwolf's business. That
        ; is true while the window is visible and false while we are concealing
        ; it: a cloaked window is not drawn but is still HIT-TESTED, so one left
        ; sitting over Hearthstone silently swallows every click that lands on
        ; it. An invisible window in the middle of the screen is worse than a
        ; visible one, because nothing on screen explains why the game stopped
        ; responding.
        ;
        ; The park records the exact rectangle and the reveal restores it, so
        ; the window still returns precisely where Overwolf put it.
    }

    warm := _FSIsWarm(hwnd)
    if (!warm && allowProbe)
        warm := (_FSProbePaint(hwnd, title) != 0)

    if warm
        _FSWarmSuppress(hwnd, title)
    else
        _FSColdSuppress(hwnd, title)
}

; Reveal-side counterpart: undo everything the cold path did, in the order that
; keeps it invisible until the last step.
; Show a Firestone window -- unless it is the notification popup, which is
; killed instead.
;
; The companion to the guard inside _FSReleaseSurface. Release and show are the
; two ways a concealed window gets back on screen, and both now refuse the one
; window that must never return. Every ShowWindow on a Firestone surface goes
; through here; the Battle.net paths have their own rules and are untouched.
_FSShowIfNotPopup(hwnd) {
    try {
        t := WinGetTitle("ahk_id " . hwnd)
        if IsFirestoneNotificationPopup(hwnd, t) {
            _FSKillNotificationPopup(hwnd, "show attempt")
            return false
        }
    }
    try DllCall("ShowWindow", "Ptr", hwnd, "Int", 8)   ; SW_SHOWNA
    return true
}

_FSReleaseSurface(hwnd) {
    global _fsParked

    ; ── A NOTIFICATION POPUP IS NEVER RELEASED. IT IS KILLED. ───────────────
    ; This is the single choke point for "make a Firestone window visible
    ; again" -- the F3 reveal, the early-cloak teardown, the overlay enforcer
    ; and the stranded-window repairs all end up here. Putting this rule at
    ; each of those sites means getting it right five times and keeping it
    ; right forever; putting it here means it cannot be got wrong at all.
    ;
    ; The popup reached the screen through this function twice already, via two
    ; different callers, which is the definition of a rule that belongs one
    ; level down. Firestone Main cannot match: this tests for the bare
    ; "Firestone" title, and Main's is "Firestone - Main".
    try {
        t := WinGetTitle("ahk_id " . hwnd)
        if IsFirestoneNotificationPopup(hwnd, t) {
            _FSKillNotificationPopup(hwnd, "release attempt")
            return
        }
    }

    _FSUnparkWindow(hwnd)             ; back on the chosen monitor, still cloaked
    _FSTabOn(hwnd)                    ; taskbar button back (no-op if never taken)
    ; Force the uncloak. The arbitration in UncloakWindow skips the DWM call when
    ; the ledger says we are not holding the cloak -- correct for avoiding churn,
    ; wrong here. A window cloaked by a previous instance, or one whose ledger entry
    ; was pruned, would be left cloaked: shown, positioned, focusable and completely
    ; invisible. The reveal must ask the window, not the ledger.
    UncloakWindow(hwnd, true)
}

; True only for the REAL Battle.net client window: launcher-titled AND
; resizable (WS_THICKFRAME) or currently maximized. That is the fingerprint
; separating it from the fixed-size auto-login shell ("Logging in" +
; Maintenance Alert panel), which keeps the SAME "Battle.net" title but has
; no resize frame and no maximize box. Styles are DPI-proof; pixel sizes are
; not, so no size thresholds are used here.
_IsProtectedBNetMain(hwnd) {
    try {
        t := WinGetTitle("ahk_id " . hwnd)
        if !(t = "Battle.net" || t = "Blizzard Battle.net")
            return false

        ; ---- OWNED WINDOWS ARE NEVER THE CLIENT ----------------------------
        ; The real Battle.net client is an unowned top-level window. Its alert
        ; panels -- maintenance notices, service outages, update prompts --
        ; are OWNED dialogs that inherit the owner's caption, so they too are
        ; titled "Battle.net" and they are laid out landscape at a size the
        ; SHAPE FALLBACK below happily accepts. That made an alert pass as the
        ; client: protected from the services blanket, and worse, latched into
        ; _bnetLauncherHwnd as the launcher's identity.
        ;
        ; This test runs before the style and shape tests because it is the
        ; only one of the three that cannot be fooled -- ownership is fixed at
        ; creation and never changes, whereas styles settle late (the reason
        ; the shape fallback exists at all) and shape is just a guess.
        if DllCall("user32\GetWindow", "Ptr", hwnd, "UInt", 4, "Ptr")   ; GW_OWNER
            return false

        style := WinGetStyle("ahk_id " . hwnd)
        if (style & 0x00040000)          ; WS_THICKFRAME: resizable = the client
            return true
        if (style & 0x01000000)          ; WS_MAXIMIZE: surely the client
            return true
        ; ---- SHAPE FALLBACK (birth-race fix) --------------------------------
        ; On several client builds WS_THICKFRAME is applied a few frames AFTER
        ; the window is created and titled. During that gap both style tests
        ; above fail, the services blanket classifies the REAL launcher as a
        ; service surface and SW_HIDEs it, and whether it is ever un-hidden
        ; depends on the exact ordering of (title set) / (style set) / (event
        ; delivery) -- the launcher inconsistency. This third test identifies
        ; the client by SHAPE while its styles are still settling.
        ;
        ; Discriminator is ASPECT, not absolute size: the client is markedly
        ; LANDSCAPE (~1.6:1), while the fixed-size auto-login shell ("Logging
        ; in" + Maintenance Alert) is portrait/square. Aspect holds at every
        ; DPI. The pixel floors only exclude small landscape dialogs; they are
        ; low enough to pass the client at 100% scaling and are never the
        ; deciding factor on a high-DPI display (where every dimension grows).
        rc := Buffer(16, 0)
        if DllCall("user32\GetWindowRect", "Ptr", hwnd, "Ptr", rc) {
            w := NumGet(rc,  8, "Int") - NumGet(rc, 0, "Int")
            h := NumGet(rc, 12, "Int") - NumGet(rc, 4, "Int")
            if (w >= 700 && h >= 400 && w > h * 1.15)
                return true
        }
    }
    return false
}

; -- Battle.net SERVICES blanket (aggressive) ---------------------------------
; Only the REAL client window (_IsProtectedBNetMain) is untouchable. EVERYTHING
; else in the Battle.net family is taken off the screen at maximum aggression
; while the blanket is armed: DWM-cloaked the instant it exists (cloak works on
; still-invisible windows, so the first shown frame is already invisible) and
; SW_HIDDEN + ledgered the moment it is visible. That includes the fixed-size
; auto-login shell ("Logging in" + Maintenance Alert), the boot splash,
; update/maintenance overlays, stray dialogs, and every Agent / Battle.net
; Helper window. Login and auth screens are hidden too: if a HUMAN actually
; has to type, the pipeline's title-based detector (which sees hidden windows)
; notices, LOGIN_WAIT flips _bnetLoginAllowed, and UnhideBNetLoginWindows
; brings back exactly those windows. Recovery paths for everything hidden
; here: NAMECHANGE janitor + 10ms tick enforcement (turns out to be the real
; client), LOGIN_WAIT (login windows), abort/exit janitors (everything).
_HideBlizzWindow(hwnd, exe := "Battle.net.exe") {
    global _bnetHiddenByUs, _bnetLoginAllowed, _bnetHideDone, _bnetLauncherHwnd
    try {
        ; IDENTITY PROTECTION: the real Battle.net client (resizable) is
        ; never hidden. This guarantees the launcher stays visible from the
        ; moment it appears, as requested. All other surfaces (splash,
        ; login shell, maintenance, Agent, Helper) are still hidden.
        if (exe = "Battle.net.exe" && _IsProtectedBNetMain(hwnd))
            return

        ; Once the reveal has shown the launcher, that exact hwnd is off-limits
        ; forever. (This is now redundant but kept for safety.)
        if (hwnd = _bnetLauncherHwnd)
            return
        ; Already hidden by us and still hidden: nothing to do.
        if (_bnetHideDone.Has(hwnd)
         && !DllCall("user32\IsWindowVisible", "Ptr", hwnd))
            return
        ; LOGIN_WAIT: hands off entirely so the user can see and type.
        if (exe = "Battle.net.exe" && _bnetLoginAllowed)
            return
        ; ONE MECHANISM: SW_HIDE only. Battle.net windows are NEVER cloaked.
        try UncloakWindow(hwnd)
        if DllCall("user32\IsWindowVisible", "Ptr", hwnd)
            _bnetHiddenByUs[hwnd] := true   ; was visible: janitors may restore
        DllCall("ShowWindow", "Ptr", hwnd, "Int", 0)       ; SW_HIDE
        _bnetHideDone[hwnd] := true
    }
}

; Move a Blizzard top-level window onto the chosen monitor WITHOUT requiring it
; to be visible (the normal placement assists skip invisible windows). Used at
; reveal time, before the window is shown, so its first visible frame lands on
; the right screen. No-op unless monitor locking is on and a monitor is chosen.
_PlaceBlizzWindowNow(hwnd) {
    global CFG, ChosenMonIdx
    if (!CFG.lockWindowsToChosenMonitor || !ChosenMonIdx)
        return
    try {
        if (DllCall("user32\GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr") != hwnd)
            return
        if (IsHelperWindow(hwnd) || IsIMEWindow(hwnd))
            return
        rc := Buffer(16, 0)
        if !DllCall("user32\GetWindowRect", "Ptr", hwnd, "Ptr", rc)
            return
        bx := NumGet(rc, 0, "Int"), by := NumGet(rc, 4, "Int")
        bw := NumGet(rc,  8, "Int") - bx
        bh := NumGet(rc, 12, "Int") - by
        if (bw < 100 || bh < 60)
            return
        if (GetMonitorIndexForPoint(bx + bw // 2, by + bh // 2) = ChosenMonIdx)
            return
        _SafeWorkArea(ChosenMonIdx, &waL, &waT, &waR, &waB)
        waW := waR - waL, waH := waB - waT
        if (waW <= 0 || waH <= 0)
            return
        nx := (bw <= waW) ? waL + (waW - bw) // 2 : waL
        ny := (bh <= waH) ? waT + (waH - bh) // 2 : waT
        DllCall("user32\SetWindowPos", "Ptr", hwnd, "Ptr", 0
            , "Int", nx, "Int", ny, "Int", 0, "Int", 0
            , "UInt", 0x0001 | 0x0004 | 0x0010)
    }
}

; ── DWM transition kill‑switch ───────────────────────────────────────────────
; DWMWA_TRANSITIONS_FORCEDISABLED (3): while TRUE, DWM draws NO minimize /
; restore / open transition animation for the window. This removes the black‑
; rectangle flicker during restore↔minimize fights.
_DisableDWMTransitions(hwnd) {
    static DWMWA_TRANSITIONS_FORCEDISABLED := 3
    v := 1
    try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", DWMWA_TRANSITIONS_FORCEDISABLED, "Int*", v, "UInt", 4)
}

_EnableDWMTransitions(hwnd) {
    static DWMWA_TRANSITIONS_FORCEDISABLED := 3
    v := 0
    try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", DWMWA_TRANSITIONS_FORCEDISABLED, "Int*", v, "UInt", 4)
}

; True if DWM currently reports the window as cloaked.
IsWindowCloakedDWM(hwnd) {
    static DWMWA_CLOAKED := 14
    v := 0
    if DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", DWMWA_CLOAKED, "UInt*", &v, "UInt", 4) = 0
        return v != 0
    return false
}

; ── FS‑Main alpha shield ──────────────────────────────────────────────────────
; Makes the window's pixels fully transparent (WS_EX_LAYERED, alpha 0).
; Applied only to suppression‑titled windows while the F3 lock is ON.
; Removed by F3 unlock, stop‑release, and ExitCleanup.
global _fsAlphaApplied := Map()   ; hwnd -> window was ALREADY layered before us
global _fsShieldDown   := Map()   ; hwnd -> OUR alpha-0 shield is currently
                                  ; armed on this kept-layered window. Lets
                                  ; every lock/unlock re-arm or clear the
                                  ; shield with pure VALUE writes -- never a
                                  ; style flip, never a FRAMECHANGED
global _fsBirthHidden   := Map()  ; hwnd -> tick we SW_HID it at CREATE,
                                  ; before it could paint. Released by the
                                  ; overlay / title-settle janitors, or by the
                                  ; timeout sweep, so nothing stays hidden by
                                  ; accident.
global _fsRevealFg      := Map()  ; hwnd -> already foregrounded during THIS
                                  ; reveal. Caps the topmost+activate at one
                                  ; per window per F3 press (it used to run on
                                  ; every 30ms tick -- the stress-test killer).
; The following map is removed because first-paint logic is no longer enforced:
; _fsPaintedTitles
global _fsEverPainted  := Map()   ; kept for reveal tracking (set when revealed)
global _fsHiddenByUs   := Map()   ; hwnd -> a Firestone-Loading suppressor
                                  ; SW_HID this window while it was VISIBLE.
                                  ; The F3 reveal may force-show ONLY these
                                  ; (the Loading->Main same-HWND retitle
                                  ; case). Windows Overwolf itself keeps
                                  ; hidden are NEVER force-shown -- doing so
                                  ; desynced Overwolf's own visibility state
                                  ; and made rapid F3 toggling kill the Main.
; The following maps are removed because they were only used for the
; first-paint safety logic, which is no longer enforced:
; _fsFirstTitledAt and _fsPaintedTitles.

; ── Layered-window mechanism probe ────────────────────────────────────────────
; A window can be layered in two mutually exclusive ways, and the difference
; decides whether it is safe to touch:
;
;   * UpdateLayeredWindow -- per-pixel alpha, which Chromium uses for its own
;     compositing. Calling SetLayeredWindowAttributes on such a window pulls it
;     out of that mode and can wedge one that is still forming. Never touch.
;   * SetLayeredWindowAttributes -- a single whole-window alpha value. Safe to
;     read and rewrite.
;
; GetLayeredWindowAttributes distinguishes them for free: it succeeds only for
; the attribute form. That is a direct question to the OS about the window's
; actual state, rather than an inference from whether it happened to look
; layered the first time this process saw it.
;
; Returns  1 = attribute-layered (alpha readable and writable)
;          0 = per-pixel layered (hands off)
;         -1 = not layered
_MapDrop(m, k) {
    try m.Delete(k)
}

_FSLayeredAlphaState(hwnd, &alpha) {
    alpha := 255
    static GWL_EXSTYLE := -20, WS_EX_LAYERED := 0x80000
    try {
        fnGet := (A_PtrSize = 8) ? "user32\GetWindowLongPtrW" : "user32\GetWindowLongW"
        ex := DllCall(fnGet, "Ptr", hwnd, "Int", GWL_EXSTYLE, "Ptr")
        if !(ex & WS_EX_LAYERED)
            return -1
        key := 0, bAlpha := 0, flags := 0
        if !DllCall("user32\GetLayeredWindowAttributes", "Ptr", hwnd
            , "UInt*", &key, "UChar*", &bAlpha, "UInt*", &flags)
            return 0
        alpha := bAlpha
        return 1
    }
    return -1
}

; ── Stuck-transparency repair ────────────────────────────────────────────────
; THE F3-REVEALS-AN-EMPTY-FRAME FIX.
;
; The shield deliberately keeps WS_EX_LAYERED across an unlock, so a window it
; has ever touched stays layered for life. If the script is then reloaded or
; restarted while Firestone is running -- which happens constantly during
; testing, and is exactly what Ctrl+Alt+R does -- the new instance starts with
; empty ledgers, sees a layered window, and (under the old logic) filed it as
; "Overwolf's own, never touch". From that moment both release paths refused to
; restore its alpha, so the window was stranded at alpha 0: shown, sized,
; focusable, and completely invisible. Pressing F3 dutifully un-hid and
; un-cloaked it, and you saw an empty outline.
;
; This walks the Overwolf family and restores full opacity on anything left
; attribute-layered at less than full alpha. Per-pixel windows are skipped by
; the probe above, so Overwolf's own compositing is never disturbed. Run at
; startup (repairs whatever a previous instance stranded) and on every F3
; unlock (guarantees the reveal cannot produce an invisible window).
FSRepairStuckAlpha() {
    global CFG, _fsAlphaApplied, _fsShieldDown
    static LWA_ALPHA := 0x2
    static lastRun := 0
    ; Throttled for the same reason as FSRepairStrandedWindows: StartFSReveal
    ; calls this on every F3 unlock, and a window cannot become stranded
    ; transparent between two key presses.
    if (lastRun && A_TickCount - lastRun < 3000)
        return
    lastRun := A_TickCount
    prev := A_DetectHiddenWindows
    DetectHiddenWindows true
    try {
        for exe in CFG.fsAlphaRepairExes {
            for h in WinGetList("ahk_exe " . exe) {
                try {
                    a := 255
                    if (_FSLayeredAlphaState(h, &a) = 1 && a < 255) {
                        DllCall("user32\SetLayeredWindowAttributes", "Ptr", h
                            , "UInt", 0, "UChar", 255, "UInt", LWA_ALPHA)
                        _MapDrop(_fsShieldDown, h)
                        _MapDrop(_fsAlphaApplied, h)
                    }
                }
            }
        }
    }
    DetectHiddenWindows prev
}

_ApplyFSAlphaShield(hwnd) {
    global _fsAlphaApplied, _fsShieldDown, CFG
    try {
        static LWA_ALPHA := 0x2
        static GWL_EXSTYLE := -20, WS_EX_LAYERED := 0x80000
        fnSet := (A_PtrSize = 8) ? "user32\SetWindowLongPtrW" : "user32\SetWindowLongW"
        fnGet := (A_PtrSize = 8) ? "user32\GetWindowLongPtrW" : "user32\GetWindowLongW"

        a := 255
        st := _FSLayeredAlphaState(hwnd, &a)

        ; Per-pixel layered (Overwolf's own compositing): record and leave it
        ; alone. The record still powers the notification sweeper's guard 3b,
        ; so downstream behaviour is unchanged. Invisibility for this window is
        ; carried by the cloak + minimize + hide, which is ample.
        if (st = 0) {
            _fsAlphaApplied[hwnd] := true
            return
        }

        ; Shield disabled (the default): record ownership so the guards that
        ; read _fsAlphaApplied behave exactly as before, but write no alpha.
        ; Nothing can be stranded transparent if nothing is ever made
        ; transparent.
        if !CFG.fsUseAlphaShield {
            if !_fsAlphaApplied.Has(hwnd)
                _fsAlphaApplied[hwnd] := false
            return
        }

        if (st = 1) {
            ; Attribute-layered -- ours, or a previous instance's. Either way
            ; the alpha is safely writable, so claim it rather than guessing.
            _fsAlphaApplied[hwnd] := false
            if !_fsShieldDown.Has(hwnd) {
                _fsShieldDown[hwnd] := true
                DllCall("user32\SetLayeredWindowAttributes", "Ptr", hwnd
                    , "UInt", 0, "UChar", 0, "UInt", LWA_ALPHA)
            }
            return
        }

        ; Not layered: first-ever shield on this hwnd.
        ex := DllCall(fnGet, "Ptr", hwnd, "Int", GWL_EXSTYLE, "Ptr")
        DllCall(fnSet, "Ptr", hwnd, "Int", GWL_EXSTYLE, "Ptr", ex | WS_EX_LAYERED)
        DllCall("user32\SetLayeredWindowAttributes", "Ptr", hwnd
            , "UInt", 0, "UChar", 0, "UInt", LWA_ALPHA)
        _fsAlphaApplied[hwnd] := false
        _fsShieldDown[hwnd]  := true
    }
}

; F3-cycle shield release: alpha back to 255, WS_EX_LAYERED DELIBERATELY KEPT.
; The old full unwind (strip the style + the FRAMECHANGED a style change
; requires) ran once per unlock -- N F3 cycles = N layered-mode round-trips
; on the live CEF window, exactly the repeated-mode-switch hazard the apply
; side documents. A layered window at alpha 255 renders fully normally, so
; keeping the style turns every later lock/unlock into a pure value write.
; The full unwind (_RemoveFSAlphaShield below) remains for the ONE-SHOT
; janitors (early-cloak release, popup closer, overlay sweep, exit), where a
; true style restore is the right thing and happens at most once per launch.
_ClearFSAlphaShield(hwnd) {
    global _fsAlphaApplied, _fsShieldDown
    _EnableDWMTransitions(hwnd)
    ; State, not ledger. Ask the window what its alpha actually is rather than
    ; consulting bookkeeping: a window stranded transparent by an earlier instance
    ; has no ledger entry, and it is exactly the case that needs repairing.
    ; Per-pixel layered windows still return 0 from the probe and are still never
    ; touched, so Chromium's own compositing is safe.
    try {
        a := 255
        if (_FSLayeredAlphaState(hwnd, &a) = 1 && a < 255) {
            DllCall("user32\SetLayeredWindowAttributes", "Ptr", hwnd
                , "UInt", 0, "UChar", 255, "UInt", 0x2)
        }
    }
    _MapDrop(_fsShieldDown, hwnd)
}

; Full unwind, for the one-shot janitors (early-cloak release, overlay sweep,
; popup closer, exit). Safe to call on ANY window, ledger entry or not.
;
; Was ledger-driven and bailed on `!_fsAlphaApplied.Has(hwnd)` -- so the exact
; window that most needs rescuing (one stranded transparent by a previous
; instance, whose ledger entry does not exist) was the one it refused to touch.
; The overlay-visibility enforcement depends on this working from a cold
; ledger, so it is now driven by the window's real state.
_RemoveFSAlphaShield(hwnd) {
    global _fsAlphaApplied, _fsShieldDown
    _MapDrop(_fsShieldDown, hwnd)
    ownedByUs := (_fsAlphaApplied.Has(hwnd) && !_fsAlphaApplied[hwnd])
    _MapDrop(_fsAlphaApplied, hwnd)
    _EnableDWMTransitions(hwnd)
    try {
        static GWL_EXSTYLE := -20, WS_EX_LAYERED := 0x80000, LWA_ALPHA := 0x2
        fnGet := (A_PtrSize = 8) ? "user32\GetWindowLongPtrW" : "user32\GetWindowLongW"
        fnSet := (A_PtrSize = 8) ? "user32\SetWindowLongPtrW" : "user32\SetWindowLongW"

        a := 255
        st := _FSLayeredAlphaState(hwnd, &a)
        if (st = 0)
            return          ; per-pixel (Overwolf's own): never touch

        ; ALWAYS restore opacity first if it is dimmed -- this is the part that
        ; must work even with no ledger entry.
        if (st = 1 && a < 255) {
            DllCall("user32\SetLayeredWindowAttributes", "Ptr", hwnd
                , "UInt", 0, "UChar", 255, "UInt", LWA_ALPHA)
        }

        ; Only strip the STYLE for a window we know we made layered. Removing
        ; it from someone else's window is the mode-switch hazard the apply
        ; side is careful to avoid; a layered window at alpha 255 renders
        ; completely normally, so leaving the style on costs nothing.
        if (ownedByUs && st = 1) {
            ex := DllCall(fnGet, "Ptr", hwnd, "Int", GWL_EXSTYLE, "Ptr")
            DllCall(fnSet, "Ptr", hwnd, "Int", GWL_EXSTYLE, "Ptr", ex & ~WS_EX_LAYERED)
            DllCall("user32\SetWindowPos", "Ptr", hwnd, "Ptr", 0
                , "Int", 0, "Int", 0, "Int", 0, "Int", 0
                , "UInt", 0x0001 | 0x0002 | 0x0004 | 0x0010 | 0x0020)
        }
    }
}

; ── IME / TSF filter ──────────────────────────────────────────────────────────
; Centralized filter for Windows IME/TSF helper windows that must never be
; touched by any window‑management API.
IsIMEWindow(hwnd) {
    try {
        ; Renamed from `class`: that is a language keyword in AutoHotkey v2 and
        ; using it as a variable is asking the parser for trouble for no gain.
        cls := WinGetClass("ahk_id " . hwnd)
        if (cls = "")
            return false

        if (cls = "IME"
         || cls = "MSCTFIME UI"
         || cls = "Default IME"
         || cls = "CicMarshalWnd"
         || cls = "CicMarshalWndClass"
         || cls = "CicLoaderWndClass"
         || cls = "CiceroUIWndFrame"
         || cls = "CUAS_MainWnd"
         || cls = "CUASMainWnd"
         || cls = "TSF_DimmItemWindow"
         || cls = "MSUIM.Win.Context"
         || cls = "MSUIM.Win.Client"
         || cls = "MSUIM.Win.TipConfig"
         || cls = "MSUIM.Win.TipBand"
         || cls = "UIAWnd")
            return true

        if (InStr(cls, "IME")
         || InStr(cls, "MSCTF")
         || InStr(cls, "Cicero")
         || InStr(cls, "CUAS")
         || SubStr(cls, 1, 10) = "MSUIM.Win.")
            return true
    } catch {
    }
    return false
}

; ── Battle.net window policy ──────────────────────────────────────────────────
; During an F2 launch the Battle.net LAUNCHER is never hidden: it appears
; normally (placed on the chosen monitor by the hook / first-show assists),
; renders unfocused for the render dwell, launches Hearthstone, and is
; minimized animation-free the instant Play fires (re-asserted at HS-PID)
; so the client's game-page navigation renders off-screen. Only SERVICE surfaces (boot splash / loading / maintenance /
; Agent) are SW_HIDDEN, by _HideBlizzWindow, for the blanket's lifetime
; (StartHSCloaker -> StopHSCloaker), the auto-login shell and login screens
; included -- LOGIN_WAIT un-hides the login windows when a human must type.
; Abort/exit restore what was hidden.
global _bnetPostMinUntil := 0
global _bnetPostMinCount := Map()   ; hwnd -> corrective minimizes performed

; ── Helper‑window immunity ───────────────────────────────────────────────────
; Infrastructure windows (Qt tray helper, tool windows) must NEVER be managed.
IsHelperWindow(hwnd) {
    try {
        if (DllCall("user32\GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr") != hwnd)
            return true
        ex := 0
        try ex := WinGetExStyle("ahk_id " . hwnd)
        if (ex & 0x80)                             ; WS_EX_TOOLWINDOW
            return true
        t := ""
        try t := WinGetTitle("ahk_id " . hwnd)
        if (t = "QTrayIconMessageWindow" || t = "QEventDispatcherWin32_Internal_Widget"
         || t = "SystemTray_Main" || t = "MSCTFIME UI" || t = "Default IME")
            return true
    } catch {
        return true
    }
    return false
}

; ── Blizzard-family helper immunity, NARROWED ────────────────────────────────
; IsHelperWindow is deliberately broad: it exempts anything OWNED by another
; window and anything carrying WS_EX_TOOLWINDOW. For Overwolf that is right --
; those really are infrastructure. For the Battle.net family it is exactly
; wrong, because the surfaces the services blanket exists to suppress ARE owned
; dialogs: the maintenance alert, service-outage notices, update prompts. Every
; Blizzard sweep called IsHelperWindow and hit `continue` on them, so the one
; class of window most worth hiding was the one class guaranteed to be skipped.
; That is the same shape as the Firestone notification-popup exemption bug --
; a broad immunity rule swallowing the thing it was supposed to catch.
;
; This is the narrowed version used by the Blizzard sweeps. It exempts only
; windows with no visible surface to suppress in the first place:
;   * IME / TSF windows            -- managing them breaks text input
;   * known Qt infrastructure      -- tray sink, event dispatcher
;   * message-only windows         -- parented to HWND_MESSAGE, never composited
;   * degenerate rectangles        -- 1x1 and smaller sinks
; Anything with real pixels on a real monitor is the blanket's business,
; ownership and tool-window style notwithstanding.
_IsBlizzInfrastructureWindow(hwnd) {
    try {
        if IsIMEWindow(hwnd)
            return true

        t := ""
        try t := WinGetTitle("ahk_id " . hwnd)
        if (t = "QTrayIconMessageWindow" || t = "QEventDispatcherWin32_Internal_Widget"
         || t = "SystemTray_Main" || t = "MSCTFIME UI" || t = "Default IME")
            return true

        ; Message-only windows are parented to HWND_MESSAGE rather than to the
        ; desktop. They are never composited, so there is nothing to conceal --
        ; and SW_HIDE on one is a pointless poke at another process's plumbing.
        par  := DllCall("user32\GetAncestor", "Ptr", hwnd, "UInt", 1, "Ptr")   ; GA_PARENT
        desk := DllCall("user32\GetDesktopWindow", "Ptr")
        if (par && desk && par != desk)
            return true

        rc := Buffer(16, 0)
        if DllCall("user32\GetWindowRect", "Ptr", hwnd, "Ptr", rc) {
            w := NumGet(rc,  8, "Int") - NumGet(rc, 0, "Int")
            h := NumGet(rc, 12, "Int") - NumGet(rc, 4, "Int")
            if (w <= 1 || h <= 1)
                return true
        }
    } catch {
        return true            ; unreadable window: leave it alone
    }
    return false
}

; Janitor: if a "QTrayIconMessageWindow" is ever VISIBLE, hide it again and log.
global _qtHelperLogged := Map()
QtHelperJanitor() {
    global _qtHelperLogged, CFG
    prevMode := A_TitleMatchMode
    SetTitleMatchMode(3)
    try {
        for h in WinGetList("QTrayIconMessageWindow") {
            try {
                if !DllCall("user32\IsWindowVisible", "Ptr", h)
                    continue
                exe := ""
                try exe := WinGetProcessName("ahk_id " . h)
                n := _qtHelperLogged.Get(h, 0)
                if (n = 0 && CFG.f1DebugLog)
                    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss")
                        . " QT-HELPER visible owner=" . exe
                        . " hwnd=" . h . " -> re-hidden`n"
                        , A_Temp . "\hs_bg_f1.log")
                if (n >= 3)
                    continue
                _qtHelperLogged[h] := n + 1
                WinHide("ahk_id " . h)
            }
        }
    }
    SetTitleMatchMode prevMode
}

; Minimize the way a human does: SC_MINIMIZE, with the shell's animation.
;
; _MinimizeWindowNoAnim below exists for a specific reason -- an animated
; minimize of a CLOAKED window composites as a solid black rectangle
; collapsing into the taskbar, which is why every Firestone and Hearthstone
; minimize in this script is animation-free.
;
; The Battle.net launcher is NOT cloaked when it minimizes; it was uncloaked
; seconds earlier, at the end of the navigation. So the reason does not apply
; to it, and suppressing the animation just made the window vanish -- "almost
; like its hidden and just put into minimization". This sends the same
; WM_SYSCOMMAND the minimize button sends, so the launcher animates into the
; taskbar exactly as if it had been clicked.
;
; DWM transitions are re-enabled first: they are force-disabled during the
; navigation cloak (so the uncloak does not fade in) and, while that attribute
; is set, DWM draws no minimize animation either. The scheduled restore
; normally beats this by several seconds; calling it here as well makes the
; animation independent of that timing.
_MinimizeWindowAnimated(hwnd) {
    static WM_SYSCOMMAND := 0x0112, SC_MINIMIZE := 0xF020
    try _EnableDWMTransitions(hwnd)
    try {
        PostMessage(WM_SYSCOMMAND, SC_MINIMIZE, 0, , "ahk_id " . hwnd)
        return true
    }
    ; Fallback for a client that ignores SC_MINIMIZE: SW_MINIMIZE still
    ; animates, it just also activates the next window in the z-order.
    try return DllCall("ShowWindow", "Ptr", hwnd, "Int", 6) != 0
    return false
}

; Minimize with no animation and no activation. Preserves the restore rect.
_MinimizeWindowNoAnim(hwnd) {
    wp := Buffer(44, 0)
    NumPut("UInt", 44, wp, 0)
    if !DllCall("user32\GetWindowPlacement", "Ptr", hwnd, "Ptr", wp)
        return false
    NumPut("UInt", 7, wp, 8)                        ; showCmd = SW_SHOWMINNOACTIVE
    return DllCall("user32\SetWindowPlacement", "Ptr", hwnd, "Ptr", wp) != 0
}

; ── Battle.net reveal / minimize lifecycle ────────────────────────────────────
; The launcher is NEVER hidden. The lifecycle is now:
;
;   RevealBNetForRender()    "LAUNCHER READY" (first call only): stamps
;                            _bnetRevealedAt -- the render dwell AND the
;                            launch gate (TryLaunchWTCG) both measure from
;                            it -- un-hides anything the blanket caught
;                            that is really the client, and puts a
;                            minimized client on screen WITHOUT taking
;                            focus (no activation, no active-window
;                            highlight). Later calls are no-ops, so it is
;                            safe as a janitor.
;   RevealBNetWindows(min)   Public entry used by every call site; if min is
;                            true it hands off to the dwell-aware minimize.
;   MinimizeBNetAfterDwell() Waits out whatever remains of
;                            CFG.bnetRevealDwellMs so the launcher is fully
;                            painted, then minimizes it animation-free and
;                            starts the post-launch minimize watchdog.
;                            Called at Play-fire (primary; the linger knob
;                            can delay it) and again the moment HS's
;                            PROCESS exists (backstop).
;   RestoreHiddenBNetServices()  Abort/exit janitor: re-shows every service
;                            window the blanket took off the screen (a
;                            stalled launch may be stalled BECAUSE of a
;                            maintenance surface the user needs to see).
;   UnhideBNetLoginWindows() LOGIN_WAIT janitor: un-hides ONLY the login /
;                            auth windows the blanket hid. Auto-login stays
;                            invisible; a human who must type gets the
;                            screen back, placed and focused.
global _bnetRevealedAt := 0        ; TickCount of Battle.net's first revealed frame (0 = still hidden)
global _bnetLaunchFiredAt := 0     ; TickCount the WTCG launch command was
                                   ; fired (0 = not yet this launch). The
                                   ; launch fires only AFTER the launcher is
                                   ; revealed and dwelled, so HS can never
                                   ; open before the launcher is on screen.
global _bnetHiddenByUs := Map()    ; hwnd -> true: the blanket SW_HIDE'd this
                                   ; window while it was VISIBLE — the only
                                   ; windows the reveal / cleanup may WinShow
global _bnetLauncherHwnd := 0      ; the EXACT launcher hwnd the reveal has
                                   ; shown. Identity beats predicates: once
                                   ; set, nothing may hide this window again.
global _bnetHideDone := Map()      ; hwnd -> we have already hidden (and, for
                                   ; the launcher, minimized) this window.
                                   ; Stops the blanket from re-issuing
                                   ; SetWindowPlacement every 10ms tick --
                                   ; the "launcher fighting itself" storm.
global _bnetLauncherStaged := false ; true once the ready-reveal has restored
                                   ; the launcher on screen -- from then on
                                   ; the hide path leaves it alone so it can
                                   ; render, launch HS, and minimize
global _bnetLoginAllowed := false  ; true while the pipeline is in LOGIN_WAIT:
                                   ; the Battle.net.exe half of the services
                                   ; blanket stands down COMPLETELY so a human
                                   ; can see and type into the login screen
                                   ; (and any authenticator popup it spawns)
global _smLastTick := 0            ; heartbeat: TickCount of the last
                                   ; LaunchStateMachine_Tick run. Lets F2
                                   ; detect a DEAD (vs busy) pipeline and
                                   ; self-heal instead of blocking forever.
global _bnetPostMinDone := false   ; one-shot: the post-launch minimize already
                                   ; ran for this F2 (HAMMERING sets it the
                                   ; moment HS's process exists)

; ── Launcher foreground pin ──────────────────────────────────────────────────
; The launcher's whole job is to be looked at: it comes up, navigates to the
; Hearthstone page, presses Play, and goes away. Opening it into whatever slot
; the z-order happens to offer means that on a desktop with anything already
; open it launches the game from behind a browser window. This gives it the
; same treatment F3 gives Firestone Main and Battlegrounds -- HWND_TOPMOST plus
; an activate -- so it is unambiguously in front for the few seconds it exists.
;
; TOPMOST rather than a plain raise, for the same reason F3 uses it: a plain
; SetForegroundWindow is subject to Windows' foreground-lock rules and loses to
; a fullscreen window, which is precisely the situation this runs in.
;
; ONE-SHOT per hwnd. RevealBNetForRender doubles as a janitor and is called
; repeatedly; repeating the activate on every call is the "hundreds of z-order
; changes and activations" pattern that killed Firestone Main under F3 spam.
;
; NEVER while Hearthstone exists. A borderless Unity window that loses the
; foreground re-runs its display-mode setup and snaps to its remembered
; monitor -- the "HS flickered to primary monitor" regression. Once the game is
; up, the foreground is its property and this stays out of it.
global _bnetFgPinned := Map()
_BNetPinForeground(hwnd) {
    global CFG, _bnetFgPinned
    if (!CFG.bnetRevealForeground || _bnetFgPinned.Has(hwnd))
        return
    if GetHSPID()
        return
    _bnetFgPinned[hwnd] := true
    try {
        DllCall("user32\SetWindowPos", "Ptr", hwnd, "Ptr", -1      ; HWND_TOPMOST
            , "Int", 0, "Int", 0, "Int", 0, "Int", 0
            , "UInt", 0x0001 | 0x0002 | 0x0010)                    ; NOSIZE|NOMOVE|NOACTIVATE
        WinActivate("ahk_id " . hwnd)
        _FSLog("BNET-FG launcher pinned topmost and activated hwnd=" . hwnd)
    }
}

; Release the pin. Called from the minimize path and from the Hearthstone
; reveal, whichever happens first.
;
; A topmost window that minimizes keeps the flag, so a launcher the user later
; restores by hand would sit over the game forever. And if the minimize is late
; -- a slow client, a retry -- the pin would otherwise put the launcher over a
; game that has already been revealed. Both are one SetWindowPos to prevent.
_BNetDropTopmost(hwnd := 0) {
    global _bnetFgPinned
    if hwnd {
        targets := [hwnd]
    } else {
        targets := []
        for h in _bnetFgPinned
            targets.Push(h)
    }
    for h in targets {
        try {
            if DllCall("user32\IsWindow", "Ptr", h)
                DllCall("user32\SetWindowPos", "Ptr", h, "Ptr", -2  ; HWND_NOTOPMOST
                    , "Int", 0, "Int", 0, "Int", 0, "Int", 0
                    , "UInt", 0x0001 | 0x0002 | 0x0010)
        }
        ; The ledger records the pin we are CURRENTLY holding, not one we once
        ; held. Releasing has to clear it, or an F2 restart that reuses the
        ; running launcher finds a stale entry, treats the window as already
        ; pinned, and brings it back behind everything -- the exact bug this
        ; whole block exists to prevent. Entry removed even when the window is
        ; already dead, so the map cannot grow across restarts.
        try _bnetFgPinned.Delete(h)
    }
}

RevealBNetForRender() {
    global _bnetRevealedAt, _bnetLauncherStaged, ChosenMonIdx, _bnetLauncherHwnd
    global _bnetHiddenByUs, _bnetHideDone, CFG
    ; Since the launcher is never hidden, this function now only positions
    ; the real client window on the chosen monitor (if not already there).
    ; The un‑hide / rescue sweep is removed because it is no longer needed.

    prev := A_DetectHiddenWindows
    DetectHiddenWindows true
    try {
        _bnetLauncherStaged := true
        for hwnd in WinGetList("ahk_exe Battle.net.exe") {
            try {
                if IsHelperWindow(hwnd)
                    continue
                if !_IsProtectedBNetMain(hwnd)
                    continue

                ; --- UN-HIDE BACKSTOP -------------------------------------
                ; This function was rewritten under the assumption that the
                ; launcher is never hidden, and its rescue sweep was deleted.
                ; That assumption does not hold on builds where the client is
                ; unidentifiable at birth: the blanket hides it before anyone
                ; can tell what it is. The reveal is the stage whose entire
                ; job is to put the launcher on screen, so it must be able to
                ; undo that. Layer 3 of 3 (identify at birth -> reclaim at
                ; 10ms -> guarantee here).
                if (_bnetHiddenByUs.Has(hwnd) || _bnetHideDone.Has(hwnd)
                 || !DllCall("user32\IsWindowVisible", "Ptr", hwnd)) {
                    _bnetHiddenByUs.Delete(hwnd)
                    _bnetHideDone.Delete(hwnd)
                    try UncloakWindow(hwnd)
                    if !DllCall("user32\IsWindowVisible", "Ptr", hwnd)
                        DllCall("ShowWindow", "Ptr", hwnd, "Int", 8)   ; SW_SHOWNA
                }

                ; --- CENTER IT (if not already on the chosen monitor) ---
                ; The window is visible, but we move it only once and while
                ; it is already visible; to avoid a visible jump we use the
                ; same cloak‑wrap that _PlaceBlizzWindowNow uses.
                if ChosenMonIdx {
                    try {
                        rc := Buffer(16, 0)
                        if DllCall("user32\GetWindowRect", "Ptr", hwnd, "Ptr", rc) {
                            bx := NumGet(rc, 0, "Int"), by := NumGet(rc, 4, "Int")
                            bw := NumGet(rc,  8, "Int") - bx
                            bh := NumGet(rc, 12, "Int") - by
                            ; Only move if not already on chosen monitor
                            if (GetMonitorIndexForPoint(bx + bw // 2, by + bh // 2) != ChosenMonIdx) {
                                _SafeWorkArea(ChosenMonIdx, &rL, &rT, &rR, &rB)
                                rW := rR - rL, rH := rB - rT
                                if (bw < 200 || bw > rW)
                                    bw := Min(rW, 1200)
                                if (bh < 150 || bh > rH)
                                    bh := Min(rH, 800)
                                px := rL + (rW - bw) // 2
                                py := rT + (rH - bh) // 2
                                ; Cloak to hide the move, then move, then uncloak
                                global _cloakState
                                wasCloaked := _cloakState.Has(hwnd)
                                if !wasCloaked
                                    CloakWindow(hwnd)
                                DllCall("user32\SetWindowPos", "Ptr", hwnd, "Ptr", 0
                                    , "Int", px, "Int", py, "Int", bw, "Int", bh
                                    , "UInt", 0x0004 | 0x0010)   ; NOZORDER|NOACTIVATE
                                if !wasCloaked {
                                    Sleep(15)
                                    UncloakWindow(hwnd)
                                }
                            }
                        }
                    }
                }

                ; IDENTITY: from here on, this exact hwnd is the launcher and
                ; nothing may hide it again (see _HideBlizzWindow).
                _bnetLauncherHwnd := hwnd

                ; Last step, and it depends on the mode.
                ;
                ; "visible": put it in front. Done last so the pin lands on a
                ; window that is already un-hidden and already on the chosen
                ; monitor -- pinning first would raise a window about to move.
                ;
                ; "minimized": put it away instead, animation-free and without
                ; activation, before it has drawn a frame anyone will see. The
                ; launch command does not care whether the client is visible,
                ; so nothing else in the sequence changes.
                if (CFG.bnetLauncherMode = "minimized") {
                    _MinimizeWindowNoAnim(hwnd)
                    _FSLog("BNET-SEQ launcher mode=minimized -- tucked away"
                         . " without being shown")
                } else {
                    _BNetPinForeground(hwnd)
                }
            }
        }
    }
    DetectHiddenWindows prev
}

; Has the launcher finished arriving, as opposed to merely existing?
;
; Deliberately shape-based rather than timed. "Visible, not minimised, and
; bigger than the placeholder rect a CEF window starts with" is evidence; a
; stopwatch is a guess, and it is wrong on exactly the machines that most need
; it to be right.
_BNetLauncherLooksReady() {
    prev  := A_DetectHiddenWindows
    DetectHiddenWindows true
    ready := false
    try {
        for hwnd in WinGetList("ahk_exe Battle.net.exe") {
            try {
                if _IsBlizzInfrastructureWindow(hwnd)
                    continue
                if !_IsProtectedBNetMain(hwnd)
                    continue
                if !DllCall("user32\IsWindowVisible", "Ptr", hwnd)
                    continue
                if (WinGetMinMax("ahk_id " . hwnd) = -1)
                    continue
                w := 0, h := 0
                WinGetPos(, , &w, &h, "ahk_id " . hwnd)
                if (w >= 700 && h >= 400) {
                    ready := true
                    break
                }
            }
        }
    }
    DetectHiddenWindows prev
    return ready
}

; Public entry (unchanged signature). See the lifecycle note above.
RevealBNetWindows(minimizeMain := false) {
    RevealBNetForRender()
    if minimizeMain
        MinimizeBNetAfterDwell()
}

; Abort/exit janitor: bring back every Battle.net-family window the services
; blanket took off the screen. A stalled launch may be stalled BECAUSE of a
; maintenance/update surface the user needs to see.
RestoreHiddenBNetServices() {
    global _bnetHiddenByUs
    prev := A_DetectHiddenWindows
    DetectHiddenWindows true
    for hwnd in _bnetHiddenByUs.Clone() {
        try {
            _bnetHiddenByUs.Delete(hwnd)
            if DllCall("user32\IsWindow", "Ptr", hwnd) {
                try UncloakWindow(hwnd)
                if !DllCall("user32\IsWindowVisible", "Ptr", hwnd)
                    DllCall("ShowWindow", "Ptr", hwnd, "Int", 8)   ; SW_SHOWNA
            }
        }
    }
    DetectHiddenWindows prev
}

; LOGIN_WAIT janitor: bring back ONLY the login/auth windows the blanket hid,
; place them, and put focus on the first so the user can type at once.
; _bnetLoginAllowed must already be true, or the 10ms blanket re-hides them.
UnhideBNetLoginWindows() {
    global _bnetHiddenByUs, _bnetHideDone
    prev := A_DetectHiddenWindows
    DetectHiddenWindows true
    focused := false
    ; Scan EVERY Battle.net window (hidden included), not just our ledger: the
    ; blanket now hides unconditionally, so a login window born hidden would
    ; never appear in the ledger and could never be restored -> unable to log
    ; in. Enumerating the process guarantees we find it however it was hidden.
    for hwnd in WinGetList("ahk_exe Battle.net.exe") {
        try {
            if IsHelperWindow(hwnd)
                continue
            t := StrLower(WinGetTitle("ahk_id " . hwnd))
            if (InStr(t, "log in") || InStr(t, "sign in") || InStr(t, "battle.net login")) {
                if _bnetHiddenByUs.Has(hwnd)
                    _bnetHiddenByUs.Delete(hwnd)
                if _bnetHideDone.Has(hwnd)
                    _bnetHideDone.Delete(hwnd)
                try UncloakWindow(hwnd)
                _PlaceBlizzWindowNow(hwnd)
                if (WinGetMinMax("ahk_id " . hwnd) = -1)
                    DllCall("ShowWindow", "Ptr", hwnd, "Int", 9)   ; SW_RESTORE
                else
                    DllCall("ShowWindow", "Ptr", hwnd, "Int", 8)   ; SW_SHOWNA
                if !focused {
                    try WinActivate("ahk_id " . hwnd)
                    focused := true
                }
            }
        }
    }
    DetectHiddenWindows prev
}

; ══════════════════════════════════════════════════════════════════════════════
; LAUNCHER MINIMISE -- anchored to Hearthstone, not to a stopwatch
; ══════════════════════════════════════════════════════════════════════════════
; The rule, stated plainly:
;
;     open -> launch Hearthstone -> once Hearthstone has launched,
;     wait a beat -> minimise.
;
; The middle clause is the important one. Guessing how long Battle.net takes
; to spawn the game makes the sequence depend on disk speed, pending patches
; and login latency; waiting for the event does not.
;
; One timer owns the decision, armed the instant the launcher becomes
; visible:
;
;   * the launcher must have been visible for bnetRevealDwellMs (never
;     flashes away),
;   * Hearthstone.exe must exist (it has launched),
;   * bnetPostPlayLingerMs must have elapsed since then (the beat),
;   * or bnetMinimizeCeilingMs, if Hearthstone never arrives (never stuck).
;
; Other code may request a minimise -- the request is idempotent -- but
; nothing else sets the timing.
; The Play command's timestamp, kept SEPARATE from _bnetLaunchFiredAt.
;
; Both are stamped at the same instant, but _bnetLaunchFiredAt is cleared by
; CancelLaunchTimers -- which runs on six paths including the SUCCESS ones --
; and the minimize and the stall watch both measure from this moment. Reusing a
; value someone else resets would make the launcher's exit depend on which
; teardown happened to run first. This one belongs to the minimize sequence and
; nothing else writes it.
global _bnetPlayFiredAt := 0

; The moment the launcher became USABLE, as opposed to merely existing.
;
; Every visible interval in the sequence is measured from here, which is what
; makes the sequence take the same time on a cold start as on a warm one. Reset
; per launch by StartBNetMinimizeSequence.
global _bnetReadyAt := 0
                               ; AFTER the launcher became visible
global _bnetMinSeqUntil := 0   ; ceiling for the sequence (0 = not running)

StartBNetMinimizeSequence() {
    global _bnetMinSeqUntil, _bnetPlayFiredAt, _bnetReadyAt, CFG
    ; Clear the anchor for THIS sequence. The predecessor this replaced was
    ; reset here; without the same reset, a second F2 in one session starts a
    ; sequence still holding the PREVIOUS launch's timestamp -- already older
    ; than the linger -- and the tick would minimize a launcher that has not
    ; pressed Play yet. Stage 3 of TryLaunchWTCG re-stamps it for real.
    _bnetPlayFiredAt := 0
    _bnetReadyAt     := 0
    _bnetMinSeqUntil := A_TickCount + CFG.bnetMinimizeCeilingMs
    SetTimer(BNetMinimizeSequenceTick, 200)
}

StopBNetMinimizeSequence() {
    global _bnetMinSeqUntil
    _bnetMinSeqUntil := 0
    SetTimer(BNetMinimizeSequenceTick, 0)
}

BNetMinimizeSequenceTick() {
    global CFG, _bnetRevealedAt, _bnetPostMinDone, _bnetPlayFiredAt, _bnetMinSeqUntil
    global _bnetReadyAt

    if (_bnetPostMinDone || !_bnetRevealedAt || !_bnetMinSeqUntil) {
        StopBNetMinimizeSequence()
        return
    }
    ; The launcher must actually have been looked at before it goes away --
    ; unless it was never shown, in which case there is nothing to look at and
    ; the floor is zero. That is the whole difference the "minimized" mode
    ; makes to this timer.
    ; Same anchor as the scheduled minimize, so the backstop can never
    ; disagree with it about when the launcher is due to go.
    dwell := (CFG.bnetLauncherMode = "minimized") ? 0 : CFG.bnetRevealDwellMs
    if (_bnetReadyAt && (A_TickCount - _bnetReadyAt) < dwell)
        return

    ; Ceiling: the launch command never fired at all. Minimize anyway rather
    ; than leaving the launcher sitting on screen forever, and say so.
    if (A_TickCount >= _bnetMinSeqUntil) {
        _FSLog("BNET-SEQ ceiling reached after "
             . (A_TickCount - _bnetRevealedAt) . "ms -- minimizing the launcher"
             . " anyway")
        _BNetSequenceMinimizeNow()
        return
    }

    ; ══════════════════════════════════════════════════════════════════════
    ; THE ANCHOR IS THE PLAY COMMAND, NOT HEARTHSTONE'S PROCESS
    ; ══════════════════════════════════════════════════════════════════════
    ; This used to wait for Hearthstone to exist and then linger. That put the
    ; launcher on screen for the whole of Hearthstone's start-up, and produced
    ; the sequence the user did not want: launcher, then game, then the
    ; launcher tidying itself away over the top of the game.
    ;
    ; Anchoring on the launch command instead means the launcher is already
    ; gone by the time the game's window appears, so the game arrives to an
    ; empty screen and takes the foreground uncontested. The launcher's job
    ; ended when it fired the command; nothing about the minimize needs to know
    ; whether the game has started yet.
    ;
    ; What the game's absence DOES matter for is a stalled launch -- a pending
    ; update or a sign-in. That is a separate question with its own owner, the
    ; stall watch armed after the minimize. See BNetStallWatchTick.
    if !_bnetPlayFiredAt
        return
    if (A_TickCount - _bnetPlayFiredAt < CFG.bnetPostPlayLingerMs)
        return

    _FSLog("BNET-SEQ Play fired " . (A_TickCount - _bnetPlayFiredAt)
         . "ms ago -- minimizing the launcher now, ahead of the game window")
    _BNetSequenceMinimizeNow()
}

; ══════════════════════════════════════════════════════════════════════════════
;  F1 GUARD — keep the launcher down while the connection is blocked
; ══════════════════════════════════════════════════════════════════════════════
; Scoping the firewall rule to Hearthstone.exe (see _HSProgramScope) removes the
; CAUSE of the launcher surfacing during F1. This is the second line: Battle.net
; restores itself for its own reasons too -- a finished background download, a
; friend request, a notification -- and mid-combat is the worst possible moment
; for a window to appear over the game.
;
; Two hard rules, so this can never become the thing that fights the user:
;   * It only ever re-minimizes a launcher THIS SCRIPT already minimized
;     (_bnetPostMinDone). A launcher the user opened themselves is not ours.
;   * It stands down completely while the stall watch has deliberately put the
;     launcher on screen for an update or a sign-in.
; And it minimizes WITHOUT animation or activation, because F1 runs while the
; user is in combat: no shrink-to-taskbar animation, no focus change.
global _f1BNetGuardUntil := 0
global _f1BNetWasMinimized := Map()   ; hwnd -> was minimized when F1 started

; Snapshot which launcher windows are minimized RIGHT NOW, then watch only
; those. _bnetPostMinDone alone was too coarse a test: it stays true for the
; rest of the session after the first launch, so the guard would also
; re-minimize a launcher the user had opened themselves and was reading during
; the F1 window. Restoring a window this script minimized is what we undo;
; a window the user chose to have open is theirs.
StartF1BNetGuard(durationMs) {
    global _f1BNetGuardUntil, _f1BNetWasMinimized
    _f1BNetWasMinimized := Map()
    prev := A_DetectHiddenWindows
    DetectHiddenWindows true
    try {
        for hwnd in WinGetList("ahk_exe Battle.net.exe") {
            try {
                if _IsBlizzInfrastructureWindow(hwnd)
                    continue
                if !_IsProtectedBNetMain(hwnd)
                    continue
                if (WinGetMinMax("ahk_id " . hwnd) = -1)
                    _f1BNetWasMinimized[hwnd] := true
            }
        }
    }
    DetectHiddenWindows prev

    if !_f1BNetWasMinimized.Count
        return                    ; nothing was tucked away: nothing to protect
    _f1BNetGuardUntil := A_TickCount + durationMs
    SetTimer(F1BNetGuardTick, 250)
}

StopF1BNetGuard() {
    global _f1BNetGuardUntil, _f1BNetWasMinimized
    _f1BNetGuardUntil   := 0
    _f1BNetWasMinimized := Map()
    SetTimer(F1BNetGuardTick, 0)
}

F1BNetGuardTick() {
    global _f1BNetGuardUntil, _f1BNetWasMinimized, _bnetStallRevealed
    if (!_f1BNetGuardUntil || A_TickCount >= _f1BNetGuardUntil) {
        StopF1BNetGuard()
        return
    }
    if _bnetStallRevealed
        return                    ; the stall watch put it up on purpose
    prev := A_DetectHiddenWindows
    DetectHiddenWindows true
    try {
        for hwnd in _f1BNetWasMinimized {
            try {
                if !DllCall("user32\IsWindow", "Ptr", hwnd)
                    continue
                if !DllCall("user32\IsWindowVisible", "Ptr", hwnd)
                    continue
                if (WinGetMinMax("ahk_id " . hwnd) = -1)
                    continue
                _FSLog("F1-GUARD the launcher restored itself during an F1"
                     . " block -- putting it back, silently")
                _MinimizeWindowNoAnim(hwnd)
            }
        }
    }
    DetectHiddenWindows prev
}

; ══════════════════════════════════════════════════════════════════════════════
;  STALLED-LAUNCH WATCH — update pending, or a sign-in the detector missed
; ══════════════════════════════════════════════════════════════════════════════
; The launcher now minimizes as soon as Play fires, without waiting to see
; whether the game actually starts. That is right in the normal case and wrong
; in exactly one: when Play could not start the game, because Battle.net is
; downloading a patch, or wants credentials, or is showing something that needs
; a human. Left alone the user would be staring at an empty desktop with a
; minimized launcher and no idea why nothing happened.
;
; So the launcher goes away optimistically and comes BACK if it turns out to
; have been needed. The test is the outcome, not the UI: no Hearthstone process
; within CFG.bnetStallRevealMs of the Play command means Play did not work.
; Reading Battle.net's own interface to find out why would mean matching
; localised text in a CEF surface, which breaks on every client update and in
; every language; the absence of a process does not.
;
; While waiting, the launch command is re-fired periodically. A download that
; finishes leaves a client where Play now works, and nothing else would ever
; press it -- TryLaunchWTCG fires exactly once per launch by design.
global _bnetStallWatchUntil := 0
global _bnetStallRevealed   := false
global _bnetStallLastRetry  := 0

StartBNetStallWatch() {
    global _bnetStallWatchUntil, _bnetStallRevealed, _bnetStallLastRetry, CFG
    _bnetStallWatchUntil := A_TickCount + CFG.bnetStallWatchMaxMs
    _bnetStallRevealed   := false
    _bnetStallLastRetry  := A_TickCount
    SetTimer(BNetStallWatchTick, 1000)
}

StopBNetStallWatch() {
    global _bnetStallWatchUntil
    _bnetStallWatchUntil := 0
    SetTimer(BNetStallWatchTick, 0)
}

BNetStallWatchTick() {
    global CFG, _bnetStallWatchUntil, _bnetStallRevealed, _bnetStallLastRetry
    global _bnetPlayFiredAt, _bnetLauncherHwnd

    if !_bnetStallWatchUntil {
        SetTimer(BNetStallWatchTick, 0)
        return
    }

    ; The game arrived. Whether it took two seconds or twenty minutes, the
    ; watch is done -- and if the launcher was brought back, put it away again.
    if GetHSPID() {
        if _bnetStallRevealed {
            _FSLog("BNET-STALL Hearthstone launched -- re-minimizing the launcher")
            try _BNetDropTopmost()
            try _BNetDwellMinimize()
        }
        StopBNetStallWatch()
        return
    }

    ; Battle.net itself is gone: nothing left to wait for.
    if !ProcessExist("Battle.net.exe") {
        StopBNetStallWatch()
        return
    }

    if (A_TickCount >= _bnetStallWatchUntil) {
        _FSLog("BNET-STALL giving up after " . CFG.bnetStallWatchMaxMs . "ms")
        StopBNetStallWatch()
        return
    }

    waited := _bnetPlayFiredAt ? (A_TickCount - _bnetPlayFiredAt) : 0
    if (waited < CFG.bnetStallRevealMs)
        return

    ; ---- Bring the launcher back, once ----
    if !_bnetStallRevealed {
        _bnetStallRevealed := true
        _FSLog("BNET-STALL no Hearthstone " . waited . "ms after Play"
             . " -- restoring the launcher so the user can see what it wants"
             . " (update or sign-in)")
        try RestoreHiddenBNetServices()   ; the reason may BE a hidden surface
        try {
            prev := A_DetectHiddenWindows
            DetectHiddenWindows true
            for hwnd in WinGetList("ahk_exe Battle.net.exe") {
                try {
                    if _IsBlizzInfrastructureWindow(hwnd)
                        continue
                    if !_IsProtectedBNetMain(hwnd)
                        continue
                    if (WinGetMinMax("ahk_id " . hwnd) = -1)
                        DllCall("ShowWindow", "Ptr", hwnd, "Int", 9)  ; SW_RESTORE
                    _bnetLauncherHwnd := hwnd
                    _BNetPinForeground(hwnd)
                }
            }
            DetectHiddenWindows prev
        }
        BgHUD.Show("Battle.net needs attention — update or sign-in", 6000)
        return
    }

    ; ---- Keep nudging Play while we wait ----
    if (A_TickCount - _bnetStallLastRetry >= CFG.bnetRelaunchEveryMs) {
        _bnetStallLastRetry := A_TickCount
        _FSLog("BNET-STALL re-firing the launch command")
        try LaunchWTCG()
    }
}

_BNetSequenceMinimizeNow() {
    ; Deliberately does NOT set _bnetPostMinDone itself. MinimizeBNetAfterDwell
    ; owns that flag and returns early if it is already set, so setting it here
    ; would make the call a no-op and the launcher would never minimize at all.
    ; One owner for the decision, one owner for the flag.
    ;
    ; The sequence timer is NOT stopped here either -- it is stopped by
    ; MinimizeBNetAfterDwell once the flag is set, and leaving it running until
    ; then means the verification below gets a second chance if the first
    ; attempt does not take.
    MinimizeBNetAfterDwell()
    SetTimer(_BNetVerifyMinimized, -400)
}

; Confirm the launcher actually ended up minimised, rather than assuming it.
;
; A SetWindowPlacement that does not take -- or a launcher that restores itself
; immediately afterwards, which this client does when a download finishes or a
; notification arrives -- is otherwise indistinguishable from success. Retries a
; few times and records the outcome either way.
_BNetVerifyMinimized() {
    static tries := 0
    ok := false, seen := false
    prev := A_DetectHiddenWindows
    DetectHiddenWindows true
    try {
        for hwnd in WinGetList("ahk_exe Battle.net.exe") {
            try {
                if IsHelperWindow(hwnd)
                    continue
                t := WinGetTitle("ahk_id " . hwnd)
                if !(t = "Battle.net" || t = "Blizzard Battle.net")
                    continue
                if !DllCall("user32\IsWindowVisible", "Ptr", hwnd)
                    continue
                seen := true
                if (WinGetMinMax("ahk_id " . hwnd) = -1)
                    ok := true
                else
                    _MinimizeWindowAnimated(hwnd)
            }
        }
    }
    DetectHiddenWindows prev

    if (ok || !seen) {
        tries := 0
        _FSLog("BNET-SEQ minimize confirmed")
        return
    }
    tries++
    if (tries < 4) {
        SetTimer(_BNetVerifyMinimized, -500)
        return
    }
    tries := 0
    _FSLog("BNET-SEQ minimize did NOT take after 4 attempts"
         . " -- the launcher is refusing SetWindowPlacement or restoring itself")
}

; Minimise the launcher now. Idempotent.
;
; All timing lives in BNetMinimizeSequenceTick, the single owner of the
; question "when should the launcher go away". This function does not
; re-derive it: a second opinion on the same question is what makes the
; sequence unpredictable, since whichever caller arrives first would set the
; timing. _bnetPostMinDone makes a duplicate call a no-op.
MinimizeBNetAfterDwell() {
    global _bnetRevealedAt, _bnetLaunchFiredAt, CFG, _bnetPostMinDone
    ; NO TIMING LIVES HERE ANY MORE.
    ;
    ; This function used to re-derive "is it too early?" from wall-clock deltas,
    ; and its own header explained that four different call sites could reach it
    ; and whichever arrived first won. That is precisely the problem
    ; BNetMinimizeSequenceTick now owns, so re-deriving it here would just
    ; reintroduce a second opinion.
    ;
    ; It is now a plain, idempotent "minimize the launcher, now". The sequence
    ; calls it when its conditions are met; the abort and late-recovery paths
    ; call it because at that point the launcher genuinely should be tucked
    ; away. _bnetPostMinDone makes a duplicate call a no-op.
    if _bnetPostMinDone
        return
    _bnetPostMinDone := true
    StopBNetMinimizeSequence()
    _BNetDwellMinimize()
    ; The launcher went away without waiting to see whether the game starts.
    ; This is what notices if it should not have. Armed here because this
    ; function is the once-only owner of the minimize; _BNetDwellMinimize is
    ; also called BY the stall watch, and arming it there would re-arm itself.
    StartBNetStallWatch()
}

_BNetDwellMinimize() {
    global ChosenMonIdx
    prev := A_DetectHiddenWindows
    DetectHiddenWindows true
    try {
        for hwnd in WinGetList("ahk_exe Battle.net.exe") {
            try {
                if IsHelperWindow(hwnd)
                    continue
                if !DllCall("user32\IsWindowVisible", "Ptr", hwnd)
                    continue    ; hidden (e.g. the ledgered auto-login shell):
                                ; already off-screen; minimizing it would pop
                                ; a ghost taskbar button
                if (WinGetMinMax("ahk_id " . hwnd) = -1)
                    continue
                title := WinGetTitle("ahk_id " . hwnd)
                if (title = "Battle.net" || title = "Blizzard Battle.net") {
                    ; Park the foreground before minimising, but only while Hearthstone does not
                    ; yet exist.
                    ;
                    ; Minimising the foreground launcher lets Windows hand the foreground to the
                    ; next eligible window, which before Hearthstone is running is the topmost
                    ; Firestone - Overlays -- and Overwolf answers that by restoring
                    ; Firestone - Main. Handing the foreground to the desktop shell first makes
                    ; the hand-off deterministic.
                    ;
                    ; Once Hearthstone exists the foreground belongs to it, and taking it away is
                    ; harmful: a borderless Unity window that loses the foreground re-runs its
                    ; display-mode setup and snaps to its remembered monitor.
                    if (!GetHSPID()
                     && DllCall("user32\GetForegroundWindow", "Ptr") = hwnd) {
                        shell := DllCall("user32\GetShellWindow", "Ptr")
                        if shell
                            try WinActivate("ahk_id " . shell)
                    }
                    ; MOVE-ONTO-CHOSEN-MONITOR, THEN MINIMIZE. Windows restores
                    ; a window to the monitor it was minimized FROM (the
                    ; minimize origin), NOT to rcNormalPosition -- so the only
                    ; reliable way to make it restore on the chosen monitor is
                    ; to have it PHYSICALLY THERE at minimize time. The launcher
                    ; is borderless, so moving it while visible is a silent
                    ; reposition. Move, confirm it landed, then minimize.
                    if (ChosenMonIdx) {
                        try {
                            WinGetPos(&mx, &my, &mw, &mh, "ahk_id " . hwnd)
                            if (mw > 0 && GetMonitorIndexForPoint(mx + mw // 2, my + mh // 2) != ChosenMonIdx) {
                                _SafeWorkArea(ChosenMonIdx, &mwaL, &mwaT, &mwaR, &mwaB)
                                mwW := mwaR - mwaL, mwH := mwaB - mwaT
                                nmx := (mw <= mwW) ? mwaL + (mwW - mw) // 2 : mwaL
                                nmy := (mh <= mwH) ? mwaT + (mwH - mh) // 2 : mwaT
                                WinMove(nmx, nmy, , , "ahk_id " . hwnd)
                                ; brief settle so the move commits before minimize
                                Sleep(20)
                            }
                        }
                    }
                    ; Release the foreground pin BEFORE minimizing. A topmost
                    ; window keeps the flag across a minimize, so a launcher
                    ; the user restores by hand later would come back floating
                    ; over the game.
                    _BNetDropTopmost(hwnd)
                    _MinimizeWindowAnimated(hwnd)   ; the launcher is not cloaked: let it animate
                }
            }
        }
    }
    DetectHiddenWindows prev
    ; Close any residual gap in the SAME thread turn as the minimize: one
    ; synchronous suppression pass re‑asserts FS‑Main's cloak and (verified)
    ; alpha shield before any Overwolf reaction can composite a frame.
    try SuppressFirestoneMainTick()
    StartBNetPostLaunchMinimize()
}

StartBNetPostLaunchMinimize(durationMs := 20000) {
    global _bnetPostMinUntil, _bnetPostMinCount
    _bnetPostMinUntil := A_TickCount + durationMs
    _bnetPostMinCount := Map()
    SetTimer(BNetPostLaunchMinimizeTick, 500)
    BNetPostLaunchMinimizeTick()
}

StopBNetPostLaunchMinimize() {
    global _bnetPostMinUntil
    _bnetPostMinUntil := 0
    SetTimer(BNetPostLaunchMinimizeTick, 0)
}

BNetPostLaunchMinimizeTick() {
    global _bnetPostMinUntil, _bnetPostMinCount, _placeCreateSeen, ChosenMonIdx

    if (!ProcessExist("Hearthstone.exe") || A_TickCount >= _bnetPostMinUntil) {
        StopBNetPostLaunchMinimize()
        return
    }

    try {
        for hwnd in WinGetList("ahk_exe Battle.net.exe") {
            try {
                if IsHelperWindow(hwnd)
                    continue
                if (WinGetMinMax("ahk_id " . hwnd) = -1)
                    continue
                WinGetPos(, , &w, &h, "ahk_id " . hwnd)
                if (w < 200 || h < 150)
                    continue
                if (_placeCreateSeen.Has(hwnd)
                 && (A_TickCount - _placeCreateSeen[hwnd] < 4000))
                    continue
                if (_bnetPostMinCount.Get(hwnd, 0) >= 3)
                    continue
                _bnetPostMinCount[hwnd] := _bnetPostMinCount.Get(hwnd, 0) + 1
                ; Move onto the chosen monitor (if the launcher got restored
                ; off it between ticks), then minimize -- so it restores THERE.
                ; The watchdog only fires when the launcher is un-minimized, so
                ; a visible borderless move is a silent reposition.
                if (ChosenMonIdx) {
                    try {
                        WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " . hwnd)
                        if (ww > 0 && GetMonitorIndexForPoint(wx + ww // 2, wy + wh // 2) != ChosenMonIdx) {
                            _SafeWorkArea(ChosenMonIdx, &wwaL, &wwaT, &wwaR, &wwaB)
                            wwW := wwaR - wwaL, wwH := wwaB - wwaT
                            nwx := (ww <= wwW) ? wwaL + (wwW - ww) // 2 : wwaL
                            nwy := (wh <= wwH) ? wwaT + (wwH - wh) // 2 : wwaT
                            WinMove(nwx, nwy, , , "ahk_id " . hwnd)
                            Sleep(20)
                        }
                    }
                }
                _MinimizeWindowAnimated(hwnd)
            } catch {
            }
        }
    }
}

; ==============================================================================
; SECTION 11b: FIRESTONE OVERLAY TOPMOST ENFORCER
; ------------------------------------------------------------------------------
; Overwolf sometimes fails to promote "Firestone - Overlays" to TOPMOST.
; This watchdog forces it via SetWindowPos(HWND_TOPMOST) after launch completes.
; ==============================================================================

StartOverlayTopmostEnforcer() {
    SetTimer(OverlayTopmostTick, 2000)
    OverlayTopmostTick()
}

StopOverlayTopmostEnforcer() {
    SetTimer(OverlayTopmostTick, 0)
}

OverlayTopmostTick() {
    ; _fsAlphaApplied must be declared global here. In AutoHotkey v2 an
    ; undeclared name inside a function is a LOCAL, and reading an unset local
    ; throws -- inside the try below, which would swallow it and skip the rest of
    ; the per-window body, silently disabling this entire enforcer.
    global _fsAlphaApplied, _fsParked, _fsTabRemoved, _cloakState
    static HWND_TOPMOST   := -1
    static SWP_NOSIZE     := 0x0001
    static SWP_NOMOVE     := 0x0002
    static SWP_NOACTIVATE := 0x0010

    if !GetHSPID() {
        StopOverlayTopmostEnforcer()
        return
    }

    hsForeground := false
    hsForeground := _HSIsForeground()

    prev     := A_DetectHiddenWindows
    prevMode := A_TitleMatchMode
    DetectHiddenWindows true
    SetTitleMatchMode(2)

    try {
        ; Scan OverwolfBrowser.exe as well: recent Overwolf builds host the in-game
        ; overlay in the browser process, so an Overwolf.exe-only scan finds nothing
        ; and this enforcer becomes a no-op on those installations.
        for exe in ["Overwolf.exe", "OverwolfBrowser.exe"] {
            for h in WinGetList("ahk_exe " . exe) {
                try {
                    title := WinGetTitle("ahk_id " . h)
                    if (title != "Firestone - Overlays")
                        continue

                    if _fsAlphaApplied.Has(h)
                        _RemoveFSAlphaShield(h)

                    ; Release ONLY if something is actually holding this
                    ; window. _FSReleaseSurface unparks, restores the taskbar
                    ; button and force-uncloaks; running all three on the
                    ; overlay every two seconds -- when the overlay is almost
                    ; never parked, tab-stripped or cloaked -- was pure churn
                    ; against the one window that must stay rock steady while
                    ; the user has comps pinned to it.
                    if (_fsParked.Has(h) || _fsTabRemoved.Has(h)
                     || _cloakState.Has(h) || IsWindowCloakedDWM(h))
                        _FSReleaseSurface(h)

                    if !hsForeground
                        continue

                    ; "GetWindowLongPtr" is not an exported symbol -- the real exports are
                    ; GetWindowLongPtrW (64-bit) and GetWindowLongW (32-bit). Use the same
                    ; A_PtrSize branch as the rest of the script rather than relying on DllCall's
                    ; implicit "W" retry, which would fail outright on a 32-bit host.
                    fnGetLong := (A_PtrSize = 8) ? "user32\GetWindowLongPtrW" : "user32\GetWindowLongW"
                    exStyle := DllCall(fnGetLong, "Ptr", h, "Int", -20, "Ptr")
                    if (exStyle & 0x00000008)   ; WS_EX_TOPMOST already set
                        continue

                    if !DllCall("user32\IsWindowVisible", "Ptr", h)
                        continue

                    DllCall("user32\SetWindowPos",
                        "Ptr",  h,
                        "Ptr",  HWND_TOPMOST,
                        "Int",  0,
                        "Int",  0,
                        "Int",  0,
                        "Int",  0,
                        "UInt", SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE)
                } catch {
                }
            }
        }
    }

    DetectHiddenWindows prev
    SetTitleMatchMode prevMode
}

; ==============================================================================
; SECTION 11d: FIRESTONE‑MAIN REVEAL (F3 unlock) — stability‑hardened
; ------------------------------------------------------------------------------
; Reveals the Firestone main window when unlocked. Uses a watchdog tick to
; wait for the window to settle and avoid touching a half‑initialised Chromium
; surface.
global _fsRevealActive    := false
global _fsRevealUntil     := 0
global _fsRevealedMainAt  := 0
global _fsRevealSettleReq := 0
global _fsRevealFirstSeen := Map()
global _fsRevealDone      := Map()   ; hwnd -> one-shot reveal work done
global _fsRevealSettled   := Map()   ; hwnd -> its move has had a frame to
                                     ; itself; z-order work may proceed
global _fsRevealNudged    := Map()
global _fsRevealSettleMs  := 1000

; Gentle, crash‑safe repaint nudge for an Overwolf/Chromium surface.
; Atomic FS show: re-checks the lock the instant before showing. A re-lock
; (LockFirestoneMain -> StopFSReveal) can land AFTER the reveal loop's top
; guard but BEFORE this call; without the re-check the reveal would show a
; window the burst is simultaneously hiding -- the taskbar-ping war that
; ends with Firestone exiting. cmd is the SW_ verb (4/8/9). Returns whether
; it showed.
_GuardedFSShow(hwnd, cmd) {
    global State
    if State.fsMainLocked
        return false            ; lock won the race: leave it hidden
    DllCall("ShowWindow", "Ptr", hwnd, "Int", cmd)
    return true
}

_ForceFSRepaint(hwnd) {
    ; InvalidateRect on the TOP-LEVEL window is close to useless for Chromium:
    ; the page is painted by a child HWND (Chrome_RenderWidgetHostHWND) into a
    ; compositor surface, so invalidating the parent asks the one window that
    ; draws nothing to redraw nothing. RedrawWindow with RDW_ALLCHILDREN
    ; actually reaches the surface that holds the content.
    static RDW_INVALIDATE := 0x1, RDW_ERASE := 0x4
    static RDW_ALLCHILDREN := 0x80, RDW_UPDATENOW := 0x100
    try DllCall("user32\RedrawWindow", "Ptr", hwnd, "Ptr", 0, "Ptr", 0
        , "UInt", RDW_INVALIDATE | RDW_ERASE | RDW_ALLCHILDREN | RDW_UPDATENOW)
}

; Stronger kick: force a real geometry change so the window receives
; WM_WINDOWPOSCHANGED / WM_SIZE. That is a signal Chromium acts on -- it
; re-lays-out and produces a frame -- whereas a bare SW_SHOWNA is not. Used on
; reveal for a window that comes back idle rather than destroyed. Size is
; nudged by one pixel and put straight back, so nothing moves perceptibly.
_FSForceRender(hwnd) {
    static SWP_NOZORDER := 0x0004, SWP_NOACTIVATE := 0x0010, SWP_NOMOVE := 0x0002
    try {
        UncloakWindow(hwnd, true)      ; a cloaked window reads as occluded
        _ForceFSRepaint(hwnd)
        rc := Buffer(16, 0)
        if !DllCall("user32\GetWindowRect", "Ptr", hwnd, "Ptr", rc)
            return
        x := NumGet(rc, 0, "Int"), y := NumGet(rc, 4, "Int")
        w := NumGet(rc, 8, "Int") - x, h := NumGet(rc, 12, "Int") - y
        if (w < 50 || h < 50)
            return
        DllCall("user32\SetWindowPos", "Ptr", hwnd, "Ptr", 0
            , "Int", x, "Int", y, "Int", w - 1, "Int", h
            , "UInt", SWP_NOZORDER | SWP_NOACTIVATE)
        DllCall("user32\SetWindowPos", "Ptr", hwnd, "Ptr", 0
            , "Int", x, "Int", y, "Int", w, "Int", h
            , "UInt", SWP_NOZORDER | SWP_NOACTIVATE)
        _ForceFSRepaint(hwnd)
    }
}

; Bring the just‑revealed Firestone window to the TRUE foreground (above other
; apps such as Chrome), but ONLY when Hearthstone is not itself the active window.
_ForegroundFSIfSafe(hwnd) {
    try {
        if WinActive("ahk_exe Hearthstone.exe")
            return
    } catch {
    }
    try WinActivate("ahk_id " . hwnd)
}

; Restored (normal) width/height of hwnd via GetWindowPlacement.
_GetRestoredSize(hwnd, &w, &h) {
    w := 0, h := 0
    wp := Buffer(44, 0)
    NumPut("UInt", 44, wp, 0)
    if !DllCall("user32\GetWindowPlacement", "Ptr", hwnd, "Ptr", wp)
        return false
    left   := NumGet(wp, 28, "Int")
    top    := NumGet(wp, 32, "Int")
    right  := NumGet(wp, 36, "Int")
    bottom := NumGet(wp, 40, "Int")
    w := right - left
    h := bottom - top
    return true
}

StartFSReveal() {
    global _fsRevealActive, _fsRevealUntil, _fsRevealedMainAt
    global _fsRevealFirstSeen, _fsRevealSettleReq, _fsRevealSettleMs
    global _fsRevealNudged, _fsRevealFg, _fsRevealDone, _fsRevealSettled
    global State, Launch
    _fsRevealActive   := true
    _fsRevealedMainAt := 0
    _fsRevealFirstSeen := Map()
    _fsRevealNudged    := Map()
    _fsRevealDone      := Map()   ; fresh: full reveal action once per window
    _fsRevealSettled   := Map()   ; fresh: position-settled gate
    _fsRevealFg        := Map()   ; fresh: foreground once per window per reveal

    ; Belt and braces: before the reveal touches anything, restore full opacity
    ; on every Overwolf surface left transparent -- including ones this
    ; instance never shielded itself. An F3 unlock must never be able to put an
    ; invisible window on screen, regardless of what happened before it.
    FSRepairStuckAlpha()
    ; Same contract for the park: nothing this reveal shows may be sitting
    ; outside the virtual desktop, including windows a previous instance
    ; parked and never came back for.
    FSRepairStrandedWindows()

    launching := State.f2Active || (Launch.state != "IDLE" && Launch.state != "DONE")
    _fsRevealSettleReq := launching ? _fsRevealSettleMs : 0
    _fsRevealUntil     := A_TickCount + (launching ? 60000 : 5000)

    SetTimer(FSRevealTick, 30)
    FSRevealTick()
}

StopFSReveal() {
    global _fsRevealActive, _fsRevealFirstSeen, _fsRevealNudged
    global _fsPaintState, CFG
    _fsRevealActive := false
    SetTimer(FSRevealTick, 0)

    ; ── The reveal is the paint proof ───────────────────────────────────
    ; This is the only context where the question can be answered honestly. The
    ; window has just been unparked, uncloaked, shown and nudged: it has had the
    ; full treatment on a real screen.
    ;
    ; So probe once, so the log records what happened, and mark the window warm
    ; either way. If it did not paint under these conditions, nothing the cold
    ; path does on a later press will help, and continuing to park and unpark it
    ; is strictly harmful. Warm means it takes the plain concealment path from
    ; here on.
    for h in _fsRevealFirstSeen {
        try {
            if !DllCall("user32\IsWindow", "Ptr", h)
                continue
            if _fsPaintState.Has(h)
                continue
            d := 0
            painted := _FSWindowHasPainted(h, &d)
            _fsPaintState[h] := 1
            if (painted && d >= CFG.fsPaintMinDistinct)
                _FSLog("FS-PAINT PROVEN AT REVEAL hwnd=" . h . " distinct=" . d
                     . " -- warm from now on, no further park/unpark")
            else
                _FSLog("FS-PAINT NOT proven at reveal hwnd=" . h . " distinct=" . d
                     . " -- marking warm anyway; the cold path cannot help a"
                     . " window that stayed blank with the reveal fully applied,"
                     . " and repeating it is what damages the renderer")
        }
    }

    _fsRevealFirstSeen := Map()
    _fsRevealNudged    := Map()
    _fsRevealDone      := Map()
    _fsRevealSettled   := Map()
}

FSRevealTick() {
    global _fsRevealActive, _fsRevealUntil, _fsRevealedMainAt, State, _fsEverPainted
    global _fsRevealFirstSeen, _fsRevealSettleReq, _fsRevealNudged, _fsHiddenByUs, CFG, _fsRevealFg
    global _fsRevealDone, _fsRevealSettled, _fsMainCandidate

    if !_fsRevealActive {
        SetTimer(FSRevealTick, 0)
        return
    }

    try {
        prev     := A_DetectHiddenWindows
        prevMode := A_TitleMatchMode
        DetectHiddenWindows true
        SetTitleMatchMode(2)

        for exe in ["Overwolf.exe", "OverwolfBrowser.exe"] {
            for h in WinGetList("ahk_exe " . exe) {
                try {
                    title := WinGetTitle("ahk_id " . h)
                    if !(IsFirestoneMainTitle(title) || IsFirestoneBattlegroundsTitle(title))
                        continue

                    if !_fsRevealFirstSeen.Has(h)
                        _fsRevealFirstSeen[h] := A_TickCount

                    if !DllCall("IsWindow", "Ptr", h)
                        continue

                    _GetRestoredSize(h, &rw, &rh)
                    if (rw < 300 || rh < 300)
                        continue

                    if (_fsRevealSettleReq && (A_TickCount - _fsRevealFirstSeen[h] < _fsRevealSettleReq))
                        continue

                    ; Mid-sweep re-lock guard (mirror of _SuppressFSHwnd's):
                    ; a lock can land between two windows of this sweep --
                    ; from that instant the burst owns the windows again, so
                    ; un-suppressing the rest would just add a flicker.
                    if (!_fsRevealActive || State.fsMainLocked)
                        continue

                    ; Hidden and NOT ours to show (no ledger entry): this is
                    ; Overwolf's own between-matches state -- the
                    ; Battlegrounds window's normal lifecycle. Leave it
                    ; EXACTLY as it is, CLOAK INCLUDED. The old uncloak here
                    ; showed nothing (the window stayed hidden anyway) but
                    ; stripped the pre-armed cloak, re-arming the one-frame
                    ; race at the window's next SHOW under match-start load
                    ; -- the residual BG flicker. A cloak left in place
                    ; makes the next locked-era show born invisible with
                    ; ZERO event or timer dependence; an UNLOCKED-era show
                    ; is released by the hook's unlocked-show janitor.
                    if (!DllCall("user32\IsWindowVisible", "Ptr", h)
                     && !_fsHiddenByUs.Has(h))
                        continue

                    _fsEverPainted[h] := true   ; the reveal below is this
                                                ; Once per window per reveal. This timer exists to WAIT for a window to become
                                                ; eligible, not to repeat the reveal on it; without this gate every action below
                                                ; would run once per 30 ms tick for the whole reveal window.
                    if !_fsRevealDone.Has(h) {
                        _fsRevealDone[h] := true
                        ; A window the user has revealed is by definition not a stray notification, so
                        ; record it in the identity ledger. The suppression funnel does not run while
                        ; the lock is off, so a revealed window would otherwise never be recorded there.
                        _fsMainCandidate[h] := true
                        _ClearFSAlphaShield(h)
                        _FSReleaseSurface(h)
                        _FSLog("FS-REVEAL title=`"" . title . "`" painted="
                             . (_FSIsWarm(h) ? "yes" : "NOT PROVEN")
                             . " visible="
                             . (DllCall("user32\IsWindowVisible", "Ptr", h) ? 1 : 0))
                    }
                    ; Show-if-hidden, LEDGER-GATED: only windows OUR loading
                    ; suppressors took off the screen (the Loading->Main
                    ; same-HWND retitle case) are force-shown here. Windows
                    ; Overwolf itself keeps hidden are left to Overwolf.
                    if (!DllCall("user32\IsWindowVisible", "Ptr", h)
                     && _fsHiddenByUs.Has(h)) {
                        if _GuardedFSShow(h, 8)   ; SW_SHOWNA, lock-checked
                            _fsHiddenByUs.Delete(h)
                    }
                    if (WinGetMinMax("ahk_id " . h) = -1)
                        _GuardedFSShow(h, 4)      ; SW_SHOWNOACTIVATE, lock-checked

                    ; Let the move settle before any z-order work.
                    ;
                    ; _FSReleaseSurface has just moved the window back and uncloaked it. Doing the
                    ; topmost pin and the activation in the same thread turn asks the compositor to
                    ; reconcile a move, an uncloak, a z-order change and a focus change in one
                    ; frame, which reads as the window jumping into place. One tick of this timer
                    ; gives the move a frame to itself, out of a 500 ms budget.
                    if !_fsRevealSettled.Has(h) {
                        _fsRevealSettled[h] := true
                        continue
                    }

                    ; ---- Bring to FOREGROUND, above Hearthstone ----
                    ; Single-monitor users need the unlocked window ON TOP of
                    ; HS. HWND_TOPMOST (-1) beats a borderless fullscreen game;
                    ; the activate gives it input focus so it is usable. Skipped
                    ; if a re-lock landed (the guard's contract).
                    ; ONCE per window per reveal. Without this cap the block
                    ; fired on every 30ms tick for the whole reveal window --
                    ; hundreds of z-order changes and activations per F3 press,
                    ; which is what killed Main after ~12 rapid presses.
                    if (CFG.fsRevealForeground && !State.fsMainLocked
                     && !_fsRevealFg.Has(h)) {
                        _fsRevealFg[h] := true
                        try {
                            DllCall("user32\SetWindowPos", "Ptr", h, "Ptr", -1
                                , "Int", 0, "Int", 0, "Int", 0, "Int", 0
                                , "UInt", 0x0001 | 0x0002 | 0x0010)  ; NOSIZE|NOMOVE|NOACTIVATE
                            WinActivate("ahk_id " . h)
                        }
                    }

                    ; ---- Gentle repaint nudge + focus-free raise ----
                    ; SKIPPED ENTIRELY FOR A WINDOW THAT IS KNOWN TO PAINT.
                    ; _FSForceRender resizes the window by a pixel and back,
                    ; twice, and _ForegroundFSIfSafe activates it -- so this
                    ; block costs a proven-good window EIGHT SetWindowPos calls
                    ; and four activations PER F3 PRESS. That is the exact
                    ; "hundreds of z-order changes and activations per press"
                    ; this script's own comments blame for killing Main after a
                    ; dozen rapid presses, and it is the single biggest reason
                    ; Main does not survive a stress test.
                    ;
                    ; The nudge exists to kick a renderer that came back idle.
                    ; A warm window did not come back idle. It needs nothing.
                    n := _fsRevealNudged.Get(h, 0)
                    if (n < 4 && !State.fsMainLocked && !_FSIsWarm(h)) {
                        _fsRevealNudged[h] := n + 1
                        ; Geometry-change kick, repeated over the first few
                        ; ticks: CEF may need a moment after the show before it
                        ; will act on a resize. Cheap, and invisible (one pixel,
                        ; put straight back).
                        _FSForceRender(h)
                        try DllCall("user32\SetWindowPos", "Ptr", h, "Ptr", 0
                            , "Int", 0, "Int", 0, "Int", 0, "Int", 0
                            , "UInt", 0x0001 | 0x0002 | 0x0010)
                        _ForegroundFSIfSafe(h)
                    }

                    ; Any suppression title stamps (BG works like Main):
                    ; the reveal may not cut itself short before showing BG.
                    if (!_fsRevealedMainAt
                     && (IsFirestoneMainTitle(title) || IsFirestoneBattlegroundsTitle(title)))
                        _fsRevealedMainAt := A_TickCount
                } catch {
                }
            }
        }

        DetectHiddenWindows prev
        SetTitleMatchMode prevMode

        if (A_TickCount >= _fsRevealUntil) {
            StopFSReveal()
            return
        }
        if (_fsRevealedMainAt && (A_TickCount - _fsRevealedMainAt) > 500)
            StopFSReveal()
    } catch {
        StopFSReveal()
    }
}

; ==============================================================================
; SECTION 11e: MONITOR LOCK — keep session windows on the launch monitor
; ------------------------------------------------------------------------------
; Locks the auxiliary session windows to the monitor the script was launched on
; (ChosenMonIdx): the Battle.net client, the Blizzard Update Agent, and
; Hearthstone itself. It is deliberately gentle and respects the 400ms settle
; margin for new windows.
; ==============================================================================

global _monLockActive := false

StartMonitorLock() {
    global _monLockActive, CFG
    if !CFG.lockWindowsToChosenMonitor
        return
    _monLockActive := true
    SetTimer(MonitorLockTick, CFG.monitorLockPollMs)
    MonitorLockTick()
}

StopMonitorLock() {
    global _monLockActive
    _monLockActive := false
    SetTimer(MonitorLockTick, 0)
}

MonitorLockTick() {
    global _monLockActive, CFG, _hsGuardActive, _bnetLauncherStaged, _bnetPostMinDone
    if !_monLockActive {
        SetTimer(MonitorLockTick, 0)
        return
    }
    ; Clean ownership: the monitor lock moves Battle.net + Agent ONLY.
    ; Hearthstone is owned exclusively by the HS placement guard
    ; (HSPlacementGuardTick), which corrects the monitor only when the game
    ; landed on the wrong one. Two systems, two disjoint window sets -- they can no longer
    ; fight over HS (the visible primary-monitor bounce). Firestone windows
    ; are not a lock concern at all; they are hidden, not placed.
    ; The launch sequence owns the launcher from reveal to minimize-complete.
    ; While it does, the lock must NOT move Battle.net -- competing placement
    ; is what ruined launch smoothness and caused the wrong-monitor minimize.
    ; _bnetLauncherStaged && !_bnetPostMinDone == "sequence in control".
    if !(_bnetLauncherStaged && !_bnetPostMinDone)
        _LockProcWindowsToChosenMonitor("Battle.net.exe", , 400)
    _LockProcWindowsToChosenMonitor("Agent.exe", , 400)
}

; ── HS native display preference ─────────────────────────────────────────────
; Writes Hearthstone's own Unity display selection so Unity itself targets the
; chosen monitor. Value is 0‑based (AHK monitor indices are 1‑based).
SetHSMonitorPref() {
    global CFG, ChosenMonIdx
    if (!CFG.setHSMonitorPref || !CFG.lockWindowsToChosenMonitor || !ChosenMonIdx)
        return
    try {
        v := _UnityMonitorIndexForChosen()
        if (v < 0)
            v := ChosenMonIdx - 1
        if (v < 0)
            v := 0
        RegWrite(v, "REG_DWORD"
            , "HKCU\Software\Blizzard Entertainment\Hearthstone"
            , "UnitySelectMonitor_h17969598")
        if CFG.f1DebugLog
            try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss")
                . " HS-MONITOR-PREF UnitySelectMonitor=" . v
                . " (chosen mon " . ChosenMonIdx . ")`n", A_Temp . "\hs_bg_f1.log")
    }
}

; Unity's 0‑based display index for the chosen monitor, or -1 if it can't be
; resolved.
_UnityMonitorIndexForChosen() {
    global ChosenMonPt
    p := StrSplit(ChosenMonPt, ",")
    if (p.Length != 2)
        return -1
    px := p[1] + 0, py := p[2] + 0
    dd := Buffer(840, 0)
    active := 0
    i := 0
    Loop 16 {
        NumPut("UInt", 840, dd, 0)
        if !DllCall("user32\EnumDisplayDevicesW", "Ptr", 0, "UInt", i, "Ptr", dd, "UInt", 0)
            break
        i++
        state := NumGet(dd, 324, "UInt")
        if !(state & 0x1)                              ; ATTACHED_TO_DESKTOP
            continue
        if (state & 0x8)                               ; MIRRORING_DRIVER
            continue
        devName := StrGet(dd.Ptr + 4, 32, "UTF-16")
        devm := Buffer(220, 0)
        NumPut("UShort", 220, devm, 68)                ; dmSize
        ok := DllCall("user32\EnumDisplaySettingsExW", "Str", devName
            , "Int", -1, "Ptr", devm, "UInt", 0)
        if ok {
            dx := NumGet(devm, 76, "Int")
            dy := NumGet(devm, 80, "Int")
            dw := NumGet(devm, 172, "UInt")
            dh := NumGet(devm, 176, "UInt")
            if (dw > 0 && dh > 0
             && px >= dx && px < dx + dw
             && py >= dy && py < dy + dh)
                return active
        }
        active++
    }
    return -1
}

; ── Corrective‑move budget ────────────────────────────────────────────────────
; Prevents endless monitor ping‑pong by limiting corrections to 4 per window
; per rolling 120s.
global _moveBudget := Map()

_MoveBudgetAllows(h) {
    global _moveBudget
    e := _moveBudget.Get(h, 0)
    if (e && A_TickCount - e.firstAt > 120000) {
        _moveBudget.Delete(h)
        e := 0
    }
    return (!e || e.count < 4)
}

_MoveBudgetNote(h) {
    global _moveBudget, CFG
    e := _moveBudget.Get(h, 0)
    if (!e || A_TickCount - e.firstAt > 120000)
        e := {count: 0, firstAt: A_TickCount}
    e.count++
    _moveBudget[h] := e
    if (CFG.f1DebugLog && e.count = 4) {
        exe := ""
        try exe := WinGetProcessName("ahk_id " . h)
        try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss")
            . " MOVE-BUDGET exhausted " . exe . " hwnd=" . h
            . " — app keeps snapping it back; leaving it`n", A_Temp . "\hs_bg_f1.log")
    }
}

_MoveBudgetReset(h) {
    global _moveBudget
    if _moveBudget.Has(h)
        _moveBudget.Delete(h)
}

; ── Core monitor‑lock function ──────────────────────────────────────────────
global _placeCreateSeen := Map()   ; hwnd -> EVENT_OBJECT_CREATE TickCount
global _placeFirstSeen  := Map()   ; hwnd -> first VISIBLE sighting TickCount

_PrunePlacementMaps() {
    global _placeCreateSeen, _placeFirstSeen, _bnetFirstMoved, _fsAlphaApplied
    global _fsDeferredPopupCloak, _moveBudget, _fsHiddenByUs, _fsShieldDown, _fsEverPainted, _cloakState, _bnetHideDone
    ; Added: these were reachable-but-unpruned ledgers. _fsBirthHidden is the
    ; important one -- its ONLY other cleanup was the timeout sweep in
    ; SuppressFirestoneMainTick, which was dead (corrupted DllCall), so it grew
    ; without bound for the whole session and kept dead HWNDs alive as keys.
    ; HWNDs are recycled by Windows, so a stale key can also make the hook
    ; mis-handle a brand-new, unrelated window.
    global _fsBirthHidden, _fsMinLastAttempt, _fsRevealFg, _bnetPostMinCount, _qtHelperLogged
    global _fsFirstTitledAt
    ; Cold-window subsystem ledgers. _fsParked is the important one: HWNDs are
    ; recycled by Windows, and a stale _fsParked key would make _FSUnparkWindow
    ; refuse to un-park a brand-new window that genuinely is parked.
    global _fsPaintState, _fsPaintProbeAt, _fsPaintHits, _fsColdSince
    global _fsParked, _fsParkedRect, _fsTabRemoved, _fsBirthReassert, _fsMainLogged
    global _fsParkCycles, _fsMainCandidate, _fsProbeGaveUp, _fsRevealDone
    global _fsRevealSettled
    ; The popup ledgers. Windows recycles HWNDs, so a stale entry here either
    ; skips a genuinely new popup (seen as already-killed) or instantly ages a
    ; brand-new window past the grace and closes a Main that is still forming.
    global _fsPopupKilled, _fsPopupFirstSeen
    for m in [_placeCreateSeen, _placeFirstSeen, _bnetFirstMoved, _fsAlphaApplied
            , _fsDeferredPopupCloak, _moveBudget, _fsHiddenByUs, _fsShieldDown, _fsEverPainted, _cloakState, _bnetHideDone
            , _fsBirthHidden, _fsMinLastAttempt, _fsRevealFg, _bnetPostMinCount, _qtHelperLogged
            , _fsFirstTitledAt
            , _fsPaintState, _fsPaintProbeAt, _fsPaintHits, _fsColdSince
            , _fsParked, _fsParkedRect, _fsTabRemoved, _fsBirthReassert, _fsMainLogged
            , _fsParkCycles, _fsMainCandidate, _fsProbeGaveUp, _fsRevealDone
            , _fsRevealSettled
            , _fsPopupKilled, _fsPopupFirstSeen] {
        dead := []
        for h in m {
            if !DllCall("user32\IsWindow", "Ptr", h)
                dead.Push(h)
        }
        for h in dead
            m.Delete(h)
    }
}

_LockProcWindowsToChosenMonitor(exe, exactTitle := "", minAgeMs := 0) {
    global ChosenMonIdx, _placeCreateSeen, _placeFirstSeen, _bnetPostMinUntil
    static lastPrune := 0

    if (exe = "Battle.net.exe" && _bnetPostMinUntil > A_TickCount)
        return
    idx := ChosenMonIdx ? ChosenMonIdx : MonitorGetPrimary()

    if (A_TickCount - lastPrune > 5000) {
        lastPrune := A_TickCount
        try _PrunePlacementMaps()
    }

    waL := 0, waT := 0, waR := 0, waB := 0
    try {
        _SafeWorkArea(idx, &waL, &waT, &waR, &waB)
    } catch {
        return
    }
    monW := waR - waL
    monH := waB - waT
    if (monW <= 0 || monH <= 0)
        return

    prev     := A_DetectHiddenWindows
    prevMode := A_TitleMatchMode
    DetectHiddenWindows false
    SetTitleMatchMode(2)

    try {
        for hwnd in WinGetList("ahk_exe " . exe) {
            try {
                if IsIMEWindow(hwnd)
                    continue
                if IsHelperWindow(hwnd)
                    continue
                if (exactTitle != "" && WinGetTitle("ahk_id " . hwnd) != exactTitle)
                    continue
                if !DllCall("user32\IsWindowVisible", "Ptr", hwnd)
                    continue
                if (WinGetMinMax("ahk_id " . hwnd) = -1)
                    continue

                if (minAgeMs > 0) {
                    anchor := 0
                    if _placeCreateSeen.Has(hwnd)
                        anchor := _placeCreateSeen[hwnd]
                    else if _placeFirstSeen.Has(hwnd)
                        anchor := _placeFirstSeen[hwnd]
                    else {
                        _placeFirstSeen[hwnd] := A_TickCount
                        continue
                    }
                    if (A_TickCount - anchor < minAgeMs)
                        continue
                }

                WinGetPos(&x, &y, &w, &h, "ahk_id " . hwnd)
                if (w < 200 || h < 150)
                    continue

                if (GetMonitorIndexForPoint(x + w // 2, y + h // 2) = idx) {
                    _MoveBudgetReset(hwnd)
                    continue
                }
                if !_MoveBudgetAllows(hwnd)
                    continue

                newX := (w <= monW) ? waL + (monW - w) // 2 : waL
                newY := (h <= monH) ? waT + (monH - h) // 2 : waT
                _MoveBudgetNote(hwnd)
                WinMove(newX, newY, , , "ahk_id " . hwnd)
            } catch {
            }
        }
    }

    DetectHiddenWindows prev
    SetTitleMatchMode prevMode
}

; One‑shot placement pass scheduled by the window event hook.
_HookedPlacementPass() {
    global CFG
    if !CFG.lockWindowsToChosenMonitor
        return
    _LockProcWindowsToChosenMonitor("Battle.net.exe", , 400)
    _LockProcWindowsToChosenMonitor("Agent.exe", , 400)
}

; ══════════════════════════════════════════════════════════════════════════════
; Battle.net FIRST‑FRAME placement (isolated subsystem)
; ══════════════════════════════════════════════════════════════════════════════
; Moves Battle.net/Agent windows once, immediately at first visibility, to the
; chosen monitor. This catches the loader/splash that would otherwise sit on
; the primary monitor for 400ms+.
global _bnetFirstMoved := Map()
global _bnetFirstShowUntil := 0

_BNetFirstShowPlace(hwnd) {
    global CFG, ChosenMonIdx, _bnetFirstMoved, _bnetCloakActive
    if (!CFG.preShowPlaceBNet || !CFG.lockWindowsToChosenMonitor || !ChosenMonIdx)
        return
    if _bnetFirstMoved.Has(hwnd)
        return
    ; ONLY place the real launcher. During the services blanket, every other
    ; Battle.net window is a SERVICE surface (splash / maintenance / Agent)
    ; that gets SW_HIDDEN -- moving it (even cloak-wrapped) was the residual
    ; primary flicker. Placing is exclusively for the window the user WILL
    ; see; services are hidden, never moved.
    if (_bnetCloakActive && !_IsProtectedBNetMain(hwnd))
        return
    try {
        if (DllCall("user32\GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr") != hwnd)
            return
        if !DllCall("user32\IsWindowVisible", "Ptr", hwnd)
            return
        if IsIMEWindow(hwnd)
            return
        if IsHelperWindow(hwnd)
            return
        exStyle := 0
        try exStyle := WinGetExStyle("ahk_id " . hwnd)
        if (exStyle & 0x80)                       ; WS_EX_TOOLWINDOW
            return

        rc := Buffer(16, 0)
        if !DllCall("user32\GetWindowRect", "Ptr", hwnd, "Ptr", rc)
            return
        bx := NumGet(rc, 0, "Int"), by := NumGet(rc, 4, "Int")
        bw := NumGet(rc,  8, "Int") - bx
        bh := NumGet(rc, 12, "Int") - by
        if (bw < 100 || bh < 60)
            return

        if (GetMonitorIndexForPoint(bx + bw // 2, by + bh // 2) = ChosenMonIdx) {
            _bnetFirstMoved[hwnd] := true
            return
        }

        _SafeWorkArea(ChosenMonIdx, &waL, &waT, &waR, &waB)
        waW := waR - waL
        waH := waB - waT
        if (waW <= 0 || waH <= 0)
            return
        nx := (bw <= waW) ? waL + (waW - bw) // 2 : waL
        ny := (bh <= waH) ? waT + (waH - bh) // 2 : waT
        ; INVISIBLE reposition: cloak, move, uncloak. A bare move here made a
        ; wrong-monitor Battle.net window (often a transient service surface)
        ; flash on primary then jump -- the second primary flicker. Cloaking
        ; for the move composites neither the wrong-monitor frame nor the jump.
        ; Track whether WE already had it cloaked (arbitrated _cloakState),
        ; so we only uncloak if we cloaked it here -- never fight a cloak
        ; another system is intentionally holding.
        global _cloakState
        wasCloaked := _cloakState.Has(hwnd)
        if !wasCloaked
            CloakWindow(hwnd)
        DllCall("user32\SetWindowPos", "Ptr", hwnd, "Ptr", 0
            , "Int", nx, "Int", ny, "Int", 0, "Int", 0
            , "UInt", 0x0001 | 0x0004 | 0x0010)
        if !wasCloaked {
            Sleep(15)
            UncloakWindow(hwnd)
        }
        _bnetFirstMoved[hwnd] := true
    } catch {
    }
}

StartBNetFirstShowAssist(durationMs := 90000) {
    global _bnetFirstShowUntil, _bnetFirstMoved, CFG
    if (!CFG.preShowPlaceBNet || !CFG.lockWindowsToChosenMonitor)
        return
    _bnetFirstShowUntil := A_TickCount + durationMs
    fresh := Map()
    for h in _bnetFirstMoved {
        if DllCall("user32\IsWindow", "Ptr", h)
            fresh[h] := true
    }
    _bnetFirstMoved := fresh
    SetTimer(_BNetFirstShowTick, 15)
    _BNetFirstShowTick()
}

StopBNetFirstShowAssist() {
    global _bnetFirstShowUntil
    _bnetFirstShowUntil := 0
    SetTimer(_BNetFirstShowTick, 0)
}

_BNetFirstShowTick() {
    global _bnetFirstShowUntil
    if (A_TickCount >= _bnetFirstShowUntil) {
        StopBNetFirstShowAssist()
        return
    }
    try {
        for exe in ["Battle.net.exe", "Agent.exe"] {
            for hwnd in WinGetList("ahk_exe " . exe)
                _BNetFirstShowPlace(hwnd)
        }
    }
}

; ── Launch‑phase placement assist ─────────────────────────────────────────────
; During F2, Battle.net (and sometimes the Blizzard Agent) create/re‑show their
; windows on whatever monitor Windows picks. This assist (250ms) and
; MonitorLockTick (1s) are polling backstops.
global _launchPlaceActive := false

StartLaunchPlaceAssist() {
    global _launchPlaceActive
    _launchPlaceActive := true
    SetTimer(_LaunchPlaceTick, 250)
    _LaunchPlaceTick()
}

StopLaunchPlaceAssist() {
    global _launchPlaceActive
    _launchPlaceActive := false
    SetTimer(_LaunchPlaceTick, 0)
}

_LaunchPlaceTick() {
    global _launchPlaceActive, CFG
    if !_launchPlaceActive {
        SetTimer(_LaunchPlaceTick, 0)
        return
    }
    if !CFG.lockWindowsToChosenMonitor
        return
    _LockProcWindowsToChosenMonitor("Battle.net.exe", , 400)
    _LockProcWindowsToChosenMonitor("Agent.exe", , 400)
}

; ==============================================================================
; SECTION 12: TIMER HELPERS
; ==============================================================================
; Tiny shared utilities for starting/stopping groups of timers cleanly.
;

CancelLaunchTimers() {
    global _lateHSUntil, _bnetLaunchFiredAt
    StopLaunchPlaceAssist()
    StopBNetFirstShowAssist()
    SetTimer(LaunchHudWatchdog,       0)
    SetTimer(LaunchStateMachine_Tick, 0)
    SetTimer(PostLoginLaunch,         0)
    SetTimer(LateHSWatch,             0)
    ; BNetMinimizeSequenceTick is deliberately NOT stopped here.
    ;
    ; CancelLaunchTimers has six call sites -- the ceiling abort, the LOGIN_WAIT
    ; abort, F2's stale-pipeline recovery, F4, and the two success paths. A timer
    ; stopped by all of them and restarted by only one is a timer that eventually
    ; stays stopped, and since this sequence is the only thing that minimises the
    ; launcher, that would mean the launcher never minimises at all.
    ;
    ; The sequence is self-governing instead: armed once, at the reveal, and it
    ; stops itself the moment it has minimised or reached its ceiling. Nothing else
    ; needs to know it exists.
    SetTimer(_BNetDwellMinimize,      0)   ; a pending dwell-minimize must
    SetTimer(MinimizeBNetAfterDwell,  0)   ; not fire into a post-abort reveal
    SetTimer(_BNetSequenceMinimizeNow, 0)  ; nor may the scheduled one -- it is
                                           ; armed as a one-shot when Play fires
                                           ; and would otherwise outlive the
                                           ; launch that armed it
    StopBNetPostLaunchMinimize()           ; -- nor may the post-Play linger
    ; A pending Firestone launch must never outlive the pipeline that
    ; scheduled it. Without this, F4 within the deferral window tears the
    ; session down and then the timer fires and starts Overwolf again.
    SetTimer(_FSDelayedLaunch, 0)
    StopBNetStallWatch()
    _lateHSUntil := 0
    _bnetLaunchFiredAt := 0
    StopLauncherHide()
}

; ==============================================================================
; SECTION 14: LAUNCH PIPELINE — F2 state machine
; ==============================================================================
; States:  IDLE → HAMMERING → LOGIN_WAIT → DONE
;
;   (OW_WAIT is gone. It existed to hold the pipeline while Overwolf started,
;    back when Firestone was launched first and Hearthstone waited on it. That
;    ordering is reversed -- Firestone now starts alongside everything else on
;    F2 and nothing waits for it -- so the state was unreachable.)
;                stability before transitioning to HAMMERING.
;   HAMMERING  — Repeatedly steps TryLaunchWTCG until HS's window appears.
;                The gate walks Battle.net through client-start -> reveal ->
;                render dwell before the real launch fires; the moment HS's
;                PROCESS exists the launcher is minimized. Detects the BNet
;                login screen and transitions to LOGIN_WAIT.
;   LOGIN_WAIT — Waits for user to authenticate in Battle.net before resuming.
;   DONE       — HS window detected; cleanup, focus, lock Firestone, arm F1.
; ==============================================================================


; ── HAMMERING entry ───────────────────────────────────────────────────────────
StartHSLaunch() {
    global Cache, State, Launch, CFG, _smLastTick
    _smLastTick := A_TickCount        ; baseline the liveness stamp: see the
                                      ; stale-pipeline guard in Hotkey_F2
    SetHSMonitorPref()
    StartLaunchPlaceAssist()
    StartBNetFirstShowAssist()
    Cache.hsPath             := ""
    Launch.state             := "HAMMERING"
    Launch.retries           := 0
    Launch.lastAttempt       := 0        ; gate stepped every tick until the
                                         ; first real launch fires
    Launch.sessionStart      := A_TickCount
    Launch.loginFallbackDone := false
    Launch.loginTitleCount   := 0
    Launch.loginEnteredAt    := 0
    TryLaunchWTCG()
    SetTimer(LaunchStateMachine_Tick, CFG.hammerFastMs)
    SetTimer(LaunchHudWatchdog,       CFG.launchHudWatchMs)
}

; ── Watchdog ──────────────────────────────────────────────────────────────────
LaunchHudWatchdog() {
    global Launch
    if (Launch.state != "HAMMERING" && Launch.state != "LOGIN_WAIT")
        return
    if (!GetHSPID())
        return
    if HSWindowExists()
        CompleteHSLaunchSuccess()
}

; ── State machine tick ────────────────────────────────────────────────────────
LaunchStateMachine_Tick() {
    global Launch, Cache, State, CFG, _lateHSUntil, _bnetRevealedAt, _bnetPostMinDone, _bnetLoginAllowed, _bnetLaunchFiredAt, _smLastTick
    _smLastTick := A_TickCount

    ; Hard ceiling (CFG.launchCeilingMs, default 5 min).
    if (Launch.state != "LOGIN_WAIT"
     && A_TickCount - Launch.sessionStart > CFG.launchCeilingMs) {
        Launch.state   := "IDLE"
        State.f2Active := false
        CancelLaunchTimers()
        StopHSCloaker()
        BgHUD.Hide()
        try {
            prev := A_DetectHiddenWindows
            DetectHiddenWindows true
            for hwnd in WinGetList("ahk_exe Hearthstone.exe") {
                try UncloakWindow(hwnd)
            }
            DetectHiddenWindows prev
        }
        RevealBNetWindows()            ; foreground the launcher if never done
        RestoreHiddenBNetServices()    ; and un-hide any service surface --
                                       ; the stall may BE a maintenance screen
        ; COLD‑LAUNCH RECOVERY: watcher for late HS appearance.
        _lateHSUntil := A_TickCount + 600000
        SetTimer(LateHSWatch, 5000)
        BgHUD.Show("Launch slow — watching for HS in background", 2500)
        return
    }

    ; ── LOGIN_WAIT ────────────────────────────────────────────────────────────
    if (Launch.state = "LOGIN_WAIT") {
        if HSWindowExists() {
            CompleteHSLaunchSuccess()
            return
        }
        if !ProcessExist("Battle.net.exe") {
            Launch.state   := "IDLE"
            State.f2Active := false
            CancelLaunchTimers()
            StopHSCloaker()
            BgHUD.Hide()
            try {
                prev := A_DetectHiddenWindows
                DetectHiddenWindows true
                for hwnd in WinGetList("ahk_exe Hearthstone.exe") {
                    try UncloakWindow(hwnd)
                }
                DetectHiddenWindows prev
            }
            RevealBNetWindows()
            RestoreHiddenBNetServices()   ; Agent may outlive Battle.net
            return
        }
        if !BNetLoginOrAuthScreen() {
            if Launch.loginEnteredAt {
                Launch.sessionStart  += A_TickCount - Launch.loginEnteredAt
                Launch.loginEnteredAt := 0
            }
            _bnetLoginAllowed      := false   ; login done: the blanket owns
                                              ; Battle.net.exe again
            Launch.state           := "HAMMERING"
            Launch.retries         := 0
            Launch.lastAttempt     := 0
            Launch.loginTitleCount := 0
            SetTimer(LaunchStateMachine_Tick, 0)
            SetTimer(PostLoginLaunch, -1500)
        }
        return
    }

    ; ── HAMMERING ─────────────────────────────────────────────────────────────
    if (Launch.state = "HAMMERING") {
        ; Keep the tick FAST through the entire BNet pre-nav/reveal/dwell
        ; sequence. These stages fire on wall-clock deltas, so a slowed tick
        ; would only ADD latency between them -- the main source of the
        ; "sometimes fast, sometimes slow" launch. Fast cadence until HS's
        ; window actually exists makes the pacing consistent.
        if (_bnetRevealedAt != 0 && !HSWindowExists())
            SetTimer(LaunchStateMachine_Tick, CFG.hammerFastMs)
        if HSWindowExists() {
            CompleteHSLaunchSuccess()
            return
        }

        ; Hearthstone's PROCESS exists — Battle.net launched it. Minimize the
        ; launcher (once), but ONLY after it has been visible long enough to
        ; render: the reveal dwell plus the post-play linger, measured from
        ; the reveal. Without this wait, HS's process (which appears at
        ; Stage 4) could trigger this minimize DURING Stage 5's linger,
        ; before the launcher painted the game page -- the "pops up then
        ; minimizes faster than it can render". Stage 5 and this share the
        ; timing and the _bnetPostMinDone flag, so exactly one minimize fires.
        ; (The HS-PID minimize backstop that lived here is gone.) It was
        ; trigger 2 of 5, and it duplicated -- with a slightly different
        ; anchor, hence a slightly different answer -- exactly what
        ; BNetMinimizeSequenceTick now does properly: wait for Hearthstone's
        ; process, then linger, then minimize. Two things computing the same
        ; deadline from different starting points is how the sequence became
        ; unpredictable in the first place.

        Launch.retries++

        loginDetected := false
        if (!Launch.skipLoginDetect && ProcessExist("Battle.net.exe")
         && Launch.retries >= CFG.loginDetectMinRetries) {
            if BNetLoginOrAuthScreen() {
                Launch.loginTitleCount++
                if (Launch.loginTitleCount >= 3) {
                    Launch.loginTitleCount := 0
                    ; A human has to see (and type into) the login screen:
                    ; stand the Battle.net blanket down and un-hide it.
                    _bnetLoginAllowed := true
                    UnhideBNetLoginWindows()
                    RevealBNetWindows()
                    Launch.state           := "LOGIN_WAIT"
                    Launch.loginEnteredAt  := A_TickCount
                    SetTimer(LaunchStateMachine_Tick, CFG.hammerSlowMs)
                    return
                }
                loginDetected := true
            } else {
                Launch.loginTitleCount := 0
            }
        }

        ; Same rule as OW_WAIT: once Hearthstone's process exists the launcher has done
        ; its job, and re-firing the launch command only re-surfaces it while the
        ; game's window is still forming.
        if (!loginDetected && !GetHSPID()) {
            elapsed := A_TickCount - Launch.sessionStart
            if (elapsed < 10000)
                refire := 700
            else if (ProcessExist("Battle.net.exe"))
                refire := 5000
            else
                refire := 2500

            if (Launch.lastAttempt = 0 || (A_TickCount - Launch.lastAttempt) > refire) {
                if TryLaunchWTCG()
                    Launch.lastAttempt := A_TickCount
            }
        }

        if (!GetHSPID() && !Launch.skipLoginDetect && !Launch.loginFallbackDone
         && Launch.retries >= CFG.loginFallbackMinRetries
         && (A_TickCount - Launch.sessionStart) > CFG.loginFallbackAfterMs) {
            Launch.loginFallbackDone := true
            if BNetLoginOrAuthScreen() {
                _bnetLoginAllowed := true     ; login fallback: humans must see it
                UnhideBNetLoginWindows()
                RevealBNetWindows()
                Launch.state          := "LOGIN_WAIT"
                Launch.loginEnteredAt := A_TickCount
                SetTimer(LaunchStateMachine_Tick, CFG.hammerSlowMs)
            } else {
                TryLaunchWTCG()
            }
            return
        }

        if (Launch.retries = 50)
            SetTimer(LaunchStateMachine_Tick, 500)
        else if (Launch.retries = 100)
            SetTimer(LaunchStateMachine_Tick, 1000)
        return
    }
}

; ── Post‑login deferred launch ────────────────────────────────────────────────
PostLoginLaunch() {
    global Launch, CFG
    Launch.lastAttempt := TryLaunchWTCG() ? A_TickCount : 0
    SetTimer(LaunchStateMachine_Tick, CFG.hammerFastMs)
}

; ── Launch complete ───────────────────────────────────────────────────────────
; Called as soon as the HS window is confirmed present.
CompleteHSLaunchSuccess() {
    global State, Launch
    if (Launch.state = "DONE" || Launch.state = "IDLE")
        return
    Launch.state   := "DONE"
    State.f2Active := false

    CancelLaunchTimers()

    HideHSOnLaunch(10000)

    BgHUD.Hide()

    ; Hearthstone's window is confirmed. The reveal below is an idempotent janitor:
    ; it guarantees the launcher has been placed on every path that reaches
    ; "Hearthstone is up", including the late-recovery and watchdog completions.
    ;
    ; It deliberately does not minimise. That decision belongs to
    ; BNetMinimizeSequenceTick, which anchors it to the game having launched; a
    ; second caller forcing it here would discard the configured pause.
    RevealBNetWindows()

    StartOverlayTopmostEnforcer()

    ; The launch is over, so the 1 ms suppression burst has no more newborn
    ; windows to beat. Let it decay to the coast rate shortly after HS settles
    ; instead of riding the full fsBurstMaxMs window.
    SetTimer(_FSBurstDecay, -5000)

    ; Post-F2 transparency repair. The symptom is reported after F2 on both the
    ; cold and restart paths, so the launch tail is exactly where it needs to
    ; be caught -- not only at startup and at F3. Cheap, and a no-op when
    ; nothing is stranded.
    SetTimer(FSRepairStuckAlpha, -1500)
    SetTimer(FSRepairStrandedWindows, -1500)

    ; NOTE: The persistent early Overwolf cloak remains active until its own
    ; conditions are met (see StartEarlyOverwolfCloak).
}

; ══════════════════════════════════════════════════════════════════════════════
; DEFERRED FIRESTONE LAUNCH (CFG.fsLaunchAfterHS)
; ══════════════════════════════════════════════════════════════════════════════
; The structural half of the Firestone-Main fix.
;
; The old order launched Firestone FIRST, at the very top of F2, so
; Firestone - Main was born into the single noisiest moment this script has:
; the 3 ms early-cloak blanket, the 10 ms loading suppressors, the 10 ms
; launcher-splash hider, the 1 ms suppression burst, the Battle.net services
; blanket at 10 ms and a five-event window hook, all live at once, all
; mutating window state, while Chromium tried to stand up a compositor for the
; first time. Even with every individual hide made paint-safe, that is a lot of
; contention to survive by design rather than by luck.
;
; This defers the Firestone launch until Hearthstone's PROCESS exists. By then
; the launch storm is over: the Battle.net sequence has fired, the launcher has
; been minimized, and the burst is decaying. Main is born into a quiet system.
;
; Overwolf detects an already-running game (it polls, it does not only watch
; for launches) and EnsureFirestoneSettings already enables
; launchFirestoneWhenGameStarts, so the overlay still attaches. Hearthstone
; needs 30-60 seconds from process start to a playable menu, so Firestone is up
; long before a Battlegrounds match can begin.




; The Firestone launch itself. Reached from _FSDelayedLaunch, CFG.fsLaunchDelayMs
; after the F2 press -- see there for why it is deferred rather than immediate.
; It arms all suppressors and launches Overwolf/Firestone.
; Returns true if a launch was actually issued.
; Schedule (or immediately perform) the Firestone launch.
;
; THE ZERO CASE IS NOT A TIMER. In AutoHotkey, SetTimer(fn, 0) DISABLES a timer
; -- and a negative period of zero is still zero, so SetTimer(fn, -0) does not
; "fire immediately", it switches the timer off. With fsLaunchDelayMs set to 0
; that would mean Firestone silently never launches at all: no error, no log,
; no overlay. A configuration value meaning "do it now" must not be able to
; turn into "never do it" because of an API edge case.
_FSScheduleLaunch() {
    global CFG
    SetTimer(_FSDelayedLaunch, 0)          ; cancel anything already pending
    if (CFG.fsLaunchDelayMs <= 0) {
        _FSLog("FS-LAUNCH immediate (fsLaunchDelayMs=0)")
        _FSDelayedLaunch()
        return
    }
    SetTimer(_FSDelayedLaunch, -CFG.fsLaunchDelayMs)
    _FSLog("FS-LAUNCH scheduled in " . CFG.fsLaunchDelayMs . "ms")
}


; One-shot timer target for the deferred Firestone launch.
;
; Re-checks FirestoneAppRunning at FIRE time, not at schedule time: five
; seconds is long enough for the user to have started it themselves, or for a
; second F2 to have arrived, and launching a second copy of Overwolf is worse
; than not launching one at all.
_FSDelayedLaunch() {
    if FirestoneAppRunning() {
        _FSLog("FS-LAUNCH deferred fire: Firestone is already running, nothing to do")
        return
    }
    LaunchFirestoneNow()
}

LaunchFirestoneNow() {
    global State, CFG
    if FirestoneAppRunning()
        return false

    ; ---- RESOLVE FIRST, ARM SECOND ----
    ; This used to arm the whole suppressor bundle -- a 1 ms sweep, a 3 ms
    ; cloak, a 10 ms loading watch, a 750 ms popup sweeper -- and only then ask
    ; whether there was anything to launch. On a machine with no Overwolf or no
    ; Firestone that meant every F2 press started a full choreography against
    ; windows that could never exist, at up to a thousand enumerations a second
    ; on a script running at high process priority, for up to two minutes. The
    ; user paid the entire cost of a feature they do not have.
    cmd := _ResolveFirestoneLaunch()
    if (cmd = "") {
        _FSLog("FS-LAUNCH no Overwolf/Firestone install found -- skipping the"
             . " Firestone stage entirely (this is not an error; the rest of"
             . " the session is unaffected)")
        StandDownFirestoneSubsystems()
        return false
    }

    ; Re-arm the suppressors at the moment of launch.
    ;
    ; All of them are armed by F2 and torn down by CancelLaunchTimers when
    ; Hearthstone's window appears. With fsLaunchAfterHS that ordering inverts --
    ; Hearthstone appearing is the trigger for launching Firestone -- so without
    ; this they would be switched off shortly before the windows they exist to
    ; suppress are created. Suppressors belong where the windows are born.
    ; With immediate launch, this is the right place to arm them.
    if State.fsMainLocked {
        StartLauncherHide()
        SetTimer(StopLauncherHide, -60000)   ; bounded: never outlive the launch
        StartEarlyOverwolfCloak()
        StartKillFirestoneLoading()
        StartFSNotifSweeper()
        StartFSBurst()

        ; Let the suppressors tick before the process exists.
        ;
        ; Arming a timer does not run it: the first tick is one interval away, and hook
        ; delivery lags the event by a few milliseconds. Firing the launch in the same
        ; thread turn would allow the first windows to be created before any suppressor
        ; had run once. This delay is far longer than every cadence involved and
        ; imperceptible next to Firestone's own start-up.
        Sleep(CFG.fsLaunchArmSettleMs)
    }

    try Run(cmd)
    ; Run() returning without throwing means a process was STARTED, not that
    ; Firestone works. A crash a second later -- the "critical error, no
    ; overlay" a user reported -- is indistinguishable from success at this
    ; point, and nothing downstream ever asked again, so the suppressors ran
    ; for the rest of the session waiting for windows that were never coming.
    ; This asks, once, well after any healthy start-up would have finished.
    SetTimer(FirestoneHealthCheck, -CFG.fsHealthCheckMs)
    return true
}

; Is there anything to manage? Cheap, cached, and never throws.
;
; The whole Firestone half of this script is optional. Every path that arms a
; Firestone timer asks this first, so a user who has never installed Overwolf
; runs a script that launches Hearthstone and does nothing else -- rather than
; one that polls an empty window list at 50 ms for the rest of the session.
FirestoneInstalled() {
    try return (_ResolveFirestoneLaunch() != "")
    return false
}

; Build the command that starts Firestone, or "" if there is nothing to start.
; Pure lookup: no side effects, safe to call before deciding anything.
_ResolveFirestoneLaunch() {
    fsCmd := GetFirestoneCmd()
    if (fsCmd != "")
        return fsCmd
    owPath := GetOverwolfPath()
    if (owPath = "")
        return ""
    appId := GetFirestoneAppId()
    return (appId != "")
        ? ('"' . owPath . '" -launchapp ' . appId)
        : ('"' . owPath . '"')
}

; Did Firestone actually come up? If not, stop waiting for it.
; RETRIED, NOT ONE-SHOT.
;
; A single check meant "not running yet" and "never coming" were the same
; answer, and standing everything down on the first was the worse mistake: the
; suppressors would be switched off moments before a slow Overwolf finally
; produced its windows, so Firestone - Main would flash on screen -- the exact
; bug this subsystem exists to prevent, reintroduced by its own safety net.
; Three checks put the verdict past three minutes, which is beyond any healthy
; start-up, so "absent" really does mean absent.
FirestoneHealthCheck() {
    global CFG
    static tries := 0
    if FirestoneAppRunning() {
        tries := 0
        _FSLog("FS-HEALTH Firestone is running")
        return
    }
    tries += 1
    if (tries < 3) {
        _FSLog("FS-HEALTH Firestone not up yet (check " . tries . " of 3)"
             . " -- giving it another " . CFG.fsHealthCheckMs . "ms")
        SetTimer(FirestoneHealthCheck, -CFG.fsHealthCheckMs)
        return
    }
    tries := 0
    _FSLog("FS-HEALTH Firestone was launched but never appeared -- it most"
         . " likely failed to start. Standing down the Firestone subsystems;"
         . " Hearthstone and the hotkeys are unaffected")
    try BgHUD.Show("Firestone did not start — continuing without it", 3000)
    StandDownFirestoneSubsystems()
}

; Switch off everything that exists only to manage Firestone windows.
;
; Called when Firestone is not installed, and when it was launched but died.
; Deliberately does NOT touch State.fsMainLocked: F3 stays meaningful, so if
; the user starts Firestone by hand later the lock is still in the state they
; expect. It only stops the timers that would otherwise poll forever -- the
; 50 ms coast sweep, the 100 ms loading guard, the 750 ms popup sweeper -- for
; windows that do not exist.
StandDownFirestoneSubsystems() {
    try StopFSBurst()
    try SetTimer(FSMainMonitor,                 0)
    try StopKillFirestoneLoading()
    try SetTimer(SuppressFirestoneLoadingTick,  0)
    try StopFSNotifSweeper()
    try StopEarlyOverwolfCloak()
    try StopLauncherHide()
    try StopFSReveal()
}

; ── Late‑HS recovery (post‑ceiling cold launches) ─────────────────────────────
; Armed ONLY by the launch‑ceiling timeout. Watches for HS to appear after the
; pipeline gave up, and runs the reduced success path.
global _lateHSUntil := 0

LateHSWatch() {
    global _lateHSUntil
    if (!_lateHSUntil || A_TickCount >= _lateHSUntil) {
        _lateHSUntil := 0
        SetTimer(LateHSWatch, 0)
        return
    }
    if (!GetHSPID() || !HSWindowExists())
        return
    _lateHSUntil := 0
    SetTimer(LateHSWatch, 0)
    CompleteHSLaunchLate()
}

; Reduced success tail for an HS that appeared after the pipeline ceiling.
CompleteHSLaunchLate() {
    StopHSCloaker()
    RevealBNetWindows(true)   ; late path: Hearthstone is already up and has
                              ; been for a while, so "minimize now" is exactly
                              ; right here and there is no linger to respect
    StartOverlayTopmostEnforcer()
    SetHSGpuPreferenceHigh()
    PauseWSearch()
}

; ==============================================================================
; SECTION 15: HOTKEYS
; ==============================================================================
;
; The four handlers users actually touch. Each is a thin conductor: it
; sets state, starts the right subsystems, and gets out of the way.

; ── System-modifier passthrough ──────────────────────────────────────────────
; The four hotkeys are declared with the `*` wildcard so they fire no matter
; which modifiers are held. That is right for Shift (sticky keys, stray shift
; during a match) and catastrophically wrong for the OS combinations:
;
;   Alt+F4  — the universal "close window" chord. With `*F4` the script ATE it
;             everywhere in Windows and ran a FULL SHUTDOWN instead: it killed
;             Hearthstone, Battle.net, Overwolf and then exited. Closing any
;             unrelated window with Alt+F4 nuked the whole session.
;   Ctrl+F4 — "close tab / close document" in browsers, Office, IDEs.
;   Win+F#  — reserved by the shell.
;
; Gating the wildcard hotkeys on this makes the modified chords INACTIVE rather
; than swallowed, so Windows receives them normally. Unmodified F1-F4 are
; unaffected: they still match here, and the SC03B..SC03E aliases below (which
; require no modifiers anyway) are a second path to the same handlers.
;
; ── FAIL-OPEN, AND SELF-HEALING ──────────────────────────────────────────────
; This one function decides whether ANY of the four hotkeys are live. That
; makes it the single most dangerous piece of code in the script: if it ever
; returns false and stays there, all four keys go silently inert -- no handler
; runs, no HUD toast, no log line, nothing to see. A user reported exactly that
; after a launch in which Firestone threw a critical error.
;
; The mechanism is a keyboard-state desync. GetKeyState(key, "P") reads the
; OS's PHYSICAL key state, which goes stale when a low-level keyboard hook
; chain is disrupted -- and Overwolf installs a global keyboard hook to deliver
; its own overlay hotkeys, so an Overwolf/Firestone crash is precisely the
; event that can drop a modifier's key-up. The modifier is then reported held
; forever, and this gate reports "a system chord is in progress" forever.
;
; Three defences, in order of when they act:
;
;   1. BOTH STATES MUST AGREE. A modifier counts as held only when the logical
;      AND physical states say so. A one-sided desync -- the common kind --
;      no longer blocks anything.
;   2. FAIL OPEN. Any exception reading key state returns TRUE (hotkeys live).
;      A gate that cannot read the keyboard must not be the reason the user
;      cannot press F4 to shut down.
;   3. SELF-HEAL. The moment this gate STARTS refusing is stamped below, and
;      HK_ReachabilityWatchdog treats a gate that has been refusing
;      continuously as proof the modifier state is wrong -- which is the only
;      test that catches the user pressing dead F-keys, because their presses
;      keep the system idle timer at zero.
;
; What this does NOT change: a real Alt+F4 / Ctrl+F4 / Win+F4 still passes
; through to Windows untouched, because a genuinely held modifier sets both
; states and is released within milliseconds of the chord ending.
global _hkGateBlockedSince := 0
HK_NoSysMods() {
    global _hkGateBlockedSince
    try {
        clear := !_HKModHeld("Alt")  && !_HKModHeld("Ctrl")
              && !_HKModHeld("LWin") && !_HKModHeld("RWin")
    } catch {
        _hkGateBlockedSince := 0
        return true                  ; unreadable: fail OPEN, never inert
    }
    if clear {
        _hkGateBlockedSince := 0
        return true
    }
    if !_hkGateBlockedSince
        _hkGateBlockedSince := A_TickCount
    return false
}

; A modifier is "held" only when the logical and physical states agree.
_HKModHeld(key) {
    return GetKeyState(key) && GetKeyState(key, "P")
}

; Releases a modifier the OS is reporting as held when nothing is being typed.
;
; The test is deliberately conservative: a modifier must report held AND there
; must have been no physical input at all for CFG.hkStuckModifierMs. Holding a
; modifier generates no input events, but no real chord lasts ten seconds --
; Alt-tabbing sends Tab presses, which reset the idle timer. So this fires only
; on a state that cannot be produced by a human hand.
;
; The repair is to send the key-up the OS never received. If the modifier
; really was held, the only consequence is that it is released, which is also
; what the user would have done next.
HK_ReachabilityWatchdog() {
    global _hkGateBlockedSince, CFG, State, Launch

    ; ---- 1. Reconcile the launch flag with the launch state ----
    ; State.f2Active gates F1 and F2. Launch.state is what the pipeline
    ; actually thinks it is doing. When the flag says "launching" and the state
    ; machine says IDLE or DONE, the flag is a leftover -- and a leftover here
    ; costs the user two of their four keys. Clearing it is always safe: a real
    ; launch keeps Launch.state on one of the working states for its whole life.
    try {
        if (State.f2Active && !_LaunchPipelineAlive()
         && (Launch.state = "IDLE" || Launch.state = "DONE")) {
            State.f2Active := false
            _FSLog("HOTKEY reconciled: f2Active was set with Launch.state="
                 . Launch.state . " -- cleared so F1/F2 are usable")
        }
    }

    ; ---- 2. Release a stuck system modifier ----
    if !CFG.hkStuckModifierRepair
        return
    stuck := ""
    try {
        ; TWO WAYS TO QUALIFY, and the second is the one that matters.
        ;
        ; (a) IDLE. A modifier reports held while nothing at all is being
        ;     typed for hkStuckModifierMs. Conservative: holding a modifier
        ;     generates no input events, but no real chord lasts ten seconds --
        ;     Alt-tabbing sends Tab presses, which reset the idle timer.
        ;
        ; (b) THE GATE HAS BEEN BLOCKING. A_TimeIdlePhysical is reset by every
        ;     keypress -- INCLUDING the F-key presses that are being swallowed.
        ;     So the exact user who most needs this repair, the one pressing F2
        ;     over and over because nothing is happening, keeps the idle timer
        ;     near zero and would never have qualified under (a) alone. That is
        ;     precisely the reported failure. HK_NoSysMods stamps the moment it
        ;     began refusing; if it has been refusing continuously for this
        ;     long, the modifier state is wrong no matter how busy the keyboard
        ;     looks.
        idleStuck  := (A_TimeIdlePhysical >= CFG.hkStuckModifierMs)
        gateStuck  := (_hkGateBlockedSince
                    && (A_TickCount - _hkGateBlockedSince) >= CFG.hkGateBlockedMs)
        if !(idleStuck || gateStuck)
            return
        for key in ["Alt", "Ctrl", "LWin", "RWin"] {
            if _HKModHeld(key)
                stuck .= (stuck = "" ? "" : ",") . key
        }
    } catch {
        return
    }
    if (stuck = "")
        return
    _FSLog("HOTKEY stuck modifier(s) " . stuck . " held with "
         . A_TimeIdlePhysical . "ms of no physical input -- releasing so the"
         . " F-keys come back")
    for key in StrSplit(stuck, ",") {
        try Send("{" . key . " up}")
    }
    _hkGateBlockedSince := 0
    try BgHUD.Show("Hotkeys restored", 1200)
}

; ── F1 — Disconnect / Reconnect ──────────────────────────────────────────────
#MaxThreadsPerHotkey 1
#HotIf HK_NoSysMods()
$*F1::Hotkey_F1()
SC03B::Hotkey_F1()
#HotIf

; Is the launch pipeline genuinely running, or just flagged as running?
;
; The single answer both F1 and F2 use. "Running" means the state machine has
; ticked recently; anything else is a corpse holding a flag. A stamp of 0 means
; it never ticked at all, which is the cold-launch failure and is also dead.
; Kept deliberately small and total -- it must never throw, because both
; hotkeys' availability depends on it returning.
_LaunchPipelineAlive() {
    global _smLastTick
    try {
        if (_smLastTick = 0)
            return false
        return (A_TickCount - _smLastTick) <= 4000
    }
    return false
}

; F1 FAILSAFE: removes the firewall block AND the input shield unconditionally.
; Armed as a one-shot the moment a block is applied, so even if the F1 thread
; dies (exception, script reload, external kill) the game is never left
; permanently disconnected or input-shielded -- the "stuck frozen, had to
; restart" failure. Harmless if the normal path already cleaned up.
_F1FailsafeRelease() {
    try RemoveIPBlock()
    try StopHSInputShield()
    ; The Battle.net guard is deliberately NOT stopped here. It is bounded and
    ; self-expiring, and this failsafe only runs when the F1 thread died -- the
    ; case where a disconnect-driven restore is MOST likely. Cancelling it here
    ; would switch the protection off exactly when it is most needed.
}

Hotkey_F1() {
    global State, CFG
    _HotkeyTone("F1")

    hsPID := GetHSPID()
    if (!hsPID) {
        BgHUD.Show("HS not running", 900)
        return
    }

    if (State.lastF1End && (A_TickCount - State.lastF1End) < CFG.cooldownTime) {
        return
    }

    ; F1 stands aside during a launch -- but only for a launch that is actually
    ; running. State.f2Active is a plain flag; if the pipeline dies without
    ; clearing it, this early return disables F1 for the rest of the session
    ; with nothing but a toast to say why. The same staleness test Hotkey_F2
    ; uses decides it here, so the two agree on what "in progress" means and
    ; neither can be wedged by a flag nobody cleared.
    if State.f2Active {
        if _LaunchPipelineAlive() {
            BgHUD.Show("F1 ignored — launch in progress", 1200)
            return
        }
        _FSLog("F1 proceeding: f2Active was set but the launch pipeline is"
             . " stale -- clearing the flag")
        State.f2Active := false
    }

    BgHUD.Show("Skip…")

    ; ── Adapter mode: no socket bookkeeping, just drop the NIC briefly ───────
    if (CFG.f1Method = "adapter") {
        try {
            StartHSInputShield("F1", CFG.f1AdapterHoldMs + 2500)
            BgHUD.Show("Skip (adapter reset)…")
            _F1AdapterReset(CFG.f1AdapterHoldMs)
            Sleep(CFG.f1AdapterHoldMs + 400)
            BgHUD.Show("Reconnecting…", 1000)
        } catch {
            BgHUD.Show("F1 adapter reset failed", 1500)
        } finally {
            Sleep(300)
            try StopHSInputShield()
            State.lastF1End := A_TickCount
        }
        return
    }

    ; ── Default: IP block ────────────────────────────────────────────────────
    r := FindGameServerIPs(hsPID)
    target := r.nonSvcIps
    if (CFG.f1Target = "all") {
        Loop Parse, r.svcIps, "," {
            ip := Trim(A_LoopField)
            if (ip != "" && !InStr("," . target . ",", "," . ip . ","))
                target .= (target = "" ? "" : ",") . ip
        }
    } else if (r.svcNewestIp != ""
            && !InStr("," . target . ",", "," . r.svcNewestIp . ",")) {
        target .= (target = "" ? "" : ",") . r.svcNewestIp
    }

    if CFG.f1DebugLog {
        try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") . " F1 method=" . CFG.f1Method
            . " target=" . CFG.f1Target . " pid=" . hsPID . " cnt=" . r.cnt
            . " svcCnt=" . r.svcCnt . " block=" . target
            . " hold=" . CFG.forcefulHoldMs . "`n"
            . r.detail, A_Temp . "\hs_bg_f1.log")
    }

    if (target = "") {
        BgHUD.Show("No game connection found", 1400)
        return
    }

    BgHUD.Show("Skip (" . target . ")…")
    try {
        StartHSInputShield("F1", CFG.forcefulHoldMs + 2500)

        if !ApplyIPBlock(target) {
            BgHUD.Show("F1: firewall rule creation failed", 1800)
            try StopHSInputShield()
            return
        }
        ; Arm the failsafe: guarantees unblock + un-shield even if this thread
        ; never reaches its own cleanup below.
        SetTimer(_F1FailsafeRelease, -(CFG.forcefulHoldMs + 3000))

        ; Keep the Battle.net launcher down for the hold and a few seconds
        ; after -- the window in which a disconnect-driven restore would land.
        StartF1BNetGuard(CFG.forcefulHoldMs + 6000)

        ; ---- FIXED HOLD ----
        ; Every press blocks for exactly CFG.forcefulHoldMs, then releases and
        ; lets the game run its own reconnect. A fixed duration is deliberate:
        ; an adaptive hold that lifted early on a "confirmed drop" made every
        ; press a different length, and could not confirm anything at all for an
        ; IPv6 target, so some presses silently took the full ceiling while
        ; others were quick. Same key, different behaviour every time. One knob,
        ; one duration.
        holdStart := A_TickCount
        Sleep(CFG.forcefulHoldMs)
        if CFG.f1DebugLog {
            ; Log the MEASURED elapsed time, not the configured value. Sleep can
            ; overshoot under load, and a hold that ran long is the first thing
            ; to check when a skip felt wrong.
            try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") . " F1 hold "
                . (A_TickCount - holdStart) . "ms (fixed " . CFG.forcefulHoldMs . ")`n"
                , A_Temp . "\hs_bg_f1.log")
        }

        RemoveIPBlock()
        ; STOP THE INPUT SHIELD NOW. It was armed for the full ceiling +2.5s;
        ; leaving it running after an EARLY lift left the game unresponsive
        ; for seconds after the network was already restored -- the reported
        ; freeze. The hold is over, so the shield's job is over.
        try StopHSInputShield()
        SetTimer(_F1FailsafeRelease, 0)      ; normal path cleaned up

        BgHUD.Show("Reconnecting…", 1000)
    } catch {
        BgHUD.Show("F1 failed — unblocking", 1500)
    } finally {
        try RemoveIPBlock()
        Sleep(300)
        try StopHSInputShield()
        State.lastF1End := A_TickCount
    }
}

; Four threads. The restart path sleeps for roughly 600 ms, and presses landing
; inside that window would otherwise be dropped with no indication. Extra
; threads bounce off the pipeline guard below instead.
#MaxThreadsPerHotkey 4
#HotIf HK_NoSysMods()
$*F2::Hotkey_F2()
SC03C::Hotkey_F2()
#HotIf

Hotkey_F2() {
    global State, Cache, Launch, CFG, _smLastTick
    _HotkeyTone("F2")


    if !State.startupDone {
        StartupCleanup()
        PreCachePaths()
    }

    ; A live pipeline blocks re-entry even if State.f2Active was cleared
    ; mid-launch (the F3 unlock does that by long-standing design). BUT: if
    ; the pipeline is DEAD rather than busy (state stuck non-IDLE yet the
    ; state-machine heartbeat is stale -- an abort that didn't reset, an
    ; exception, an external timer kill), do NOT block forever. Detect the
    ; stale state and force a clean reset so this F2 proceeds. A live launch
    ; ticks every few hundred ms at most, so a >4s gap means dead.
    launchingNow := (State.f2Active || (Launch.state != "IDLE" && Launch.state != "DONE"))
    if launchingNow {
        ; A pipeline that has never ticked is DEAD, not busy.
        ;
        ; This read `_smLastTick != 0 && ...`, which meant a stamp of 0 could
        ; never be judged stale no matter how much time passed. _smLastTick is
        ; written by LaunchStateMachine_Tick, so a launch that died before its
        ; first tick -- the cold-start case, where Launch.state leaves IDLE
        ; several calls before the timer is armed -- left the stamp at 0 and
        ; this guard returned early on EVERY subsequent press. F2 was inert for
        ; the rest of the session, and F1 with it (it refuses to run while
        ; f2Active). Both entry points now baseline the stamp, and a 0 here is
        ; treated as dead so an older build's state cannot wedge this one.
        pipelineDead := !_LaunchPipelineAlive()
        if !pipelineDead
            return                      ; genuinely busy: block re-entry
        ; Stale/dead pipeline -- reset and fall through to a fresh launch.
        CancelLaunchTimers()
        Launch.state   := "IDLE"
        BgHUD.Show("Recovering stalled launch…", 1500)
    }
    State.f2Active := true

    isRestart              := GetHSPID()
    Launch.skipLoginDetect := false
    Launch.bnetWasRunning  := ProcessExist("Battle.net.exe") != 0

    if isRestart {
        ; ── RESTART PATH ─────────────────────────────────────────────────────
        KillFirestoneLoadingExisting()

        if State.fsMainLocked {
            LockFirestoneMain()
        }

        StartHSCloaker()

        StartLauncherHide()

        ; StartFSNotifSweeper()   ; removed – already running from startup

        BgHUD.Show("Restarting Hearthstone…", 0)

        RemoveIPBlock()

        Sleep(100)

        try ProcessClose(isRestart)

        Sleep(300)

        try ProcessClose("Agent.exe")
        try ProcessClose("Battle.net Helper.exe")
        try ProcessClose("Battle.net.exe")

        Sleep(200)

        Cache.hsPath           := ""
        ; Login detection stays ENABLED on the restart path. Battle.net is not still
        ; authenticated here -- this branch closed it a few lines above -- so a restart
        ; that lands on a credential prompt must be able to reach LOGIN_WAIT. Detection
        ; costs a title match after a short delay and is a no-op whenever auto-login
        ; works.
        Launch.skipLoginDetect := false

        EnsureFirestoneSettings()

        StartEarlyOverwolfCloak()

        StartKillFirestoneLoading()

        ; The restart path deliberately does NOT kill Overwolf, so Firestone is
        ; normally still running and this is a no-op. It is armed anyway for
        ; the case where Overwolf died or was closed between sessions: without
        ; it, a restart would leave you with no overlay and nothing watching
        ; for that. LaunchFirestoneNow() self-checks FirestoneAppRunning().
        ; The deferred launch is no longer used; we launch Firestone immediately
        ; if it isn't running.
        ; ── FIRESTONE STARTS BEFORE HEARTHSTONE, AND THAT ORDER MATTERS ─────
        ; Firestone reads the game's memory to drive its overlay. Starting it
        ; BEFORE Hearthstone exists lets it be in place and waiting as the game
        ; comes up; starting it midway through Hearthstone's initialisation
        ; makes it attach to a process that is not ready, which fails with
        ; "CRITICAL ERROR: Could not read the game's memory" and leaves the user
        ; with no overlay for the session.
        ;
        ; A delay was briefly introduced here to move Firestone's windows out of
        ; the busiest part of the launch, so a birth-time concealment race had
        ; less to compete with. It fixed a cosmetic flash and broke the product.
        ; See CFG.fsLaunchDelayMs, which is 0 for this reason.
        if !FirestoneAppRunning() {
            _FSScheduleLaunch()
        }

        StartHSLaunch()

    } else {
        ; ── FRESH LAUNCH PATH ────────────────────────────────────────────────

        LockFirestoneMain()

        StartEarlyOverwolfCloak()

        StartHSCloaker()

        StartKillFirestoneLoading()

        StartLauncherHide()

        ; StartFSNotifSweeper()   ; removed – already running from startup

        EnsureFirestoneSettings()

        if Launch.bnetWasRunning
            Launch.skipLoginDetect := true

        ; ── LAUNCH ORDER ──────────────────────────────────────────────────────
        ; Firestone is launched immediately, at the same time as Battle.net.
        ; The old deferred launch (waiting for Hearthstone.exe) is removed.
        ; Launch Firestone if it isn't already running.
        if !FirestoneAppRunning() {
            ; Same ordering as the restart path above: Firestone goes up
            ; before Hearthstone so it can attach cleanly. See
            ; _FSScheduleLaunch and CFG.fsLaunchDelayMs.
            _FSScheduleLaunch()
        }
        ; Start the Hearthstone launch pipeline (Battle.net → Play → HS)
        StartHSLaunch()
    }
}

; ── Shutdown — triggered by the F4 key ──────────────────────────────────────
#MaxThreadsPerHotkey 10
#HotIf HK_NoSysMods()
$*F4::Hotkey_F4()
SC03E::Hotkey_F4()
#HotIf

Hotkey_F4() {
    Critical(false)
    global State, Launch, _f4Shutdown
    _HotkeyTone("F4")

    try {
        ; ── Shutdown: do not restore what is about to be killed ─────────────
        ; F4 kills Overwolf. Those windows are about to stop existing, so restoring
        ; them first achieves nothing except showing them briefly on the way out.
        ;
        ; The restore janitors exist for the other exit paths -- tray exit, reload,
        ; crash -- where this script goes away but Overwolf keeps running and a parked
        ; window would be left genuinely unreachable. That reasoning does not apply
        ; when we are killing the process that owns the window.
        ;
        ; Flag it, keep the lock on so nothing releases, kill, and only then decide.
        ; If the kill succeeded there is nothing left to restore; if it did not, the
        ; flag is cleared below and ExitCleanup restores normally -- an unreachable
        ; window is worse than a brief flash.
        _f4Shutdown := true

        Launch.state       := "IDLE"
        State.f2Active     := false
        CancelLaunchTimers()
        StopLauncherHide()
        StopEarlyOverwolfCloak()
        StopHSCloaker()
        StopHSInputShield()
        StopHSHiddenLaunchWatch()
        StopHSPlacementGuard()
        StopOverlayTopmostEnforcer()
        StopMonitorLock()
        StopFSReveal()
        StopBNetPostLaunchMinimize()
        SetTimer(_FSDelayedLaunch, 0)   ; F4 means stop -- including the
                                       ; Firestone launch that has not
                                       ; happened yet. Without this, F4
                                       ; inside the deferral window tears
                                       ; the session down and the timer
                                       ; then starts Overwolf again.

; (_FSUnparkAll deliberately NOT called here -- see the note above.)

        _ForceReleaseHighResTimer()

        SetTimer(FSMainMonitor,                 0)
        SetTimer(RevealHSAfterLaunch,           0)
        SetTimer(HSHiddenLaunchWatch,           0)
        SetTimer(SuppressFirestoneLoadingTick,  0)
        SetTimer(KillFirestoneLoading,          0)
        SetTimer(StopKillFirestoneLoading,      0)
        SetTimer(F4Watchdog,                    0)

        try BgHUD.Hide()

        try UnmuteHearthstone()

        try ResumeWSearch()

        try Run('taskkill /F /IM OverwolfLauncher.exe /T', , "Hide")
        try Run('taskkill /F /IM OverwolfBrowser.exe /T',  , "Hide")
        try Run('taskkill /F /IM Overwolf.exe /T',         , "Hide")

        try Run('taskkill /F /IM Agent.exe /T',               , "Hide")
        try Run('taskkill /F /IM "Battle.net Helper.exe" /T', , "Hide")
        try Run('taskkill /F /IM Battle.net.exe /T',          , "Hide")

        try Run('taskkill /F /IM Hearthstone.exe /T',         , "Hide")

        ; Verify the kill before trusting it. taskkill is issued asynchronously, so
        ; "we asked" is not "it is gone". Only if Overwolf is genuinely dead is the
        ; restore skipped; otherwise a failed kill would leave its windows parked
        ; off-screen with no taskbar button and nothing running to bring them back.
        _f4Deadline := A_TickCount + 1500
        while (A_TickCount < _f4Deadline) {
            if !(ProcessExist("Overwolf.exe") || ProcessExist("OverwolfBrowser.exe"))
                break
            Sleep(50)
        }
        if (ProcessExist("Overwolf.exe") || ProcessExist("OverwolfBrowser.exe")) {
            _f4Shutdown := false     ; kill failed: let ExitCleanup restore
            _FSLog("F4 shutdown: Overwolf survived the taskkill"
                 . " -- restoring its windows rather than leaving them parked")
        }
    } catch {
    } finally {
        ExitApp()
    }
}

; ── FS lock toggle — triggered by the F3 key ────────────────────────────────
#MaxThreadsPerHotkey 1
#HotIf HK_NoSysMods()
$*F3::Hotkey_F3()
SC03D::Hotkey_F3()
#HotIf

; Has a window titled exactly "Firestone - Main" ever existed this session?
;
; Latched, not polled: once true it stays true, so the scan below runs only
; while the answer is still no. Enumerating hidden windows is required -- Main
; is concealed the moment it appears, and a concealed window is still a window
; that has opened.
global _fsMainEverOpened := false
FSMainHasOpened() {
    global _fsMainEverOpened, _fsParked, _fsHiddenByUs
    if _fsMainEverOpened
        return true

    ; A SECOND WAY TO QUALIFY, so this gate cannot wedge shut.
    ;
    ; The primary test is an exact "Firestone - Main" title. If a Firestone
    ; build ever names that window differently, that test would fail on every
    ; press forever and F3 would be dead with nothing to tell the user why. So
    ; anything the script is ALREADY concealing counts too: if there is a
    ; Firestone window parked or hidden, there is by definition something for
    ; F3 to reveal, whatever it happens to call itself.
    if (_fsParked.Count || _fsHiddenByUs.Count) {
        _fsMainEverOpened := true
        return true
    }
    prev := A_DetectHiddenWindows
    DetectHiddenWindows true          ; Main is hidden on purpose; still counts
    try {
        for exe in ["Overwolf.exe", "OverwolfBrowser.exe"] {
            for h in WinGetList("ahk_exe " . exe) {
                try {
                    if IsFirestoneMainTitle(WinGetTitle("ahk_id " . h)) {
                        _fsMainEverOpened := true
                        break
                    }
                }
            }
            if _fsMainEverOpened
                break
        }
    }
    DetectHiddenWindows prev
    return _fsMainEverOpened
}

Hotkey_F3() {
    global State

    ; ── F3 IS COMPLETELY INERT UNTIL FIRESTONE MAIN EXISTS ──────────────────
    ; Before that point there is nothing for it to toggle, and every part of
    ; pressing it is a liability rather than a no-op:
    ;
    ;   * It flips State.fsMainLocked, which is what tells the suppression
    ;     subsystems to conceal Firestone's windows AS THEY ARE BORN. Unlocking
    ;     before Main exists disarms the concealment for the exact window it
    ;     was armed for, so the window arrives visible.
    ;   * It clears State.f2Active, standing the launch pipeline's Firestone
    ;     stage down mid-flight.
    ;   * It plays a note, which says "that did something" when it did not.
    ;
    ; This returns BEFORE the tone and before the debounce stamp, so an early
    ; press is silent and costs nothing -- it is not consumed, not queued, and
    ; not remembered. The first press after Main opens behaves as the first
    ; press.
    if !FSMainHasOpened()
        return

    _HotkeyTone("F3")

    ; Debounce: rapid re-toggling style-flaps the CEF window (layered alpha
    ; on/off + a FRAMECHANGED SetWindowPos per cycle) -- the documented wedge
    ; hazard for a forming Firestone - Main. Presses landing inside the
    ; window are acknowledged on the HUD and dropped; state never flaps.
    static lastF3 := 0
    if (A_TickCount - lastF3 < 250) {
        ; (no HUD toast here: the debounce still protects the window, but a
        ;  spammed F3 should not paint a message about being spammed.)
        return
    }
    lastF3 := A_TickCount

    ; ATOMIC TOGGLE. Without this the suppression sweep, the 30 ms reveal tick
    ; and the window event hook can all interrupt this handler PART-WAY
    ; THROUGH -- between clearing the lock flag and starting the reveal, or
    ; between starting the reveal and the first sweep. Each interleaving leaves
    ; the two halves briefly disagreeing about who owns the window, and every
    ; disagreement costs a show or a hide on a live CEF surface. Under a stress
    ; test they stack up. Critical makes the whole state change one indivisible
    ; step; the body contains no Sleep, so nothing is starved, and it clears
    ; automatically when the thread ends.
    ; CRITICAL COVERS THE STATE CHANGE ONLY -- NOT THE WINDOW WORK.
    ;
    ; Critical(true) forbids every other thread from running: no timer, no
    ; other hotkey, nothing. That is exactly right for flipping the flag and
    ; stopping the timers, which is a handful of assignments and cannot block.
    ; It was catastrophically wrong for the window work that used to sit inside
    ; it -- StartFSReveal and LockFirestoneMain both enumerate every Overwolf
    ; window and touch each one, and a single call that stalls on a crashed
    ; Firestone window then freezes the ENTIRE script, hotkeys included, with
    ; no watchdog able to run either (they are timers, and timers are exactly
    ; what Critical is suppressing). One slow window call became "nothing
    ; responds".
    ;
    ; The atomicity that mattered is still here: the flag and the timers change
    ; together, so no sweep can observe a half-applied toggle. The subsequent
    ; window work is idempotent and re-entrancy is already handled by the 250 ms
    ; debounce above and by each function's own guards.
    unlocking := false
    Critical(true)
    try {
        if State.fsMainLocked {
            State.fsMainLocked := false
            SetTimer(FSMainMonitor, 0)
            StopFSBurst()
            State.f2Active := false   ; long-standing unlock behavior: ends
                                      ; launch-mode for the FS subsystems.
                                      ; Double-F2 is prevented by the pipeline
                                      ; guard in Hotkey_F2, not by this flag.
            ; THE NOTIFICATION SWEEPER IS NOT STOPPED HERE. DO NOT ADD IT BACK.
            ;
            ; It used to be, and that single line is what made the popup "linked
            ; to F3". Stopping the closer is bad enough on its own -- but it also
            ; runs immediately before StopEarlyOverwolfCloak below, which checks
            ; whether the sweeper is alive to decide whether to HAND a popup over
            ; or RELEASE it. With the sweeper just killed, that check fails, the
            ; popup is uncloaked instead of handed over, and nothing is left
            ; running to close it. Press F3, get a painted popup that never goes
            ; away.
            ;
            ; The lock decides whether FIRESTONE'S OWN windows are on screen. A
            ; notification is not one of those and never was.
            StopEarlyOverwolfCloak()
            unlocking := true
        }
    } catch {
        Critical(false)
        BgHUD.Show("F3 error – reset", 1200)
        return
    }
    Critical(false)

    try {
        if unlocking {
            StartFSReveal()
            BgHUD.Show("FS Unlocked", 800)
        } else {
            LockFirestoneMain()
            BgHUD.Show("FS Locked", 800)
        }
    } catch {
        try {
            State.fsMainLocked := true
            SetTimer(FSMainMonitor, 200)
            SuppressFirestoneMainTick()
        }
        BgHUD.Show("F3 error – reset", 1200)
    }
}

; ==============================================================================
; SECTION 16: STARTUP / BACKGROUND TASKS
; ==============================================================================
;
; Everything that runs once when the script boots: pick the launch monitor,
; elevate to admin, repair anything a crashed previous run left hidden,
; arm the permanent window hook, and start the steady‑state watchers.
;

; Resolve the launch monitor BEFORE elevation.
ResolveChosenMonitor()

; Require elevation — relaunches as admin if not already, handing off the launch
; monitor (/mon:x,y).
if !A_IsAdmin {
    try Run('*RunAs "' . A_AhkPath . '" /restart "' . A_ScriptFullPath . '" /mon:' . ChosenMonPt)
    ExitApp()
}

A_IconTip := "Battle Grounds " . HSBG_BUILD . " — running"

; ── Tray menu: reach the settings file without hunting for it ────────────────
; The settings file can end up in one of two folders depending on whether the
; script's own folder turned out to be writable, and a user should never have
; to work out which. These two items remove the question entirely.
;
; There is a second, less obvious reason "Open settings" earns its place: this
; script runs ELEVATED, so an editor launched from here is elevated too. If the
; .ini did land somewhere only an administrator can write, opening it this way
; is the one route that can actually save the file. That is precisely the
; failure this menu exists to answer.
try {
    A_TrayMenu.Insert("1&")                       ; separator above the defaults
    A_TrayMenu.Insert("1&", "What is under my cursor?", (*) => WhatIsUnderCursor())
    A_TrayMenu.Insert("1&", "Test hotkey sound", (*) => TestHotkeySound())
    A_TrayMenu.Insert("1&", "Reload settings", (*) => ReloadUserConfig())
    A_TrayMenu.Insert("1&", "Open settings (HSBG.ini)", (*) => OpenConfigFile())
}

OpenConfigFile() {
    path := _ConfigPath()
    try {
        if !FileExist(path)
            _WriteDefaultConfig(path)
        _MakeConfigEditable(path)
        Run('notepad.exe "' . path . '"')       ; explicit: no file association
    } catch {                                   ; needed, and it can always save
        try Run(path)
    }
}

; Re-read HSBG.ini and apply what can be applied without a restart.
;
; Honest about its limits: the monitor lock starts and stops cleanly, and the
; hotkey tones only need their files built. Anything else in CFG was consumed
; during start-up and is not revisited, which is why the file itself tells the
; user to restart rather than promising this covers everything.
ReloadUserConfig() {
    global CFG
    LoadUserConfig()
    try {
        if CFG.lockWindowsToChosenMonitor
            StartMonitorLock()
        else
            StopMonitorLock()
    }
    if CFG.hotkeyAudio
        try EnsureHotkeyTones()
    _FSLog("CONFIG reloaded from " . _ConfigPath()
         . " -- MonitorLock=" . (CFG.lockWindowsToChosenMonitor ? 1 : 0)
         . " HotkeyAudio="    . (CFG.hotkeyAudio ? 1 : 0))
    BgHUD.Show("Settings reloaded", 1500)
}

; Apply configured script process priority.
if CFG.scriptAboveNormalPriority
    ; High (was AboveNormal): the 1ms burst and the event hook must hold
    ; their cadence through a Battlegrounds MATCH-START load spike -- the
    ; exact moment fresh Firestone windows are born. The script's per-tick
    ; work is microseconds, so this costs the game nothing.
    try ProcessSetPriority("High")

; Defensive startup pass: uncloak any window that may have been left cloaked.
try {
    _startupPrevDHW := A_DetectHiddenWindows
    DetectHiddenWindows true
    for _startupExe in ["Overwolf.exe", "OverwolfBrowser.exe", "OverwolfLauncher.exe", "Hearthstone.exe"] {
        for _startupHwnd in WinGetList("ahk_exe " . _startupExe) {
            try UncloakWindow(_startupHwnd)
        }
    }
    ; This loop only ever UNCLOAKED. Transparency left behind by a previous run
    ; (the launcher fade, or the alpha shield) was never cleared here -- only
    ; the Battle.net loop below did that -- so an invisible Overwolf window
    ; survived a restart of the script untouched. FSRepairStuckAlpha covers the
    ; whole Overwolf family and skips per-pixel windows.
    try FSRepairStuckAlpha()
    ; Battle.net/Agent repair: uncloak + unfade everything. Force-SHOW only a
    ; window carrying this script's own crash fingerprint — hidden AND still
    ; DWM-cloaked (only a mid-launch crash leaves that combination) — and only
    ; for the Battle.net client itself. A launcher the user closed to the tray
    ; is hidden but NOT cloaked, and Agent's shell window is MEANT to be
    ; invisible; neither is ever popped onto the screen here.
    for _startupExe in ["Battle.net.exe", "Battle.net Launcher.exe", "Battle.net Helper.exe", "Agent.exe"] {
        for _startupHwnd in WinGetList("ahk_exe " . _startupExe) {
            try {
                _startupWasCloaked := IsWindowCloakedDWM(_startupHwnd)
                UncloakWindow(_startupHwnd)
                try WinSetTransparent("Off", "ahk_id " . _startupHwnd)
                if (_startupExe = "Battle.net.exe" && _startupWasCloaked
                 && !DllCall("user32\IsWindowVisible", "Ptr", _startupHwnd)
                 && WinGetTitle("ahk_id " . _startupHwnd) != "") {
                    WinGetPos(, , &_sw, &_sh, "ahk_id " . _startupHwnd)
                    if (_sw > 200 && _sh > 150)
                        DllCall("ShowWindow", "Ptr", _startupHwnd, "Int", 8)  ; SW_SHOWNA
                }
            }
        }
    }
    DetectHiddenWindows _startupPrevDHW
}

; Recover from previous failed launch state.
try StopFSBurst()

; Repair anything a PREVIOUS instance of this script left transparent. The
; shield keeps WS_EX_LAYERED across unlocks by design, so a reload or restart
; while Firestone is running used to inherit stranded alpha-0 windows that no
; code path would ever restore -- the "F3 unlocks them and they are invisible"
; failure. Must run before the lock arms.
try FSRepairStuckAlpha()

; Same, for the cold-window park: bring back anything a previous instance left
; sitting outside the virtual desktop. Must also run before the lock arms.
try FSRepairStrandedWindows()

; Start Firestone‑Main monitor in locked mode.
LockFirestoneMain()

; Register deterministic cleanup for all exit paths.
OnExit(ExitCleanup)
ExitCleanup(*) {
    ; _fsAlphaApplied, _fsHiddenByUs and _bnetHiddenByUs must be declared global
    ; here. In AutoHotkey v2 an undeclared name inside a function is a LOCAL, and
    ; reading an unset local throws -- inside the try that wraps the restore
    ; block, which would swallow it and abandon the entire cleanup.
    global _fsAlphaApplied, _fsHiddenByUs, _bnetHiddenByUs, _f4Shutdown
    try ResumeWSearch()
    try UnmuteHearthstone()

    try StopOWCreateHook()
    try StopEarlyOverwolfCloak()
    try SetTimer(LateHSWatch, 0)
    try {
        prevT := A_DetectHiddenWindows
        DetectHiddenWindows true
        for exe in ["Overwolf.exe", "OverwolfBrowser.exe"] {
            for hwnd in WinGetList("ahk_exe " . exe)
                try _EnableDWMTransitions(hwnd)
        }
        DetectHiddenWindows prevT
    }

    try {
        prev     := A_DetectHiddenWindows
        prevMode := A_TitleMatchMode
        DetectHiddenWindows true
        SetTitleMatchMode(2)
        for exe in ["Overwolf.exe", "OverwolfBrowser.exe", "Battle.net.exe", "Agent.exe", "Battle.net Helper.exe"] {
            for h in WinGetList("ahk_exe " . exe) {
                try {
                    if (_fsAlphaApplied.Has(h)
                     && IsFirestoneSuppressionTitle(WinGetTitle("ahk_id " . h)))
                        _RemoveFSAlphaShield(h)
                }
                try UncloakWindow(h)
            }
        }
        ; ── Selective restore ───────────────────────────────────────────────
        ; The purpose of an exit janitor is to leave nothing UNREACHABLE. It is not to
        ; put transient surfaces back on screen.
        ;
        ; A boot splash, a loading popup or a notification left hidden is not
        ; unreachable: the owning application knows about it and will show it again
        ; whenever it likes. A window this script PARKED outside the virtual desktop
        ; with its taskbar button removed IS unreachable, and so is one left cloaked.
        ;
        ; So: always undo what was done to a window's reachability; only ever show a
        ; window the user actually needs.
        ;
        ; Battle.net: the real client only. Service surfaces stay concealed.
        for h in _bnetHiddenByUs.Clone() {
            try {
                if !DllCall("user32\IsWindow", "Ptr", h)
                    continue
                if DllCall("user32\IsWindowVisible", "Ptr", h)
                    continue
                if _IsProtectedBNetMain(h)
                    WinShow("ahk_id " . h)
            }
        }
        ; Firestone: the same rule. Show back the windows the user reaches with F3 and
        ; the overlay that must render -- Main, Battlegrounds, Overlays. The Loading
        ; splash and the bare-"Firestone" notification are not restored: they are
        ; transient surfaces Overwolf owns and re-creates at will.
        ;
        ; The unpark and the taskbar-button restore below are NOT conditional. They run
        ; for every window this script touched, because those are the two things that
        ; would genuinely leave a window unreachable.
        if !_f4Shutdown {
            for h in _fsHiddenByUs.Clone() {
                try {
                    if !DllCall("user32\IsWindow", "Ptr", h)
                        continue
                    if DllCall("user32\IsWindowVisible", "Ptr", h)
                        continue
                    ht := ""
                    try ht := WinGetTitle("ahk_id " . h)
                    if (ht = "Firestone - Main" || ht = "Firestone - Battlegrounds"
                     || ht = "Firestone - Overlays")
                        WinShow("ahk_id " . h)
                }
            }
        }
        DetectHiddenWindows prev
        SetTitleMatchMode prevMode
    }

    try ForceEnableHSWindow()
    try StopHSInputShield()
    try StopLauncherHide()
    try StopHSHiddenLaunchWatch()
    try StopHSCloaker()
    try StopHSPlacementGuard()
    try StopOverlayTopmostEnforcer()
    try StopMonitorLock()
    try StopFSReveal()
    ; LEAVE NO TRACE, park edition. A window left parked outside the virtual
    ; desktop by an exiting instance has no taskbar button and no Alt-Tab
    ; entry, so nothing could ever bring it back. Unpark our ledger, then
    ; sweep for anything stranded that is not in it.
    if !_f4Shutdown {
        try _FSUnparkAll()
        try FSRepairStrandedWindows()
    }
    try _ForceReleaseHighResTimer()
    try SetTimer(FSMainMonitor,               0)
    try SetTimer(SuppressFirestoneLoadingTick, 0)
    try SetTimer(KillFirestoneLoading,        0)
    try SetTimer(StopKillFirestoneLoading,    0)
    try SetTimer(HSHiddenLaunchWatch,         0)
    try SetTimer(RevealHSAfterLaunch,         0)
    try SetTimer(BNetStallWatchTick,          0)
    try SetTimer(F1BNetGuardTick,             0)
    try SetTimer(BNetMinimizeSequenceTick,    0)
    try SetTimer(HK_ReachabilityWatchdog,     0)

    try {
        prev := A_DetectHiddenWindows
        DetectHiddenWindows true
        for hwnd in WinGetList("ahk_exe Hearthstone.exe") {
            if IsIMEWindow(hwnd)
                continue
            if IsHelperWindow(hwnd)
                continue
            try UncloakWindow(hwnd)
            WinShow("ahk_id " . hwnd)
            WinSetTransparent("Off", "ahk_id " . hwnd)
        }
        DetectHiddenWindows prev
    }

    try DeleteRules()
    try DeleteGameRule()
}

; One‑shot startup cleanup: run synchronously so first F2 cannot race it.
StartupCleanup() {
    global State, CFG, HSBG_BUILD
    try DeleteRules()
    try DeleteGameRule()
    State.startupDone := true

    ; The settings actually in force go to the LOG ONLY.
    ;
    ; This briefly showed them on the HUD at every launch as well. That was
    ; added to make a config problem diagnosable at a glance, and it did -- but
    ; nobody asked for a start-up banner, and a message that appears every
    ; single launch to tell you nothing has gone wrong is noise. The
    ; information is still recorded, and the tray menu can report it on demand;
    ; it just no longer interrupts a launch that is working.
    try {
        _FSLog("STARTUP " . HSBG_BUILD . " settings in force: MonitorLock="
             . (CFG.lockWindowsToChosenMonitor ? 1 : 0) . " HotkeyAudio="
             . (CFG.hotkeyAudio ? 1 : 0) . " vol=" . CFG.hotkeyAudioVolume
             . " freqMode=" . CFG.hotkeyFreqMode . " from " . _ConfigPath())
    }
}

; One‑shot startup warmup: resolve and cache Overwolf/Firestone paths.
PreCachePaths() {
    GetOverwolfPath()
    GetFirestoneCmd()
    if !ProcessExist("Overwolf.exe")
        EnsureFirestoneSettings()
}

; Run the first‑use‑sensitive startup work immediately.
StartupCleanup()
PreCachePaths()

; Create the ITaskbarList object ONCE, here, before anything can reach it from
; a window-event callback. See _FSTaskbarInit.
try _FSTaskbarInit()

; Arm the window event hook at startup.
StartOWCreateHook()

; Background loading-popup guard: a low-rate (100ms) always-on instance of the
; Firestone loading suppression, so a loading window appearing BEFORE the first
; F2 (or right after a too-quick F2) is caught instead of flashing on primary.
; No-op when no loading popup exists. F2 still arms the fast 10ms instance.
;
; FIRESTONE IS OPTIONAL. Nothing below is armed on a machine with no Overwolf
; and no Firestone install: these timers exist solely to manage Firestone's
; windows, and on such a machine they would poll an empty window list forever.
; The check is a cached path lookup, so it costs one filesystem probe.
if FirestoneInstalled()
    SetTimer(SuppressFirestoneLoadingTick, 100)

; Deferred 3s: warm PowerShell once after startup settles.
SetTimer(PrewarmRules, -3000)
PrewarmRules() {
    global State
    if !State.startupDone {
        SetTimer(PrewarmRules, -500)
        return
    }
    try Run(A_ComSpec . ' /c powershell -NoProfile -Command exit', , "Hide")
}

; Shutdown watchdog: polls physical F4 key state every 500ms so shutdown still
; fires even when DirectInput/fullscreen mode swallows the window message.
SetTimer(F4Watchdog, 500)

; Build the hotkey notes if HSBG.ini turned them on. Deferred off the start-up
; path: generating four waveforms takes about a second, and a hotkey pressed in
; that second must not wait for it -- a press before they exist builds them on
; the spot and falls back to a plain beep, so it is never silent.
;
; Logged either way. If the sound was switched on and nothing was heard, this
; line is the first thing to check: it says whether the script saw the setting
; at all, which separates "the audio failed" from "the file you edited is not
; the file the script read".
if CFG.hotkeyAudio {
    _FSLog("AUDIO enabled in config -- building notes shortly")
    SetTimer(EnsureHotkeyTones, -1200)
} else {
    _FSLog("AUDIO disabled (HotkeyAudio=0 in " . _ConfigPath() . ")")
}

; Hotkey watchdog: releases a system modifier the OS is reporting as held while
; nothing is being typed. That state makes all four F-keys inert with no
; visible symptom, so this is the one timer whose job is to keep the script
; reachable at all. See HK_NoSysMods.
SetTimer(HK_ReachabilityWatchdog, CFG.hkWatchdogPollMs)

; Qt‑helper janitor: keeps Battle.net's hidden helper windows hidden.
SetTimer(QtHelperJanitor, 2000)

; Point Hearthstone's own display preference at the chosen monitor.
SetHSMonitorPref()

; Monitor lock: keep the HUD / Battle.net / Agent / Hearthstone on the launch monitor.
StartMonitorLock()

; F3 STARTS IN THE LOCKED STATE. State.fsMainLocked already defaults to true,
; but nothing ever ARMED it at startup: LockFirestoneMain() is what starts the
; 1ms suppression burst and runs the first sweep. Without this call a Firestone
; that was already running when the script started stayed visible until the
; first F2/F3. Now FS-Main and FS-Battlegrounds are hidden from startup.
;
; Skipped entirely when Firestone is not installed -- LockFirestoneMain arms
; the 50ms coast sweep, and there is nothing for it to sweep.
if FirestoneInstalled() {
    LockFirestoneMain()
    StartFSNotifSweeper()   ; starts the popup closer immediately
} else {
    _FSLog("STARTUP no Overwolf/Firestone install detected -- Firestone"
         . " subsystems stay dormant. F1, F2 and F4 work normally; F3 has"
         . " nothing to toggle")
}

; ── LOAD STAMP ────────────────────────────────────────────────────────────────
; A distinct rising 3-note chord the instant THIS build finishes loading.
; Purpose: AutoHotkey does NOT hot-reload an edited script -- the previously
; launched instance keeps running until it is exited and relaunched. If you
; save a new build but do not relaunch (or a stale second instance is live),
; you are testing OLD code, which presents exactly as "fixes didn't take" and
; can eat hotkey beeps. Hear this chord = the new build is the running one.
; Ctrl+Alt+R force-reloads from disk at any time (see below).

; Reload from the tray icon if a build needs to be re-read from disk. A global
; Ctrl+Alt+R chord is deliberately not registered: other applications want it.

F4Watchdog() {
    if !GetHSPID()
        return
    ; Same modifier rule as the hotkeys themselves. Without it this poll was a
    ; back door around the passthrough above: Alt+F4 in any application left F4
    ; physically down, the poll saw it 500 ms later and ran the full shutdown
    ; anyway. Only a BARE F4 hold is a shutdown request.
    if !HK_NoSysMods()
        return
    if GetKeyState("F4", "P")
        Hotkey_F4()
}