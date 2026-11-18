# Roadmap

## Principles
- **Set and forget.** The module applies the tuning once at boot (`post-fs-data.sh`, then `service.sh` 20 s after boot) and exits. No watcher, loop or daemon. No `tc` replacement.
- **The cleaner never runs on its own.** It runs only when you press a button in the WebUI.
- **Quick clean** (no reboot) and **full clean** (always reboots, asks first).
- **Never uninstalls apps.** No `pm uninstall` anywhere.
- **Standalone.** POSIX `sh` only: no Termux, no bash.
- **Honest status.** Every tuning write is read back. Anything this phone doesn't support is labelled **Not supported** and can't be toggled.
- **The hard rules in `CLAUDE.md` apply**: no SD card, no app or APK removal, logins kept, and everything is deleted through `empty_dir`/`zap`.

Layout and section details: see `CLAUDE.md`.

## Phases
1. ✅ Repo, Termux script v10.0, lint CI, automatic releases
2. ✅ v10.1: standalone module and WebUI, quick/full clean, uninstall logic removed, Termux script deprecated
3. Try it on the device. Fix whatever the WebUI reports as not working
4. Imports from [IMPORTS.md](IMPORTS.md), one at a time, starting with list A
5. Remove the deprecated Termux script from the repo
