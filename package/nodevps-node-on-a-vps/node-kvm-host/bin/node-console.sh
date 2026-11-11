#!/usr/bin/env bash
# Attach to a node's serial console (ttyS0) — same TUI as `zbb run qemu`.
# Detach with Ctrl+].   Usage: bin/node-console.sh <name>
source "$(dirname "$0")/../lib/common.sh"
[ $# -eq 1 ] || die "usage: $0 <node-name>"
exec virsh --connect qemu:///system console "$1"
