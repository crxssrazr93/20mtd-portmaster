#!/bin/bash
# Prints sizes and times of every file the setup (tools/patchscript) creates or changes; the
# launcher reruns the setup when this differs from .patch_stamp. Run from gamedata/.
stat -c '%s %Y %n' MinutesTillDawn.x86_64 UnityPlayer.so MinutesTillDawn_Data/*.assets \
  MinutesTillDawn_Data/Resources/* MinutesTillDawn_Data/MonoBleedingEdge/x86_64/* \
  MinutesTillDawn_Data/Managed/Assembly-CSharp.dll 2>/dev/null
