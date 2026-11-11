#!/usr/bin/env bash
# Read-only sanity checks. Fails fast if this host can't run KVM guests.
source "$(dirname "$0")/../lib/common.sh"

grep -qE '(vmx|svm)' /proc/cpuinfo || die "no vmx/svm CPU flag — your VPS provider does not expose nested virtualization to this VM"
[ -e /dev/kvm ] || die "/dev/kvm missing — kvm module not loaded"

virt="$(systemd-detect-virt 2>/dev/null || true)"
if [ "$virt" != "none" ] && [ -n "$virt" ]; then
  log "running nested (this host is a '$virt' guest) — node VMs are L2 guests"
fi

. /etc/os-release
log "host: $PRETTY_NAME, kernel $(uname -r), $(nproc) vCPU, $(free -g | awk '/^Mem:/{print $2}')G RAM"
log "disk free on /: $(df -h --output=avail / | tail -1 | tr -d ' ')"
ok "preflight passed"
