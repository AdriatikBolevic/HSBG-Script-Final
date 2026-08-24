# Releasing HSBG

The update check in `HSBG Script Final.ahk` compares its own build stamp against
the newest release tag on GitHub. **Three numbers have to agree**, and if they
drift, users get told to install a version they already have — every launch,
until it is corrected.

| Where | What it must say |
|---|---|
| `HSBG Script Final.ahk`, line ~253 | `global HSBG_BUILD := "v5.0.0"` |
| The GitHub release tag | `v5.0.0` |
| `version.json`, `"version"` | `"v5.0.0"` |

They are compared as numbers, so `v5.0.0`, `5.0.0` and `5.0` are all equal and
all fine. A tag like `release-5` or `final2` is not a version and is ignored —
the check logs it and says nothing to the user.

---

## Publishing 4.0.0 (what the repository needs now)

The repository currently has no releases and its README is two versions behind.

**1. Replace the tracked files** with the current ones:

```
HSBG Script Final.ahk      ← v4.0.0
HSBG Config.ini            ← 13 keys, including UpdateCheck
README.md                  ← documents v4.0.0
version.json               ← new
.gitignore                 ← new
```

**2. Nothing to clean up — `.gitignore` is preventative.** The repository has
never tracked `HSBG.log`, which is correct: the script writes a fresh one beside
itself on every machine that runs it, so a committed copy would only ever be one
stale session belonging to whoever generated it. Every line in it carries an
absolute path, so that copy would also carry a Windows username.

The `.gitignore` exists so that stays true. The realistic way it would break is
a `git add -A` run from a folder you have actually been running the script in —
which is exactly what step 3 does.

**3. Commit and tag:**

```bash
git add -A
git commit -m "v4.0.0"
git tag v4.0.0
git push origin main --tags
```

**4. Publish the release.** On GitHub: *Releases* → *Draft a new release* →
choose the `v4.0.0` tag → **attach `HSBG Script Final.ahk` as a binary asset** →
publish.

The attached file is what the tray item downloads. A release without it still
announces itself, but the tray item can only open the releases page.

---

## Every release after this one

1. Bump `HSBG_BUILD` in the script.
2. Bump `"version"` in `version.json`, and put one plain sentence in `"notes"` —
   it is written into the user's log, so it should say what changed, not "misc
   fixes".
3. Commit, tag with the **same** number prefixed `v`, push with `--tags`.
4. Draft the release on that tag and attach the `.ahk`.

Someone running the old version sees the notice within about ten seconds of
their next start-up.

### Worth knowing

- **`raw.githubusercontent.com` caches for about five minutes.** If you push
  `version.json` and test immediately, you may still get the old one. The
  Releases API is not cached this way, so a properly published release shows up
  at once.
- **Users can turn it off.** `UpdateCheck=0` in `HSBG Config.ini` means no
  network request is ever made. Anyone who sets it will not hear about releases.
- **Don't delete an old release to force an upgrade.** The check only ever
  compares against the newest tag; removing older ones changes nothing and
  breaks the download links of anyone mid-install.
- **A downgrade is never announced.** If you publish `v5.0.0` and then pull it,
  the newest tag becomes `v4.0.0` again and nobody is told to move backwards.
