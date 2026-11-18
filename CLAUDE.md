# DeepPurge — Project Context

Working context for any AI/dev session on this repo. The script is `deeppurge.sh` at the repo root and is also the module's cleaner engine. Module source: `module/` (layout in `docs/ROADMAP.md`). Import candidates from ASB/HyperCool: `docs/IMPORTS.md`.

## How to work with me (keep token use low)
- **Never read the whole script.** Use `grep -n` to find the function you need, then read only those lines.
- Make small, targeted edits. Don't rewrite whole sections.
- Before handing back, check the file: `bash -n deeppurge.sh` must pass, and `shellcheck -S warning -e SC2034,SC2012,SC2155,SC2059,SC2016 deeppurge.sh` must be clean. Module scripts: `shellcheck -S warning -s sh module/*.sh`. Build: `tools/build-module.sh`.
- Bump `VERSION=` and the header line on every release, and tell me the new line count (`wc -l`). The install command below prints it so I can confirm.
- Keep replies short: what changed, then one combined command block. I prefer **single command blocks**.

## Device
- OnePlus 15 (CPH2747), ColorOS 17 / Android 17, kernel 6.12.69-android16
- Root: KernelSU fork **ReSukiSU / BakaSU**, ksud 4.2.0. Boot scripts go in `/data/adb/post-fs-data.d/` and `/data/adb/service.d/`
- The script runs in **Termux** as root (`exec su -c`), with `PATH=/system/bin` first (toybox)
- I also have a Mac with adb, for recovery if something goes wrong

## Goal
A very deep system clean that **keeps app logins**, plus network and kernel tuning. Modular sections with simple Y/N questions. A test run comes first. Professional ALL-CAPS Termux output. **The phone always reboots at the end.** I reboot in airplane mode, then turn data/Wi-Fi back on.

## Hard rules (never break)
1. **Nothing on the SD card** is touched (`/sdcard`, `/data/media`).
2. **No whitelist or custom app-set features.**
3. **App logins and data are kept.** Never delete app data dirs, except in sections 9 and 10, which are verified and opt-in.
4. **Never remove or move APKs.** In v6 an APK sweep deleted 43 apps' APKs; recovering them took adb. "Such errors are unacceptable."
5. Fresh reinstall must **keep ReSukiSU, Morphe and Termux** (not on Play Store).
6. **No `pm art cleanup`.** I run it manually.
7. **No no-reboot option.** Always reboot. (A test run, `--dry`, changes nothing and doesn't reboot.)
8. Fresh reinstall is asked **once, at the start** (typed YES).
9. Everything deleted goes through `empty_dir`/`zap`, so a test run (DRY=1) only measures.
10. Don't touch `/data/oplus/os` (battery/auto-start rules), `/data/oplus/multimedia` (weather alert sounds) or `/data/oplus/uxicons` (themed icons). In uxicons, only `temp_u0`, `__MACOSX` and `.DS_Store` may be cleared.
11. I'm OK with some risk ("we can be a bit unsafe"), but nothing that breaks apps.

## Module rules
- **No watcher, loop or daemon.** Boot tuning runs once per pass and exits. The cleaner never runs on its own: only from the WebUI buttons or Termux.
- **Full deep clean** toggle = `--sections=all`. Turning it on greys out and turns off the section toggles.
- Fresh reinstall in the WebUI needs a typed YES for each run and is never saved.
- **Report honestly.** Anything not supported on the device is labelled as such and can't be toggled. Nothing is silently skipped.
- Nothing from ASB/HyperCool is added without being listed in `docs/IMPORTS.md` first and checked on the device.

## Script structure (v10.1, 1153 lines)
- The whole script is wrapped in `{ … exit 0 }`, so replacing the file mid-run is safe. Single-instance lock at `/dev/deeppurge.lock`. Installs are atomic (`.new` + `mv`).
- The ALL-CAPS `printf` wrapper only applies on a tty. The log is unaffected.
- Flags: `--revert` (undo tuning and props, remove boot scripts; with the module, turns its tuning off), `--restore` (reinstall apps on the pending list). Non-interactive (WebUI): `--sections=LIST|all`, `--dry`, `--fresh-yes`, `--fresh-list`.
- Module mode (`/data/adb/modules/deeppurge` present and enabled): `install_tuning` writes `$MOD_DIR/tuning.sh` instead of the `*.d` scripts. Settings turned off in the WebUI are listed in `/data/adb/deeppurge/tuning.off`, and `w` records them as `off`.
- APK integrity check at the start, and again before reboot. **The reboot is refused if any installed app is missing its APK.**
- Logs: `$HOME/.deeppurge/*.log`. Pending reinstall list: `$HOME/.deeppurge/restore_pending.list`.

**Sections** (functions `sec_1`…`sec_12`):
1. System settings & telemetry (setprops, including the ssr ramdump props)
2. Network & kernel tuning (`tuning_body`, `install_tuning`)
3. System caches & temp files (`purge_system_caches`)
4. App / WebView / GPU caches, ad SDKs, Termux caches (`purge_caches`)
5. Browser & in-app web data (`web_scan`/`web_purge`; closes apps except protected ones)
6. Logs & crash reports (`purge_logs`; includes ColorOS powermonitor_backup, bsp_kevent, mmdump)
7. Activity history (`wipe_history`; usagestats, ColorOS power history, stat resets)
8. ColorOS & Google telemetry (`purge_telemetry`; DCS, statsd, Clearcut, Firebase)
9. Uninstalled-app leftovers (`sweep_leftovers`; verified with `pm list -u` and a per-package dumpsys check, max 15)
10. Fresh reinstall from Play (`fresh_scan`/`fresh_purge`; opt-in, data kept)
11. ART reset & dalvik wipe (`reset_profiles`; per-app `pm compile --reset`, not `-a`, which fails with "Failed transaction")
12. Storage GC & TRIM (`storage_maint`; F2FS gc_urgent loop, `sm fstrim`)

Other functions: `fresh_prompt`, `run_sections`, `print_summary`, `apk_check`, `cleanup`.

## Network / kernel tuning
- One `tuning_body` is the single source. With the module, it's the module's `tuning.sh` (generated by `tools/build-module.sh`, rewritten by section 2), run by `post-fs-data.sh` (PASS=1) and `service.sh` (PASS=2). Without the module, it's written to two boot scripts:
  - `/data/adb/post-fs-data.d/99_deeppurge_tuning.sh` (PASS=1, at the very start of boot)
  - `/data/adb/service.d/99_deeppurge_tuning.sh` (PASS=2, after boot_completed + `BOOT_DELAY=20`s; `--now` applies immediately)
- Every write is read back and recorded in `/data/adb/deeppurge_tuning.status` as `ok`, `FAIL` or `missing`, with a `boot+Ns` stamp. Pass 1's date reads 1970 because the clock isn't set that early.
- The 9 settings, all confirmed **ok** at both passes on the device:
  `default_qdisc fq_codel`, `tcp_congestion_control bbr`, `tcp_fastopen 3`, `tcp_mtu_probing 1`, `tcp_slow_start_after_idle 0`, `tcp_notsent_lowat 16384`, `printk "0 0 0 0"`, `vfs_cache_pressure 50`, `tracing_on 0`
- Policy: **whatever doesn't apply gets removed.** `enable_ramdumps` was removed in 10.0 because the kernel lacks it.
- fq_codel only takes effect on an interface when it is first brought up. The active rmnet link stays on Qualcomm's htb by design, and that's accepted. **There is no tc-replacement or watcher logic, and none should be added.**

## Install / check commands (Termux)
Save the file to Download first, then:
```
su -c 'cat /sdcard/Download/deeppurge.sh' > "$PREFIX/bin/deeppurge.new" && bash -n "$PREFIX/bin/deeppurge.new" && chmod 755 "$PREFIX/bin/deeppurge.new" && mv -f "$PREFIX/bin/deeppurge.new" "$PREFIX/bin/deeppurge" && echo "✓ INSTALLED — $(wc -l < "$PREFIX/bin/deeppurge") LINES"
```
After a change to tuning, run section 2 once so the boot scripts are rewritten.
Check tuning after a reboot: `su -c 'cat /data/adb/deeppurge_tuning.status'`

## Status
v10.0 (Termux) is installed and working. v10.1 adds the module and WebUI and hasn't been tested on the device yet. Next: test it on the device, then imports from `docs/IMPORTS.md`. Follow the rules above.

## Releases (GitHub)
Bump `VERSION=` and the header line, add a `## <version>` section to `CHANGELOG.md`, and push to `main`. The `release` workflow checks the scripts, builds the module, and publishes release `v<version>` with `deeppurge.sh`, its SHA-256, `DeepPurge-v<version>.zip` and `update.json` (the module's update check reads it from the latest release). If the tag already exists, it does nothing.
