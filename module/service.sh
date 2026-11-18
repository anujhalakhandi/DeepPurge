#!/system/bin/sh
# Tuning pass 2: 20 s after boot completes, after vendor boot scripts. Runs once and exits.
MODDIR=${0%/*}
until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 3; done
sleep 20
[ -f "$MODDIR/tuning.sh" ] && PASS=2 sh "$MODDIR/tuning.sh"
