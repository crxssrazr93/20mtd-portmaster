#!/bin/bash
# TEST ONLY (render comparison, tests/compare in the 20mtd repo). Runs the port's game path with the
# PortCapture helper; scenario and run tag come from ports/20mtdcmp/run.cfg (SCEN=idle|shoot TAG=name).
XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
if [ -d "/opt/system/Tools/PortMaster/" ]; then controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then controlfolder="$XDG_DATA_HOME/PortMaster"
else controlfolder="/roms/ports/PortMaster"; fi
source $controlfolder/control.txt
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"
get_controls
GAMEDIR=/$directory/ports/20mtdcmp
DATADIR=$GAMEDIR/gamedata
cd "$GAMEDIR"
exec > >(tee "$GAMEDIR/log.txt") 2>&1
SCEN=idle; TAG=dev; source "$GAMEDIR/run.cfg"
OUT="$GAMEDIR/portcap/$TAG"; rm -rf "$OUT"; mkdir -p "$OUT/frames"
rm -rf "$GAMEDIR/home"; mkdir -p "$GAMEDIR/home"
FRAMES="TitleScreen:120,300,600;Battle:30,60,90,120,150,200,250,300,350,400,450,500,550,600,650,700,800,1000,1500"
S=900; GAP=120
INPUT="TitleScreen:$((S - 60)):+RT"; [ "$SCEN" = idle ] && INPUT=""
for k in 0 1 2 3 4; do INPUT="${INPUT:+$INPUT;}TitleScreen:$((S + k * GAP)):A"; done
if [ "$SCEN" = shoot ]; then
  for k in $(seq 0 60); do INPUT="$INPUT;Battle:$((40 + k * 60)):-RT;Battle:$((45 + k * 60)):+RT"; done
  dirs=(RIGHT DOWN LEFT UP); prev=
  for k in $(seq 0 40); do
    f=$((60 + k * 90)); d=${dirs[$((k % 4))]}
    INPUT="$INPUT;Battle:$f:${prev:+-$prev;Battle:$f:}+$d"; prev=$d
  done
fi
echo "scenario $SCEN tag $TAG"; echo "$INPUT" > "$OUT/input.txt"
while read -r kind file off orig new name; do
  want="$new"; [ "$kind" = crop ] && [ "${DISPLAY_WIDTH:-0}" -gt 800 ] && want="$orig"
  file="$DATADIR/MinutesTillDawn_Data/$file"
  cur="$(od -An -tx1 -j "$off" -N$(( ${#orig} / 2 )) "$file" 2>/dev/null | tr -d ' \n')"
  if [ "$cur" != "$want" ] && { [ "$cur" = "$orig" ] || [ "$cur" = "$new" ]; }; then
    printf "$(sed 's/../\\x&/g' <<< "$want")" | dd of="$file" bs=1 seek="$off" conv=notrunc 2>/dev/null
  fi
done < "$GAMEDIR/tools/level_edits.txt"
weston_dir=/tmp/weston
$ESUDO mkdir -p "${weston_dir}"
weston_runtime="weston_pkg_0.2"
[[ "$PM_CAN_MOUNT" != "N" ]] && $ESUDO umount "${weston_dir}" 2>/dev/null
$ESUDO mount "$controlfolder/libs/${weston_runtime}.squashfs" "${weston_dir}"
chmod a+x "$GAMEDIR/box64/box64"
REAL_XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
# real input devices are disabled inside the game by PortCapture (PORTCAP_ONLYPAD)
cd "$DATADIR"
$ESUDO env WRAPPED_LIBRARY_PATH="$GAMEDIR/glespass" GLESPASS_CTXFIX=1 \
  GLESPASS_VENDOR=Generic GLESPASS_RENDERER=GLES-device GLESPASS_FPSCAP=0 \
  PORTCAP_DIR="$OUT/frames" PORTCAP_FRAMES="$FRAMES" PORTCAP_SEED=1234 PORTCAP_STATE=1 PORTCAP_TRACE=0 PORTCAP_DUMP= PORTCAP_INPUT="$INPUT" \
  $weston_dir/westonwrap.sh headless noop kiosk crusty_glx \
  BOX64_LOG=1 BOX64_LD_LIBRARY_PATH="$GAMEDIR/box64/box64-x86_64-linux-gnu" \
  BOX64_DYNAREC_BLEEDING_EDGE=0 BOX64_DYNAREC_STRONGMEM=1 BOX64_DYNAREC_BIGBLOCK=2 \
  XDG_RUNTIME_DIR="$REAL_XDG_RUNTIME_DIR" HOME="$GAMEDIR/home" XDG_CONFIG_HOME="$GAMEDIR/home/.config" \
  "$GAMEDIR/box64/box64" ./MinutesTillDawn.x86_64 -screen-fullscreen 1 \
  -screen-width 640 -screen-height 480 -logFile "$OUT/player.log"
$ESUDO $weston_dir/westonwrap.sh cleanup
[[ "$PM_CAN_MOUNT" != "N" ]] && $ESUDO umount "${weston_dir}"
pm_finish
