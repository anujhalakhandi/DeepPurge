# Changelog

Each `## <version>` heading becomes the notes of the GitHub release for that version.

## 10.1
**Two kinds of clean**
- **Quick clean**: only what is safe while the phone is running. No reboot. Items that are rebuilt at boot or held open by running apps are left out and listed as "full clean only".
- **Full clean**: everything, then a reboot. It now asks for permission first: in Termux you're asked before anything changes, and the WebUI needs a ticked "I understand the phone will reboot" box. Non-interactive runs need `--reboot-ok`, otherwise nothing is changed.

**Removed: everything that uninstalls apps**
- Fresh reinstall (old section 10), `--restore` and the reinstall list are gone.
- Section 9 no longer removes apps that were uninstalled with their data kept. It only removes folders Android has no record of (double-checked, capped).
- DeepPurge never runs `pm uninstall`. Sections are now 1–11: ART reset is 10, Storage GC & TRIM is 11.

**KernelSU module with a WebUI (first release)**
- Boot tuning with a toggle for each setting. It's applied once at boot start and again 20 s after boot, and nothing runs in the background. Each setting shows if it was applied at the last boot. Unsupported ones are labelled **Not supported** and can't be toggled.
- Quick/Full switch, an **All sections** toggle that greys out the section toggles, Test run, live output with Stop, and Revert.
- In a quick clean, ART reset is shown as "needs a reboot" and can't be selected. Partly-quick sections say what they leave out.
- The cleaner never runs on its own. The manager's Action button only shows the tuning status.

**Script**
- Flags: `--mode=quick|full`, `--sections=LIST|all`, `--dry`, `--reboot-ok`; `-y` = full clean of every section with reboot permission. Unknown flags are refused.
- With the module installed, section 2 updates the module's tuning instead of the standalone boot scripts, and `--revert` turns the module's tuning off.
- Plain output when there's no terminal. Logs go to `/data/adb/deeppurge/logs` without Termux.
- Code cleanup: 1071 → 970 lines.

## 10.0
First release on GitHub. Termux script, 12 sections, run as root.

- Network & kernel tuning is written to two boot scripts (pass 1 in `post-fs-data.d`, pass 2 in `service.d` after boot + 20 s). Every setting is read back into `/data/adb/deeppurge_tuning.status`.
- 9 settings, all confirmed `ok` on a OnePlus 15: `fq_codel`, `bbr`, `tcp_fastopen 3`, `tcp_mtu_probing 1`, `tcp_slow_start_after_idle 0`, `tcp_notsent_lowat 16384`, `printk 0 0 0 0`, `vfs_cache_pressure 50`, `tracing_on 0`.
- Removed `enable_ramdumps` (the kernel doesn't have it).
- APK integrity check at the start and before reboot. The reboot is refused if any installed app is missing its APK.
- Flags: `-y`, `--revert`, `--restore`.
