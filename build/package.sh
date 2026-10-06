#!/bin/bash
# Zips port/ into 20minutestilldawn.zip, the layout PortMaster installs into ports/. Like PortMaster's
# tools/build_release.py, the metadata (port.json, gameinfo.xml, images) goes into the port folder
# and README.md becomes 20minutestilldawn.md.
set -e
R="$(cd "$(dirname "$0")/.." && pwd)"
for f in box64/box64 glespass/libGL.so.1 box64/box64-x86_64-linux-gnu/libgcc_s.so.1; do
  [ -f "$R/port/20minutestilldawn/$f" ] || { echo "missing $f: run build/build.sh first"; exit 1; }
done
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
cd "$R/port"
cp "20 Minutes Till Dawn.sh" "$stage/"
cp -r 20minutestilldawn "$stage/"
rm -rf "$stage"/20minutestilldawn/{conf,log.txt,.patch_stamp}
find "$stage/20minutestilldawn/gamedata" -mindepth 1 ! -name 'Copy the game files here.txt' -exec rm -rf {} +
cp port.json gameinfo.xml screenshot.png cover.png "$stage/20minutestilldawn/"
cp README.md "$stage/20minutestilldawn/20minutestilldawn.md"
rm -f "$R/20minutestilldawn.zip"
(cd "$stage" && zip -9 -r -q -X "$R/20minutestilldawn.zip" .)
ls -la "$R/20minutestilldawn.zip"
