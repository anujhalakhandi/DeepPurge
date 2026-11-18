# DeepPurge

A deep system clean for rooted ColorOS phones that **keeps app logins**, plus network and kernel tuning.

- **Now:** a Termux script (`deeppurge.sh`). It runs as root, asks simple Y/N questions per section, does a test run first, and always reboots at the end.
- **Later:** a KernelSU/Magisk module with a WebUI. The module only *sets things*: one-shot boot scripts, no watcher or daemon. See [docs/ROADMAP.md](docs/ROADMAP.md).

Built and tested on a OnePlus 15 (CPH2747), ColorOS 17 / Android 17, with ReSukiSU (KernelSU fork).

## What it never touches
- Shared storage (`/sdcard`, `/data/media`)
- Installed APKs (`/data/app`). The reboot is refused if any installed app is missing its APK.
- App databases, shared_prefs, cookies or sign-ins (except the verified, opt-in sections 9 and 10)
- `/data/oplus/os`, `/data/oplus/multimedia`, `/data/oplus/uxicons`

## Sections
| # | Section |
|---|---|
| 1 | System settings & telemetry props |
| 2 | Network & kernel tuning (boot scripts, read-back status) |
| 3 | System caches & temp files |
| 4 | App / WebView / GPU caches, ad SDKs |
| 5 | Browser & in-app web data |
| 6 | Logs & crash reports |
| 7 | Activity history |
| 8 | ColorOS & Google telemetry |
| 9 | Uninstalled-app leftovers (verified, capped) |
| 10 | Fresh reinstall from Play (opt-in, data kept) |
| 11 | ART reset & dalvik wipe |
| 12 | Storage GC & TRIM |

## Install (Termux)
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

Flags: `-y` does a full run with no questions. `--revert` undoes the tuning and props and removes the boot scripts. `--restore` reinstalls the apps on the pending list.

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
