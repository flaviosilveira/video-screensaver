#!/bin/bash
# Usage: ./make-saver.sh <video.mp4|mov|m4v> <Name> [--install]
set -euo pipefail

usage() { echo "usage: $0 <video.mp4|mov|m4v> <Name> [--install]" >&2; exit 1; }

[[ $# -ge 2 ]] || usage
video=$1
name=$2
install=${3:-}

[[ -f $video ]] || { echo "video not found: $video" >&2; exit 1; }
ext=$(echo "${video##*.}" | tr '[:upper:]' '[:lower:]')
[[ $ext =~ ^(mp4|mov|m4v)$ ]] || { echo "unsupported video type: .$ext" >&2; exit 1; }
[[ $name =~ ^[A-Za-z][A-Za-z0-9]*$ ]] || { echo "name must be letters/digits, starting with a letter" >&2; exit 1; }

root=$(cd "$(dirname "$0")" && pwd)
slug=$(echo "$name" | tr '[:upper:]' '[:lower:]')
class="${name}VideoSaverView"
bundle_id="com.local.${slug}.screensaver"
saver="$root/build/$name.saver"
work="$root/build/obj/$name"

rm -rf "$saver" "$work"
mkdir -p "$saver/Contents/MacOS" "$saver/Contents/Resources" "$work"

sed "s/VideoSaverView/$class/g" "$root/Sources/VideoSaverView.swift" > "$work/$class.swift"
sed -e "s/__NAME__/$name/g" -e "s/__BUNDLE_ID__/$bundle_id/g" -e "s/__CLASS__/$class/g" \
    "$root/Resources/Info.plist" > "$saver/Contents/Info.plist"
plutil -lint -s "$saver/Contents/Info.plist"

xcrun swiftc -O -swift-version 5 \
    -target "$(uname -m)-apple-macos14.0" \
    -module-name "$class" \
    -emit-library -Xlinker -bundle \
    -o "$saver/Contents/MacOS/$name" "$work/$class.swift"

cp "$video" "$saver/Contents/Resources/video.$ext"
codesign --force --sign - "$saver"
codesign --verify --strict "$saver"
echo "built $saver"

if [[ $install == --install ]]; then
    dest="$HOME/Library/Screen Savers/$name.saver"
    mkdir -p "$HOME/Library/Screen Savers"
    if [[ -e $dest ]]; then
        backup="$dest.backup-$(date +%Y%m%d%H%M%S)"
        mv "$dest" "$backup"
        echo "previous version backed up to $backup"
    fi
    ditto "$saver" "$dest"
    # Drop the cached host process so System Settings picks up the new build.
    killall legacyScreenSaver 2>/dev/null || true
    echo "installed $dest"
fi
