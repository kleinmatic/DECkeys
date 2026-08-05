#!/bin/sh
# Generate DECkeys.icns from make-icon.swift.  Run once; the result is committed
# so a fresh clone does not need to.
set -e
cd "$(dirname "$0")"
swiftc -O -o /tmp/deckeys-mkicon make-icon.swift -framework AppKit
/tmp/deckeys-mkicon /tmp/deckeys-icon.png
rm -rf /tmp/DECkeys.iconset && mkdir -p /tmp/DECkeys.iconset
for sz in 16 32 128 256 512; do
    sips -z $sz $sz        /tmp/deckeys-icon.png --out /tmp/DECkeys.iconset/icon_${sz}x${sz}.png    >/dev/null
    sips -z $((sz*2)) $((sz*2)) /tmp/deckeys-icon.png --out /tmp/DECkeys.iconset/icon_${sz}x${sz}@2x.png >/dev/null
done
iconutil -c icns /tmp/DECkeys.iconset -o DECkeys.icns
rm -rf /tmp/DECkeys.iconset /tmp/deckeys-mkicon
echo "wrote DECkeys.icns ($(du -h DECkeys.icns | cut -f1))"
