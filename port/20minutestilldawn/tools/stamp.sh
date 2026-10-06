#!/bin/bash
# Prints sizes and times of every file the setup (tools/patchscript) creates or changes; the
# launcher reruns the setup when this differs from .patch_stamp. Run from gamedata/.
# muOS has no stat; ls and date give the same "size mtime name" lines there.
files=(MinutesTillDawn.x86_64 UnityPlayer.so MinutesTillDawn_Data/*.assets
  MinutesTillDawn_Data/Resources/* MinutesTillDawn_Data/MonoBleedingEdge/x86_64/*
  MinutesTillDawn_Data/Managed/Assembly-CSharp.dll)
if command -v stat >/dev/null; then
  stat -c '%s %Y %n' "${files[@]}" 2>/dev/null
else
  for f in "${files[@]}"; do
    [ -e "$f" ] && echo "$(ls -lnL "$f" | awk '{print $5}') $(date -r "$f" +%s) $f"
  done
fi
exit 0
