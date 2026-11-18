#!/system/bin/sh
# Read-only device check for the WebUI. Prints "key=value" and "X|field|field…" lines.
MODDIR=${0%/*}
CONF=/data/adb/deeppurge
ST=/data/adb/deeppurge_tuning.status
OFF=$CONF/tuning.off
TB=/data/data/com.termux/files/usr/bin/bash
ENG="$MODDIR/deeppurge.sh"
ver() { sed -n 's/^VERSION="\(.*\)"/\1/p' "$1" 2>/dev/null | head -n 1; }

echo "module=$(sed -n 's/^version=//p' "$MODDIR/module.prop")"
echo "engine=$(ver "$ENG")"
echo "termux_cmd=$(ver /data/data/com.termux/files/usr/bin/deeppurge)"
[ -x "$TB" ] && echo "bash=$TB" || echo "bash="
echo "model=$(getprop ro.product.marketname || true)"
echo "model2=$(getprop ro.product.model)"
echo "build=$(getprop ro.build.display.id)"
echo "android=$(getprop ro.build.version.release)"
echo "kernel=$(uname -r)"
echo "oplusrom=$(getprop ro.build.version.oplusrom)"
ls /sys/fs/f2fs/*/gc_urgent >/dev/null 2>&1 && echo "f2fs=1" || echo "f2fs=0"
echo "avail_cc=$(cat /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null)"
L=/dev/deeppurge.lock
if [ -f "$L" ] && kill -0 "$(cat "$L" 2>/dev/null)" 2>/dev/null; then echo "running=$(cat "$L")"; else echo "running="; fi
[ -f "$CONF/webui.conf" ] && grep -E '^(mode|all|sections)=' "$CONF/webui.conf" | sed 's/^/ui_/'

# Sections, read from the engine so the titles always match the script
sed -n '/^SEC_TITLE=(/,/^)/s/^  "\(.*\)"$/\1/p' "$ENG" | awk '{print "S|" NR "|" $0}'
sed -n '/^SEC_HINT=(/,/^)/s/^  "\(.*\)"$/\1/p' "$ENG" | awk '{print "H|" NR "|" $0}'
# live / mixed / reboot per section, and what a quick clean leaves out
sed -n 's/^SEC_MODE=( *\(.*\) *)$/\1/p' "$ENG" | tr ' ' '\n' | awk 'NF {print "M|" NR "|" $0}'
sed -n '/^SEC_QUICK_SKIP=(/,/^)/s/^  "\(.*\)"$/\1/p' "$ENG" | awk '{print "Q|" NR "|" $0}'

# Last boot passes
grep '^pass ' "$ST" 2>/dev/null | sed 's/^/B|/'

# Tuning: T|path|value|exists|off|last state|last detail
sed -n 's/^w \(\/[^ ]*\) \(.*\)$/\1|\2/p' "$MODDIR/tuning.sh" | tr -d '"' | while IFS='|' read -r p v; do
  e=0; [ -e "$p" ] && e=1
  o=0; [ -f "$OFF" ] && grep -qxF "$p" "$OFF" && o=1
  last=$(grep -F " $p" "$ST" 2>/dev/null | tail -n 1)
  state=$(echo "$last" | awk '{print $1}')
  detail=$(echo "$last" | sed -n 's/^ *[A-Za-z]* *[^ ]* = //p')
  echo "T|$p|$v|$e|$o|$state|$detail"
done

exit 0
