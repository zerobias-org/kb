#!/usr/bin/env bash
# libvirt NAT network + the dir storage pool node disks live in.
source "$(dirname "$0")/../lib/common.sh"
require_root "$@"

# --- network ---------------------------------------------------------------
if ! virsh_ net-info "$LIBVIRT_NET" >/dev/null 2>&1; then
  [ "$LIBVIRT_NET" = default ] || die "network '$LIBVIRT_NET' does not exist"
  log "defining libvirt 'default' NAT network"
  virsh_ net-define /usr/share/libvirt/networks/default.xml >/dev/null
fi
# Capture before grepping: `virsh | grep -q` under pipefail fails when grep
# exits early and virsh takes SIGPIPE.
info="$(virsh_ net-info "$LIBVIRT_NET")"
grep -q 'Active:.*yes'    <<<"$info" || virsh_ net-start "$LIBVIRT_NET" >/dev/null
grep -q 'Autostart:.*yes' <<<"$info" || virsh_ net-autostart "$LIBVIRT_NET" >/dev/null
ok "network '$LIBVIRT_NET' active + autostart"

# --- storage pool ----------------------------------------------------------
mkdir -p "$POOL_DIR/base"
if ! virsh_ pool-info "$POOL_NAME" >/dev/null 2>&1; then
  log "defining dir pool '$POOL_NAME' at $POOL_DIR"
  virsh_ pool-define-as "$POOL_NAME" dir --target "$POOL_DIR" >/dev/null
fi
info="$(virsh_ pool-info "$POOL_NAME")"
grep -q 'State:.*running' <<<"$info" || virsh_ pool-start "$POOL_NAME" >/dev/null
grep -q 'Autostart:.*yes' <<<"$info" || virsh_ pool-autostart "$POOL_NAME" >/dev/null
ok "pool '$POOL_NAME' ($POOL_DIR) running + autostart"
