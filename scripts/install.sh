#!/bin/zsh
# Build a signed Release of OpenText and install the one copy at /Applications/OpenText.app.
# Builds in a throwaway DerivedData folder and deletes it afterwards, so Spotlight and
# "Open With" never see a second OpenText. Never launches the app.
set -euo pipefail

repo=${0:A:h:h}
dd=$(mktemp -d /tmp/opentext-build.XXXXXX)
lsr=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
dest=/Applications/OpenText.app

cleanup() { "$lsr" -u "$dd/Build/Products/Release/OpenText.app" 2>/dev/null || true; rm -rf "$dd"; }
trap cleanup EXIT

cd "$repo"
xcodebuild -project OpenText.xcodeproj -scheme OpenText -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$dd" \
  DEVELOPMENT_TEAM=7ZT7J8C9QP -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  build -quiet

# Drop every other registered copy (old build folders, DerivedData) before installing.
"$lsr" -dump 2>/dev/null | grep -E "^path:.*/OpenText\.app \(" | sed -E 's/^path: +//; s/ \(0x[0-9a-f]+\)$//' | sort -u |
  while read -r p; do [[ "$p" == "$dest" ]] || "$lsr" -u "$p" 2>/dev/null || true; done

rm -rf "$dest"
ditto "$dd/Build/Products/Release/OpenText.app" "$dest"
codesign --verify --deep --strict "$dest"
"$lsr" -f "$dest"
echo "Installed $dest"
