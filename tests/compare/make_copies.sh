#!/bin/bash
# Builds the two game copies the comparison runs (see README.md):
#   cmp-ref   the port's whole patch pipeline EXCEPT setup/gles_shaders2019.py: the game's original
#             OpenGLCore shader programs, everything else as shipped
#   cmp-port  the whole pipeline, what the port ships
# and then, identically in both, the test only PortCapture helper (PortCapture.cs) and the launcher's
# level edits (crop off for screens up to 800 wide, XP bar fix; port/.../tools/level_edits.txt).
# The steps follow build/make_patches.sh. Nothing under port/, setup/ or build/ is touched.
#
# Usage: tests/compare/make_copies.sh [workspace]     (default ~/Games/steam-ports/20mtd; needs
#        macos/20MinutesTillDawn.app and unity/UnitySetup-Linux-Mono-Support-for-Editor-2019.4.40f1.exe)
# Env:   PYTHON   python with UnityPy, lz4 (setup/requirements.txt); default: tests/compare/.venv,
#                 created on first use
set -e
C="$(cd "$(dirname "$0")" && pwd)"; R="$(cd "$C/../.." && pwd)"
WS="$(cd "${1:-$HOME/Games/steam-ports/20mtd}" && pwd)"
APP="$WS/macos/20MinutesTillDawn.app/Contents/Resources/Data"
EXE="$WS/unity/UnitySetup-Linux-Mono-Support-for-Editor-2019.4.40f1.exe"
[ -d "$APP" ] && [ -f "$EXE" ] || { echo "need $APP and $EXE"; exit 1; }
if [ -z "$PYTHON" ]; then
  PYTHON="$C/.venv/bin/python"
  if ! "$PYTHON" -c 'import UnityPy, lz4' 2>/dev/null; then
    python3 -m venv "$C/.venv" && "$C/.venv/bin/pip" install -q -r "$R/setup/requirements.txt" || exit 1
  fi
fi
CECIL="${CECIL:-$(ls -d /usr/lib/mono/gac/Mono.Cecil/0.11*/ | tail -1)Mono.Cecil.dll}"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
FILES=(resources.assets sharedassets0.assets sharedassets1.assets "Resources/unity_builtin_extra"
       "Resources/unity default resources" Managed/Assembly-CSharp.dll level0 level1)

echo "== Unity Linux player"
VAR='$INSTDIR$_59_/Variations/linux64_withgfx_nondevelopment_mono'
7z x -y -o"$W/player" "$EXE" "$VAR" >/dev/null
V="$W/player/$VAR"

# build <dest> <with shaders: 1|0>   (the steps of build/make_patches.sh, then a runnable game folder)
build() {
  local dest="$1" shaders="$2" PD="$1/MinutesTillDawn_Data"
  echo "== $(basename "$dest") (shader conversion: $shaders)"
  rm -rf "$dest"; mkdir -p "$dest"
  cp -r "$APP" "$PD"
  mkdir -p "$PD/Resources"
  cp "$V/Data/Resources/unity default resources" "$PD/Resources/"
  cp -r "$V/Data/MonoBleedingEdge" "$PD/MonoBleedingEdge"
  cp "$V/LinuxPlayer" "$dest/MinutesTillDawn.x86_64"; cp "$V/UnityPlayer.so" "$dest/"
  chmod +x "$dest/MinutesTillDawn.x86_64"
  [ "$shaders" = 1 ] && "$PYTHON" "$R/setup/gles_shaders2019.py" "$PD"
  mkdir -p "$W/ttl" && cp "$CECIL" "$W/ttl/"
  [ -f "$W/ttl/ttl_patch.exe" ] || mcs -r:"$CECIL" -out:"$W/ttl/ttl_patch.exe" "$R/setup/ttl_patch.cs"
  mono "$W/ttl/ttl_patch.exe" "$APP/Managed" "$PD/Managed/Assembly-CSharp.dll"
  "$PYTHON" "$R/setup/ui_levels.py" "$PD"
  "$PYTHON" "$R/setup/font_rescale.py" "$PD"
  "$PYTHON" "$R/setup/audio_loadtype.py" "$PD"
  "$PYTHON" "$R/setup/byte_edits.py" "$PD" | awk '$2 == "sharedassets0.assets"' |
    while read -r kind file off orig new name; do
      printf "$(sed 's/../\\x&/g' <<< "$new")" | dd of="$PD/$file" bs=1 seek="$off" conv=notrunc 2>/dev/null
    done
}
build "$WS/cmp-ref" 0
build "$WS/cmp-port" 1

echo "== integrity: cmp-port must match the MD5s the port's patchscript expects"
PS="$R/port/20minutestilldawn/tools/patchscript"
bad=0
for f in "${FILES[@]}"; do
  want=$(grep -E "^(FILES=\")?$f\|[0-9a-f]{32}\|[0-9a-f]{32}" "$PS" | head -1 | cut -d'|' -f3 | tr -d '"')
  got=$(md5sum < "$WS/cmp-port/MinutesTillDawn_Data/$f" | cut -c1-32)
  [ "$want" = "$got" ] && echo "  ok   $f" || { echo "  DIFF $f (want $want, got $got)"; bad=1; }
done
[ $bad = 0 ] || { echo "cmp-port does not match the shipped patch results"; exit 1; }

echo "== PortCapture (test helper) and the launcher's level edits, in both copies"
"$C/install_capture.sh" "$WS"

echo "== files that differ between cmp-ref and cmp-port (must be the shader carrying files only)"
(cd "$WS/cmp-ref" && find . -type f | sort) > "$W/l1"; (cd "$WS/cmp-port" && find . -type f | sort) > "$W/l2"
cmp -s "$W/l1" "$W/l2" || { echo "file lists differ:"; diff "$W/l1" "$W/l2"; exit 1; }
diff=$(cd "$WS/cmp-ref" && while read -r f; do cmp -s "$f" "$WS/cmp-port/$f" || echo "$f"; done < "$W/l1")
echo "$diff" | sed 's/^/  /'
allowed='resources.assets|sharedassets0.assets|sharedassets1.assets|unity_builtin_extra|unity default resources'
if echo "$diff" | grep -v -E "$allowed" | grep -q .; then echo "UNEXPECTED difference above"; exit 1; fi
echo "done: $WS/cmp-ref and $WS/cmp-port"
