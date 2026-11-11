#!/usr/bin/env bash
# Rename a node VM: libvirt domain, its disk file, and NAME in its nodes/*.env.
# libvirt can only rename a shut-off domain, so this gracefully shuts the node
# down first (ACPI, guest-side systemd shutdown) and starts it again after.
# Don't run it while the node is mid-update (dpkg lock held) — wait for the
# update's reboot to finish.
#   Usage: bin/node-rename.sh <old-name> <new-name>
source "$(dirname "$0")/../lib/common.sh"
require_root "$@"
[ $# -eq 2 ] || die "usage: $0 <old-name> <new-name>"
old="$1" new="$2"

virsh_ dominfo "$old" >/dev/null 2>&1 || die "no such domain: $old"
virsh_ dominfo "$new" >/dev/null 2>&1 && die "domain already exists: $new"

env_file="$(grep -lx "NAME=$old" "$KIT_DIR"/nodes/*.env 2>/dev/null | head -1 || true)"
[ -n "$env_file" ] || warn "no nodes/*.env has NAME=$old — renaming the domain only"

was_running=false
if [ "$(virsh_ domstate "$old")" = running ]; then
  was_running=true
  log "$old: shutting down"
  virsh_ shutdown "$old" >/dev/null
  for _ in $(seq 1 180); do
    [ "$(virsh_ domstate "$old")" = "shut off" ] && break
    sleep 1
  done
  [ "$(virsh_ domstate "$old")" = "shut off" ] || die "$old did not shut down within 180s — left as is"
fi

virsh_ domrename "$old" "$new" >/dev/null
log "domain: $old → $new"

old_disk="$POOL_DIR/$old.qcow2" new_disk="$POOL_DIR/$new.qcow2"
if [ -f "$old_disk" ]; then
  mv "$old_disk" "$new_disk"
  virt-xml --connect qemu:///system "$new" --edit target=vda --disk "path=$new_disk" >/dev/null
  virsh_ pool-refresh "$POOL_NAME" >/dev/null
  log "disk: $old_disk → $new_disk"
fi

if [ -n "$env_file" ]; then
  new_env="$KIT_DIR/nodes/$new.env"
  sed -i "s/^NAME=$old\$/NAME=$new/" "$env_file"
  [ "$env_file" = "$new_env" ] || mv "$env_file" "$new_env"
  chown --reference="$KIT_DIR" "$new_env"
  log "env: $(basename "$env_file") → $(basename "$new_env")"
fi

virsh_ autostart "$new" >/dev/null
$was_running && virsh_ start "$new" >/dev/null
ok "$new ready ($(virsh_ domstate "$new"))"
