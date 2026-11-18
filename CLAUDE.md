# DeepPurge — Project Context

Working context for any AI/dev session on this repo. **The product is the KernelSU module in `module/`.** The Termux script `deeppurge.sh` at the repo root is deprecated: it is kept only for existing users and is not part of the module. Import candidates from ASB/HyperCool: `docs/IMPORTS.md`.

## How to work with me (keep token use low)
- **Never read a whole script.** Use `grep -n` to find the function you need, then read only those lines.
- Make small, targeted edits. Don't rewrite whole sections.
- Before handing back: `shellcheck -S warning -s sh module/*.sh` must be clean and `tools/build-module.sh` must build. If `deeppurge.sh` was touched: `bash -n deeppurge.sh` and `shellcheck -S warning -e SC2034,SC2012,SC2155,SC2059,SC2016 deeppurge.sh`.
- Bump `version=` and `versionCode=` in `module/module.prop` on every release (`10.2` → `1002`).
- Keep replies short: what changed, then one combined command block. I prefer **single command blocks**.

## Device
- OnePlus 15 (CPH2747), ColorOS 17 / Android 17, kernel 6.12.69-android16
- Root: KernelSU fork **ReSukiSU / BakaSU**, ksud 4.2.0
- I also have a Mac with adb, for recovery if something goes wrong

## Goal
A very deep system clean that **keeps app logins**, plus network and kernel tuning, as a module with a WebUI.

## Hard rules (never break)
1. **Nothing on the SD card** is touched (`/sdcard`, `/data/media`).
2. **No whitelist or custom app-set features.**
3. **Never install, uninstall or move apps, and never touch APKs.** No `pm uninstall` anywhere. (Fresh reinstall and kept-data removal were removed in 10.1 as too risky for a public module. In v6 an APK sweep deleted 43 apps' APKs; "such errors are unacceptable".)
4. **App logins and data are kept.** Never delete app data dirs, except section 8's orphaned folders (packages Android has no record of, double-checked, capped).
5. **No `pm art cleanup`.** I run it manually.
6. **Two kinds of clean.** Quick clean: only items safe while Android runs, never reboots. Full clean: everything, always ends with a reboot, and **asks permission before anything changes** (WebUI ticked box → `--reboot-ok`; without it the cleaner exits and changes nothing). A test run (`--dry`) changes nothing and doesn't reboot.
7. Items only rebuilt at boot or held open by running apps are full-clean only: wrap the worker step in `boot_only` and its output line in `bitem`, and keep the section's kind and "left out" text in `SECTIONS` in sync.
8. Everything deleted goes through `empty_dir`/`zap`, so a test run only measures.
9. Don't touch `/data/oplus/os` (battery/auto-start rules), `/data/oplus/multimedia` (weather alert sounds) or `/data/oplus/uxicons` (themed icons). In uxicons, only `temp_u0`, `__MACOSX` and `.DS_Store` may be cleared.
10. I'm OK with some risk ("we can be a bit unsafe"), but nothing that breaks apps.

## Module rules
- **No watcher, loop or daemon.** Boot tuning runs once per pass and exits. The cleaner never runs on its own: only from the WebUI buttons.
- **Standalone.** No Termux, no bash, no knowledge of the old script. Everything is POSIX `sh` (runs with Android's mksh and busybox ash).
- Quick/Full switch → `--mode=`. **All sections** toggle = `--sections=all`; turning it on greys out and turns off the section toggles.
- **Report honestly.** Anything not supported on the device is labelled as such and can't be toggled. Nothing is silently skipped.
- Nothing from ASB/HyperCool is added without being listed in `docs/IMPORTS.md` first and checked on the device.

## Module layout
```
module/module.prop        version (source of truth for releases)
module/cleaner.sh         the cleaner (POSIX sh). Flags: --mode=quick|full, --sections=LIST|all, --dry, --reboot-ok, --revert, --info
module/tuning.sh          boot tuning: one `w PATH VALUE` line per setting
module/post-fs-data.sh    tuning pass 1 (PASS=1)
module/service.sh         tuning pass 2, 20 s after boot_completed (PASS=2), then exits
module/probe.sh           read-only device check for the WebUI
module/action.sh          manager Action button: shows tuning status, never cleans
module/customize.sh       install: permissions only
module/uninstall.sh       removes /data/adb/deeppurge
module/webroot/index.html WebUI (KernelSU ksu.exec)
tools/build-module.sh     → dist/DeepPurge-v<ver>.zip + dist/update.json
```
On the device: `/data/adb/deeppurge/` holds `tuning.status`, `tuning.off`, `webui.conf`, `run.out` and `logs/`. Lock: `/dev/deeppurge.lock`.

**Sections** (`SECTIONS` table and `sec_1`…`sec_10` in `cleaner.sh`):
1. System settings & telemetry (settings + setprops) — live
2. System caches & temp files (`purge_system_caches`) — mixed: package & overlay caches full only
3. App / WebView / GPU caches, ad SDKs (`purge_caches`) — mixed: code_cache full only
4. Browser & in-app web data (`web_scan`/`web_purge`; never closes the app in front, keyboard, launcher, VPN, accessibility, System UI, Phone, Play services) — live
5. Logs & crash reports (`purge_logs`) — live
6. Activity history (`wipe_history`; counters live, `wipe_history_files` full only) — mixed
7. ColorOS & Google telemetry (`purge_telemetry`; Clearcut & Firebase full only) — mixed
8. Uninstalled-app leftovers (`sweep_leftovers`; `pm list -u` + per-package dumpsys check, max 15) — live
9. ART reset & dalvik wipe (`reset_profiles`; per-app `pm compile --reset`, not `-a`, which fails with "Failed transaction") — full only
10. Storage GC & TRIM (`storage_maint`; F2FS gc_urgent loop, `sm fstrim`) — live

A full clean runs `apk_check` before rebooting and **refuses to reboot if any installed app is missing its APK**.

## Network / kernel tuning
- `module/tuning.sh` is applied by `post-fs-data.sh` (PASS=1, start of boot, before network interfaces exist) and `service.sh` (PASS=2, 20 s after boot_completed). The WebUI's Apply now runs PASS=now.
- Every write is read back and recorded in `/data/adb/deeppurge/tuning.status` as `ok`, `FAIL`, `missing` or `off`, with a `boot+Ns` stamp. Pass 1's date reads 1970 because the clock isn't set that early.
- The 9 settings, all confirmed **ok** at both passes on the device (with the Termux version):
  `default_qdisc fq_codel`, `tcp_congestion_control bbr`, `tcp_fastopen 3`, `tcp_mtu_probing 1`, `tcp_slow_start_after_idle 0`, `tcp_notsent_lowat 16384`, `printk "0 0 0 0"`, `vfs_cache_pressure 50`, `tracing_on 0`
- Policy: **whatever doesn't apply gets removed.** `enable_ramdumps` was removed in 10.0 because the kernel lacks it.
- fq_codel only takes effect on an interface when it is first brought up. The active rmnet link stays on Qualcomm's htb by design, and that's accepted. **There is no tc-replacement or watcher logic, and none should be added.**

## Status
v10.1: first module release, not yet tested on the device. The Termux script is deprecated; moving off it (and removing its leftovers) is the user's job. Next: test on the device, then imports from `docs/IMPORTS.md`.

## Releases (GitHub)
Bump `version=`/`versionCode=` in `module/module.prop`, add a `## <version>` section to `CHANGELOG.md`, and push to `main`. The `release` workflow checks the scripts, builds the module, and publishes release `v<version>` with `DeepPurge-v<version>.zip`, `update.json` (the module's update check reads it from the latest release) and the deprecated Termux script. If the tag already exists, it does nothing. CI uploads a test zip on every push.

## Deprecated: Termux script (`deeppurge.sh`, 946 lines)
Kept as is for existing users. Not part of the module and not developed further. It writes its own boot scripts (`/data/adb/post-fs-data.d/99_deeppurge_tuning.sh`, `/data/adb/service.d/99_deeppurge_tuning.sh`, status `/data/adb/deeppurge_tuning.status`) and logs to `~/.deeppurge/`. Don't run it together with the module: both would apply the tuning.
