#!/usr/bin/env bash
# Builds the TubeMini .deb on a Linux machine that has Theos (docs/SETUP.md) and copies it back.
# Runs from Git Bash on Windows (or any POSIX shell).
#
#   TM_BUILD_HOST=user@host scripts/ios-build.sh [make args...]     e.g. FINALPACKAGE=1
#
# Env:
#   TM_BUILD_HOST   ssh target of the build machine (required)
#   TM_BUILD_KEY    ssh private key (optional)
#   TM_BUILD_DIR    work dir on the build machine (default: ~/TestLab/TubeMini)
#   THEOS_REMOTE    Theos dir on the build machine (default: ~/theos)
set -euo pipefail

: "${TM_BUILD_HOST:?set TM_BUILD_HOST=user@host of the Theos build machine}"
DIR="${TM_BUILD_DIR:-TestLab/TubeMini}"
REMOTE_THEOS="${THEOS_REMOTE:-\$HOME/theos}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/ios/TubeMini"
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=15)
[[ -n "${TM_BUILD_KEY:-}" ]] && SSH+=(-i "$TM_BUILD_KEY")

echo "==> sync ios/TubeMini -> $TM_BUILD_HOST:$DIR/src"
tar -C "$APP" --exclude=.theos --exclude=packages -cf - . |
    "${SSH[@]}" "$TM_BUILD_HOST" "rm -rf $DIR/src && mkdir -p $DIR/src && tar -xf - -C $DIR/src"

echo "==> make package $*"
"${SSH[@]}" "$TM_BUILD_HOST" "cd $DIR/src && export THEOS=$REMOTE_THEOS && make package $*"

echo "==> check binary (expect: armv7 only, minimum iOS 5.0)"
"${SSH[@]}" "$TM_BUILD_HOST" "cd $DIR/src && T=$REMOTE_THEOS/toolchain/linux/iphone/bin && B=\$(ls -t .theos/obj/*/TubeMini.app/TubeMini .theos/obj/TubeMini.app/TubeMini 2>/dev/null | head -1) && echo \$B && \$T/lipo -info \$B && \$T/otool -l \$B | grep -A3 LC_VERSION_MIN_IPHONEOS | grep -E 'version|sdk'"

DEB="$("${SSH[@]}" "$TM_BUILD_HOST" "ls -t $DIR/src/packages/*.deb | head -1")"
mkdir -p "$APP/packages"
SCP=(scp -o BatchMode=yes -q)
[[ -n "${TM_BUILD_KEY:-}" ]] && SCP+=(-i "$TM_BUILD_KEY")
"${SCP[@]}" "$TM_BUILD_HOST:$DEB" "$APP/packages/"
echo "==> $APP/packages/$(basename "$DEB")"
