#!/usr/bin/env bash
# Host memory tuning for spiky guests.
#
# Node RAM in total must fit in the host's (most VPS providers do not allow
# oversubscription). Memory guests free flows back to the host via
# virtio-balloon free page reporting (set per-domain in 50-nodes.sh). This step
# adds the safety net for when guests and the host peak together:
#   - KSM (via ksmtuned): merges identical pages across guests — node VMs run
#     the same Debian image + same containers, so the win is real. ksmtuned
#     only scans when free memory gets low, so idle cost is ~zero.
#   - zram (zstd, high priority): compressed swap in RAM, absorbs the first wave.
#   - disk swapfile (low priority): last resort before the OOM killer picks a qemu.
#   - sysctls tuned for zram-first swapping and earlier background reclaim.
# No hugepages: they can't be swapped, merged or ballooned — the opposite of
# what overcommit needs. THP stays at Ubuntu's default (madvise; qemu opts in).
source "$(dirname "$0")/../lib/common.sh"
require_root "$@"

# --- zram ------------------------------------------------------------------
write_if_changed /etc/default/zramswap \
"ALGO=zstd
PERCENT=$ZRAM_PERCENT
PRIORITY=100" && log "configured zram (zstd, ${ZRAM_PERCENT}% of RAM, prio 100)" || true
systemctl enable --now zramswap.service >/dev/null 2>&1

# Reconcile the live device against the config. zramswap's own stop can't
# reset a device while the module is in use, so a plain restart keeps the
# old size/algo — swapoff + reset the device ourselves, then start it.
want_size=$(( $(awk '/^MemTotal/{print $2}' /proc/meminfo) * 1024 * ZRAM_PERCENT / 100 ))
have_size="$(cat /sys/block/zram0/disksize 2>/dev/null || echo 0)"
have_algo="$(sed -E 's/.*\[([a-z0-9-]+)\].*/\1/' /sys/block/zram0/comp_algorithm 2>/dev/null || true)"
if [ "$have_size" != "$want_size" ] || [ "$have_algo" != zstd ]; then
  log "zram0 is ${have_algo:-none}/$(( have_size >> 30 ))G, want zstd/$(( want_size >> 30 ))G — resetting"
  swapoff /dev/zram0 2>/dev/null || true
  echo 1 > /sys/block/zram0/reset
  systemctl restart zramswap.service
fi

# --- disk swapfile ---------------------------------------------------------
if [ ! -f "$SWAPFILE" ]; then
  log "creating $SWAPFILE ($SWAPFILE_SIZE)"
  fallocate -l "$SWAPFILE_SIZE" "$SWAPFILE"
  chmod 600 "$SWAPFILE"
  mkswap -q "$SWAPFILE"
fi
if ! grep -qE "^$SWAPFILE\s" /etc/fstab; then
  echo "$SWAPFILE none swap sw,pri=10 0 0" >> /etc/fstab
  log "added $SWAPFILE to /etc/fstab"
fi
[[ "$(swapon --show=NAME --noheadings)" == *"$SWAPFILE"* ]] || swapon -p 10 "$SWAPFILE"

# --- sysctls ---------------------------------------------------------------
# swappiness 100 + page-cluster 0: with zram in front, swapping cold guest
# pages early is cheap and keeps headroom for spikes. min_free/watermark: start
# kswapd sooner so a spike doesn't stall in direct reclaim.
if write_if_changed /etc/sysctl.d/90-zbnode-host.conf \
"vm.swappiness = 100
vm.page-cluster = 0
vm.min_free_kbytes = 1048576
vm.watermark_scale_factor = 125"; then
  sysctl -q --system
  log "applied sysctls"
fi

# --- KSM -------------------------------------------------------------------
systemctl enable --now ksmtuned.service >/dev/null 2>&1

ok "swap: $(swapon --show=NAME,SIZE,PRIO --noheadings | tr -s ' ' | paste -sd ';')"
ok "ksm: run=$(cat /sys/kernel/mm/ksm/run) (ksmtuned toggles it under memory pressure)"
