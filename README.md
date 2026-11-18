# DeepPurge

A deep system clean for rooted ColorOS phones that **keeps app logins**, plus network and kernel tuning.

Two ways to use it, same engine:
- **Termux script** (`deeppurge.sh`). Runs as root, asks simple Y/N questions, and offers a test run first.
- **KernelSU module with a WebUI.** Boot tuning with a toggle per setting, and the cleaner sections as toggles. Nothing runs in the background, and the cleaner never runs on its own. See [Module](#module).

Built and tested on a OnePlus 15 (CPH2747), ColorOS 17 / Android 17, with ReSukiSU (KernelSU fork).

## Quick clean or full clean
- **Quick clean**: only what is safe while the phone is running. No reboot.
- **Full clean**: everything, including caches that are only rebuilt at boot (package, overlay, app code, dalvik). It always ends with a reboot, and asks for your permission before it starts.

## What it never touches
- Apps: DeepPurge never installs, uninstalls or moves an app
- Shared storage (`/sdcard`, `/data/media`)
- Installed APKs (`/data/app`). Before a full clean reboots, every app is checked; the reboot is refused if any app is missing its APK.
- App databases, shared_prefs, cookies or sign-ins. Section 9 only removes data folders of packages Android has no record of at all (double-checked, capped).
- `/data/oplus/os`, `/data/oplus/multimedia`, `/data/oplus/uxicons`

## Sections
| # | Section | Quick clean |
|---|---|---|
| 1 | System settings & telemetry props | ✓ |
| 2 | Network & kernel tuning (boot scripts, read-back status) | ✓ |
| 3 | System caches & temp files | ✓ except package & overlay caches |
| 4 | App / WebView / GPU caches, ad SDKs | ✓ except app code caches |
| 5 | Browser & in-app web data | ✓ |
| 6 | Logs & crash reports | ✓ |
| 7 | Activity history | counters only; history files need a reboot |
| 8 | ColorOS & Google telemetry | ✓ except Clearcut & Firebase queues |
| 9 | Uninstalled-app leftovers (verified, capped) | ✓ |
| 10 | ART reset & dalvik wipe | ✗ full clean only |
| 11 | Storage GC & TRIM | ✓ |

## Module
Download **DeepPurge-v….zip** from the [latest release](https://github.com/anujhalakhandi/DeepPurge/releases/latest) and install it in your root manager (KernelSU / ReSukiSU). Reboot, then open the module's WebUI.

- **Boot tuning**: each network/kernel setting has its own toggle. They're applied once at the start of boot and again 20 s after it, then nothing runs. Each one shows whether it was applied at the last boot. A setting your kernel doesn't have is shown as **Not supported** and can't be turned on.
- **Clean**: pick **Quick clean** or **Full clean**, then **All sections** (greys out and turns off the section toggles) or the sections you want. **Test run** measures only. A full clean asks you to confirm the reboot before it starts.
- **Revert** puts section 1 settings back to stock and turns all tuning off. Use it before uninstalling.
- The cleaner needs Termux installed: it runs with Termux's `bash`. Without Termux, only the boot tuning works, and the WebUI says so.
- Installing the module removes the old standalone boot scripts in `/data/adb/post-fs-data.d/` and `/data/adb/service.d/`, because the module applies the tuning now.

## Install the Termux script
1. On the phone, download **[deeppurge.sh](https://github.com/anujhalakhandi/DeepPurge/releases/latest/download/deeppurge.sh)** from the latest release. It saves to the `Download` folder. If an older copy is there, delete it first, so the browser doesn't save it as `deeppurge (1).sh`.
2. Open Termux and paste:
```bash
su -c 'cat /sdcard/Download/deeppurge.sh' > "$PREFIX/bin/deeppurge.new" && bash -n "$PREFIX/bin/deeppurge.new" && chmod 755 "$PREFIX/bin/deeppurge.new" && mv -f "$PREFIX/bin/deeppurge.new" "$PREFIX/bin/deeppurge" && echo "✓ INSTALLED — $(wc -l < "$PREFIX/bin/deeppurge") LINES"
```
   It prints the line count. Compare it with the number in the release notes.
3. Run it:
```bash
deeppurge
```

Updating works the same way: download the new `deeppurge.sh`, then paste the command from step 2 again.

Flags: `--mode=quick` runs a quick clean with no questions. `-y` runs a full clean with no questions, including the reboot. `--revert` undoes the tuning and props and removes the boot scripts. See `deeppurge --help`.

Check the tuning after a reboot:
```bash
su -c 'cat /data/adb/deeppurge_tuning.status'
```

## Credits
Future versions will bring in ideas and code from:
- [AutoSystemBoost](https://github.com/krilikd-factory/AutoSystemBoost) by Dima Krylov (MIT)
- [HyperCool](https://github.com/yudharn/HyperCool) by Yudharn (GPL-3.0)

## License
GPL-3.0. See [LICENSE](LICENSE). This keeps the door open to reuse HyperCool's GPL-3.0 code, and MIT code from AutoSystemBoost can be included under it with its notice kept.

> Use at your own risk. Keep adb access (or a computer) at hand for recovery.
