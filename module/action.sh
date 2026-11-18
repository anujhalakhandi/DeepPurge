#!/system/bin/sh
# Manager "Action" button: show the tuning status. It never starts the cleaner.
ST=/data/adb/deeppurge/tuning.status
echo "DEEPPURGE — TUNING STATUS (LAST BOOT)"
echo
if [ -f "$ST" ]; then cat "$ST"; else echo "No status yet. It is written at the next boot."; fi
echo
echo "Open the WebUI to change settings or run the cleaner."
