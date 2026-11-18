# DeepPurge installer (runs in the root manager's shell)
ui_print "- DeepPurge $(grep_prop version "$MODPATH/module.prop")"
mkdir -p /data/adb/deeppurge
# The standalone boot scripts from the Termux version would apply the tuning a second time
for f in /data/adb/post-fs-data.d/99_deeppurge_tuning.sh /data/adb/service.d/99_deeppurge_tuning.sh \
         /data/adb/post-fs-data.d/99_deeppurge_net.sh; do
  [ -f "$f" ] && rm -f "$f" && ui_print "- Removed $f (the module applies the tuning now)"
done
if [ -x /data/data/com.termux/files/usr/bin/bash ]; then
  ui_print "- Termux found: the cleaner is available in the WebUI"
else
  ui_print "! Termux not found: boot tuning works, but the cleaner needs Termux's bash"
fi
set_perm_recursive "$MODPATH" 0 0 0755 0644
for f in post-fs-data.sh service.sh action.sh uninstall.sh probe.sh tuning.sh deeppurge.sh; do
  [ -f "$MODPATH/$f" ] && set_perm "$MODPATH/$f" 0 0 0755
done
ui_print "- Only the tuning runs at boot. The cleaner never runs on its own."
