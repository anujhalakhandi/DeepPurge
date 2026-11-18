#!/data/data/com.termux/files/usr/bin/bash
#  DEEPPURGE 10.1 — deep clean for rooted OnePlus 15
#  ColorOS 17 · KernelSU · app logins preserved
#
#  Safety rules this script follows:
#   • Never installs, uninstalls or moves apps, and never touches APKs
#     (/data/app), shared storage (/sdcard, /data/media), ColorOS battery
#     rules (/data/oplus/os), or any app's databases, shared_prefs,
#     no_backup or sign-in data (cookies, logins).
#   • Clears caches, web site data, logs, telemetry, usage history,
#     temp/OTA leftovers and compiled code — all rebuilt automatically.
#   • Apps are closed only right before their web data is cleared — never
#     the keyboard, launcher, VPN, accessibility apps, Termux, System UI,
#     Phone or Play services.
#   • Leftover app data is removed only when Android has no record of the
#     package at all, double-checked per package, with a hard cap.
#
#  Two kinds of clean:
#   • Quick clean — only what is safe while Android is running. No reboot.
#   • Full clean  — everything, including caches rebuilt at boot (package,
#     overlay, code, dalvik). Always ends with a reboot, and asks first.
#     Refuses to reboot if any installed app is missing its APK.
#
#  Usage: deeppurge                interactive: choose quick or full, optional test run
#         deeppurge --revert       undo settings & boot tweaks (cleaning can't be undone)
#  Non-interactive (used by the module's WebUI, works in Termux too):
#         deeppurge --mode=quick [--sections=LIST|all]              quick clean, no reboot
#         deeppurge --mode=full  [--sections=LIST|all] --reboot-ok  full clean, then reboot
#         deeppurge -y             same as --mode=full --sections=all --reboot-ok
#         … --dry                  test run of the same selection: measure only, no reboot

# The whole script is one { … } block: bash reads it completely before
# running, so replacing this file during a run cannot affect that run.
{
VERSION="10.1"

# ── Configuration ────────────────────────────────────────────────────
GC_MAX_SECONDS=300     # F2FS urgent GC stops when done, stalled, or after this long (0 = skip)
BOOT_DELAY=20          # network & kernel tuning: applied at boot start, then again this many seconds after boot
LEFTOVER_CAP=15        # if more leftover folders than this are found, something is off: skip them all
# Never closed by section 5 (web data), in addition to the keyboard, launcher, VPN and accessibility apps
PROTECT_APPS="com.termux com.termux.api com.termux.boot com.termux.widget com.resukisu.resukisu app.morphe.manager"

DO_REVERT=0; MODE=""; SEL=""; DRYRUN=0; REBOOT_OK=0; NONINT=0
for a in "$@"; do
  case "$a" in
    -y|--yes)     MODE=full; SEL=all; REBOOT_OK=1; NONINT=1 ;;
    --revert)     DO_REVERT=1 ;;
    --mode=quick|--quick) MODE=quick; NONINT=1 ;;
    --mode=full|--full)   MODE=full; NONINT=1 ;;
    --sections=*) SEL="${a#*=}"; NONINT=1 ;;
    --dry)        DRYRUN=1; NONINT=1 ;;
    --reboot-ok)  REBOOT_OK=1 ;;
    -h|--help)    printf 'Usage: deeppurge [--revert] | [--mode=quick|full] [--sections=LIST|all] [--dry] [--reboot-ok] | -y\n'; exit 0 ;;
    *)            printf 'Unknown option: %s (see --help)\n' "$a"; exit 2 ;;
  esac
done

[ "$(id -u)" -ne 0 ] && exec su -c "$0 $*"
export PATH="/system/bin:/system/xbin:/vendor/bin:/data/adb/ksu/bin:$PATH"

# ── Paths ────────────────────────────────────────────────────────────
T_HOME=/data/data/com.termux/files/home
T_PREFIX=/data/data/com.termux/files/usr
# Logs live in Termux's home; without Termux (module only) they go to /data/adb
if [ -d "$T_HOME" ]; then LOG_DIR="$T_HOME/.deeppurge"; else LOG_DIR=/data/adb/deeppurge/logs; fi
LOG="$LOG_DIR/$(date +%Y%m%d-%H%M%S).log"
TMPD="/dev/deeppurge.$$"
BOOT_SCRIPT=/data/adb/service.d/99_deeppurge_tuning.sh
EARLY_SCRIPT=/data/adb/post-fs-data.d/99_deeppurge_tuning.sh   # same tuning, at the very start of boot
TUNE_STATUS=/data/adb/deeppurge_tuning.status                   # per-boot record: every value, both passes
# DeepPurge module: when installed, it applies the tuning at boot instead of the two scripts above
MOD_DIR=/data/adb/modules/deeppurge
MOD_TUNE="$MOD_DIR/tuning.sh"
TUNE_OFF=/data/adb/deeppurge/tuning.off   # settings turned off in the WebUI (one path per line)
MODULE=0; [ -d "$MOD_DIR" ] && [ ! -e "$MOD_DIR/remove" ] && [ ! -e "$MOD_DIR/disable" ] && MODULE=1
USERS=$(ls /data/user 2>/dev/null | tr '\n' ' ')
mkdir -p "$LOG_DIR" "$TMPD"
LOCK=/dev/deeppurge.lock
if [ -f "$LOCK" ] && kill -0 "$(cat "$LOCK" 2>/dev/null)" 2>/dev/null; then
  echo "  DEEPPURGE IS ALREADY RUNNING (PID $(cat "$LOCK")). CLOSE IT FIRST."; exit 1
fi
echo $$ > "$LOCK"

# ── UI ───────────────────────────────────────────────────────────────
if [ -t 1 ]; then
  R=$'\033[0m'; B=$'\033[1m'; D=$'\033[2m'; CY=$'\033[36m'
  GR=$'\033[32m'; YL=$'\033[33m'; RD=$'\033[31m'; WH=$'\033[97m'
else
  R=; B=; D=; CY=; GR=; YL=; RD=; WH=
fi
# All-caps display. Only output going to the terminal is upper-cased; colour
# codes, format specifiers and anything written to files or pipes (data
# lists, the log) are left untouched, so package names stay exact.
RX_ESC='^(\\033\[[0-9;?]*[A-Za-z])'
RX_FMT='^(%[-+ 0#]*[0-9]*(\.[0-9]+)?[a-zA-Z%])'
RX_BSL='^(\\[0-7]{1,3}|\\[a-zA-Z])'
upfmt() {
  local s="$1" o=""
  while [ -n "$s" ]; do
    if [[ $s =~ $RX_ESC ]] || [[ $s =~ $RX_FMT ]] || [[ $s =~ $RX_BSL ]]; then
      o+="${BASH_REMATCH[1]}"; s="${s:${#BASH_REMATCH[1]}}"
    else
      local c="${s:0:1}"; o+="${c^^}"; s="${s:1}"
    fi
  done
  REPLY="$o"
}
printf() {
  if [ "$1" = -v ] || [ ! -t 1 ]; then builtin printf "$@"; return; fi
  upfmt "$1"; local fmt="$REPLY"; shift
  local a out=()
  for a in "$@"; do
    case "$a" in $'\033'*) out+=("$a") ;; *) out+=("${a^^}") ;; esac
  done
  builtin printf "$fmt" "${out[@]}"
}

W=$( { stty size </dev/tty; } 2>/dev/null | awk '{print $2}')
[ -z "$W" ] && W=60; [ "$W" -gt 72 ] && W=72; [ "$W" -lt 44 ] && W=44

log()    { printf '%s\n' "$*" >> "$LOG"; }
rule()   { local s; printf -v s '%*s' $((W - 4)) ''; printf '  %s%s%s\n' "$D" "${s// /─}" "$R"; }
kv()     { local v="$2" max=$((W - 13)); log "$1: $2"
           [ "${#v}" -gt "$max" ] && v="${v:0:$((max - 1))}…"
           printf '  %s%-10s%s %s\n' "$D" "$1" "$R" "$v"; }
item()   { printf '          %s›%s %s\n' "$D" "$R" "$1"; log "    - $1"; }
warn()   { printf '          %s!%s %s\n' "$YL" "$R" "$1"; log "    ! $1"; }
# bitem TEXT — an item that only a full clean does; a quick clean says it was left out
bitem()  { if [ "$QUICK" = 1 ]; then printf '          %s– %s · full clean only%s\n' "$D" "$1" "$R"; log "    – $1 (full clean only)"; else item "$1"; fi; }
now_kb()  { df -kP /data 2>/dev/null | awk 'NR==2 {v=$3} END {print v+0}'; }   # never empty
free_kb() { df -kP /data 2>/dev/null | awk 'NR==2 {v=$4} END {print v+0}'; }
fmt_kb() { awk -v k="$1" 'BEGIN { if (k <= 0) print "-"; else if (k >= 1048576) printf "%.2f GB\n", k/1048576; else if (k >= 1024) printf "%.1f MB\n", k/1024; else printf "%d KB\n", k }'; }
fmt_t()  { if [ "$1" -ge 60 ]; then printf '%dm %02ds' $(($1 / 60)) $(($1 % 60)); else printf '%ds' "$1"; fi; }
cnt()    { local n; n=$(wc -l < "$1" 2>/dev/null | tr -d ' '); echo "${n:-0}"; }

# ask "Title" Y|N "hint"  → returns 0 for yes
ask() {
  local def="$2" a opts
  [ "$def" = Y ] && opts="[Y/N · ENTER = YES]" || opts="[Y/N · ENTER = NO]"
  printf '\n  %s%s%s\n' "$B" "$1" "$R"
  printf '  %s%s%s  %s%s%s ' "$D" "$3" "$R" "$CY" "$opts" "$R"
  read -r a </dev/tty
  [ -z "$a" ] && a="$def"
  case "$a" in y|Y|yes|YES) log "ASK $1: yes"; return 0 ;; *) log "ASK $1: no"; return 1 ;; esac
}

STEP=0; TOTAL=0; NAMES=(); FREED=(); SPIN_PID=
begin() {
  STEP=$((STEP + 1)); S_NAME="$1"; S_T0=$SECONDS; S_KB=$(now_kb); : > "$TMPD/dry_acc"
  printf '\n  %s%s[%02d/%02d]%s %s%s%s\n' "$CY" "$B" "$STEP" "$TOTAL" "$R" "$B" "$1" "$R"
  log ""; log "[$STEP/$TOTAL] $1"
}
finish() {
  local kb dt
  if [ "$DRY" = 1 ]; then kb=$(awk '{s+=$1} END {print s+0}' "$TMPD/dry_acc"); else kb=$((S_KB - $(now_kb))); fi
  dt=$((SECONDS - S_T0))
  NAMES+=("$S_NAME"); FREED+=("$kb")
  local verb=""; [ "$DRY" = 1 ] && verb="would free "
  printf '          %s✓%s %s %s· %s · %s%s%s\n' "$GR" "$R" "${1:-Done}" "$D" "$(fmt_t $dt)" "$verb" "$(fmt_kb $kb)" "$R"
  log "    OK ${1:-Done} ($(fmt_t $dt), $(fmt_kb $kb))"
}
spin() {
  local label="$1"; shift
  if [ ! -t 1 ]; then   # no terminal (WebUI): one line, no animation
    printf '          … %s\n' "$label"
    "$@" >> "$LOG" 2>&1; return
  fi
  "$@" >> "$LOG" 2>&1 &
  SPIN_PID=$!
  local i=0 t0=$SECONDS fr=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
  printf '\033[?25l'
  while kill -0 "$SPIN_PID" 2>/dev/null; do
    printf '\r\033[K          %s%s%s %s %s%s%s' "$CY" "${fr[i++ % 10]}" "$R" "$label" "$D" "$(fmt_t $((SECONDS - t0)))" "$R"
    sleep 0.1
  done
  wait "$SPIN_PID"; local rc=$?; SPIN_PID=
  printf '\r\033[K\033[?25h'
  return $rc
}
gc_off() { local g; for g in /sys/fs/f2fs/*/gc_urgent; do [ -w "$g" ] && echo 0 > "$g"; done 2>/dev/null; }
cleanup() {
  gc_off
  [ -t 1 ] && printf '\033[?25h'
  rm -rf "$TMPD"; rm -f "$LOCK"
  local id; id=$(stat -c %u "$T_HOME" 2>/dev/null)
  [ -n "$id" ] && chown -R "$id:$id" "$LOG_DIR" 2>/dev/null
  restorecon -R "$LOG_DIR" >/dev/null 2>&1
  ls -1t "$LOG_DIR"/*.log 2>/dev/null | tail -n +11 | while read -r f; do rm -f "$f"; done
}
trap cleanup EXIT
trap '[ -n "$SPIN_PID" ] && kill "$SPIN_PID" 2>/dev/null; printf "\n\n  %s✗ Aborted by user.%s\n\n" "$RD" "$R"; log "ABORTED"; exit 130' INT TERM

# ── Deletion primitives ──────────────────────────────────────────────
# Every deletion in this script goes through empty_dir or zap. In a test
# run (DRY=1) they only measure what would be freed and delete nothing.
DRY=0
dry_add() { du -sk "$@" 2>/dev/null | awk '{s+=$1} END {print s+0}' >> "$TMPD/dry_acc"; }
# empty_dir DIR — delete a directory's contents, keep the directory
empty_dir() {
  [ -d "$1" ] || return 0
  if [ "$DRY" = 1 ]; then dry_add "$1"; else find "$1" -mindepth 1 -delete >/dev/null 2>&1; fi
}
# zap PATH… — delete files/folders
zap() {
  local f; for f in "$@"; do [ -e "$f" ] || continue
    if [ "$DRY" = 1 ]; then dry_add "$f"; else rm -rf "$f" 2>/dev/null; fi
  done
}

# settle [seconds] — flush writes and give system services time to catch up
settle() { [ "$DRY" = 1 ] && return 0; sync; sleep "${1:-2}"; }

# Quick clean (QUICK=1) leaves out everything that is only rebuilt or re-read
# at boot, or that running apps and services still hold open.
QUICK=0
boot_only() { [ "$QUICK" = 1 ] && return 0; "$@"; }

# apk_check — every installed app must still have its APK file.
# Writes broken package names to $TMPD/apk_broken; returns 1 if any.
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
  empty_dir /data/local/tmp                     # temp files
  empty_dir /data/lost+found                    # fragments from filesystem repairs
  empty_dir /data/ota_package                   # downloaded OTA update (re-downloads if pending)
  # ColorOS theme-unpacking leftovers (the themed icons themselves are kept)
  empty_dir /data/oplus/uxicons/temp_u0
  find /data/oplus/uxicons \( -name .DS_Store -o -name __MACOSX \) -print 2>/dev/null | while IFS= read -r f; do zap "$f"; done
  if [ "$DRY" = 1 ]; then dry_add /data/user/*/com.android.mtp; return 0; fi
  pm clear com.android.mtp >/dev/null 2>&1      # MTP host data (fixes stale file lists over USB)
}

# Only Android-defined cache folders and well-known browser/GPU cache
# folders. Nothing that holds site data, offline content or app state.
purge_caches() {
  local base names
  : > "$TMPD/cachedirs"
  names=( -name cache )
  [ "$QUICK" = 1 ] || names+=( -o -name code_cache )   # code caches are in use by running apps; rebuilt after the reboot
  local d
  for base in /data/user/*/ /data/user_de/*/; do
    find "$base" -mindepth 2 -maxdepth 2 -type d \( "${names[@]}" \) -print 2>/dev/null
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
  zap "$T_PREFIX"/var/cache/apt/archives/*.deb "$T_PREFIX"/var/cache/apt/*.bin
  empty_dir "$T_HOME/.cache"                    # Termux tool caches (pip, npm, etc.)
}

purge_logs() {
  local d
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
  local base d
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
# History files are kept in memory by system services and written back, so
# deleting them only sticks across a reboot (full clean).
wipe_history_files() {
  local u d
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
  empty_dir /data/oplus/psw/powermonitor        # ColorOS power history (battery rules in /data/oplus/os are never touched)
}

purge_telemetry() {
  local u t
  for u in $USERS; do
    # ColorOS diagnostics/telemetry collectors only (no functional services)
    for t in com.oplus.DCS com.oplus.statistics.rom com.oplus.logkit com.oplus.onetrace \
             com.oplus.crashbox com.oplus.criticallog com.heytap.habit.analysis; do
      if [ "$DRY" = 1 ]; then dry_add "/data/user/$u/$t" "/data/user_de/$u/$t"
      else pm clear --user "$u" "$t" >/dev/null 2>&1; fi
    done
    # Google Clearcut logging queue (open in Play services while it runs: full clean only)
    boot_only zap "/data/user/$u/com.google.android.gms/databases/"*clearcut* "/data/user/$u/com.google.android.gms/files/clearcut"
  done
  # statsd: metrics queued for upload (recreated by statsd)
  empty_dir /data/misc/stats-data
  empty_dir /data/misc/stats-active-metric
  # Firebase Analytics / transport queues (analytics only, recreated on demand;
  # open in running apps, so full clean only)
  [ "$QUICK" = 1 ] && return 0
  local f
  find /data/user/*/ -mindepth 3 -maxdepth 3 -type f -path '*/databases/*' \( \
    -name 'google_app_measurement*' -o -name 'com.google.android.datatransport.events*' \
  \) 2>/dev/null | while IFS= read -r f; do zap "$f"; done
}

# Removes data folders only for packages Android has NO record of —
# not installed, not uninstalled-with-data-kept, not archived.
# Never runs pm uninstall: apps uninstalled with their data kept are left alone.
# Every candidate is re-checked individually; too many candidates = abort.
sweep_leftovers() {
  local u L d p KNOWN="$TMPD/known" CAND="$TMPD/cand" OUT="$TMPD/leftovers"
  : > "$KNOWN"; : > "$CAND"; : > "$OUT"; : > "$TMPD/warn"
  for u in $USERS; do
    L="$TMPD/pkgs_$u"
    pm list packages -u --user "$u" 2>/dev/null | cut -d: -f2 | tr -d '\r' > "$L"
    cat "$L" >> "$KNOWN"
    local ndirs; ndirs=$(ls "/data/user/$u" 2>/dev/null | wc -l)
    if [ "$(wc -l < "$L")" -lt 50 ] || [ "$(wc -l < "$L")" -lt $((ndirs / 2)) ]; then
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
  if [ "$(wc -l < "$KNOWN")" -ge 50 ]; then
    for d in /data/misc/profiles/ref/*; do
      [ -d "$d" ] || continue
      p=${d##*/}
      case "$p" in .*|*[!a-zA-Z0-9._]*) continue ;; *.*) ;; *) continue ;; esac
      grep -qxF "$p" "$KNOWN" || echo "$d" >> "$CAND"
    done
  fi
  if [ "$(wc -l < "$CAND")" -gt "$LEFTOVER_CAP" ]; then
    echo "Found $(wc -l < "$CAND") candidates — more than $LEFTOVER_CAP, so nothing was removed" >> "$TMPD/warn"
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

# Web data in browsers (app_chrome) and in-app web views (app_webview), every
# profile. Cookies, saved passwords and logins live in "Cookies", "Network"
# and "Login Data", which are never touched.
web_scan() {
  local d pkg
  find /data/user/*/ -mindepth 4 -maxdepth 4 -type d \( -path '*/app_chrome/*' -o -path '*/app_webview/*' \) \
    \( "${WEB_STORE_NAMES[@]}" \) -prune -print 2>/dev/null > "$TMPD/web_dirs"
  while IFS= read -r d; do
    pkg=${d#/data/user/*/}; pkg=${pkg%%/*}
    printf '%s %s\n' "$pkg" "$(du -sk "$d" 2>/dev/null | cut -f1)"
  done < "$TMPD/web_dirs" | awk '{s[$1]+=$2} END {for (p in s) print p, s[p]}' | sort -k2 -nr > "$TMPD/web_pkgs"
}
# Apps are closed first — never the keyboard, launcher, VPN, accessibility
# apps, Termux, System UI, Phone or Play services (their web data is kept).
web_purge() {
  local ime vpn launcher a11y protect pkg d
  ime=$(settings get secure default_input_method 2>/dev/null | cut -d/ -f1)
  vpn=$(settings get secure always_on_vpn_app 2>/dev/null)
  launcher=$(cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null | tail -n 1 | cut -d/ -f1)
  a11y=$(settings get secure enabled_accessibility_services 2>/dev/null | tr ':' '\n' | cut -d/ -f1 | tr '\n' ' ')
  protect=" $PROTECT_APPS $ime $vpn $launcher $a11y com.android.systemui com.android.phone com.google.android.gms com.google.android.gsf "
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

# Chromium storage folder names that hold site data (not cookies/logins)
WEB_STORE_NAMES=( -name "Service Worker" -o -name IndexedDB -o -name "Local Storage" \
                  -o -name "Session Storage" -o -name databases -o -name "File System" -o -name WebStorage )

# Reset one package per request — a single all-apps request is too large
# for the binder call and fails with "Failed transaction" on Android 17.
reset_profiles() {
  local p n=0
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
  # Dalvik wipe (same as a custom recovery's "Wipe Dalvik"), rebuilt at the reboot
  empty_dir /data/dalvik-cache
  # ART boot image built by odrefresh — rebuilt automatically at the next boot
  empty_dir /data/misc/apexdata/com.android.art/dalvik-cache
}

# Smart F2FS GC (after ClearBox disk_gc): urgent GC on /data until the
# kernel finishes, dirty segments stop dropping, or the time limit.
storage_maint() {
  local dev dir g dirty prev stall=0 t=0
  sync
  if [ "$GC_MAX_SECONDS" -gt 0 ]; then
    dev=$(getprop dev.mnt.dev.data)
    dir="/sys/fs/f2fs/$dev"
    if [ -z "$dev" ] || [ ! -w "$dir/gc_urgent" ]; then
      dir=""
      for g in /sys/fs/f2fs/*/gc_urgent; do [ -w "$g" ] && { dir=${g%/gc_urgent}; break; }; done
    fi
    if [ -n "$dir" ]; then
      prev=$(cat "$dir/dirty_segments" 2>/dev/null || echo 0)
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
SEC_TITLE=(
  "System settings & telemetry"
  "Network & kernel tuning"
  "System caches & temp files"
  "App, WebView & GPU caches"
  "Browser & in-app web data"
  "Logs & crash reports"
  "Activity history"
  "ColorOS & Google telemetry"
  "Uninstalled app leftovers"
  "ART reset & dalvik wipe"
  "Storage GC & TRIM"
)
SEC_HINT=(
  "animations 0.85×, debug & telemetry toggles off"
  "BBR, fq_codel, TCP Fast Open, quiet kernel log (persists)"
  "package & overlay caches, temp, lost+found, OTA download, MTP data"
  "Android cache folders, browser/GPU, ad-SDK & Termux caches · logins kept"
  "site data in browsers & in-app web pages · cookies & logins kept"
  "system, vendor, root, bug reports, crash reports & in-app logs"
  "screen time, data usage, battery & power history, recents, notifications"
  "ColorOS diagnostics, Android statsd, Google Clearcut, Firebase analytics"
  "orphaned data of apps Android has no record of · double-checked, capped"
  "profiles, dalvik & boot image · apps slower for a few days"
  "smart F2FS garbage collection + TRIM"
)
# live = all of it is safe without a reboot · mixed = part of it needs a full clean · reboot = full clean only
SEC_MODE=( live live mixed mixed live live mixed mixed live reboot live )
# what a quick clean leaves out, per section
SEC_QUICK_SKIP=(
  ""
  ""
  "package-manager & overlay caches (rebuilt at boot)"
  "app code caches (in use by running apps)"
  ""
  ""
  "history files (system services write them back until a reboot)"
  "Clearcut & Firebase queues (open in running apps)"
  ""
  "all of it (dalvik and boot image are rebuilt at boot)"
  ""
)

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
  item "Child-process restrictions off (Termux-friendly)"
  item "Error reports, debug logging, ramdumps & UX telemetry off"
  finish
}

# Network & kernel tuning. One body, installed twice:
#   early  (post-fs-data.d) — before Wi-Fi and the modem create interfaces,
#                             so every interface starts on fq_codel
#   late   (service.d)      — BOOT_DELAY s after boot completes, so vendor
#                             boot scripts can't leave their own values behind
tuning_body() {
  cat << 'TUNE_EOF'
ST=/data/adb/deeppurge_tuning.status
[ "$PASS" = 1 ] && : > "$ST"                    # new boot: start a fresh record
echo "pass $PASS  boot+$(cut -d. -f1 /proc/uptime)s  $(date '+%F %T')" >> "$ST"
OFF=/data/adb/deeppurge/tuning.off             # paths turned off in the module's WebUI
# w PATH VALUE — write, read back, record ok / FAIL / missing / off
w() {
  if [ -f "$OFF" ] && grep -qxF "$1" "$OFF"; then echo "  off      $1" >> "$ST"; return; fi
  [ -e "$1" ] || { echo "  missing  $1" >> "$ST"; return; }
  { echo "$2" > "$1"; } 2>/dev/null
  got=$(tr -s ' \t\n' ' ' < "$1" 2>/dev/null | sed 's/ $//')
  if [ "$got" = "$2" ]; then echo "  ok       $1 = $2" >> "$ST"
  else echo "  FAIL     $1 = $got (wanted $2)" >> "$ST"; fi
}
w /proc/sys/net/core/default_qdisc fq_codel
w /proc/sys/net/ipv4/tcp_congestion_control bbr
w /proc/sys/net/ipv4/tcp_fastopen 3
w /proc/sys/net/ipv4/tcp_mtu_probing 1
w /proc/sys/net/ipv4/tcp_slow_start_after_idle 0
w /proc/sys/net/ipv4/tcp_notsent_lowat 16384
w /proc/sys/kernel/printk "0 0 0 0"
w /proc/sys/vm/vfs_cache_pressure 50
w /sys/kernel/tracing/tracing_on 0
TUNE_EOF
}

install_tuning() {
  if [ "$MODULE" -eq 1 ]; then
    # The module runs this file at boot (pass 1 and pass 2); the standalone scripts would double it
    rm -f "$EARLY_SCRIPT" "$BOOT_SCRIPT" /data/adb/post-fs-data.d/99_deeppurge_net.sh
    { echo '#!/system/bin/sh'
      echo '# DEEPPURGE tuning — run by the module: post-fs-data.sh (PASS=1), service.sh (PASS=2)'
      echo 'PASS=${PASS:-now}'
      tuning_body
    } > "$MOD_TUNE.new" && chmod 644 "$MOD_TUNE.new" && mv -f "$MOD_TUNE.new" "$MOD_TUNE"
    return
  fi
  mkdir -p "${EARLY_SCRIPT%/*}" "${BOOT_SCRIPT%/*}"
  rm -f /data/adb/post-fs-data.d/99_deeppurge_net.sh   # older name of the early script
  { echo '#!/system/bin/sh'
    echo '# DEEPPURGE tuning — pass 1, start of boot (before network interfaces exist)'
    echo 'PASS=1'
    tuning_body
  } > "$EARLY_SCRIPT"
  { echo '#!/system/bin/sh'
    echo "# DEEPPURGE tuning — pass 2, ${BOOT_DELAY}s after boot completes (after vendor boot scripts)"
    echo 'PASS=2'
    echo 'if [ "$1" = "--now" ]; then PASS=now; else'
    echo '  until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 3; done'
    echo "  sleep $BOOT_DELAY"
    echo 'fi'
    tuning_body
  } > "$BOOT_SCRIPT"
  chmod 755 "$EARLY_SCRIPT" "$BOOT_SCRIPT"
}

sec_2() {
  if [ "$DRY" = 1 ]; then item "Network & kernel settings only — no space change"; finish "Would apply"; return; fi
  install_tuning
  # last boot's two passes, then apply now
  local p1 p2 n bad
  n=$(tuning_body | grep -c '^w /')
  p1=$(awk '/^pass 1/{f=1;next} /^pass/{f=0} f && /^  ok/' "$TUNE_STATUS" 2>/dev/null | wc -l)
  p2=$(awk '/^pass 2/{f=1;next} /^pass/{f=0} f && /^  ok/' "$TUNE_STATUS" 2>/dev/null | wc -l)
  if grep -q '^pass 1' "$TUNE_STATUS" 2>/dev/null; then
    item "Last boot: $p1/$n applied at start · $p2/$n re-applied after ${BOOT_DELAY}s"
  fi
  if [ "$MODULE" -eq 1 ]; then PASS=now sh "$MOD_TUNE" >/dev/null 2>&1; else sh "$BOOT_SCRIPT" --now >/dev/null 2>&1; fi
  awk '/^pass now/{f=1;next} /^pass/{f=0} f' "$TUNE_STATUS" 2>/dev/null | tail -n "$n" > "$TMPD/tune_now"
  item "Applied now: $(grep -c '^  ok' "$TMPD/tune_now")/$n"
  local off; off=$(grep -c '^  off' "$TMPD/tune_now")
  [ "$off" -gt 0 ] && item "$off turned off in the module's WebUI"
  grep -E 'FAIL|missing' "$TMPD/tune_now" | while read -r bad; do warn "$bad"; done
  local cc qd
  cc=$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null)
  qd=$(cat /proc/sys/net/core/default_qdisc 2>/dev/null)
  item "TCP ${cc:-?} · qdisc ${qd:-?} · Fast Open · notsent_lowat 16K"
  item "Console logging & kernel tracing off · vfs_cache_pressure 50"
  if [ "$MODULE" -eq 1 ]; then item "Applied by the DeepPurge module at the start of every boot and again ${BOOT_DELAY}s after it"
  else item "Applied at the start of every boot and again ${BOOT_DELAY}s after it"; fi
  finish
}

sec_3() {
  spin "Clearing system caches" purge_system_caches
  bitem "Package-manager & overlay caches cleared (rebuilt at boot)"
  item "Temp files, lost+found & downloaded OTA update removed"
  item "ColorOS theme-unpacking leftovers removed (icons kept)"
  item "MTP host data reset"
  finish
}

sec_4() {
  spin "Scanning app data" purge_caches
  item "$(cnt "$TMPD/cachedirs") cache folders · $(cnt "$TMPD/x_ads") ad-SDK folders emptied"
  bitem "App code caches cleared (rebuilt after reboot)"
  item "Termux package downloads & tool caches cleared"
  finish
}

sec_5() {
  spin "Measuring web data" web_scan
  if [ ! -s "$TMPD/web_pkgs" ]; then item "No browser or in-app web data found"; finish; return; fi
  local pkg kb n
  n=$(cnt "$TMPD/web_pkgs")
  head -n 6 "$TMPD/web_pkgs" | while read -r pkg kb; do item "$(printf '%-34s %s' "$pkg" "$(fmt_kb "$kb")")"; done
  [ "$n" -gt 6 ] && item "…and $((n - 6)) more apps"
  spin "Closing apps & clearing web data" web_purge
  [ -s "$TMPD/web_skip" ] && item "Kept (in use): $(tr '\n' ' ' < "$TMPD/web_skip")"
  item "Cookies, saved passwords & logins kept"
  finish
}

sec_6() {
  spin "Removing logs" purge_logs
  item "System, kernel, pstore, trace & Qualcomm vendor logs"
  item "Saved bug reports · ColorOS & root logs"
  item "$(cnt "$TMPD/x_logs") in-app log & crash-report folders"
  finish
}

sec_7() {
  spin "Clearing history" wipe_history
  item "Battery, process, binder & looper stats reset"
  bitem "Data usage, battery & permission-usage history files"
  bitem "Recent apps & notification history"
  bitem "Screen-time stats & ColorOS power history"
  finish
}

sec_8() {
  spin "Resetting telemetry stores" purge_telemetry
  item "ColorOS DCS, statistics, log & crash collectors reset"
  item "Android statsd metrics queue cleared"
  bitem "Google Clearcut queue · Firebase Analytics queues"
  finish
}

sec_9() {
  spin "Checking against the package manager" sweep_leftovers
  [ -s "$TMPD/warn" ] && while read -r l; do warn "$l"; done < "$TMPD/warn"
  local n; n=$(cnt "$TMPD/leftovers")
  if [ "$n" -gt 0 ]; then
    while read -r l; do item "${l#/data/}"; done < "$TMPD/leftovers"
  else
    item "No orphaned folders found"
  fi
  finish "$n removed"
}

art_estimate() {
  dry_add /data/app/*/*/oat /data/misc/profiles/cur /data/misc/profiles/ref /data/dalvik-cache \
          /data/misc/apexdata/com.android.art/dalvik-cache
}

sec_10() {
  if [ "$DRY" = 1 ]; then
    spin "Measuring compiled code & profiles" art_estimate
    item "Compiled app code, profiles, dalvik cache & boot image (rebuilt)"
    finish; return
  fi
  spin "Resetting profiles app by app" reset_profiles
  local n f; n=$(cat "$TMPD/reset_n" 2>/dev/null || echo 0); f=$(cnt "$TMPD/reset_fail")
  item "Profiles reset for $((n - f)) of $n apps · install-time compilation"
  [ "$f" -gt 0 ] && warn "$f apps couldn't be reset (listed in log)" && cat "$TMPD/reset_fail" >> "$LOG"
  item "Dalvik cache & ART boot image wiped — first boot takes a few minutes longer"
  item "Android rebuilds profiles with use; nightly dexopt recompiles"
  finish
}

sec_11() {
  if [ "$DRY" = 1 ]; then item "Flash maintenance only — no space change"; finish "Would run"; return; fi
  settle 3
  spin "Garbage-collecting & trimming flash" storage_maint
  if [ -s "$TMPD/gc_before" ]; then
    item "F2FS dirty segments $(cat "$TMPD/gc_before") → $(cat "$TMPD/gc_after" 2>/dev/null || echo ?) in $(fmt_t "$(cat "$TMPD/gc_time" 2>/dev/null || echo 0)")"
  elif [ "$GC_MAX_SECONDS" -gt 0 ]; then
    item "F2FS GC not available on this kernel"
  fi
  local t; t=$(cat "$TMPD/trim" 2>/dev/null)
  if [ -n "$t" ]; then item "$t"; else item "TRIM issued via StorageManager"; fi
  finish
}

# ── Header ───────────────────────────────────────────────────────────
log "DEEPPURGE $VERSION — $(date)"
[ -t 1 ] && clear
printf '\n  %s%sDEEPPURGE%s  %sv%s%s\n' "$B" "$CY" "$R" "$D" "$VERSION" "$R"
printf '  %sDeep system clean · app logins preserved%s\n' "$D" "$R"
rule
MODEL=$(getprop ro.product.marketname); [ -z "$MODEL" ] && MODEL=$(getprop ro.product.model)
KSU=$(/data/adb/ksud -V 2>/dev/null | head -n 1); [ -z "$KSU" ] && KSU="root (uid 0)"
BATINFO=$(dumpsys battery 2>/dev/null)
BAT=$(printf '%s\n' "$BATINFO" | awk '/ level:/ {print $2; exit}')
PLUG=$(printf '%s\n' "$BATINFO" | grep -c 'powered: true')
USED0=$(now_kb); FREE0=$(free_kb)
kv Device  "$MODEL"
kv Build   "$(getprop ro.build.display.id) · Android $(getprop ro.build.version.release)"
kv Kernel  "$(uname -r | cut -d- -f1-3)"
kv Root    "$KSU"
kv Storage "$(fmt_kb "$USED0") used · $(fmt_kb "$FREE0") free"
kv Battery "${BAT:-?}%$([ "${PLUG:-0}" -gt 0 ] && echo ' · charging')"
if apk_check; then kv Apps "$(cat "$TMPD/apk_total") installed · all APKs present ✓"
else kv Apps "$(cnt "$TMPD/apk_broken") apps are missing their APK!"; fi
rm -f /data/adb/service.d/98_deeppurge_once.sh 2>/dev/null   # leftover job from v8.5, if any
rule

if [ "$DO_REVERT" -eq 1 ]; then
  printf '\n  %sReverting settings & boot tweaks%s\n' "$B" "$R"
  {
    for k in window_animation_scale transition_animation_scale animator_duration_scale; do settings put global $k 1.0; done
    for k in settings_enable_monitor_phantom_procs send_action_app_error dropbox_max_files bugreport_in_power_menu oplus_customize_ota_recommended; do settings delete global $k; done
    for k in send_action_app_error upload_debug_log_pref user_experience_enabled oplus_user_experience; do settings delete secure $k; done
    for k in user_experience_enabled oppo_log_switch oplus_log_switch log_switch_type; do settings delete system $k; done
    # also undoes changes made by older versions of this script
    device_config delete activity_manager max_phantom_processes
    device_config set_sync_disabled_for_tests none
    for p in persist.sys.assert.panic persist.sys.assert.enable persist.sys.oplus.log.config persist.vendor.ssr.enable_ramdumps persist.vendor.sys.ssr.enable_ramdumps; do
      if command -v resetprop >/dev/null 2>&1; then resetprop -p -d "$p"; else setprop "$p" ""; fi
    done
    rm -f "$BOOT_SCRIPT" "$EARLY_SCRIPT" /data/adb/post-fs-data.d/99_deeppurge_net.sh
    # module: turn every tuning setting off (the module stays installed, applying nothing)
    if [ "$MODULE" -eq 1 ]; then mkdir -p "${TUNE_OFF%/*}"; tuning_body | sed -n 's/^w \([^ ]*\) .*/\1/p' > "$TUNE_OFF"; fi
  } >/dev/null 2>&1
  item "Animations back to 1×, telemetry & debug settings back to stock"
  item "Boot tweak script removed — reboot to return the kernel to stock"
  [ "$MODULE" -eq 1 ] && item "Module tuning turned off — turn settings back on in the WebUI"
  printf '\n'; exit 0
fi

if [ -n "$BAT" ] && [ "$BAT" -lt 20 ] && [ "${PLUG:-0}" -eq 0 ]; then
  printf '\n  %s✗ Battery at %s%%. Charge to 20%% or plug in first.%s\n\n' "$RD" "$BAT" "$R"; exit 1
fi

# Older versions changed flag sync; undo that silently on every run
device_config set_sync_disabled_for_tests none >/dev/null 2>&1

run_sections() {
  local i
  for ((i = 0; i < NSEC; i++)); do
    [ "${RUN[i]}" -eq 1 ] || continue
    begin "${SEC_TITLE[i]}"
    "sec_$((i + 1))"
    settle 2   # let services catch up before the next section
  done
}

print_summary() {
  local i total=0
  printf '\n'; rule
  printf '  %s%s%s%s\n' "$B" "$WH" "$1" "$R"
  rule
  for i in "${!NAMES[@]}"; do
    printf '  %-30s %12s\n' "${NAMES[$i]}" "$(fmt_kb "${FREED[$i]}")"
    log "SUMMARY ${NAMES[$i]}: $(fmt_kb "${FREED[$i]}")"
    total=$((total + ${FREED[$i]}))
  done
  rule
  if [ "$DRY" = 1 ]; then
    printf '  %s%s%-30s %12s%s\n' "$B" "$GR" "Estimated saving" "$(fmt_kb "$total")" "$R"
    printf '  %sTest run — nothing was changed.%s\n' "$D" "$R"
  else
    printf '  %s%s%-30s %12s%s\n' "$B" "$GR" "Total reclaimed" "$(fmt_kb $((USED0 - $(now_kb))))" "$R"
    printf '  %-30s %12s\n' "Free space now" "$(fmt_kb "$(free_kb)")"
  fi
  printf '  %-30s %12s\n' "Elapsed" "$(fmt_t $((SECONDS - START)))"
  rule
  log "SUMMARY END ($1)"
}

# ── Mode & selection ─────────────────────────────────────────────────
NSEC=${#SEC_TITLE[@]}
RUN=()
sel_all() { local i; for ((i = 0; i < NSEC; i++)); do RUN[i]=1; done; }

if [ "$NONINT" -eq 1 ]; then
  [ -n "$MODE" ] || MODE=full
  for ((i = 0; i < NSEC; i++)); do RUN[i]=0; done
  if [ -z "$SEL" ] || [ "$SEL" = all ]; then sel_all
  else
    for n in ${SEL//,/ }; do
      case "$n" in ''|*[!0-9]*) continue ;; esac
      [ "$n" -ge 1 ] && [ "$n" -le "$NSEC" ] && RUN[n-1]=1
    done
  fi
  [ "$DRYRUN" -eq 1 ] && DRY=1
  [ "$MODE" = quick ] && QUICK=1
else
  printf '\n  %sChoose the kind of clean%s\n' "$B" "$R"
  printf '  %s1%s  Quick clean  %sonly what is safe while the phone runs · no reboot%s\n' "$CY" "$R" "$D" "$R"
  printf '  %s2%s  Full clean   %severything, incl. caches rebuilt at boot · ends with a reboot%s\n' "$CY" "$R" "$D" "$R"
  printf '  %s[1/2 · ENTER = 1]%s ' "$CY" "$R"
  read -r a </dev/tty
  if [ "$a" = 2 ]; then MODE=full; else MODE=quick; QUICK=1; fi
  log "MODE: $MODE"
  if ask "Do a test run first?" Y "measures what a $MODE clean would free · changes nothing"; then
    DRY=1; sel_all; TOTAL=0
    for ((i = 0; i < NSEC; i++)); do [ "$QUICK" = 1 ] && [ "${SEC_MODE[i]}" = reboot ] && RUN[i]=0; [ "${RUN[i]}" -eq 1 ] && TOTAL=$((TOTAL + 1)); done
    printf '\n'; rule
    printf '  %sTest run · %s clean · measuring only, nothing is changed%s\n' "$B" "$MODE" "$R"
    rule
    START=$SECONDS
    run_sections
    print_summary "TEST RUN — ESTIMATE"
    DRY=0; STEP=0; TOTAL=0; NAMES=(); FREED=(); RUN=(); USED0=$(now_kb)
  fi
  if ask "Run every section?" Y "or choose them one by one"; then sel_all
  else
    printf '\n  %sChoose sections — press Enter to accept the default%s\n' "$D" "$R"
    for ((i = 0; i < NSEC; i++)); do
      if [ "$QUICK" = 1 ] && [ "${SEC_MODE[i]}" = reboot ]; then RUN[i]=0; continue; fi
      if ask "${SEC_TITLE[i]}" Y "${SEC_HINT[i]}"; then RUN[i]=1; else RUN[i]=0; fi
    done
  fi
fi

# A quick clean never runs what needs a reboot
if [ "$QUICK" = 1 ]; then
  for ((i = 0; i < NSEC; i++)); do
    if [ "${SEC_MODE[i]}" = reboot ] && [ "${RUN[i]}" -eq 1 ]; then
      RUN[i]=0; warn "${SEC_TITLE[i]}: needs a reboot — full clean only. Skipped."
    fi
  done
fi

TOTAL=0
for ((i = 0; i < NSEC; i++)); do [ "${RUN[i]}" -eq 1 ] && TOTAL=$((TOTAL + 1)); done
if [ "$TOTAL" -eq 0 ]; then
  printf '\n  Nothing selected. Exiting.\n\n'; exit 0
fi

# A full clean always ends with a reboot: ask for permission before anything changes
if [ "$QUICK" = 0 ] && [ "$DRY" != 1 ]; then
  if [ "$NONINT" -eq 1 ]; then
    if [ "$REBOOT_OK" -ne 1 ]; then
      printf '\n  %s✗ A full clean ends with a reboot. Add --reboot-ok to confirm. Nothing was changed.%s\n\n' "$RD" "$R"
      exit 2
    fi
  else
    printf '\n'; rule
    printf '  %s%sTHIS CLEAN ENDS WITH A REBOOT%s\n' "$B" "$YL" "$R"
    rule
    item "The phone restarts by itself when the clean is done"
    item "Save anything open first · tip: turn on airplane mode before you start"
    item "First boot after a full clean takes a few minutes longer"
    if ! ask "Start the full clean and reboot when done?" N "type Y to give permission"; then
      printf '\n  Cancelled. Nothing was changed.\n\n'; exit 0
    fi
  fi
fi

printf '\n'; rule
if [ "$DRY" = 1 ]; then printf '  %sTest run · %s clean · %d of %d sections · measuring only, nothing is changed%s\n' "$B" "$MODE" "$TOTAL" "$NSEC" "$R"
elif [ "$QUICK" = 1 ]; then printf '  %sQuick clean · %d of %d sections · no reboot%s\n' "$B" "$TOTAL" "$NSEC" "$R"
else printf '  %sFull clean · %d of %d sections · reboots when done%s\n' "$B" "$TOTAL" "$NSEC" "$R"; fi
rule
START=$SECONDS

# ── Run ──────────────────────────────────────────────────────────────
run_sections

# ── Summary ──────────────────────────────────────────────────────────
if [ "$DRY" = 1 ]; then   # --dry: estimate only, nothing changed, no reboot
  print_summary "TEST RUN — ESTIMATE"
  printf '  %sLog  ~/.deeppurge/%s%s\n\n' "$D" "${LOG##*/}" "$R"
  exit 0
fi
print_summary "SUMMARY"
printf '  %sLog  ~/.deeppurge/%s%s\n\n' "$D" "${LOG##*/}" "$R"
if [ "$QUICK" = 1 ]; then
  printf '  %sQuick clean done · no reboot needed.%s\n\n' "$GR" "$R"
  exit 0
fi

# Final safety net: never reboot with an installed app missing its APK
if ! apk_check; then
  printf '\n  %s✗ %d installed apps are missing their APK — NOT rebooting.%s\n' "$RD" "$(cnt "$TMPD/apk_broken")" "$R"
  while read -r l; do item "$l"; done < "$TMPD/apk_broken"
  { echo "APK CHECK FAILED:"; cat "$TMPD/apk_broken"; } >> "$LOG"
  printf '\n  %sReinstall these from Play Store first. Send ~/.deeppurge/%s for help.%s\n\n' "$YL" "${LOG##*/}" "$R"
  exit 1
fi
item "All $(cat "$TMPD/apk_total") installed apps verified (APKs present)"

if [ -t 1 ]; then
  for i in 5 4 3 2 1; do
    printf '\r\033[K  %sRebooting in %ds%s  %s(Ctrl+C to cancel)%s' "$YL" "$i" "$R" "$D" "$R"
    sleep 1
  done
  printf '\r\033[K  Rebooting…\n'
else
  printf '  Rebooting in 5s\n'; sleep 5; printf '  Rebooting…\n'
fi
cleanup; trap - EXIT; settle 3; reboot
exit 0
}
