#!/usr/bin/env bash
# Download + verify the node qcow2 base image from the CDN.
#
# Base images are kept per version and never modified — node disks are qcow2
# overlays backed by them (50-nodes.sh), so a base must stay as long as any
# node references it. A new IMAGE_VERSION only affects nodes created after it.
# Running nodes don't need it anyway: AUTO_UPDATE=auto apt-upgrades them.
source "$(dirname "$0")/../lib/common.sh"
require_root "$@"

read -r version url sha <<<"$(resolve_image)"
dest="$(base_image_path "$version")"
log "image: v$version ($url)"

if [ -f "$dest" ] && echo "$sha  $dest" | sha256sum -c --quiet 2>/dev/null; then
  ok "already present + verified: $dest"
  exit 0
fi

mkdir -p "$(dirname "$dest")"
tmp="$dest.part"
curl -fL --retry 3 -C - -o "$tmp" "$url"
echo "$sha  $tmp" | sha256sum -c --quiet || { rm -f "$tmp"; die "sha256 mismatch for $url"; }
mv "$tmp" "$dest"
chmod 0444 "$dest"
ok "downloaded + verified: $dest ($(qemu-img info --output=json "$dest" | jq -r '."virtual-size" / 1073741824 | floor')G virtual)"
