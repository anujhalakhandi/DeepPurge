# DeepPurge installer (runs in the root manager's shell)
ui_print "- DeepPurge $(grep_prop version "$MODPATH/module.prop")"
mkdir -p /data/adb/deeppurge
set_perm_recursive "$MODPATH" 0 0 0755 0644
for f in post-fs-data.sh service.sh action.sh uninstall.sh probe.sh tuning.sh cleaner.sh; do
  set_perm "$MODPATH/$f" 0 0 0755
done
ui_print "- Boot tuning runs once at each boot. The cleaner only runs from the WebUI."
