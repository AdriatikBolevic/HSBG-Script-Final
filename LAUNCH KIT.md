# HSBG — launch kit

Everything below is paste-ready. Work down the list in order; the repo housekeeping
takes about ten minutes and should be done *before* anything gets posted, because
the first wave of visitors is the one that decides whether you get stars.

---

## 1 · Repo housekeeping

### LICENSE

`LICENSE` is written and sits beside this file. Drop it in the repo root and commit.
Without it, GitHub shows "no license" and legally nobody can fork or reuse your work.

### Topics

Repo home → the **⚙ gear** beside "About" (top right) → **Topics**. Paste these:

```
autohotkey
autohotkey-v2
hearthstone
hearthstone-battlegrounds
battlegrounds
windows
window-management
hotkeys
game-tools
overwolf
```

These are most of your passive discovery — GitHub topic pages are browsable and
`autohotkey-v2` in particular is small enough that you will actually be visible on it.

### About box

Same gear. Your current description is fine but leads with the riskier half. Suggested:

```
One-key launch, window and monitor management for Hearthstone Battlegrounds. AutoHotkey v2, single file, no install.
```

### Social preview

Settings → **Social preview** → upload `hsbg-social-preview.png` (delivered with this
kit). This is what Reddit and Discord show when someone pastes your link. Without it
they show a grey box, and a grey box gets scrolled past.

### Release

Releases → **Create a new release**.

- Tag: `v9.0`
- Title: `v9.0 — first public release`
- Attach: `HSBG Script Final.ahk` (**attach the file itself**, don't rely on the repo browser)

Body:

```markdown
First public release.

**What it is** — a single-file AutoHotkey v2 tool that starts a whole Hearthstone
Battlegrounds session from one key, keeps every window on the monitor you chose,
and keeps Firestone's desktop clutter out of your way until you ask for it.

| Key | |
|:---:|---|
| **F1** | Skip the combat animation |
| **F2** | Launch the session — Battle.net, Play, Hearthstone, Firestone, in the right order |
| **F3** | Show/hide Firestone's desktop windows |
| **F4** | Shut it all down and put everything back |

**Install** — install [AutoHotkey v2.0](https://www.autohotkey.com/), download
`HSBG Script Final.ahk` below, and start it **on the monitor you want to play on**.
Accept the UAC prompt, press F2. Settings write themselves to `HSBG Config.ini`
on first run.

**Requires** Windows 10/11 · AutoHotkey v2.0 · admin rights. Firestone optional.
```

### Screen recording — the one thing I can't do for you

This is the highest-leverage item in the whole kit and it needs your machine.

Get [ScreenToGif](https://www.screentogif.com/) (free, no install needed — portable
`.exe`). Record **two** clips:

1. **The launch, ~12 seconds.** Start from a clean desktop, nothing running. Press F2.
   Let it run through Battle.net appearing, Play firing, the launcher minimising, and
   Hearthstone arriving. This is the money shot — it is the whole pitch in one loop.
2. **The skip, ~6 seconds.** A combat starting, F1, and the result appearing.

Crop to the action, cap the width at about 800px so it loads fast, and put clip 1
directly under the title in the README. Clip 2 goes in the `F1` section.

A tool that saves time has to *show* the time being saved. Text cannot do it.

---

## 2 · r/AutoHotkey — post this first

Your best first audience: they will read the source, the ToS question doesn't arise
for them, and a well-documented v2 project genuinely does well there. Check the sub's
current rules before posting; flair it **Showcase** (or whatever the equivalent is now).

**Title:**

```
I automated four Windows apps that actively fight back — 10.9k lines of AHK v2, fully commented
```

**Body:**

```markdown
I play a lot of Hearthstone Battlegrounds, and starting a session meant: open Battle.net,
wait, click Play, wait, drag the game to the right monitor, start my tracker, close its
three nag popups. Every time.

So it's one key now. But the interesting part wasn't the automation — it was that three
of those four applications actively resist being managed, and every obvious approach
fails in its own specific way. A few things I learned the hard way:

**`ShowWindow(SW_HIDE)` is a trap for Chromium windows.** Overwolf and the Battle.net
client are both Chromium-based, and they read SW_HIDE as *you no longer exist* and tear
down their compositor. Hide one before it has ever painted and it may never paint again —
you get a correctly sized, correctly framed, completely blank rectangle. The fix is to
stop hiding things: **move the window off the virtual desktop instead.** A move is
synchronous and atomic, the window stays alive and fully rendered, it simply isn't over
a monitor any more. Add a DWM cloak and taskbar-button removal and it's indistinguishable
from hidden — no pixels, no taskbar entry, no Alt-Tab entry, no thumbnail — while the app
stays perfectly healthy.

**Never trust your own bookkeeping about window state.** I keep a ledger of what I've
concealed, but only to skip redundant work — never as evidence. The owning app is editing
that state concurrently: a cloak gets silently reset by an ordinary window operation, a
window gets repositioned back on screen a millisecond after you moved it off. Anywhere the
answer has to be *correct*, query the OS, not your notes.

**One owner per window per phase.** Two timers concealing the same window from different
starting points don't average out — they fight, and which one wins varies by machine and
by run. Nearly every flicker and race I had traced back to two subsystems both thinking
they owned a window.

**`#HotIf` has a deadline.** I had a bug where clicks on the game would die, then start
working again if you moved the cursor to another monitor and back. That's not an
overlapping window — moving the cursor wouldn't fix one. `#HotIf` mouse context is
evaluated by the input hook on *every click* with a short deadline, and an expression
that's too slow gets abandoned with the previous result reused. Mine was enumerating every
game window and reading each one's class and rect. Per click. It's one boolean and a PID
comparison now.

Also in there: AHK v2's 100ms default sleep after every `WinMove`/`WinShow`/`WinActivate`,
which on a timer-driven script blocked *everything including hotkeys* for about 90% of the
launch window. That one setting was the single biggest source of "it feels slow".

Source is one file, ~10,900 lines, ~4,200 of them comments. I wrote the comments to be
sufficient to rebuild the thing from scratch — each subsystem states the constraint it
exists to satisfy rather than what it does, because in nearly every case the obvious
implementation is the one that fails, and the comment explains which failure.

https://github.com/AdriatikBolevic/HSBG-Script-Final

Happy to answer anything about the window handling — it's the part I'd do differently
if I started again.
```

**Replying to comments:** this sub rewards engagement. Answer every question in the first
six hours; that's what keeps a post alive. If someone asks about F1, answer plainly — it
adds a temporary Windows firewall rule scoped to Hearthstone's executable and one remote
address, then removes it. Don't get defensive; it's a technical sub and that's a technical
answer.

---

## 3 · r/BobsTavern — the actual player audience

**Read the rules first.** Most game subs restrict tool and self-promotion posts to
specific days or require mod approval. If they do, message the mods rather than posting
and getting removed — a removed post can't be reposted with the same link for a while.

**Title:**

```
I got tired of the 6-click start-up, so now my whole BG session opens on one key
```

**Body:**

```markdown
Free, open source, no install — one AutoHotkey file you double-click.

**F2** opens Battle.net, presses Play, minimises it before the game window arrives, and
brings Firestone up in parallel so the overlay is ready when the game is. Everything lands
on whichever monitor you started the script from. Battle.net's splash, login shell and
update-agent windows never appear at all, and Firestone's "your abilities are ready" popup
gets closed on sight.

**F3** shows/hides Firestone's desktop windows — the in-game overlay is never touched, and
each window goes back exactly where you put it.

**F4** closes everything and puts your system back how it was.

**F1** skips the combat animation.

It doesn't touch the game's memory, files or process — it's window management plus hotkeys.
Hearthstone itself is never hidden, muted or resized; fullscreen vs borderless stays entirely
your setting.

https://github.com/AdriatikBolevic/HSBG-Script-Final

Windows only, needs AutoHotkey v2 and admin rights. Firestone is optional — everything else
works without it.
```

**On F1 here:** I've left it as one line among four rather than the headline. That's
deliberate — the launch automation is the uncontroversial pitch and it's genuinely the
bigger piece of work. Lead with the skip in a player sub and the comments become a
referendum on whether it's cheating instead of a conversation about your tool. Anyone
who wants it will find it in the README.

---

## 4 · Firestone Discord

Warm audience — you built real Firestone integration and they'll get why immediately.
Find the community/off-topic or showcase channel, don't drop it in support.

```
Built a free AHK tool for BG sessions that does quite a lot of Firestone-specific work,
thought this crowd might find it useful.

One key opens Battle.net → Play → Hearthstone, and starts Firestone *first*, in parallel,
before Hearthstone exists — because starting it midway through HS initialisation is what
causes "CRITICAL ERROR: could not read the game's memory" and kills your overlay for the
session. Another key shows/hides the desktop windows (Main + Battlegrounds) while leaving
the in-game overlay completely untouched, and each window returns to exactly where you
had it. The notification popup gets closed on sight.

The popup handling was the fiddly part — it and Main are indistinguishable by title and
size while Main is still loading, so nothing gets closed unless a separate "Firestone - Main"
window also exists at that moment.

Open source, one file: https://github.com/AdriatikBolevic/HSBG-Script-Final
```

---

## 5 · Hacker News — only if the AHK post goes well

Don't lead here. If r/AutoHotkey responds, the engineering story has legs and you can
"Show HN" it. Post Tuesday–Thursday, roughly 9–11am US Eastern.

**Title** (HN hates exclamation marks and hype — this is deliberately flat):

```
Show HN: Automating four Windows apps that resist being automated
```

First comment from you, immediately after posting, giving the context the title can't:
the three principles, the SW_HIDE compositor teardown, and what you'd do differently.
That comment matters more than the post.

---

## 6 · Order and timing

1. LICENSE, topics, About box, social preview, release — **all before posting anywhere**
2. Record both GIFs, put clip 1 at the top of the README
3. r/AutoHotkey, midweek morning US time. Stay in the comments for six hours.
4. r/BobsTavern a few days later, once the README has the GIF in it
5. Firestone Discord any time after that
6. HN only if #3 lands

Don't post everywhere on the same day. If the first post teaches you that something in the
README is confusing — and it will — you want to fix it before the next audience arrives.
