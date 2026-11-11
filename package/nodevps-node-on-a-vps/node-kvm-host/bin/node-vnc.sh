#!/usr/bin/env bash
# Print how to reach a node's VGA console over VNC. VNC listens on
# 127.0.0.1 only, so connect through an SSH tunnel from your workstation.
#   Usage: bin/node-vnc.sh <name>
source "$(dirname "$0")/../lib/common.sh"
[ $# -eq 1 ] || die "usage: $0 <node-name>"
disp="$(virsh_ vncdisplay "$1")" || die "no VNC display for '$1' (is it running?)"
port=$(( 5900 + ${disp##*:} ))
host="$(hostname -f 2>/dev/null || hostname)"
cat <<EOF
$1 VNC: 127.0.0.1:$port (display $disp)

From your workstation:
  ssh -N -L $port:127.0.0.1:$port $(id -un)@$host
then point a VNC client at localhost:$port
EOF
