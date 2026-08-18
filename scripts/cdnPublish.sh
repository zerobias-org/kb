#! /bin/bash

set -e

# Re-render published ct articles onto the CDN, without touching npm.
#
# WHY THIS EXISTS
#
# A theme change reaches NO article on its own. Articles are static HTML rendered
# at publish time, so `generate-kb` only re-renders the one package a module release
# happened to dispatch for. Everything else keeps serving whatever theme it was
# rendered with — which is how all the live ct articles ended up several theme
# revisions behind while the templates in this repo moved on.
#
# auditlogic/kb solves the same problem with scripts/cdnUpdate.sh + its REBUILD_LIST
# input. This is the ct counterpart, and deliberately mirrors it: same dist-tag loop,
# same rc skip, same cache-control, same abort-before-rendering on a bad entry.
#
# HOW IT DIFFERS FROM cdnUpdate.sh, AND WHY
#
# cdnUpdate.sh renders from `package/<dir>/` on disk. This repo has no package/ dir —
# ct articles exist only as PUBLISHED npm packages, generated from auditlogic/module
# vendor packages. So the article source is fetched with `npm pack` instead of read
# from the working tree. Nothing is published, versioned, or dist-tagged here; this
# only re-renders what is already published and copies it to the CDN.
#
# NO REBUILD_ALL, ON PURPOSE
#
# There is no reliable way to enumerate the ct packages. `npm search @auditlogic/kb-ct`
# against pkg.zerobias.org returns ZERO results for a scope that demonstrably has
# packages — `npm view @auditlogic/kb-ctgithubgithub-github-github` resolves fine with
# five dist-tags. A rebuild-all built on that search would silently render a fraction
# of the fleet and report success, which is worse than having no rebuild-all. The list
# is explicit until something can enumerate them honestly.
#
# Note the package SCOPE is inherited from the module, not fixed: a ct article built
# from @auditlogic/module-github-github publishes as @auditlogic/kb-ctgithubgithub-…,
# while one built from a @zerobias-org module publishes under @zerobias-org. Pass the
# full package name so the scope is never guessed.
#
# USAGE
#
#   REBUILD_LIST="@auditlogic/kb-ctgithubgithub-github-github" ./scripts/cdnPublish.sh
#
# Entries are separated by commas, spaces or newlines. CODE_PREFIX, CDNROOT, S3URI and
# CACHE_CONTROL are all env-overridable; pointing S3URI at a local directory renders
# without touching the CDN, which is how this gets exercised outside CI.

ROOT=$(pwd)
CODE_PREFIX=${CODE_PREFIX:-ct}
CDNROOT=${CDNROOT:-https://cdn.zerobias.com/$CODE_PREFIX}
S3URI=${S3URI:-s3://auditmation-cdn/$CODE_PREFIX}

# Rendered articles otherwise ship with NO caching header at all, which leaves
# CloudFront on the distribution default TTL and the BROWSER on heuristic freshness —
# a window derived from the object's age, with no revalidation, so the longer an
# article sits the longer a reader keeps a stale copy. Five minutes plus revalidation
# makes propagation predictable. Same value as auditlogic/kb's cdnUpdate.sh, so kb and
# ct articles age out of the edge on the same clock.
#
# It matters more here than on a normal site because nothing in this pipeline purges
# CloudFront: no distributionId reaches this workflow, so a re-render stays invisible
# until the edge copy expires on its own.
CACHE_CONTROL=${CACHE_CONTROL:-"public, max-age=300, must-revalidate"}

if [ -z "${REBUILD_LIST:-}" ]; then
  echo "REBUILD_LIST is empty — nothing to do." >&2
  echo "Pass published ct article package names, e.g." >&2
  echo "  REBUILD_LIST=\"@auditlogic/kb-ctgithubgithub-github-github\"" >&2
  exit 1
fi

mkdir -p "$ROOT/data"

# The registry credentials npm needs to see the private scopes. `npm pack` runs in a
# temp directory outside the repo, so it cannot pick up the root .npmrc — each temp
# dir gets its own copy, same as actions/generate-kb does.
NPMRC='@auditlogic:registry=https://pkg.zerobias.org
@zerobias-org:registry=https://pkg.zerobias.org
//pkg.zerobias.org/:_authToken=${ZB_TOKEN}'

PACKAGES=$(printf '%s' "$REBUILD_LIST" | tr ',\n\r\t' '    ' | tr -s ' ' | sed -E 's/^ +| +$//g')

# Resolve every entry BEFORE rendering anything. A typo that surfaced halfway through
# would leave the fleet half-updated and still exit non-zero, which reads exactly like
# a partial outage; failing first costs one npm call per entry and leaves the CDN
# untouched.
MISSING=""
for package in $PACKAGES; do
  case "$package" in
    */kb-*) ;;
    *)
      MISSING="$MISSING $package(not-a-kb-package-name)"
      continue
      ;;
  esac
  if ! npm view --json "$package" dist-tags > /dev/null 2>&1; then
    MISSING="$MISSING $package"
  fi
done

if [ -n "$MISSING" ]; then
  echo "REBUILD_LIST: these entries do not resolve on the registry:$MISSING" >&2
  echo "Nothing rendered. Fix the list and re-run." >&2
  exit 1
fi

echo "ct articles to re-render ($(printf '%s\n' $PACKAGES | grep -c .)):"
printf '  %s\n' $PACKAGES

for package in $PACKAGES; do
  # Same derivation cdnUpdate.sh uses: the code is the second dash-delimited field of
  # the package name (@scope/kb-<code>-<module>). It cannot be recovered from the code
  # alone — ctamazonawss3 came from amazon-aws-s3 and the dashes are gone — which is
  # why this takes package names rather than bare codes.
  CODE=$(printf '%s' "$package" | sed -E 's#.*/kb-([^-]+)-.*#\1#')
  echo "==> $package (code $CODE)"

  TAGS=$(npm view --json "$package" dist-tags)

  for tag in $(printf '%s' "$TAGS" | jq -r 'keys[]'); do
    VERSION=$(printf '%s' "$TAGS" | jq --arg tag "$tag" -r '.[$tag]')

    # rc is skipped for the same reason cdnUpdate.sh skips it: there is no /ct/rc/ or
    # /kb/rc/ path on the CDN, and the rc tag routinely points at an older version
    # than the rest, so rendering it would publish a different article to a URL
    # nothing serves.
    if [ "$tag" = "rc" ]; then
      echo "  $tag $VERSION — skipping rc"
      continue
    fi

    if [ "$tag" = "latest" ]; then
      BASE="$CDNROOT/$CODE"
      DEST="$S3URI/$CODE"
    else
      BASE="$CDNROOT/$tag/$CODE"
      DEST="$S3URI/$tag/$CODE"
    fi

    echo "  $tag $VERSION -> $DEST"

    # Each tag is fetched at ITS OWN version rather than rendering one version to every
    # path. The tags drift apart in normal operation (dev ahead of latest, uat behind),
    # and flattening them here would quietly overwrite one environment's article with
    # another's.
    TMPDIR=$(mktemp -d)
    printf '%s' "$NPMRC" > "$TMPDIR/.npmrc"
    ( cd "$TMPDIR" && npm pack --silent "$package@$VERSION" > /dev/null )
    TARBALL=$(ls "$TMPDIR"/*.tgz | head -1)
    tar xf "$TARBALL" -C "$TMPDIR"
    CONTENT="$TMPDIR/package"

    # script-header.html reads hugo.Data.kb.code to stamp the KBNavLoad message the
    # embedding app listens for, and Hugo only sees it through the site data dir.
    echo "{\"code\": \"$CODE\"}" > "$ROOT/data/kb.json"

    rm -rf "$CONTENT/public"
    hugo --source "$ROOT" --contentDir "$CONTENT" --destination "$CONTENT/public" -b "$BASE"
    aws s3 sync "$CONTENT/public" "$DEST" --cache-control "$CACHE_CONTROL"

    rm -rf "$TMPDIR"
  done
done

echo "Done."
