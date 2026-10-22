#!/bin/zsh
# Builds Blossom (Release, Apple Silicon + Intel) and packs it into a tall DMG:
# the app on top, a small dotted arrow, and the Applications link below, on a quiet plum background.
#
# Usage: ./make-dmg.sh [output.dmg]     (default: ../Blossom-v<version>.dmg)
# Needs: Xcode, create-dmg (brew install create-dmg), Pillow (pip3 install pillow).
# The first run asks to let Terminal control Finder: Finder lays out the window.
set -euo pipefail

here=${0:A:h}
project=${here:h}
work=$(mktemp -d /tmp/blossom-dmg.XXXX)
trap 'rm -rf "$work"' EXIT

echo "Building Blossom…"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project "$project/Blossom.xcodeproj" -scheme Blossom -configuration Release \
  -derivedDataPath "$work/build" ONLY_ACTIVE_ARCH=NO -quiet build
app="$work/build/Build/Products/Release/Blossom.app"
version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$app/Contents/Info.plist")
out=${1:-$project/Blossom-v$version.dmg}

echo "Drawing the background…"
python3 "$here/background.py" "$work"
# One TIFF with both sizes, so the background is sharp on Retina screens
tiffutil -cathidpicheck "$work/background.png" "$work/background@2x.png" -out "$work/background.tiff"

mkdir "$work/source"
cp -R "$app" "$work/source/"

echo "Packing the DMG…"
rm -f "$out"
# Window and icon positions match APP and APPLICATIONS in background.py
create-dmg \
  --volname "Blossom" \
  --volicon "$app/Contents/Resources/AppIcon.icns" \
  --background "$work/background.tiff" \
  --window-pos 200 120 \
  --window-size 420 600 \
  --icon-size 112 \
  --text-size 13 \
  --icon "Blossom.app" 210 175 \
  --hide-extension "Blossom.app" \
  --app-drop-link 210 445 \
  --no-internet-enable \
  "$out" "$work/source"

echo "Done: $out"
