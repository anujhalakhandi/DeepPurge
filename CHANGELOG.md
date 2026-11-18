# Changelog

Each `## <version>` heading becomes the notes of the GitHub release for that version.

## 10.2
**WebUI**
- Two tabs: **Optimizer** (boot tuning, grouped, with an "n of N tweaks on" summary and a Reset) and **Cleaner** (Quick or Full). Cleaner gets bigger mode cards and a cleaner layout.
- The 10 section toggles and the "All sections" switch are gone. You pick Quick clean or Full clean; each runs every section it can.
- One Stop button and one Close button under the output. Close is greyed out and can't be pressed while a command runs; Stop is only active while one runs.

**New tuning** (from HyperCool and AutoSystemBoost; anything the kernel lacks shows as Not supported)
- Memory write-back: `dirty_writeback_centisecs`, `dirty_expire_centisecs` 6000, `dirty_background_ratio` 20, `dirty_ratio` 40, `stat_interval` 60.
- Quiet kernel debug: `printk_devkmsg off`, `sched_schedstats 0`, `nmi_watchdog 0`, `perf_cpu_time_max_percent 2`, `exception-trace 0`.

**Section 1 now also sets** (and Revert removes): network power saving (`mobile_data_always_on 0`, `network_recommendations_enabled 0`, `wifi_wakeup_enabled 0`) and telemetry switches (watchlist, tron, gmscorestat, clearcut, analytics, uploading, ga_collection off; `limit_ad_tracking 1`). Wi-Fi and Bluetooth scanning are left as they are.

## 10.1
First release of the **DeepPurge module** for KernelSU, with a WebUI. It works on its own: no Termux, no bash, only the phone's built-in shell.

**Boot tuning**
- A toggle for each network/kernel setting. Applied once at boot start and again 20 s after boot. Nothing runs in the background.
- Each setting shows whether it was applied at the last boot. Settings the kernel doesn't support are labelled **Not supported** and can't be toggled.

**Two kinds of clean**
- **Quick clean**: only what is safe while the phone is running. No reboot. What it leaves out is listed as "full clean only".
- **Full clean**: everything, then a reboot. It needs a ticked "I understand the phone will reboot" box before it starts, and it still refuses to reboot if any installed app is missing its APK.
- **All sections** toggle (greys out the section toggles), Test run, live output with Stop, and Revert.
- The cleaner never runs on its own. The manager's Action button only shows the tuning status.

**Removed**
- Everything that uninstalls apps: Fresh reinstall, the reinstall list, and removal of apps uninstalled with their data kept. DeepPurge never runs `pm uninstall`.

**Termux script: deprecated**
- `deeppurge.sh` is no longer developed and isn't part of the module. It stays attached to releases for existing users. See the README for how to remove it and its leftovers.

## 10.0
First release on GitHub. Termux script, 12 sections, run as root.

- Network & kernel tuning is written to two boot scripts (pass 1 in `post-fs-data.d`, pass 2 in `service.d` after boot + 20 s). Every setting is read back into `/data/adb/deeppurge_tuning.status`.
- 9 settings, all confirmed `ok` on a OnePlus 15: `fq_codel`, `bbr`, `tcp_fastopen 3`, `tcp_mtu_probing 1`, `tcp_slow_start_after_idle 0`, `tcp_notsent_lowat 16384`, `printk 0 0 0 0`, `vfs_cache_pressure 50`, `tracing_on 0`.
- Removed `enable_ramdumps` (the kernel doesn't have it).
- APK integrity check at the start and before reboot. The reboot is refused if any installed app is missing its APK.
- Flags: `-y`, `--revert`, `--restore`.
