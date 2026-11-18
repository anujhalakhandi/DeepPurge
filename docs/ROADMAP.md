# Roadmap: from Termux script to module

## Principles
- **Set and forget.** The module applies settings at boot (`post-fs-data.sh`, `service.sh`) and then exits. No watcher, no loop, no daemon. This matches the current tuning rule: no tc replacement or watcher logic.
- **WebUI = a control panel.** It picks options, writes a config file, and runs one-off actions (clean now, revert, show status). Changes to tuning apply on the next boot, or right away with "apply now".
- **The script's hard rules still apply** (see `CLAUDE.md`): no SD card, no APK removal, logins kept, always reboot after a clean, every delete goes through `empty_dir`/`zap` so a dry run only measures.
- **Whatever doesn't apply gets removed.** Each setting is read back and written to a status file. Anything the kernel lacks is dropped rather than kept "just in case".

## Planned layout
```
module/
  module.prop           id=deeppurge
  customize.sh          install checks (root manager, device, API level)
  post-fs-data.sh       tuning pass 1 (same body as today's 99_deeppurge_tuning.sh)
  service.sh            tuning pass 2 after boot_completed, then exit
  action.sh             manager "Action" button: run a clean with saved choices
  uninstall.sh          same as --revert
  common/
    deeppurge.sh        the cleaner, shared by Termux and the module
    tuning.sh           tuning_body, split out of deeppurge.sh
  config/
    deeppurge.conf      sections on/off, tuning options (written by WebUI)
  webroot/
    index.html          WebUI (KernelSU `ksu.exec` API)
```
The Termux command stays: `deeppurge` in Termux calls `common/deeppurge.sh` when the module is installed.

## Phases
1. **Repo + script** (done): v10.0 in git, lint CI.
2. **Split the script**: move `tuning_body` and the section functions into files the module can source. Add a non-interactive mode that reads `deeppurge.conf` instead of asking Y/N. Termux output stays the same.
3. **Module skeleton**: `module.prop`, boot scripts that run the existing tuning, `uninstall.sh` = revert. Replaces writing into `/data/adb/*.d/`.
4. **WebUI**: section toggles, tuning toggles, "dry run", "clean now + reboot", status page from `deeppurge_tuning.status`.
5. **Imports** (below), one feature at a time, each checked on the device and dropped if it doesn't apply.

## Candidate imports
Pick only one-shot settings. Skip anything that needs a background loop.

**From AutoSystemBoost (MIT)**
- Network: per-route TCP and qdisc settings, buffers, transmit queues, Wi-Fi scan / power-save settings
- Interface: animation speed, blur, LTPO behaviour
- Battery & sleep: Doze, wakelock and background GPS settings
- WebUI patterns: config.json-driven panels, device_info detection, i18n
- Skip: adaptive profiles, native governor, thermal learning (they need a watcher)

**From HyperCool (GPL-3.0)**
- One-shot kernel tuning at boot (its "extra kernel tuning" panel)
- Battery-drain kernel settings, RAM management settings
- WebUI pattern: "configure, then reboot", which is close to what DeepPurge wants
- Skip: the optional "keepers" (background processes)

For each import: note the source file and commit in the commit message, and keep the original copyright notice.
