#!/usr/bin/env bash
# KVM + libvirt packages, services, and operator group membership.
source "$(dirname "$0")/../lib/common.sh"
require_root "$@"

PKGS=(qemu-system-x86 qemu-utils libvirt-daemon-system libvirt-clients virtinst
      ovmf ksmtuned zram-tools curl python3 jq
      cloud-guest-utils gdisk e2fsprogs)   # growpart (+sgdisk for GPT) for 50-nodes' offline root grow

missing=()
for p in "${PKGS[@]}"; do
  [ "$(dpkg-query -W -f='${Status}' "$p" 2>/dev/null)" = "install ok installed" ] || missing+=("$p")
done
if [ ${#missing[@]} -gt 0 ]; then
  log "installing: ${missing[*]}"
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends "${missing[@]}"
else
  ok "packages already installed"
fi

systemctl enable --now libvirtd.service >/dev/null 2>&1 || systemctl enable --now virtqemud.socket
# Gracefully shut guests down on host reboot instead of hard-killing them.
systemctl enable libvirt-guests.service >/dev/null 2>&1 || true
write_if_changed /etc/default/libvirt-guests \
'ON_BOOT=ignore
ON_SHUTDOWN=shutdown
SHUTDOWN_TIMEOUT=120' && log "configured libvirt-guests (shutdown on host reboot)" || true

user="$(operator_user)"
for g in kvm libvirt; do
  if [[ " $(id -nG "$user") " == *" $g "* ]]; then
    ok "$user already in $g"
  else
    usermod -aG "$g" "$user"
    warn "added $user to $g — log out/in (or 'newgrp $g') for it to take effect"
  fi
done

ok "kvm/libvirt ready ($(virsh --version) libvirt, $(qemu-system-x86_64 --version | head -1))"
