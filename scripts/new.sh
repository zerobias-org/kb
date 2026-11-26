#! /bin/bash
# Scaffold a hand-authored article:  ./scripts/new.sh kbc<N>-<slug> "<description>"
#
# <N> is the next free number in THIS repo (highest package/kbc* + 1).
# auditlogic/kb owns kb<N>; this repo owns kbc<N> — the gate rejects anything else.
set -e

export HUGO_NAME=$1
export HUGO_DESCRIPTION=$2
export HUGO_AUTHOR=$(git config --get user.email)
IFS=- read code rest <<< "$HUGO_NAME"
export HUGO_CODE=$code
export HUGO_TITLE=$rest

if ! [[ "$HUGO_CODE" =~ ^kbc[0-9]+$ ]] || [ -z "$HUGO_TITLE" ]; then
  echo "usage: $0 kbc<N>-<slug> \"<description>\"   (got '$HUGO_NAME')" >&2
  exit 1
fi
if ls -d package/"$HUGO_CODE"-*/ > /dev/null 2>&1; then
  echo "$HUGO_CODE is already taken: $(ls -d package/"$HUGO_CODE"-*/)" >&2
  exit 1
fi

mkdir -p package
hugo new --kind kb --contentDir=package $HUGO_NAME

mv package/$1/package.json.md package/$1/package.json

# Gradle/zbb pipeline: every package needs a per-package marker and an
# .npmrc (the gate validator requires both).
mv package/$1/build.gradle.kts.md package/$1/build.gradle.kts
cp .npmrc package/$1/.npmrc
