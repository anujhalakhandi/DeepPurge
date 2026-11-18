#!/system/bin/sh
# Read-only device check for the WebUI. Prints "key=value" and "X|field|field…" lines.
MODDIR=${0%/*}
CONF=/data/adb/deeppurge
ST=$CONF/tuning.status
OFF=$CONF/tuning.off

echo "module=$(sed -n 's/^version=//p' "$MODDIR/module.prop")"
echo "model=$(getprop ro.product.marketname)"
echo "model2=$(getprop ro.product.model)"
echo "build=$(getprop ro.build.display.id)"
echo "android=$(getprop ro.build.version.release)"
echo "kernel=$(uname -r)"
echo "oplusrom=$(getprop ro.build.version.oplusrom)"
echo "avail_cc=$(cat /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null)"
L=/dev/deeppurge.lock
if [ -f "$L" ] && kill -0 "$(cat "$L" 2>/dev/null)" 2>/dev/null; then echo "running=$(cat "$L")"; else echo "running="; fi
[ -f "$CONF/webui.conf" ] && grep -E '^(mode|all|sections)=' "$CONF/webui.conf" | sed 's/^/ui_/'

# Sections, from the cleaner: S|number|kind|title|hint|left out by a quick clean
sh "$MODDIR/cleaner.sh" --info | sed 's/^/S|/'

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
