#!/usr/bin/env bash
# Permanently remove a node VM and its disk. The node record in Hub (and its
# org registration) is NOT removed — delete it there too, or re-register.
#   Usage: bin/node-destroy.sh <name>
source "$(dirname "$0")/../lib/common.sh"
[ $# -eq 1 ] || die "usage: $0 <node-name>"
name="$1"
virsh_ dominfo "$name" >/dev/null 2>&1 || die "no such domain: $name"

read -r -p "Destroy $name and delete its disk? Type the name to confirm: " answer
[ "$answer" = "$name" ] || die "aborted"

virsh_ destroy "$name" >/dev/null 2>&1 || true
virsh_ undefine "$name" --remove-all-storage --nvram >/dev/null 2>&1 \
  || virsh_ undefine "$name" --remove-all-storage >/dev/null
ok "$name destroyed (base images under $POOL_DIR/base are kept)"
