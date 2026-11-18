#!/system/bin/sh
# DeepPurge cleaner. Started from the WebUI only, never at boot.
#
#   cleaner.sh --mode=quick [--sections=LIST|all] [--dry]               quick clean, no reboot
#   cleaner.sh --mode=full  [--sections=LIST|all] [--dry] [--reboot-ok]  full clean, then reboot
#   cleaner.sh --revert                                                  settings & tuning back to stock
#   cleaner.sh --info                                                    section table for the WebUI
#
# Quick clean: only what is safe while Android is running.
# Full clean:  everything, including caches rebuilt at boot. Always ends with a
#              reboot and refuses to start without --reboot-ok (the WebUI asks first).
#
# Safety rules:
#  • Never installs, uninstalls or moves apps, and never touches APKs (/data/app),
#    shared storage (/sdcard, /data/media), ColorOS battery rules (/data/oplus/os),
#    or any app's databases, shared_prefs, no_backup or sign-in data.
#  • Every deletion goes through empty_dir / zap, so a test run (--dry) only measures.
#  • Leftover app data is removed only when Android has no record of the package,
#    double-checked per package, with a hard cap.
#  • A full clean refuses to reboot if any installed app is missing its APK.
#
# POSIX sh: runs with Android's /system/bin/sh and the root manager's busybox.

MODDIR=${0%/*}
CONF=/data/adb/deeppurge
LOG_DIR=$CONF/logs
LOCK=/dev/deeppurge.lock
GC_MAX_SECONDS=300   # F2FS urgent GC stops when done, stalled, or after this long
LEFTOVER_CAP=15      # more leftover folders than this means something is off: remove none

# number|kind|title|what it cleans|what a quick clean leaves out
# kind: live = all of it works without a reboot · mixed = part of it needs a full clean · reboot = full clean only
SECTIONS='1|live|System settings & telemetry|animations 0.85×, debug & telemetry toggles off|
2|mixed|System caches & temp files|package & overlay caches, temp, lost+found, OTA download, MTP data|package-manager & overlay caches (rebuilt at boot)
3|mixed|App, WebView & GPU caches|Android cache folders, browser/GPU & ad-SDK caches · logins kept|app code caches (in use by running apps)
4|live|Browser & in-app web data|site data in browsers & in-app web pages · cookies & logins kept|
5|live|Logs & crash reports|system, vendor, root, bug reports, crash reports & in-app logs|
6|mixed|Activity history|screen time, data usage, battery & power history, recents, notifications|history files (system services write them back until a reboot)
7|mixed|ColorOS & Google telemetry|ColorOS diagnostics, Android statsd, Google Clearcut, Firebase analytics|Clearcut & Firebase queues (open in running apps)
8|live|Uninstalled app leftovers|data of apps Android has no record of · double-checked, capped|
9|reboot|ART reset & dalvik wipe|profiles, dalvik & boot image · apps slower for a few days|all of it (dalvik and boot image are rebuilt at boot)
10|live|Storage GC & TRIM|smart F2FS garbage collection + TRIM|'
NSEC=10
sec_field() { printf '%s\n' "$SECTIONS" | awk -F'|' -v n="$1" -v f="$2" '$1 == n { print $f }'; }

# ── Options ──────────────────────────────────────────────────────────
MODE=""; SEL=all; DRY=0; REBOOT_OK=0; DO_REVERT=0
for a in "$@"; do
  case "$a" in
    --mode=quick) MODE=quick ;;
    --mode=full)  MODE=full ;;
    --sections=*) SEL=${a#*=} ;;
    --dry)        DRY=1 ;;
    --reboot-ok)  REBOOT_OK=1 ;;
    --revert)     DO_REVERT=1 ;;
    --info)       printf '%s\n' "$SECTIONS"; exit 0 ;;
    *)            echo "Unknown option: $a"; exit 2 ;;
  esac
done
[ "$DO_REVERT" = 1 ] || [ -n "$MODE" ] || { echo "Choose --mode=quick or --mode=full."; exit 2; }
[ "$(id -u)" = 0 ] || { echo "DeepPurge needs root."; exit 1; }
export PATH="/system/bin:/system/xbin:/vendor/bin:$PATH"
QUICK=0; [ "$MODE" = quick ] && QUICK=1

if [ -f "$LOCK" ] && kill -0 "$(cat "$LOCK" 2>/dev/null)" 2>/dev/null; then
  echo "DeepPurge is already running (PID $(cat "$LOCK"))."; exit 1
fi
echo $$ > "$LOCK"
TMPD=/dev/deeppurge.$$
mkdir -p "$LOG_DIR" "$TMPD"
LOG="$LOG_DIR/$(date +%Y%m%d-%H%M%S).log"
USERS=$(ls /data/user 2>/dev/null | tr '\n' ' ')
VER=$(sed -n 's/^version=//p' "$MODDIR/module.prop" 2>/dev/null)

# ── Output ───────────────────────────────────────────────────────────
log()   { printf '%s\n' "$*" >> "$LOG"; }
say()   { printf '%s\n' "$*"; log "$*"; }
rule()  { say "  ────────────────────────────────────────────────"; }
item()  { printf '          › %s\n' "$1"; log "    - $1"; }
warn()  { printf '          ! %s\n' "$1"; log "    ! $1"; }
# bitem TEXT — an item only a full clean does; a quick clean says it was left out
bitem() {
  if [ "$QUICK" = 1 ]; then printf '          – %s · full clean only\n' "$1"; log "    – $1 (full clean only)"
  else item "$1"; fi
}
now()     { date +%s; }
now_kb()  { df -kP /data 2>/dev/null | awk 'NR==2 {v=$3} END {print v+0}'; }
free_kb() { df -kP /data 2>/dev/null | awk 'NR==2 {v=$4} END {print v+0}'; }
fmt_kb()  { awk -v k="$1" 'BEGIN { if (k <= 0) print "-"; else if (k >= 1048576) printf "%.2f GB\n", k/1048576; else if (k >= 1024) printf "%.1f MB\n", k/1024; else printf "%d KB\n", k }'; }
fmt_t()   { if [ "$1" -ge 60 ]; then printf '%dm %02ds' $(($1 / 60)) $(($1 % 60)); else printf '%ds' "$1"; fi; }
cnt()     { n=$(wc -l < "$1" 2>/dev/null | tr -d ' '); echo "${n:-0}"; }

STEP=0; TOTAL=0
begin() {
  STEP=$((STEP + 1)); S_NAME=$1; S_T0=$(now); S_KB=$(now_kb); : > "$TMPD/dry_acc"
  printf '\n  [%02d/%02d] %s\n' "$STEP" "$TOTAL" "$1"; log ""; log "[$STEP/$TOTAL] $1"
}
finish() {
  if [ "$DRY" = 1 ]; then kb=$(awk '{s+=$1} END {print s+0}' "$TMPD/dry_acc"); else kb=$((S_KB - $(now_kb))); fi
  dt=$(( $(now) - S_T0 ))
  printf '%s|%s\n' "$S_NAME" "$kb" >> "$TMPD/summary"
  verb=""; [ "$DRY" = 1 ] && verb="would free "
  printf '          ✓ %s · %s · %s%s\n' "${1:-Done}" "$(fmt_t "$dt")" "$verb" "$(fmt_kb "$kb")"
  log "    OK ${1:-Done} ($(fmt_t "$dt"), $(fmt_kb "$kb"))"
}
# step LABEL CMD… — run a worker, its own output goes to the log
step() { label=$1; shift; printf '          … %s\n' "$label"; "$@" >> "$LOG" 2>&1; }

gc_off() { for g in /sys/fs/f2fs/*/gc_urgent; do [ -w "$g" ] && echo 0 > "$g"; done 2>/dev/null; }
cleanup() {
  gc_off
  rm -rf "$TMPD"; rm -f "$LOCK"
  ls -1t "$LOG_DIR"/*.log 2>/dev/null | tail -n +11 | while IFS= read -r f; do rm -f "$f"; done
}
trap cleanup EXIT
trap 'say ""; say "  ✗ Stopped."; exit 130' INT TERM

# ── Deletion primitives ──────────────────────────────────────────────
# Every deletion goes through empty_dir or zap. In a test run they only measure.
dry_add() { du -sk "$@" 2>/dev/null | awk '{s+=$1} END {print s+0}' >> "$TMPD/dry_acc"; }
# empty_dir DIR — delete a directory's contents, keep the directory
empty_dir() {
  [ -d "$1" ] || return 0
  if [ "$DRY" = 1 ]; then dry_add "$1"; else find "$1" -mindepth 1 -delete >/dev/null 2>&1; fi
}
# zap PATH… — delete files or folders
zap() {
  for f in "$@"; do
    [ -e "$f" ] || continue
    if [ "$DRY" = 1 ]; then dry_add "$f"; else rm -rf "$f" 2>/dev/null; fi
  done
}
# settle [seconds] — flush writes and give system services time to catch up
settle() { [ "$DRY" = 1 ] && return 0; sync; sleep "${1:-2}"; }
# boot_only CMD… — skipped in a quick clean (rebuilt at boot, or held open by running apps)
boot_only() { [ "$QUICK" = 1 ] && return 0; "$@"; }

# apk_check — every installed app must still have its APK. Writes broken ones to apk_broken.
apk_check() {
  pm list packages -f 2>/dev/null | tr -d '\r' | while IFS= read -r l; do
    l=${l#package:}; [ -f "${l%=*}" ] || echo "${l##*=}"
  done > "$TMPD/apk_broken"
  pm list packages 2>/dev/null | wc -l | tr -d ' ' > "$TMPD/apk_total"
  [ ! -s "$TMPD/apk_broken" ]
}

# ── Workers ──────────────────────────────────────────────────────────
purge_system_caches() {
  boot_only empty_dir /data/system/package_cache   # parsed-APK cache, rebuilt by the package manager at boot
  boot_only empty_dir /data/resource-cache         # overlay (theme) idmaps, regenerated at boot
  empty_dir /data/local/tmp                        # temp files
  empty_dir /data/lost+found                       # fragments from filesystem repairs
  empty_dir /data/ota_package                      # downloaded OTA update (re-downloads if pending)
  # ColorOS theme-unpacking leftovers (the themed icons themselves are kept)
  empty_dir /data/oplus/uxicons/temp_u0
  find /data/oplus/uxicons \( -name .DS_Store -o -name __MACOSX \) -print 2>/dev/null | while IFS= read -r f; do zap "$f"; done
  if [ "$DRY" = 1 ]; then dry_add /data/user/*/com.android.mtp; return 0; fi
  pm clear com.android.mtp >/dev/null 2>&1         # MTP host data (fixes stale file lists over USB)
}

# Only Android-defined cache folders and well-known browser/GPU cache folders.
# Nothing that holds site data, offline content or app state.
purge_caches() {
  for base in /data/user/*/ /data/user_de/*/; do
    if [ "$QUICK" = 1 ]; then
      find "$base" -mindepth 2 -maxdepth 2 -type d -name cache -print 2>/dev/null
    else   # code caches are in use by running apps; rebuilt after the reboot
      find "$base" -mindepth 2 -maxdepth 2 -type d \( -name cache -o -name code_cache \) -print 2>/dev/null
    fi
    find "$base" -mindepth 3 -maxdepth 5 -type d \( \
      -name GPUCache -o -name ShaderCache -o -name GrShaderCache -o -name DawnCache -o \
      -name GraphiteDawnCache -o -name DawnGraphiteCache -o -name DawnWebGPUCache -o \
      -name "Code Cache" -o -name Crashpad -o -name "Crash Reports" \
    \) -prune -print 2>/dev/null
  done > "$TMPD/cachedirs"
  while IFS= read -r d; do empty_dir "$d"; done < "$TMPD/cachedirs"
  # ad-SDK plugin download folders (Pangle, Kuaishou ads…)
  for base in /data/user/*/; do
    find "$base" -mindepth 2 -maxdepth 3 -type d \( -name app_adnet -o -name app_sodler -o -name app_tt_pangle_bykv_file \
      -o -name ksad_dynamic -o -name kwad_ex -o -name ksadsdk -o -name ksdsdk_ziptmp -o -name 'pangle_*' \) -prune -print 2>/dev/null
  done > "$TMPD/x_ads"
  while IFS= read -r d; do empty_dir "$d"; done < "$TMPD/x_ads"
}

# Site data in browsers (app_chrome) and in-app web views (app_webview), every
# profile. Cookies, saved passwords and logins live in "Cookies", "Network" and
# "Login Data", which are never touched.
web_scan() {
  find /data/user/*/ -mindepth 4 -maxdepth 4 -type d \( -path '*/app_chrome/*' -o -path '*/app_webview/*' \) \
    \( -name "Service Worker" -o -name IndexedDB -o -name "Local Storage" -o -name "Session Storage" \
       -o -name databases -o -name "File System" -o -name WebStorage \) -prune -print 2>/dev/null > "$TMPD/web_dirs"
  while IFS= read -r d; do
    pkg=${d#/data/user/*/}; pkg=${pkg%%/*}
    printf '%s %s\n' "$pkg" "$(du -sk "$d" 2>/dev/null | cut -f1)"
  done < "$TMPD/web_dirs" | awk '{s[$1]+=$2} END {for (p in s) print p, s[p]}' | sort -k2 -nr > "$TMPD/web_pkgs"
}
# Apps are closed first — never the app in front (the WebUI's host), the
# keyboard, launcher, VPN, accessibility apps, System UI, Phone or Play services.
web_purge() {
  ime=$(settings get secure default_input_method 2>/dev/null | cut -d/ -f1)
  vpn=$(settings get secure always_on_vpn_app 2>/dev/null)
  launcher=$(cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null | tail -n 1 | cut -d/ -f1)
  a11y=$(settings get secure enabled_accessibility_services 2>/dev/null | tr ':' '\n' | cut -d/ -f1 | tr '\n' ' ')
  front=$(dumpsys activity activities 2>/dev/null | grep -E 'mResumedActivity|topResumedActivity' | head -n 1 | grep -oE '[A-Za-z0-9_.]+/' | head -n 1 | tr -d /)
  protect=" $front $ime $vpn $launcher $a11y com.android.systemui com.android.phone com.google.android.gms com.google.android.gsf "
  : > "$TMPD/web_skip"
  while read -r pkg _; do
    case "$protect" in *" $pkg "*) echo "$pkg" >> "$TMPD/web_skip"; continue ;; esac
    [ "$DRY" != 1 ] && am force-stop "$pkg" >/dev/null 2>&1
  done < "$TMPD/web_pkgs"
  [ "$DRY" != 1 ] && sleep 2   # let closed apps fully exit before their files are removed
  while IFS= read -r d; do
    pkg=${d#/data/user/*/}; pkg=${pkg%%/*}
    grep -qxF "$pkg" "$TMPD/web_skip" && continue
    empty_dir "$d"
  done < "$TMPD/web_dirs"
}

purge_logs() {
  for d in \
    /data/system/dropbox /data/system/dropbox_oplus /data/system/heapdump /data/system/shutdown-checkpoints \
    /data/anr /data/tombstones /data/local/traces \
    /data/misc/logd /data/misc/perfetto-traces /data/misc/trace /data/misc/wmtrace /data/misc/a11ytrace \
    /data/misc/hprofs /data/misc/heapprofd /data/misc/update_engine_log /data/misc/incidents \
    /data/misc/snapshotctl_log /data/misc/bluetooth/logs \
    /data/vendor/ramdump /data/vendor/ssr_ramdump /data/vendor/tombstones /data/vendor/wlan_logs \
    /data/vendor/diag_logs /data/vendor/bluetooth/logs /data/vendor/modem_log /data/vendor/tz_log \
    /data/persist_log /data/oplus/log /data/oplus/blackbox /data/oplus/heapdump \
    /data/vendor/oplus/log /data/oppo/log /data/oppo/common/log /data/oplus/psw/powermonitor_backup \
    /data/oplus/bsp_kevent /data/oplus/mmdump \
    /data/user_de/*/com.android.shell/files/bugreports /sys/fs/pstore; do
    empty_dir "$d"
  done
  zap /data/adb/*.log /data/adb/modules/*/*.log
  if [ "$DRY" != 1 ]; then logcat -b all -c 2>/dev/null; dmesg -c >/dev/null 2>&1; fi
  # In-app log folders and crash-report SDK folders (Crashlytics / Fabric)
  for base in /data/user/*/ /data/user_de/*/; do
    find "$base" -mindepth 3 -maxdepth 3 -type d -path '*/files/*' \( \
      -name '.com.google.firebase.crashlytics*' -o -name '.crashlytics*' -o -name .Fabric \
      -o -name log -o -name logs -o -name xlog \
    \) -prune -print 2>/dev/null
  done > "$TMPD/x_logs"
  while IFS= read -r d; do empty_dir "$d"; done < "$TMPD/x_logs"
}

# Note: wiping usage stats means apps you then don't open for months may be
# treated as "unused" by Android and have their permissions auto-revoked.
wipe_history() {
  boot_only wipe_history_files
  # in-memory counters: battery usage screen, process stats, binder/looper stats
  if [ "$DRY" != 1 ]; then
    dumpsys batterystats --reset
    dumpsys procstats --clear
    cmd binder_calls_stats --reset
    cmd looper_stats reset
  fi
}
# System services keep these in memory and write them back, so deleting them
# only sticks across a reboot (full clean).
wipe_history_files() {
  for u in $USERS; do
    for d in daily weekly monthly yearly; do
      empty_dir "/data/system/usagestats/$u/$d"; empty_dir "/data/system_ce/$u/usagestats/$d"
    done
    empty_dir "/data/system_ce/$u/notification_history"
    empty_dir "/data/system_ce/$u/snapshots"
    empty_dir "/data/system_ce/$u/recent_images"
    empty_dir "/data/system_ce/$u/recent_tasks"
  done
  empty_dir /data/system/netstats
  empty_dir /data/misc/apexdata/com.android.tethering/netstats
  empty_dir /data/system/appops/history
  empty_dir /data/system/appops/discrete
  empty_dir /data/system/battery-history
  empty_dir /data/system/graphicsstats
  empty_dir /data/oplus/psw/powermonitor   # ColorOS power history (battery rules in /data/oplus/os are never touched)
}

purge_telemetry() {
  for u in $USERS; do
    # ColorOS diagnostics/telemetry collectors only (no functional services)
    for t in com.oplus.DCS com.oplus.statistics.rom com.oplus.logkit com.oplus.onetrace \
             com.oplus.crashbox com.oplus.criticallog com.heytap.habit.analysis; do
      if [ "$DRY" = 1 ]; then dry_add "/data/user/$u/$t" "/data/user_de/$u/$t"
      else pm clear --user "$u" "$t" >/dev/null 2>&1; fi
    done
    # Google Clearcut logging queue (open in Play services while it runs)
    boot_only zap "/data/user/$u/com.google.android.gms/databases/"*clearcut* "/data/user/$u/com.google.android.gms/files/clearcut"
  done
  # statsd: metrics queued for upload (recreated by statsd)
  empty_dir /data/misc/stats-data
  empty_dir /data/misc/stats-active-metric
  # Firebase Analytics / transport queues (open in running apps, so full clean only)
  [ "$QUICK" = 1 ] && return 0
  find /data/user/*/ -mindepth 3 -maxdepth 3 -type f -path '*/databases/*' \( \
    -name 'google_app_measurement*' -o -name 'com.google.android.datatransport.events*' \
  \) 2>/dev/null | while IFS= read -r f; do zap "$f"; done
}

# Removes data folders only for packages Android has NO record of —
# not installed, not uninstalled-with-data-kept, not archived.
# Every candidate is re-checked individually; too many candidates = remove none.
sweep_leftovers() {
  KNOWN="$TMPD/known"; CAND="$TMPD/cand"; OUT="$TMPD/leftovers"
  : > "$KNOWN"; : > "$CAND"; : > "$OUT"; : > "$TMPD/warn"
  for u in $USERS; do
    L="$TMPD/pkgs_$u"
    pm list packages -u --user "$u" 2>/dev/null | cut -d: -f2 | tr -d '\r' > "$L"
    cat "$L" >> "$KNOWN"
    npk=$(cnt "$L"); ndirs=$(ls "/data/user/$u" 2>/dev/null | wc -l)
    if [ "$npk" -lt 50 ] || [ "$npk" -lt $((ndirs / 2)) ]; then
      echo "User $u skipped (package list looks incomplete)" >> "$TMPD/warn"; continue
    fi
    for d in "/data/user/$u"/* "/data/user_de/$u"/* "/data/misc/profiles/cur/$u"/*; do
      [ -d "$d" ] || continue
      p=${d##*/}
      case "$p" in .*|*[!a-zA-Z0-9._]*) continue ;; *.*) ;; *) continue ;; esac
      grep -qxF "$p" "$L" || echo "$d" >> "$CAND"
    done
  done
  sort -u "$KNOWN" -o "$KNOWN"
  if [ "$(cnt "$KNOWN")" -ge 50 ]; then
    for d in /data/misc/profiles/ref/*; do
      [ -d "$d" ] || continue
      p=${d##*/}
      case "$p" in .*|*[!a-zA-Z0-9._]*) continue ;; *.*) ;; *) continue ;; esac
      grep -qxF "$p" "$KNOWN" || echo "$d" >> "$CAND"
    done
  fi
  if [ "$(cnt "$CAND")" -gt "$LEFTOVER_CAP" ]; then
    echo "Found $(cnt "$CAND") candidates — more than $LEFTOVER_CAP, so nothing was removed" >> "$TMPD/warn"
    cat "$CAND"; return
  fi
  while IFS= read -r d; do
    p=${d##*/}
    # Second, independent check: does the package manager know this name at all?
    if dumpsys package "$p" 2>/dev/null | grep -q "Package \[$p\]"; then
      echo "Kept $d (package still registered)" >> "$TMPD/warn"; continue
    fi
    zap "$d"; echo "$d" >> "$OUT"
  done < "$CAND"
}

# Reset one package per request — a single all-apps request is too large
# for the binder call and fails with "Failed transaction" on Android 17.
reset_profiles() {
  n=0
  find /data/misc/profiles/cur /data/misc/profiles/ref -type f -name '*.prof' -delete 2>/dev/null
  : > "$TMPD/reset_fail"
  for p in $(pm list packages 2>/dev/null | cut -d: -f2 | tr -d '\r'); do
    n=$((n + 1))
    [ $((n % 25)) -eq 0 ] && sleep 1   # short breather so the package service never backs up
    if pm compile --reset "$p" 2>&1 | grep -qiE 'fail|error|exception'; then
      pm art clear-app-profiles "$p" >/dev/null 2>&1 || echo "$p" >> "$TMPD/reset_fail"
    fi
  done
  echo "$n" > "$TMPD/reset_n"
  empty_dir /data/dalvik-cache                                  # rebuilt at the reboot
  empty_dir /data/misc/apexdata/com.android.art/dalvik-cache    # ART boot image, rebuilt by odrefresh at boot
}
art_estimate() {
  dry_add /data/app/*/*/oat /data/misc/profiles/cur /data/misc/profiles/ref /data/dalvik-cache \
          /data/misc/apexdata/com.android.art/dalvik-cache
}

# Smart F2FS GC: urgent GC on /data until the kernel finishes, dirty segments
# stop dropping, or the time limit.
storage_maint() {
  sync
  if [ "$GC_MAX_SECONDS" -gt 0 ]; then
    dev=$(getprop dev.mnt.dev.data); dir="/sys/fs/f2fs/$dev"
    if [ -z "$dev" ] || [ ! -w "$dir/gc_urgent" ]; then
      dir=""
      for g in /sys/fs/f2fs/*/gc_urgent; do [ -w "$g" ] && { dir=${g%/gc_urgent}; break; }; done
    fi
    if [ -n "$dir" ]; then
      prev=$(cat "$dir/dirty_segments" 2>/dev/null || echo 0); stall=0; t=0
      echo "$prev" > "$TMPD/gc_before"
      echo 1 > "$dir/gc_urgent"
      while [ "$t" -lt "$GC_MAX_SECONDS" ]; do
        sleep 5; t=$((t + 5))
        [ "$(cat "$dir/gc_urgent" 2>/dev/null)" = 0 ] && break
        dirty=$(cat "$dir/dirty_segments" 2>/dev/null || echo 0)
        [ "$dirty" -le 100 ] && break
        if [ "$dirty" -ge "$prev" ]; then stall=$((stall + 1)); [ "$stall" -ge 6 ] && break; else stall=0; fi
        prev=$dirty
      done
      echo 0 > "$dir/gc_urgent"
      cat "$dir/dirty_segments" > "$TMPD/gc_after" 2>/dev/null
      echo "$t" > "$TMPD/gc_time"
    fi
  fi
  sync
  sm fstrim
  if command -v fstrim >/dev/null; then fstrim -v /data > "$TMPD/trim" 2>/dev/null; fstrim /metadata 2>/dev/null; fi
  sync
}

# ── Sections ─────────────────────────────────────────────────────────
sec_1() {
  if [ "$DRY" = 1 ]; then item "Settings only — no space change"; finish "Would apply"; return; fi
  {
    settings put global window_animation_scale 0.85
    settings put global transition_animation_scale 0.85
    settings put global animator_duration_scale 0.85
    settings put global settings_enable_monitor_phantom_procs false
    settings put global send_action_app_error 0
    settings put global dropbox_max_files 1
    settings put global bugreport_in_power_menu 0
    settings put secure send_action_app_error 0
    settings put secure upload_debug_log_pref 0
    settings put secure user_experience_enabled 0
    settings put secure oplus_user_experience 0
    settings put system user_experience_enabled 0
    settings put system oppo_log_switch 0
    settings put system oplus_log_switch 0
    settings put system log_switch_type 0
    setprop persist.sys.assert.panic false
    setprop persist.sys.assert.enable false
    setprop persist.sys.oplus.log.config 0
    setprop persist.vendor.ssr.enable_ramdumps 0
    setprop persist.vendor.sys.ssr.enable_ramdumps 0
  } >/dev/null 2>&1
  item "Animation scale 0.85×"
  item "Child-process restrictions off"
  item "Error reports, debug logging, ramdumps & UX telemetry off"
  finish
}
sec_2() {
  step "Clearing system caches" purge_system_caches
  bitem "Package-manager & overlay caches cleared (rebuilt at boot)"
  item "Temp files, lost+found & downloaded OTA update removed"
  item "ColorOS theme-unpacking leftovers removed (icons kept)"
  item "MTP host data reset"
  finish
}
sec_3() {
  step "Scanning app data" purge_caches
  item "$(cnt "$TMPD/cachedirs") cache folders · $(cnt "$TMPD/x_ads") ad-SDK folders emptied"
  bitem "App code caches cleared (rebuilt after reboot)"
  finish
}
sec_4() {
  step "Measuring web data" web_scan
  if [ ! -s "$TMPD/web_pkgs" ]; then item "No browser or in-app web data found"; finish; return; fi
  n=$(cnt "$TMPD/web_pkgs")
  head -n 6 "$TMPD/web_pkgs" | while read -r pkg kb; do item "$pkg · $(fmt_kb "$kb")"; done
  [ "$n" -gt 6 ] && item "…and $((n - 6)) more apps"
  step "Closing apps & clearing web data" web_purge
  [ -s "$TMPD/web_skip" ] && item "Kept (in use): $(tr '\n' ' ' < "$TMPD/web_skip")"
  item "Cookies, saved passwords & logins kept"
  finish
}
sec_5() {
  step "Removing logs" purge_logs
  item "System, kernel, pstore, trace & Qualcomm vendor logs"
  item "Saved bug reports · ColorOS & root logs"
  item "$(cnt "$TMPD/x_logs") in-app log & crash-report folders"
  finish
}
sec_6() {
  step "Clearing history" wipe_history
  item "Battery, process, binder & looper stats reset"
  bitem "Data usage, battery & permission-usage history files"
  bitem "Recent apps & notification history"
  bitem "Screen-time stats & ColorOS power history"
  finish
}
sec_7() {
  step "Resetting telemetry stores" purge_telemetry
  item "ColorOS DCS, statistics, log & crash collectors reset"
  item "Android statsd metrics queue cleared"
  bitem "Google Clearcut queue · Firebase Analytics queues"
  finish
}
sec_8() {
  step "Checking against the package manager" sweep_leftovers
  [ -s "$TMPD/warn" ] && while IFS= read -r l; do warn "$l"; done < "$TMPD/warn"
  n=$(cnt "$TMPD/leftovers")
  if [ "$n" -gt 0 ]; then
    while IFS= read -r l; do item "${l#/data/}"; done < "$TMPD/leftovers"
  else
    item "No orphaned folders found"
  fi
  finish "$n removed"
}
sec_9() {
  if [ "$DRY" = 1 ]; then
    step "Measuring compiled code & profiles" art_estimate
    item "Compiled app code, profiles, dalvik cache & boot image (rebuilt)"
    finish; return
  fi
  step "Resetting profiles app by app" reset_profiles
  n=$(cat "$TMPD/reset_n" 2>/dev/null || echo 0); f=$(cnt "$TMPD/reset_fail")
  item "Profiles reset for $((n - f)) of $n apps · install-time compilation"
  [ "$f" -gt 0 ] && warn "$f apps couldn't be reset (listed in the log)" && cat "$TMPD/reset_fail" >> "$LOG"
  item "Dalvik cache & ART boot image wiped — first boot takes a few minutes longer"
  finish
}
sec_10() {
  if [ "$DRY" = 1 ]; then item "Flash maintenance only — no space change"; finish "Would run"; return; fi
  settle 3
  step "Garbage-collecting & trimming flash" storage_maint
  if [ -s "$TMPD/gc_before" ]; then
    item "F2FS dirty segments $(cat "$TMPD/gc_before") → $(cat "$TMPD/gc_after" 2>/dev/null || echo ?) in $(fmt_t "$(cat "$TMPD/gc_time" 2>/dev/null || echo 0)")"
  else
    item "F2FS GC not available on this kernel"
  fi
  t=$(cat "$TMPD/trim" 2>/dev/null)
  if [ -n "$t" ]; then item "$t"; else item "TRIM issued via StorageManager"; fi
  finish
}

# ── Revert ───────────────────────────────────────────────────────────
if [ "$DO_REVERT" = 1 ]; then
  log "DEEPPURGE $VER — revert — $(date)"
  say "  Reverting settings & tuning"
  {
    for k in window_animation_scale transition_animation_scale animator_duration_scale; do settings put global "$k" 1.0; done
    for k in settings_enable_monitor_phantom_procs send_action_app_error dropbox_max_files bugreport_in_power_menu; do settings delete global "$k"; done
    for k in send_action_app_error upload_debug_log_pref user_experience_enabled oplus_user_experience; do settings delete secure "$k"; done
    for k in user_experience_enabled oppo_log_switch oplus_log_switch log_switch_type; do settings delete system "$k"; done
    for p in persist.sys.assert.panic persist.sys.assert.enable persist.sys.oplus.log.config persist.vendor.ssr.enable_ramdumps persist.vendor.sys.ssr.enable_ramdumps; do
      if command -v resetprop >/dev/null 2>&1; then resetprop -p -d "$p"; else setprop "$p" ""; fi
    done
  } >/dev/null 2>&1
  sed -n 's/^w \(\/[^ ]*\) .*/\1/p' "$MODDIR/tuning.sh" > "$CONF/tuning.off"
  item "Animations back to 1×, telemetry & debug settings back to stock"
  item "Every tuning setting turned off — reboot to return the kernel to stock"
  exit 0
fi

# ── Header ───────────────────────────────────────────────────────────
log "DEEPPURGE $VER — $MODE clean — $(date)"
USED0=$(now_kb)
BATINFO=$(dumpsys battery 2>/dev/null)
BAT=$(printf '%s\n' "$BATINFO" | awk '/ level:/ {print $2; exit}')
PLUG=$(printf '%s\n' "$BATINFO" | grep -c 'powered: true')
say "  DEEPPURGE $VER"
item "Storage: $(fmt_kb "$USED0") used · $(fmt_kb "$(free_kb)") free"
item "Battery: ${BAT:-?}%$([ "${PLUG:-0}" -gt 0 ] && echo ' · charging')"
if [ "$DRY" != 1 ] && [ -n "$BAT" ] && [ "$BAT" -lt 20 ] && [ "${PLUG:-0}" -eq 0 ]; then
  say "  ✗ Battery at $BAT%. Charge to 20% or plug in first."; exit 1
fi

# ── Selection ────────────────────────────────────────────────────────
if [ "$SEL" = all ]; then i=1; while [ "$i" -le "$NSEC" ]; do echo "$i"; i=$((i + 1)); done
else printf '%s\n' "$SEL" | tr ',' '\n' | grep -xE '[0-9]+' | awk -v m="$NSEC" '$1 >= 1 && $1 <= m' | sort -nu
fi > "$TMPD/sel"
: > "$TMPD/run"
while IFS= read -r n; do
  if [ "$QUICK" = 1 ] && [ "$(sec_field "$n" 2)" = reboot ]; then
    warn "$(sec_field "$n" 3): needs a reboot — full clean only. Skipped."; continue
  fi
  echo "$n" >> "$TMPD/run"
done < "$TMPD/sel"
TOTAL=$(cnt "$TMPD/run")
[ "$TOTAL" -gt 0 ] || { say "  Nothing selected."; exit 0; }

# A full clean always ends with a reboot: nothing changes without permission
if [ "$QUICK" = 0 ] && [ "$DRY" != 1 ] && [ "$REBOOT_OK" != 1 ]; then
  say "  ✗ A full clean ends with a reboot. Confirm it with --reboot-ok. Nothing was changed."; exit 2
fi

say ""; rule
if [ "$DRY" = 1 ]; then say "  Test run · $MODE clean · $TOTAL of $NSEC sections · measuring only, nothing is changed"
elif [ "$QUICK" = 1 ]; then say "  Quick clean · $TOTAL of $NSEC sections · no reboot"
else say "  Full clean · $TOTAL of $NSEC sections · reboots when done"; fi
rule
START=$(now)
: > "$TMPD/summary"

# ── Run ──────────────────────────────────────────────────────────────
# read from fd 3, so commands inside a section can't swallow the list
while IFS= read -r n <&3; do
  begin "$(sec_field "$n" 3)"
  "sec_$n"
  settle 2   # let services catch up before the next section
done 3< "$TMPD/run"

# ── Summary ──────────────────────────────────────────────────────────
say ""; rule
if [ "$DRY" = 1 ]; then say "  TEST RUN — ESTIMATE"; else say "  SUMMARY"; fi
rule
total=0
while IFS='|' read -r name kb; do
  say "$(printf '  %-32s %12s' "$name" "$(fmt_kb "$kb")")"
  total=$((total + kb))
done < "$TMPD/summary"
rule
if [ "$DRY" = 1 ]; then
  say "$(printf '  %-32s %12s' "Estimated saving" "$(fmt_kb "$total")")"
  say "  Test run — nothing was changed."
else
  say "$(printf '  %-32s %12s' "Total reclaimed" "$(fmt_kb $((USED0 - $(now_kb))))")"
  say "$(printf '  %-32s %12s' "Free space now" "$(fmt_kb "$(free_kb)")")"
fi
say "$(printf '  %-32s %12s' "Elapsed" "$(fmt_t $(( $(now) - START )))")"
rule
say "  Log: ${LOG#"$CONF"/}"

[ "$DRY" = 1 ] && exit 0
if [ "$QUICK" = 1 ]; then say ""; say "  Quick clean done · no reboot needed."; exit 0; fi

# Final safety net: never reboot with an installed app missing its APK
if ! apk_check; then
  say ""; say "  ✗ $(cnt "$TMPD/apk_broken") installed apps are missing their APK — NOT rebooting."
  while IFS= read -r l; do item "$l"; done < "$TMPD/apk_broken"
  say "  Reinstall these from Play Store first."
  exit 1
fi
item "All $(cat "$TMPD/apk_total") installed apps verified (APKs present)"
say "  Rebooting in 5s"
sleep 5
say "  Rebooting…"
cleanup; trap - EXIT
sync; sleep 3
reboot
