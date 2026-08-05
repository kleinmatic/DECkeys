#!/bin/sh
# Build DECkeys.app.
#
# SIGNING MATTERS MORE THAN IT LOOKS.  macOS attaches an Accessibility grant to
# an app's "designated requirement".  Ad-hoc signing (codesign -s -) makes that
# requirement a raw hash of the binary:
#
#     designated => cdhash H"c89320224e49b5ee5502..."
#
# so every rebuild is a different app as far as TCC is concerned, and you have
# to re-grant Accessibility every single time.  Signing with a stable
# self-signed identity instead makes it
#
#     designated => identifier "com.kleinmatic.deckeys" and certificate leaf ...
#
# which survives rebuilds.  Run ./make-cert.sh once to create that identity.
set -e
cd "$(dirname "$0")"

IDENTITY="DECkeys Local Signing"
APP=DECkeys.app

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>DECkeys</string>
    <key>CFBundleDisplayName</key>     <string>DECkeys</string>
    <key>CFBundleExecutable</key>      <string>DECkeys</string>
    <key>CFBundleIdentifier</key>      <string>com.kleinmatic.deckeys</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>0.2</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>CFBundleIconFile</key>        <string>DECkeys</string>
    <key>LSUIElement</key>             <true/>
    <key>NSHighResolutionCapable</key> <true/>
</dict>
</plist>
PLIST

# The bundled copy is the fallback; the editable one lives in ~/.config/deckeys.
cp profile.json "$APP/Contents/Resources/profile.json"
# Icon: the PF1 keycap. Regenerate with ./make-icon.sh if you change the art.
[ -f DECkeys.icns ] && cp DECkeys.icns "$APP/Contents/Resources/DECkeys.icns"

swiftc -O -o "$APP/Contents/MacOS/DECkeys" DECkeys.swift \
    -framework AppKit -framework ApplicationServices

if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    # NOT --options runtime.  The Hardened Runtime blocks synthetic event
    # posting without specific entitlements, so adding it silently killed every
    # button (2026-08-04).  A locally-signed development app gains nothing from
    # it here.
    codesign --force --sign "$IDENTITY" "$APP"
    echo "signed with: $IDENTITY"
else
    codesign --force --sign - "$APP"
    echo "WARNING: '$IDENTITY' not found — fell back to ad-hoc signing, so the"
    echo "         Accessibility grant will NOT survive this rebuild."
    echo "         Run ./make-cert.sh once to fix that permanently."
fi

echo "--- designated requirement (what TCC keys the grant on) ---"
codesign -d -r- "$APP" 2>&1 | grep designated || true
echo "built $APP"

# ./build.sh install  -- put it in /Applications.  Safe: the Accessibility grant
# is keyed to the bundle id + signing certificate, not the path, so it survives
# the move (verified).  Your profile stays in ~/.config/deckeys/profile.json,
# outside the bundle, so a rebuild cannot overwrite it.
if [ "${1:-}" = install ]; then
    rm -rf /Applications/DECkeys.app
    cp -R "$APP" /Applications/
    echo "installed /Applications/DECkeys.app"
fi
