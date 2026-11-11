#!/usr/bin/env bash
# Node VMs + host memory picture (overcommit, balloon, KSM, swap).
source "$(dirname "$0")/../lib/common.sh"

printf '%-16s %-10s %5s %8s %10s %8s  %s\n' NAME STATE VCPU MAX_GB RSS_GB VNC IP
for d in $(virsh_ list --all --name); do
  state="$(virsh_ domstate "$d")"
  vcpu="$(virsh_ dominfo "$d" | awk '/^CPU\(s\)/{print $2}')"
  max="$(( $(virsh_ dominfo "$d" | awk '/^Max memory/{print $3}') / 1048576 ))"
  rss="-" ip="-" vnc="-"
  if [ "$state" = running ]; then
    rss="$(virsh_ dommemstat "$d" | awk '/^rss/{printf "%.1f", $2/1048576}')"
    ip="$(virsh_ domifaddr "$d" --source lease 2>/dev/null | awk '/ipv4/{print $4}' | head -1)"
    disp="$(virsh_ vncdisplay "$d" 2>/dev/null)" && vnc=$(( 5900 + ${disp##*:} ))
  fi
  printf '%-16s %-10s %5s %8s %10s %8s  %s\n' "$d" "$state" "$vcpu" "$max" "$rss" "$vnc" "${ip:--}"
done

echo
free -g | awk 'NR<=3'
echo "KSM: run=$(cat /sys/kernel/mm/ksm/run) pages_sharing=$(cat /sys/kernel/mm/ksm/pages_sharing) (~$(( $(cat /sys/kernel/mm/ksm/pages_sharing) * 4 / 1024 ))M saved)"
swapon --show
