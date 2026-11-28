#! /bin/bash

set -e

# Render hand-authored articles under package/ and sync them to the CDN.
# Same logic as auditlogic/kb scripts/cdnUpdate.sh — keep the two in step.
# (Generated "connect to" articles have no package/ dir: see cdnPublish.sh.)
#
#   default        articles whose files changed since $SINCE
#   REBUILD_LIST   only these (codes or dir names; comma/space/newline separated),
#                  unknown entries abort before anything renders
#   REBUILD_ALL    every article — for theme changes; publishes nothing
#
# Both repos render into the SAME CDN directory (/kb/<code>): the dataloader's
# default cdnDirectory is kb, and kbviewer sends every non-ct code to /kb/. That is
# safe only because the code prefixes differ (kb<N> there, kbc<N> here).
SINCE=${SINCE:-HEAD~2}
ROOT=$(pwd)
mkdir -p "$ROOT/data"

CDNROOT=${CDNROOT:-https://cdn.zerobias.com/kb}
S3URI=${S3URI:-s3://auditmation-cdn/kb}

# Nothing in this pipeline purges CloudFront, so without a short max-age a
# re-render stays invisible until the edge copy expires on its own.
CACHE_CONTROL=${CACHE_CONTROL:-"public, max-age=300, must-revalidate"}

if [ -n "${REBUILD_LIST:-}" ]; then
  PACKAGES=""
  MISSING=""
  for entry in $(printf '%s' "$REBUILD_LIST" | tr ',\n' '  '); do
    [ -z "$entry" ] && continue
    entry=${entry#package/}
    entry=${entry%/}
    if [ -d "package/$entry" ]; then
      match="package/$entry"
    else
      match=$(ls -d package/"$entry"-*/ 2>/dev/null | sed -E 's#/$##' | head -1)
    fi
    if [ -z "$match" ]; then
      MISSING="$MISSING $entry"
    else
      PACKAGES="${PACKAGES}${match}
"
    fi
  done
  if [ -n "$MISSING" ]; then
    echo "REBUILD_LIST: no package directory matches:$MISSING" >&2
    echo "Nothing rendered. Fix the list and re-run." >&2
    exit 1
  fi
  PACKAGES=$(printf '%s' "$PACKAGES" | sort -u || true)
  echo "REBUILD_LIST: re-rendering $(printf '%s\n' "$PACKAGES" | grep -c . ) named KB package(s)"
elif [ "${REBUILD_ALL:-false}" = "true" ]; then
  PACKAGES=$(ls -d package/*/ 2>/dev/null \
    | sed -E 's#/$##' \
    | sort || true)
  echo "REBUILD_ALL: re-rendering every KB package"
else
  PACKAGES=$(git diff --name-only "$SINCE" HEAD -- 'package/' \
    | grep -E '^package/[^/]+/' \
    | sed -E 's#^(package/[^/]+)/.*#\1#' \
    | sort -u || true)
fi

# Skip articles flagged deprecated in package.json. Skips are listed, not silent.
if [ "${INCLUDE_DEPRECATED:-false}" != "true" ]; then
  KEPT=""
  SKIPPED=""
  for package in $PACKAGES; do
    if [ "$(jq -r '(.zerobias.deprecated // .auditmation.deprecated) // false' "$ROOT/$package/package.json" 2>/dev/null)" = "true" ]; then
      SKIPPED="$SKIPPED $(basename "$package")"
    else
      KEPT="${KEPT}${package}
"
    fi
  done
  if [ -n "$SKIPPED" ]; then
    echo "Skipping $(printf '%s\n' $SKIPPED | grep -c .) deprecated package(s):$SKIPPED"
  fi
  PACKAGES=$(printf '%s' "$KEPT")
fi

if [ -z "$PACKAGES" ]; then
  echo "No changed KB packages since $SINCE — nothing to publish to CDN"
  exit 0
fi

echo "KB packages to render ($(echo "$PACKAGES" | wc -l | tr -d ' ')):"
echo "$PACKAGES"

# Fail the run unless the page just synced is really served: HTTP 200 and the
# article's own code in the body. A green run must mean the article is live.
# Retries cover CloudFront still holding a cached 404 for a brand-new article.
verify_live() {
  local url="$1" code="$2" attempt status body
  body=$(mktemp)
  for attempt in 1 2 3 4 5 6; do
    status=$(curl -s -o "$body" -w '%{http_code}' "$url?verify=$(date +%s)" || echo 000)
    if [ "$status" = "200" ] && grep -q "$code" "$body"; then
      echo "Live: $url"
      rm -f "$body"
      return 0
    fi
    echo "Not live yet ($status), attempt $attempt/6: $url"
    sleep 10
  done
  rm -f "$body"
  echo "CDN check failed: $url did not return 200 with code '$code'" >&2
  exit 1
}

for package in $PACKAGES; do
  [ -f "$ROOT/$package/package.json" ] || { echo "Skipping $package (no package.json)"; continue; }
  cd "$ROOT/$package"

  NAME=$(jq -r '.name' package.json)
  VERSION=$(jq -r '.version' package.json)

  echo "Checking dist-tags for $NAME@$VERSION"
  TAGS=$(npm view --json "$NAME@$VERSION" | jq -r '."dist-tags"')

  for tag in $(echo "$TAGS" | jq -r 'keys[]'); do
    tagVersion=$(echo "$TAGS" | jq --arg tag "$tag" -r '.[$tag]')
    echo "Checking $tag $tagVersion against $VERSION"
    if [ "$tagVersion" = "$VERSION" ]; then
      echo "Version matches, uploading new version to cdn"
      # Drop the scope before splitting: "@zerobias-org" itself contains a hyphen, so
      # splitting the full name gives "org/kb" instead of the code. (auditlogic/kb's
      # copy splits the full name, which only works because "@auditlogic" has none.)
      code=$(jq -r '.name | split("/")[1] | split("-")[1]' package.json)
      if ! [[ "$code" =~ ^kbc[0-9]+$ ]]; then
        echo "Refusing to publish: derived code '$code' from $NAME is not kbc<N>" >&2
        exit 1
      fi
      echo "{\"code\": \"$code\"}" > "$ROOT/data/kb.json"
      if [ "$tag" = "latest" ]; then
        npm run clean && npm run build -- -b "$CDNROOT/$code"
        aws s3 sync public "$S3URI/$code" --cache-control "$CACHE_CONTROL"
        verify_live "$CDNROOT/$code/index.html" "$code"
      elif [ "$tag" = "rc" ]; then
        echo "Skipping rc"
      else
        echo "Publishing $NAME@$VERSION to $tag"
        npm run clean && npm run build -- -b "$CDNROOT/$tag/$code"
        aws s3 sync public "$S3URI/$tag/$code" --cache-control "$CACHE_CONTROL"
        verify_live "$CDNROOT/$tag/$code/index.html" "$code"
      fi
    fi
  done

  cd "$ROOT"
done
