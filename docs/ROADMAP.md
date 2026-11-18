# Roadmap

## Principles
- **Set and forget.** The module applies the tuning once at boot (`post-fs-data.sh`, then `service.sh` 20 s after boot) and exits. No watcher, loop or daemon. No `tc` replacement.
- **The cleaner never runs on its own.** It runs only when you press a button in the WebUI, or run `deeppurge` in Termux.
- **Quick clean** (no reboot) and **full clean** (always reboots, asks first).
- **Never uninstalls apps.** No `pm uninstall` anywhere.
- **One engine.** `deeppurge.sh` is both the Termux command and the module's cleaner. The WebUI drives it with `--mode=`, `--sections=`, `--dry` and `--reboot-ok`.
- **Honest status.** Every tuning write is read back. Anything this phone doesn't support is labelled **Not supported** and can't be toggled.
- **The hard rules in `CLAUDE.md` still apply**: no SD card, no app or APK removal, logins kept, and everything is deleted through `empty_dir`/`zap`.

## Layout
```
deeppurge.sh                 engine (Termux command, also packed into the module)
module/                      module source (tools/build-module.sh adds deeppurge.sh, tuning.sh, version)
  module.prop                version filled in at build time
  customize.sh               install: removes the old standalone boot scripts, checks for Termux
  post-fs-data.sh            tuning pass 1
  service.sh                 tuning pass 2 (once, then exits)
  action.sh                  manager Action button: shows the tuning status, never cleans
  uninstall.sh               removes /data/adb/deeppurge and the status file
  probe.sh                   read-only device check for the WebUI
  webroot/index.html         WebUI
tools/build-module.sh        → dist/DeepPurge-v<ver>.zip + dist/update.json
```
On the device: settings in `/data/adb/deeppurge/` (`tuning.off`, `webui.conf`, `run.out`), status in `/data/adb/deeppurge_tuning.status`.

## Phases
1. ✅ Repo, script v10.0, lint CI, automatic releases
2. ✅ v10.1: module and WebUI, quick/full clean, uninstall logic removed
3. Try it on the device. Fix whatever the WebUI reports as not working
4. Imports from [IMPORTS.md](IMPORTS.md), one at a time, starting with list A
5. Optional: a WebUI button that installs the module's engine as the Termux command, so both copies stay the same version
