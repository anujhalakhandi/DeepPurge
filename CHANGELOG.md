# Changelog

Each `## <version>` heading becomes the notes of the GitHub release for that version.

## 10.1
First release of the **KernelSU module with a WebUI**. The Termux script works as before.

**Module**
- Boot tuning with a toggle for each setting. Applied once at boot start and again 20 s after boot. Nothing runs in the background.
- Each setting shows if it was applied at the last boot. Settings the kernel doesn't support are labelled **Not supported** and can't be toggled.
- Cleaner sections as toggles. **Full deep clean** greys out and turns off the other toggles. Test run (no reboot) and Run & reboot. Fresh reinstall needs a typed YES for each run.
- Live output, a Stop button, the reinstall list with Play Store links, and Revert.
- The cleaner never runs on its own. The manager's Action button only shows the tuning status.

**Script**
- New flags for the WebUI (they work in Termux too): `--sections=LIST|all`, `--dry`, `--fresh-yes`, `--fresh-list`.
- When the module is installed, section 2 updates the module's tuning instead of writing the standalone boot scripts, and `--revert` turns the module's tuning off.
- Plain output when there's no terminal: no spinner, no screen clearing.
- Logs go to `/data/adb/deeppurge/logs` if Termux isn't installed.

## 10.0
First release on GitHub. Termux script, 12 sections, run as root.

- Network & kernel tuning is written to two boot scripts (pass 1 in `post-fs-data.d`, pass 2 in `service.d` after boot + 20 s). Every setting is read back into `/data/adb/deeppurge_tuning.status`.
- 9 settings, all confirmed `ok` on a OnePlus 15: `fq_codel`, `bbr`, `tcp_fastopen 3`, `tcp_mtu_probing 1`, `tcp_slow_start_after_idle 0`, `tcp_notsent_lowat 16384`, `printk 0 0 0 0`, `vfs_cache_pressure 50`, `tracing_on 0`.
- Removed `enable_ramdumps` (the kernel doesn't have it).
- APK integrity check at the start and before reboot. The reboot is refused if any installed app is missing its APK.
- Flags: `-y`, `--revert`, `--restore`.
