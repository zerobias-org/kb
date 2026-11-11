# Shared helpers for node-kvm-host scripts. Source, don't execute.
# shellcheck shell=bash

set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../config.env
source "$KIT_DIR/config.env"

log()  { printf '\e[1;34m[%s]\e[0m %s\n' "$(basename "$0" .sh)" "$*"; }
ok()   { printf '\e[1;32m[%s]\e[0m %s\n' "$(basename "$0" .sh)" "$*"; }
warn() { printf '\e[1;33m[%s]\e[0m %s\n' "$(basename "$0" .sh)" "$*" >&2; }
die()  { printf '\e[1;31m[%s]\e[0m %s\n' "$(basename "$0" .sh)" "$*" >&2; exit 1; }

# Re-exec the calling script under sudo, preserving args.
require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    exec sudo --preserve-env=SUDO_USER "$0" "$@"
  fi
}

# The human operator (not root) — for group membership etc.
operator_user() { echo "${SUDO_USER:-$(logname 2>/dev/null || id -un)}"; }

# Write $2 to file $1 only if content differs. Returns 0 if changed, 1 if not.
write_if_changed() {
  local path="$1" content="$2"
  if [ -f "$path" ] && [ "$(cat "$path")" = "$content" ]; then
    return 1
  fi
  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$content" > "$path"
  return 0
}

virsh_() { virsh --connect qemu:///system "$@"; }

# Resolve IMAGE_VERSION ("latest" or explicit) → "version url sha256".
resolve_image() {
  local manifest
  manifest="$(curl -fsSL --max-time 30 "$IMAGE_MANIFEST_URL")" || die "cannot fetch $IMAGE_MANIFEST_URL"
  MANIFEST="$manifest" python3 - "$IMAGE_VERSION" <<'PY'
import json, os, sys
want = sys.argv[1]
m = json.loads(os.environ["MANIFEST"])
def key(v):
    return tuple(int(p) if p.isdigit() else 0 for p in v.split('-')[0].split('.'))
vs = m["versions"]
if want == "latest":
    vs = sorted((v for v in vs if not v.get("prerelease")), key=lambda v: key(v["version"]), reverse=True)
else:
    vs = [v for v in vs if v["version"] == want]
for v in vs:
    for d in v["disk_images"]:
        if d["arch"] == "x64":
            print(v["version"], d["url"], d["sha256"]); sys.exit(0)
sys.exit(f"no x64 image for version '{want}' in manifest")
PY
}

base_image_path() { echo "$POOL_DIR/base/zb_node_v$1_x64.qcow2"; }

# Grow the root partition (p2) + ext4 of a not-yet-booted node disk to fill
# its virtual size. The image's own first-boot grow-root-disk does this online,
# but zerobias-update-boot isn't ordered after it: on a fresh 2.2G root the
# boot-time apt run hits ENOSPC, "succeeds" against stale indexes, and the node
# comes up un-upgraded. Pre-grown, there's nothing for first boot to race.
grow_root_offline() {
  local disk="$1" dev=""
  modprobe nbd max_part=8
  for d in /sys/block/nbd*; do
    [ -e "$d/pid" ] || { dev="/dev/$(basename "$d")"; break; }
  done
  [ -n "$dev" ] || die "no free /dev/nbd* device"
  qemu-nbd -c "$dev" -f qcow2 "$disk"
  # shellcheck disable=SC2064
  trap "qemu-nbd -d $dev >/dev/null" RETURN
  udevadm settle
  growpart "$dev" 2 || [ $? -eq 1 ]   # 1 = NOCHANGE (already full size)
  e2fsck -fy "${dev}p2" >/dev/null || [ $? -le 1 ]
  resize2fs "${dev}p2" >/dev/null 2>&1
}
