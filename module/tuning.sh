#!/system/bin/sh
# DeepPurge boot tuning. Run with PASS=1 by post-fs-data.sh, PASS=2 by service.sh,
# and PASS=now by the WebUI's "Apply now". Runs once and exits.
CONF=/data/adb/deeppurge
ST=$CONF/tuning.status   # every value of the last boot: ok / FAIL / missing / off
OFF=$CONF/tuning.off     # paths turned off in the WebUI, one per line
PASS=${PASS:-now}
mkdir -p "$CONF"
[ "$PASS" = 1 ] && : > "$ST"   # new boot: start a fresh record
echo "pass $PASS  boot+$(cut -d. -f1 /proc/uptime)s  $(date '+%F %T')" >> "$ST"

# w PATH VALUE — write, read back, record the result
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
