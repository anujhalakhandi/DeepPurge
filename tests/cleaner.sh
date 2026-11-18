#!/usr/bin/env bash
# Runs module/cleaner.sh against stubbed Android commands, under every shell
# available (mksh = Android's shell, dash, busybox ash). Needs root: the cleaner
# refuses to run without it and writes /data/adb/deeppurge and /dev/deeppurge.lock.
#   sudo bash tests/cleaner.sh
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd); M="$ROOT/module"
SB=$(mktemp -d); mkdir -p "$SB/bin"; CALLS="$SB/calls.log"
# Stubs log their calls; nothing real happens (reboot, fstrim, dmesg included)
for c in settings dumpsys getprop cmd am sm device_config setprop resetprop reboot fstrim dmesg logcat; do
  printf '#!/bin/sh\necho "%s $*" >> %s\n' "$c" "$CALLS" > "$SB/bin/$c"
done
# pm lists one app whose APK is missing, so a full clean must refuse to reboot
cat > "$SB/bin/pm" <<STUB
#!/bin/sh
echo "pm \$*" >> $CALLS
case "\$*" in "list packages"*) echo "package:/data/app/~~x/com.example-1/base.apk=com.example" ;; esac
STUB
chmod +x "$SB/bin/"*
export PATH="$SB/bin:$PATH"

FAIL=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; FAIL=1; }
t()   { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
mk()  { mkdir -p /data/system/package_cache /data/local/tmp; echo x > /data/system/package_cache/a; echo y > /data/local/tmp/b; : > "$CALLS"; }
O="$SB/out"

for SH in mksh dash "busybox ash"; do
  command -v "${SH%% *}" >/dev/null || { echo "== $SH: not installed, skipped"; continue; }
  echo "== $SH"
  t "--info lists 10 sections" '[ "$($SH "$M/cleaner.sh" --info | wc -l)" -eq 10 ]'
  $SH "$M/cleaner.sh" --bogus >/dev/null 2>&1; t "unknown flag exits 2" "[ $? -eq 2 ]"

  mk; $SH "$M/cleaner.sh" --mode=quick --sections=2 </dev/null >"$O" 2>&1; rc=$?
  t "quick: exit 0" "[ $rc -eq 0 ]"
  t "quick: temp files removed" '[ ! -e /data/local/tmp/b ]'
  t "quick: package cache kept (full clean only)" '[ -e /data/system/package_cache/a ]'
  t "quick: no reboot" '! grep -q "^reboot" "$CALLS"'

  $SH "$M/cleaner.sh" --mode=quick --sections=9 </dev/null >"$O" 2>&1
  t "quick: ART reset refused (needs reboot)" 'grep -q "needs a reboot" "$O" && grep -q "Nothing selected" "$O"'

  mk; $SH "$M/cleaner.sh" --mode=full --sections=2 </dev/null >"$O" 2>&1; rc=$?
  t "full without --reboot-ok: exit 2" "[ $rc -eq 2 ]"
  t "full without --reboot-ok: nothing changed" '[ -e /data/system/package_cache/a ] && [ -e /data/local/tmp/b ]'

  mk; $SH "$M/cleaner.sh" --mode=full --sections=2 --reboot-ok </dev/null >"$O" 2>&1
  t "full: package cache removed" '[ ! -e /data/system/package_cache/a ]'
  t "full: missing APK blocks the reboot" 'grep -q "NOT rebooting" "$O" && ! grep -q "^reboot" "$CALLS"'

  mk; $SH "$M/cleaner.sh" --mode=full --dry </dev/null >"$O" 2>&1; rc=$?
  t "full dry: all 10 sections, exit 0" "[ $rc -eq 0 ] && [ \"\$(grep -c '^  \\[' \"$O\")\" -eq 10 ]"
  t "full dry: nothing deleted" '[ -e /data/system/package_cache/a ] && [ -e /data/local/tmp/b ]'
  t "full dry: no shell errors" '! grep -qiE "syntax|bad substitution|unexpected|not found" "$O"'

  $SH "$M/cleaner.sh" --mode=quick --sections=1,3,4,5,6,7,8,10 </dev/null >"$O" 2>&1; rc=$?
  t "quick real, 8 sections: exit 0, no shell errors" "[ $rc -eq 0 ] && ! grep -qiE 'syntax|bad substitution|unexpected|not found' \"$O\""

  $SH "$M/cleaner.sh" --revert </dev/null >"$O" 2>&1
  t "revert: every tuning setting turned off" '[ "$(wc -l < /data/adb/deeppurge/tuning.off)" -eq "$(grep -c "^w /" "$M/tuning.sh")" ]'
  rm -f /data/adb/deeppurge/tuning.off
  t "lock released" '[ ! -e /dev/deeppurge.lock ]'
done
rm -f /data/system/package_cache/a /data/local/tmp/b
rm -rf "$SB"
[ "$FAIL" -eq 0 ] && echo "ALL CLEANER TESTS PASSED" || echo "SOME CLEANER TESTS FAILED"
exit "$FAIL"
