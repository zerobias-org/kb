#!/usr/bin/env bash
# Create (or reconcile) one libvirt domain per nodes/*.env.
#
# Create-only: an existing domain is never redefined or its disk touched —
# this step just ensures it's autostarted + running and reports drift from
# the .env. To change an existing node's shape, edit the .env and use
# `virsh setvcpus/setmaxmem --config`, or bin/node-destroy.sh + re-run.
#
# Registration is done by hand on the console (bin/node-console.sh or VNC):
# the node TUI shows the registration flow on first boot.
source "$(dirname "$0")/../lib/common.sh"
require_root "$@"

shopt -s nullglob
envs=("$KIT_DIR"/nodes/*.env)
[ ${#envs[@]} -gt 0 ] || { warn "no nodes/*.env — nothing to do"; exit 0; }

for env in "${envs[@]}"; do
  # Per-node defaults, overridable in the .env.
  NAME="" VCPUS=8 MEMORY_GB=16 DISK_GB=200 VNC_PORT="" NODE_IMAGE_VERSION=""
  # shellcheck disable=SC1090
  source "$env"
  [ -n "$NAME" ] || die "$env: NAME is required"
  [ -n "$VNC_PORT" ] || die "$env: VNC_PORT is required (stable port per node)"

  if virsh_ dominfo "$NAME" >/dev/null 2>&1; then
    cur_vcpus="$(virsh_ dominfo "$NAME" | awk '/^CPU\(s\)/{print $2}')"
    cur_mem_gb="$(( $(virsh_ dominfo "$NAME" | awk '/^Max memory/{print $3}') / 1048576 ))"
    [ "$cur_vcpus" = "$VCPUS" ]      || warn "$NAME: has $cur_vcpus vCPU, .env says $VCPUS (not changed)"
    [ "$cur_mem_gb" = "$MEMORY_GB" ] || warn "$NAME: has ${cur_mem_gb}G, .env says ${MEMORY_GB}G (not changed)"
    virsh_ autostart "$NAME" >/dev/null
    if [ "$(virsh_ domstate "$NAME")" != running ]; then
      virsh_ start "$NAME" >/dev/null && log "$NAME: started"
    fi
    ok "$NAME: exists, $(virsh_ domstate "$NAME")"
    continue
  fi

  IMAGE_VERSION="${NODE_IMAGE_VERSION:-$IMAGE_VERSION}"
  read -r version _ _ <<<"$(resolve_image)"
  base="$(base_image_path "$version")"
  [ -f "$base" ] || die "$NAME: base image $base missing — run step 40 (IMAGE_VERSION=$IMAGE_VERSION)"

  disk="$POOL_DIR/$NAME.qcow2"
  if [ ! -f "$disk" ]; then
    qemu-img create -q -f qcow2 -F qcow2 -b "$base" "$disk" "${DISK_GB}G"
    grow_root_offline "$disk"
    log "$NAME: disk $disk (${DISK_GB}G thin, root pre-grown, backed by v$version)"
  fi
  virsh_ pool-refresh "$POOL_NAME" >/dev/null

  log "$NAME: defining (${VCPUS} vCPU, ${MEMORY_GB}G, VNC 127.0.0.1:$VNC_PORT)"
  # host-passthrough: expose this (L1) CPU's features to the L2 guest as-is —
  # the cheapest model under nested virt, and the node needs nothing portable.
  # memballoon freePageReporting: guest hands freed pages back to the host —
  # what makes the RAM overcommit in 20-memory.sh hold up with spiky guests.
  # discard=unmap: guest TRIM shrinks the thin overlay.
  # VGA + ttyS0: the node TUI renders on both; VNC listens on localhost only
  # (this host has a public IP) — reach it with an SSH tunnel.
  virt-install --connect qemu:///system \
    --name "$NAME" \
    --import \
    --osinfo debian12 \
    --machine q35 \
    --vcpus "$VCPUS" \
    --cpu host-passthrough \
    --memory "$(( MEMORY_GB * 1024 ))" \
    --memballoon model=virtio,freePageReporting=on \
    --disk "path=$disk,format=qcow2,bus=virtio,cache=none,discard=unmap" \
    --network "network=$LIBVIRT_NET,model=virtio" \
    --graphics "vnc,listen=127.0.0.1,port=$VNC_PORT" \
    --video vga \
    --serial pty \
    --console pty,target_type=serial \
    --rng /dev/urandom \
    --autostart \
    --noautoconsole \
    >/dev/null
  ok "$NAME: created + started — register it from the console: bin/node-console.sh $NAME"
done
