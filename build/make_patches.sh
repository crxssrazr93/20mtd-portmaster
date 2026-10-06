#!/bin/bash
# Regenerates the game file changes the port ships:
#   port/20minutestilldawn/patch/*.xdelta   (setup/gles_shaders2019.py, setup/ttl_patch.cs,
#     setup/ui_levels.py, setup/font_rescale.py, setup/audio_loadtype.py, the Canvas Scaler edit
#     of setup/byte_edits.py)
#   the MD5s in port/20minutestilldawn/tools/patchscript
#   port/20minutestilldawn/tools/level_edits.txt (the camera crop bytes the launcher sets per screen)
# from an untouched copy of the macOS Steam depot and Unity's Linux player installer.
# Needs python3 with UnityPy, TypeTreeGeneratorAPI and lz4 (setup/requirements.txt), 7z, mono with mcs and Mono.Cecil 0.11,
# and docker (xdelta3 from Ubuntu 20.04).
# Usage: build/make_patches.sh <folder holding 20MinutesTillDawn.app> <UnitySetup-Linux-Mono-Support-for-Editor-2019.4.40f1.exe>
set -e
R="$(cd "$(dirname "$0")/.." && pwd)"
APP="$(cd "$1" && pwd)/20MinutesTillDawn.app/Contents/Resources/Data"
EXE="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
PY="${PYTHON:-python3}"
P="$R/port/20minutestilldawn"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
FILES=(resources.assets sharedassets0.assets sharedassets1.assets "Resources/unity_builtin_extra"
       "Resources/unity default resources" Managed/Assembly-CSharp.dll level0 level1)
# the patched copy sits in a <name>_Data folder: ui_levels.py and font_rescale.py read the game's
# script types from it
PD="$W/g/MinutesTillDawn_Data"

mkdir -p "$W/orig/Resources"
cp -r "$APP/Managed" "$W/orig/Managed"
cp "$APP/globalgamemanagers.assets" "$W/orig/"
mkdir -p "$W/g" && cp -r "$APP" "$PD"
7z e -y -o"$W/player" "$EXE" '$INSTDIR$_59_/Variations/linux64_withgfx_nondevelopment_mono/Data/Resources/unity default resources' >/dev/null
cp "$W/player/unity default resources" "$PD/Resources/"
for f in "${FILES[@]}"; do cp "$PD/$f" "$W/orig/$f"; done
"$PY" "$R/setup/gles_shaders2019.py" "$PD"
CECIL="${CECIL:-$(ls -d /usr/lib/mono/gac/Mono.Cecil/0.11*/ | tail -1)Mono.Cecil.dll}"
mkdir -p "$W/ttl" && cp "$CECIL" "$W/ttl/"
mcs -r:"$CECIL" -out:"$W/ttl/ttl_patch.exe" "$R/setup/ttl_patch.cs"
mono "$W/ttl/ttl_patch.exe" "$W/orig/Managed" "$PD/Managed/Assembly-CSharp.dll"
"$PY" "$R/setup/ui_levels.py" "$PD"
"$PY" "$R/setup/font_rescale.py" "$PD"
"$PY" "$R/setup/audio_loadtype.py" "$PD"
# the camera crop bytes depend on the screen, so the launcher sets them (offsets in the patched
# level files); the Canvas Scaler edit in sharedassets0.assets goes into its xdelta
"$PY" "$R/setup/byte_edits.py" "$PD" | grep -E '^crop level[01] ' > "$P/tools/level_edits.txt"
"$PY" "$R/setup/byte_edits.py" "$PD" | awk '$2 == "sharedassets0.assets"' |
  while read -r kind file off orig new name; do
    printf "$(sed 's/../\\x&/g' <<< "$new")" | dd of="$PD/$file" bs=1 seek="$off" conv=notrunc 2>/dev/null
  done

mkdir -p "$P/patch"
docker run --rm -v "$W:/w" -v "$P/patch:/out" ubuntu:20.04 bash -c '
  apt-get update -qq >/dev/null && apt-get install -y -qq xdelta3 >/dev/null 2>&1
  for f in resources.assets sharedassets0.assets sharedassets1.assets Resources/unity_builtin_extra "Resources/unity default resources" Managed/Assembly-CSharp.dll level0 level1; do
    b=$(basename "$f"); xdelta3 -9 -e -f -s "/w/orig/$f" "/w/g/MinutesTillDawn_Data/$f" "/out/${b// /_}.xdelta"
  done
  chown -R '"$(id -u):$(id -g)"' /out'

S="$P/tools/patchscript"
for f in "${FILES[@]}"; do
  orig=$(md5sum < "$W/orig/$f" | cut -c1-32)
  new=$(md5sum < "$PD/$f" | cut -c1-32)
  sed -i "s#^\(FILES=\"\)\?${f}|[0-9a-f]\{32\}|[0-9a-f]\{32\}\(\"\)\?\$#\1${f}|$orig|$new\2#" "$S"
done
grep -A8 '^FILES=' "$S"
ls -la "$P/patch"
