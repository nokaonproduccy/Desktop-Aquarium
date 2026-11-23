#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

if [[ "$(uname -s)" != Darwin ]]; then
  printf 'Build Koi Aquarium on macOS.\n' >&2
  exit 1
fi
if ! xcode-select -p >/dev/null 2>&1; then
  printf 'Install the Apple Command Line Tools with xcode-select --install, then run this file again.\n' >&2
  exit 1
fi

APP="$PWD/Koi Aquarium.app"
STAGING="$(mktemp -d "$PWD/.aquarium-build.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
BUNDLE="$STAGING/Koi Aquarium.app"
mkdir -p "$BUNDLE/Contents/MacOS"
unset SDKROOT TOOLCHAINS SWIFT_EXEC
shopt -s nullglob
printf 'import AppKit\n' > "$STAGING/Probe.swift"
build_with_tools() {
  local compiler sdk default_sdk sdk_parent
  compiler="$(xcrun --find swiftc 2>>"$STAGING/toolchain.log")" || return 2
  default_sdk="$(xcrun --sdk macosx --show-sdk-path 2>>"$STAGING/toolchain.log")" || return 2
  sdk_parent="$(dirname "$default_sdk")"

  for sdk in "$default_sdk" "$sdk_parent"/MacOSX[0-9]*.sdk; do
    [[ -d "$sdk" ]] || continue
    printf '\nChecking %s with %s\n' "$sdk" "$compiler" >> "$STAGING/toolchain.log"
    if "$compiler" -sdk "$sdk" -typecheck "$STAGING/Probe.swift" >>"$STAGING/toolchain.log" 2>&1; then
      printf 'Building with %s\n' "$sdk"
      "$compiler" -sdk "$sdk" -O Aquarium.swift -framework AppKit \
        -o "$BUNDLE/Contents/MacOS/Aquarium" || return 1
      return 0
    fi
  done
  return 2
}

result=2
if build_with_tools; then
  result=0
else
  result=$?
fi

for developer in /Applications/Xcode*.app/Contents/Developer "$HOME"/Applications/Xcode*.app/Contents/Developer; do
  [[ "$result" == 2 ]] || break
  if (export DEVELOPER_DIR="$developer"; build_with_tools); then
    result=0
  else
    result=$?
  fi
done

if [[ "$result" == 2 ]]; then
  tail -n 20 "$STAGING/toolchain.log" >&2
  printf '\nNo compatible Swift compiler and macOS SDK were found. Update Command Line Tools in System Settings → General → Software Update, or install a matching Xcode, then rerun this script.\n' >&2
  exit 1
fi
[[ "$result" == 0 ]] || exit "$result"
cp Info.plist "$BUNDLE/Contents/Info.plist"
codesign --force --sign - "$BUNDLE"
if [[ -e "$APP" ]]; then
  ditto "$BUNDLE" "$APP"
else
  mv "$BUNDLE" "$APP"
fi
open "$APP"
