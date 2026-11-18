# DeepPurge

A KernelSU module that deep-cleans rooted ColorOS phones while **keeping app logins**, plus network and kernel tuning. Everything is set from a WebUI. Nothing runs in the background, and the cleaner never runs on its own.

Built and tested on a OnePlus 15 (CPH2747), ColorOS 17 / Android 17, with ReSukiSU (KernelSU fork).

## Install
1. Download **DeepPurge-v….zip** from the [latest release](https://github.com/anujhalakhandi/DeepPurge/releases/latest).
2. Install it in your root manager (KernelSU / ReSukiSU) and reboot.
3. Open the module's WebUI.

No other app is needed. The module uses only the phone's built-in shell.

## Boot tuning
Each network/kernel setting has its own toggle. They're applied once at the start of boot and again 20 s after it, then nothing runs. Each one shows whether it was applied at the last boot. A setting your kernel doesn't have is shown as **Not supported** and can't be turned on.

| Setting | Value |
|---|---|
| Packet queue | fq_codel |
| TCP congestion control | BBR |
| TCP Fast Open | 3 |
| MTU probing | 1 |
| Slow start after idle | off |
| TCP notsent_lowat | 16 KB |
| Kernel console log | quiet |
| vfs_cache_pressure | 50 |
| Kernel tracing | off |

## Cleaning: quick or full
- **Quick clean**: only what is safe while the phone is running. No reboot.
- **Full clean**: everything, including caches that are only rebuilt at boot. It always ends with a reboot, and you must tick "I understand the phone will reboot" before it starts.

Pick **All sections** (greys out and turns off the section toggles) or the sections you want. **Test run** measures what would be freed and changes nothing.

| # | Section | Quick clean |
|---|---|---|
| 1 | System settings & telemetry | ✓ |
| 2 | System caches & temp files | ✓ except package & overlay caches |
| 3 | App / WebView / GPU caches, ad SDKs | ✓ except app code caches |
| 4 | Browser & in-app web data | ✓ |
| 5 | Logs & crash reports | ✓ |
| 6 | Activity history | counters only; history files need a reboot |
| 7 | ColorOS & Google telemetry | ✓ except Clearcut & Firebase queues |
| 8 | Uninstalled-app leftovers (verified, capped) | ✓ |
| 9 | ART reset & dalvik wipe | ✗ full clean only |
| 10 | Storage GC & TRIM | ✓ |

**Revert** puts section 1 settings back to stock and turns all tuning off. Use it before uninstalling.

## What it never touches
- Apps: DeepPurge never installs, uninstalls or moves an app, and never touches APKs (`/data/app`)
- Shared storage (`/sdcard`, `/data/media`)
- App databases, shared_prefs, cookies or sign-ins. Section 8 only removes data folders of packages Android has no record of at all (double-checked, capped).
- ColorOS battery rules (`/data/oplus/os`), weather alert sounds and themed icons

Before a full clean reboots, every installed app is checked; the reboot is refused if any app is missing its APK.

## The old Termux script (deprecated)
`deeppurge.sh` in this repo is the old Termux version. It's no longer developed and isn't part of the module. Don't use both: they would both apply the tuning. To remove the old script and everything it left behind, run this in Termux. The first command puts its settings back to stock, so skip it if you're keeping those settings through the module:
```bash
deeppurge --revert; su -c 'rm -f /data/adb/post-fs-data.d/99_deeppurge_tuning.sh /data/adb/post-fs-data.d/99_deeppurge_net.sh /data/adb/service.d/99_deeppurge_tuning.sh /data/adb/service.d/98_deeppurge_once.sh /data/adb/deeppurge_tuning.status /dev/deeppurge.lock' && rm -rf "$HOME/.deeppurge" && rm -f "$PREFIX/bin/deeppurge" "$PREFIX/bin/deeppurge.new" && echo "✓ OLD DEEPPURGE REMOVED — REBOOT"
```

## Credits
Future versions may bring in ideas and code from:
- [AutoSystemBoost](https://github.com/krilikd-factory/AutoSystemBoost) by Dima Krylov (MIT)
- [HyperCool](https://github.com/yudharn/HyperCool) by Yudharn (GPL-3.0)

See [docs/IMPORTS.md](docs/IMPORTS.md).

## License
GPL-3.0. See [LICENSE](LICENSE). This keeps the door open to reuse HyperCool's GPL-3.0 code, and MIT code from AutoSystemBoost can be included under it with its notice kept.

> Use at your own risk. Keep adb access (or a computer) at hand for recovery.
