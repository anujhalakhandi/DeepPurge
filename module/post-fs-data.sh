#!/system/bin/sh
# Tuning pass 1: at the very start of boot, before network interfaces exist
MODDIR=${0%/*}
[ -f "$MODDIR/tuning.sh" ] && PASS=1 sh "$MODDIR/tuning.sh"
