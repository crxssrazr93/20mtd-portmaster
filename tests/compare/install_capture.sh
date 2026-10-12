#!/bin/bash
# Compiles PortCapture.cs against the game's own class libraries, injects it into Assembly-CSharp.dll
# of cmp-ref and cmp-port (capture_inject.cs, Mono.Cecil) and applies the launcher's level edits
# (crop off, XP bar fix) to both. Run by make_copies.sh; run it alone after changing PortCapture.cs
# (the unpatched assemblies are kept as Managed/*.dll.nocap).
# Usage: tests/compare/install_capture.sh [workspace]
set -e
C="$(cd "$(dirname "$0")" && pwd)"; R="$(cd "$C/../.." && pwd)"
WS="$(cd "${1:-$HOME/Games/steam-ports/20mtd}" && pwd)"
CECIL="${CECIL:-$(ls -d /usr/lib/mono/gac/Mono.Cecil/0.11*/ | tail -1)Mono.Cecil.dll}"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
M="$WS/cmp-port/MinutesTillDawn_Data/Managed"
# the game's mscorlib, not the host's: it lacks newer overloads (string.Split(char, options))
mcs -target:library -noconfig -nostdlib -r:"$M/mscorlib.dll" -r:"$M/System.dll" -r:"$M/System.Core.dll" -r:"$M/netstandard.dll" \
    -r:"$M/UnityEngine.CoreModule.dll" -r:"$M/UnityEngine.ParticleSystemModule.dll" \
    -r:"$M/UnityEngine.ImageConversionModule.dll" -r:"$M/Unity.InputSystem.dll" -r:"$M/UnityEngine.JSONSerializeModule.dll" -r:"$M/UnityEngine.Physics2DModule.dll" -out:"$W/PortCapture.dll" "$C/PortCapture.cs"
cp "$CECIL" "$W/"; mcs -r:"$CECIL" -out:"$W/capture_inject.exe" "$C/capture_inject.cs"
for d in cmp-ref cmp-port; do
  PD="$WS/$d/MinutesTillDawn_Data"
  cp "$W/PortCapture.dll" "$PD/Managed/"
  mono "$W/capture_inject.exe" "$PD/Managed" "$PD/Managed/PortCapture.dll"
  # launcher: apply_level_edits with a screen up to 800 wide (crop off, XP bar fix)
  while read -r kind file off orig new name; do
    printf "$(sed 's/../\\x&/g' <<< "$new")" | dd of="$PD/$file" bs=1 seek="$off" conv=notrunc 2>/dev/null
  done < "$R/port/20minutestilldawn/tools/level_edits.txt"
done
echo "PortCapture installed in cmp-ref and cmp-port"
