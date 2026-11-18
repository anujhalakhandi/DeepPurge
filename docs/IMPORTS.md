# Import candidates: AutoSystemBoost & HyperCool

**Imported in 10.2** (still to be confirmed on the device): the memory write-back lines and the quiet-debug lines (table A, except mini ramdumps, debugfs tracing and the ASB per-profile values), network power saving and telemetry switches (table C). Background Wi-Fi/BLE scanning is deliberately left as it is. The rest of this list is not in DeepPurge yet. It lists what we **could** add with small, direct changes, checked against the two projects' source:

- **AutoSystemBoost (ASB)** by Dima Krylov, MIT
- **HyperCool (HC)** by Yudharn, GPL-3.0

## Rules for importing
- **One-shot only.** Each item is written once, at boot or in a cleaner section. No loops, watchers or keepers.
- **Read it back and report it.** Every write is checked. On the device it shows as `ok`, `FAIL` or `missing`. A setting this kernel or ROM doesn't have is shown as **Not supported** in the WebUI and can't be toggled.
- **Whatever doesn't apply gets removed.** If an item is `missing` or `FAIL` on the OnePlus 15, it is dropped, not kept "just in case".
- **Credit the source.** Each import names the source project and file in the commit message.
- Values below are the source project's defaults. Check each one on the device before shipping it.

---

## A. One line in boot tuning (easiest)
Add a `w PATH VALUE` line to `module/tuning.sh`. The WebUI then shows it with its own toggle and a supported/unsupported label. No other code changes are needed (add a friendly name in `TUNE_LABEL` in `module/webroot/index.html` if you like).

| Item | Path = value | From | Notes |
|---|---|---|---|
| Writeback interval 60 s | `/proc/sys/vm/dirty_writeback_centisecs` = `6000` | HC `vm_tune` | Fewer flash wake-ups |
| Dirty expiry 60 s | `/proc/sys/vm/dirty_expire_centisecs` = `6000` | HC `vm_tune` | Pairs with the line above |
| Dirty background ratio | `/proc/sys/vm/dirty_background_ratio` = `20` | HC `vm_tune` | ASB tunes `dirty_bytes` instead; pick one approach |
| Dirty ratio | `/proc/sys/vm/dirty_ratio` = `40` | HC `vm_tune` | |
| VM stats every 60 s | `/proc/sys/vm/stat_interval` = `60` | HC `vm_tune` | |
| /dev/kmsg writes off | `/proc/sys/kernel/printk_devkmsg` = `off` | HC `debug_off`, ASB | Matches our quiet-printk setting |
| Scheduler stats off | `/proc/sys/kernel/sched_schedstats` = `0` | HC `debug_off`, ASB | |
| NMI watchdog off | `/proc/sys/kernel/nmi_watchdog` = `0` | HC `debug_off` | Often missing on arm64 phones; then it's dropped |
| Perf sampling cap 2 % | `/proc/sys/kernel/perf_cpu_time_max_percent` = `2` | HC `debug_off` | |
| Exception trace off | `/proc/sys/debug/exception-trace` = `0` | HC `debug_off` | |
| Mini ramdumps off | `/sys/module/subsystem_restart/parameters/enable_mini_ramdumps` = `0` | HC `debug_off` | `enable_ramdumps` was missing on this kernel (removed in 10.0), so this one probably is too |
| Debugfs tracing off | `/sys/kernel/debug/tracing/tracing_on` = `0` | HC `debug_off` | Only if debugfs is mounted |
| Sched autogroup | `/proc/sys/kernel/sched_autogroup_enabled` = `0` or `1` | ASB kernel controls | ASB picks it per profile; choose one value |
| Child runs first | `/proc/sys/kernel/sched_child_runs_first` = `0` or `1` | ASB kernel controls | Same |
| hrtimer migration | `/proc/sys/kernel/hrtimer_migration` = `0` or `1` | ASB kernel controls | Same; often missing |
| MGLRU min TTL | `/sys/kernel/mm/lru_gen/min_ttl_ms` = value | ASB kernel controls | Only with MGLRU kernels |
| TCP keepalive | `/proc/sys/net/ipv4/tcp_keepalive_time` = value | ASB `asb_lpm.sh` | ASB changes it with screen state; we'd set one fixed value |

## B. Boot tuning, but needs a small helper (a few lines)

| Item | What | From | The small change |
|---|---|---|---|
| Block I/O stats off | `queue/iostats` = `0` and `queue/add_random` = `0` on `/sys/block/sd*`, `dm-*` | HC `io_tune` | `w` takes one path; add a loop over the block devices that calls `w` for each one |
| Clear driver debug masks | every `/sys/module/*/parameters/debug_mask` that isn't 0 → `0` | HC `debug_off` | Same loop pattern. Record the count, not every path |
| Runtime debug props | `debug.sf.*`, `log.*`, `persist.logd.size`, `ro.lmk.debug=false` … (HC `x_props.txt`, ASB `asb_log_apply.sh`) | HC, ASB | Add a `p PROP VALUE` helper next to `w` (`resetprop -n`, read back with `getprop`). Runtime only, so it's applied every boot like the sysctls |

## C. One-shot settings in a cleaner section (section 1 style)
Add `settings put …` lines to `sec_1` in `module/cleaner.sh` (safe in a quick clean), and the matching `settings delete …` lines to its `--revert` block. These persist, so there's nothing to do at boot.

| Item | Settings | From | Notes |
|---|---|---|---|
| Background scanning off | `global wifi_scan_always_enabled 0`, `global ble_scan_always_enabled 0`, `global wifi_scan_throttle_enabled 1` | HC `scan_off`, ASB | Android 12+ also needs `cmd wifi set-scan-always-available disabled`; read it back with `cmd wifi status` |
| Network power saving | `global mobile_data_always_on 0`, `global network_recommendations_enabled 0`, `global wifi_wakeup_enabled 0` | HC `net_save` | Mobile data no longer kept alive on Wi-Fi |
| Avoid bad Wi-Fi | `global network_avoid_bad_wifi 1` | ASB net apply | |
| Telemetry switches | `global network_watchlist_enabled / tron_enabled / gmscorestat_enabled / clearcut_enabled / analytics_enabled / uploading_enabled / ga_collection_enabled 0`, `global limit_ad_tracking 1` | HC `tracking_off` | Fits section 7 (telemetry). Only apps that read these keys react |
| Less stats collection | `global looper_stats enabled=false`, `global binder_calls_stats …`, `global battery_stats_constants …` | HC `stats_reduce` | `device_config` parts can be reset by the server's flag sync; leave those out |
| App standby enforced | `global app_standby_enabled 1`, `adaptive_battery_management_enabled 1`, `forced_app_standby_enabled 1`, `app_auto_restriction_enabled 1` | HC `standby` | Mostly the stock values; check before adding |
| Background location throttle | `global location_background_throttle_interval_ms` = 1/2/4 h | HC `loc_throttle` | Would need a choice in the WebUI (one value is simpler) |
| Blur off | `global disable_window_blurs 1` | ASB blur | Visible UI change; ColorOS has its own blur path, so check it on the device |

---

## Already covered by DeepPurge
- BBR, fq_codel, Fast Open, MTU probing, notsent_lowat, quiet printk, tracing off: boot tuning
- Animation scale, phantom-process limit, error/debug reports off: section 1
- Junk and cache cleanup (HC `cache_clean.sh`, ASB `asb_junk_cleanup.sh`): sections 2–5
- F2FS GC and TRIM (HC `f2gc.sh`): section 10, run once instead of on a schedule
- Ramdump props: section 1. The `enable_ramdumps` sysfs node was removed in 10.0 (missing on this kernel)
- Anything a candidate adds to a cleaner section must say whether it is safe without a reboot (quick clean) or full-clean only (`boot_only`)

## Not suitable (needs a watcher or big code changes)
These stay out because they need a loop, a daemon or per-SoC tables:
- CPU/GPU frequency caps and locks, prime-core parking, WALT tuning (HC heat control): per-SoC tables, and ROM services fight them
- Screen-off profiles, radio/data/Wi-Fi keepers, charge limits, battery calibration (HC keepers)
- Weekly F2FS GC / dexopt schedulers (HC `f2gc.sh`, `dxauto.sh`)
- Adaptive profiles, native governor, Smart learning, thermal envelopes (ASB core)
- Per-interface `tc` qdisc replacement (ASB net apply). DeepPurge deliberately doesn't do this
- DSP, camera, LTPO, haptics, Bluetooth audio (ASB)
- App freezing, background blocking, debloat lists (HC). These conflict with DeepPurge's no-app-set rule
