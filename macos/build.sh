#!/usr/bin/env bash
# Builds bin/Clawd.app using the Swift compiler that ships with the Xcode Command
# Line Tools. Nothing to install beyond those: no SDK download, no packages, no Xcode
# project, no Swift Package Manager.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname "$here")"
app="$root/bin/Clawd.app"
bundle_id="com.clawd.Clawd"
min_macos="13.0"

if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "Could not find the Swift compiler."
  echo "Install the Xcode Command Line Tools with:  xcode-select --install"
  exit 1
fi

swiftc="$(xcrun --find swiftc)"
sdk="$(xcrun --show-sdk-path)"
sources=("$here"/Sources/*.swift)
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# -sdk has to be spelled out: overriding -target stops swiftc inferring it, and it then
# fails to find the standard library.
compile() {   # compile <arch> <output>
  "$swiftc" -O -wmo -swift-version 5 \
    -module-name Clawd \
    -target "$1-apple-macos$min_macos" -sdk "$sdk" \
    -framework AppKit -framework CoreGraphics -framework CoreAudio -framework ServiceManagement \
    -o "$2" "${sources[@]}"
}

# Universal where possible, so the same bundle runs on Apple silicon and Intel.
slices=()
for arch in arm64 x86_64; do
  if compile "$arch" "$work/Clawd-$arch" 2>"$work/$arch.log"; then
    slices+=("$work/Clawd-$arch")
  else
    if [ "$arch" = "$(uname -m)" ]; then
      echo
      echo "BUILD FAILED"
      cat "$work/$arch.log"
      exit 1
    fi
    echo "note: skipping the $arch slice (no SDK support on this machine)"
  fi
done

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

if [ "${#slices[@]}" -gt 1 ]; then
  lipo -create "${slices[@]}" -output "$app/Contents/MacOS/Clawd"
else
  cp "${slices[0]}" "$app/Contents/MacOS/Clawd"
fi

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>              <string>Clawd</string>
  <key>CFBundleDisplayName</key>       <string>Clawd</string>
  <key>CFBundleExecutable</key>        <string>Clawd</string>
  <key>CFBundleIdentifier</key>        <string>$bundle_id</string>
  <key>CFBundlePackageType</key>       <string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key>           <string>1</string>
  <key>CFBundleIconFile</key>          <string>Clawd</string>
  <key>LSMinimumSystemVersion</key>    <string>$min_macos</string>
  <key>LSUIElement</key>               <true/>
  <key>NSHighResolutionCapable</key>   <true/>
</dict>
</plist>
PLIST

# The icon is only for Finder: the app itself never shows in the Dock.
if [ -f "$root/assets/clawd-256.png" ]; then
  sips -s format icns "$root/assets/clawd-256.png" \
       --out "$app/Contents/Resources/Clawd.icns" >/dev/null 2>&1 || true
fi

# Ad-hoc signature. Nothing here is notarised, but a signed bundle is what "Open at
# login" needs in order to register itself, and it keeps Gatekeeper quiet on relaunch.
codesign --force --sign - --identifier "$bundle_id" "$app" >/dev/null 2>&1 \
  || echo "note: could not ad-hoc sign the bundle; Open at login may not work"

echo "Built bin/Clawd.app"
