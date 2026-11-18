# Changelog

Each `## <version>` heading becomes the notes of the GitHub release for that version.

## 10.0
First release on GitHub. Termux script, 12 sections, run as root.

- Network & kernel tuning is written to two boot scripts (pass 1 in `post-fs-data.d`, pass 2 in `service.d` after boot + 20 s). Every setting is read back into `/data/adb/deeppurge_tuning.status`.
- 9 settings, all confirmed `ok` on a OnePlus 15: `fq_codel`, `bbr`, `tcp_fastopen 3`, `tcp_mtu_probing 1`, `tcp_slow_start_after_idle 0`, `tcp_notsent_lowat 16384`, `printk 0 0 0 0`, `vfs_cache_pressure 50`, `tracing_on 0`.
- Removed `enable_ramdumps` (the kernel doesn't have it).
- APK integrity check at the start and before reboot. The reboot is refused if any installed app is missing its APK.
- Flags: `-y`, `--revert`, `--restore`.
