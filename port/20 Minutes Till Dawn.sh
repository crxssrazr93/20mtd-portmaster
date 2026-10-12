#!/bin/bash

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi

source $controlfolder/control.txt
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"
get_controls

GAMEDIR=/$directory/ports/20minutestilldawn
DATADIR=$GAMEDIR/gamedata
cd "$GAMEDIR"

mv -f "$GAMEDIR/log.txt" "$GAMEDIR/log.prev.txt" 2>/dev/null
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1
export PORT_REPORT_FILES="ports/20minutestilldawn/log.txt, setup_log.txt and player.log"
source "$GAMEDIR/tools/portlog.sh"
port_header "20 Minutes Till Dawn launcher"

if [ ! -f "$DATADIR/MinutesTillDawn.x86_64" ] && [ ! -d "$DATADIR/20MinutesTillDawn.app" ]; then
  pm_message "Game files missing. Copy 20MinutesTillDawn.app from the Steam (macOS) download into ports/20minutestilldawn/gamedata (see README)."
  sleep 5
  exit 1
fi
chmod a+x "$GAMEDIR/box64/box64"

patch_stamp() { (cd "$DATADIR" && bash "$GAMEDIR/tools/stamp.sh"); }
setup_done() { [ -s .patch_stamp ] && [ "$(LC_ALL=C sort .patch_stamp)" = "$(patch_stamp | LC_ALL=C sort)" ]; }
port_files "$DATADIR/MinutesTillDawn.x86_64" "$DATADIR/UnityPlayer.so" "$DATADIR/MinutesTillDawn_Data/Managed/Assembly-CSharp.dll"
if setup_done; then port_log "setup: up to date"; else port_log "setup: needed (first run, game update or changed files)"; fi
if ! setup_done; then
  export GAMEDIR DATADIR DEVICE_ARCH controlfolder
  chmod +x "$GAMEDIR/tools/patchscript"
  export PATCHER_FILE="$GAMEDIR/tools/patchscript"
  export PATCHER_GAME="20 Minutes Till Dawn"
  export PATCHER_TIME="about a minute"
  port_log "running the setup (tools/patchscript), its log is setup_log.txt"
  source "$controlfolder/utils/patcher.txt"
  if ! setup_done; then
    port_log "setup stamp mismatch: $(wc -l < .patch_stamp 2>/dev/null || echo 0) lines saved, $(patch_stamp | wc -l) files now"
    port_log "setup failed"
    port_report
    pm_message "Preparing the game failed. See ports/20minutestilldawn/setup_log.txt and the README. To report it, send $PORT_REPORT_FILES."
    sleep 8
    pm_finish
    exit 1
  fi
fi

apply_level_edits() {
  local kind file off orig new name want cur
  while read -r kind file off orig new name; do
    want="$new"
    [ "$kind" = crop ] && [ "${DISPLAY_WIDTH:-0}" -gt 800 ] && want="$orig"
    file="$DATADIR/MinutesTillDawn_Data/$file"
    cur="$(od -An -tx1 -j "$off" -N$(( ${#orig} / 2 )) "$file" 2>/dev/null | tr -d ' \n')"
    if [ "$cur" != "$want" ] && { [ "$cur" = "$orig" ] || [ "$cur" = "$new" ]; }; then
      printf "$(sed 's/../\\x&/g' <<< "$want")" | dd of="$file" bs=1 seek="$off" conv=notrunc 2>/dev/null
    fi
  done < "$GAMEDIR/tools/level_edits.txt"
}
apply_level_edits

weston_dir=/tmp/weston
$ESUDO mkdir -p "${weston_dir}"
weston_runtime="weston_pkg_0.2"
if [ ! -f "$controlfolder/libs/${weston_runtime}.squashfs" ]; then
  if [ ! -f "$controlfolder/harbourmaster" ]; then
    pm_message "This port requires the latest PortMaster to run, please go to https://portmaster.games/ for more info."
    sleep 5
    exit 1
  fi
  $ESUDO $controlfolder/harbourmaster --quiet --no-check runtime_check "${weston_runtime}.squashfs"
fi
if [[ "$PM_CAN_MOUNT" != "N" ]]; then
  $ESUDO umount "${weston_dir}"
fi
$ESUDO mount "$controlfolder/libs/${weston_runtime}.squashfs" "${weston_dir}"
port_mounted "$weston_runtime" "$weston_dir/westonwrap.sh"

mapping_pad() {
  local guid="${1%%,*}" name="${1#*,}" ev id pads=()
  name="${name%%,*}"
  le16() { local v=$((16#$(cat "$1" 2>/dev/null || echo 0))); printf '%02x%02x' $((v & 255)) $((v >> 8 & 255)); }
  for ev in /sys/class/input/event*/device; do
    [ -d "$ev/id" ] && ls -d "$ev"/js* >/dev/null 2>&1 || continue
    id="$(le16 "$ev/id/bustype")0000$(le16 "$ev/id/vendor")0000$(le16 "$ev/id/product")0000$(le16 "$ev/id/version")0000"
    [ "${id:0:4}${id:8}" = "${guid:0:4}${guid:8}" ] && { echo "$ev"; return; }
  done
  for ev in /sys/class/input/event*/device; do
    [ "$(cat "$ev/name" 2>/dev/null)" = "$name" ] && { echo "$ev"; return; }
  done
  for ev in /sys/class/input/event*/device; do
    ls -d "$ev"/js* >/dev/null 2>&1 || continue
    [ -n "$(cat "$ev/capabilities/key" 2>/dev/null)" ] && pads+=("$ev")
  done
  [ ${#pads[@]} -eq 1 ] && echo "${pads[0]}"
}
legacy_sdl_mapping() {
  local mapping="$1" name="${1#*,}" dev="" ev wbits=64 n i b w code
  name="${name%%,*}"
  dev="$(mapping_pad "$mapping")"
  [ -n "$dev" ] || { echo "$mapping"; return; }
  case "$(uname -m)" in aarch64|x86_64) ;; *) wbits=32 ;; esac
  local words=($(cat "$dev/capabilities/key")) codes=()
  n=${#words[@]}
  for ((i = 0; i < n; i++)); do
    w=$((16#${words[n-1-i]}))
    for ((b = 0; b < wbits; b++)); do
      (( (w >> b) & 1 )) && codes+=($((i * wbits + b)))
    done
  done
  local -A old_idx=()
  local o=0 cur=0 out="" f
  for code in "${codes[@]}"; do (( code >= 0x120 )) && old_idx[$code]=$((o++)); done
  for code in "${codes[@]}"; do (( code < 0x120 )) && old_idx[$code]=$((o++)); done
  local -A cur_to_old=()
  for code in "${codes[@]}"; do
    cur_to_old[$cur]=${old_idx[$code]}
    cur=$((cur + 1))
  done
  IFS=, read -ra fields <<< "$mapping"
  for f in "${fields[@]}"; do
    if [[ "$f" =~ ^([^:]+):b([0-9]+)$ ]] && [ -n "${cur_to_old[${BASH_REMATCH[2]}]}" ]; then
      f="${BASH_REMATCH[1]}:b${cur_to_old[${BASH_REMATCH[2]}]}"
    fi
    out+="$f,"
  done
  echo "$out"
}
unity_mapping=""
while IFS= read -r line; do
  [ -n "$line" ] || continue
  unity_mapping="$(legacy_sdl_mapping "$line")"
  break
done <<< "$SDL_GAMECONTROLLERCONFIG"
unity_mapping="$(sed -E 's/(^|,)dpup:/\1-lefty:/; s/(^|,)dpdown:/\1+lefty:/;
  s/(^|,)dpleft:/\1-leftx:/; s/(^|,)dpright:/\1+leftx:/' <<< "$unity_mapping")"
unity_mapping="$(printf '%s' "$unity_mapping" | tr ' ' '.')"

mkdir -p "$GAMEDIR/conf"
if [ "$CFW_NAME" = "muOS" ] && [ -n "$GPTOKEYB2" ]; then
  $GPTOKEYB2 "MinutesTillDawn.x86_64" -c "$GAMEDIR/20minutestilldawn.gptk" &
else
  $GPTOKEYB "MinutesTillDawn.x86_64" -c "$GAMEDIR/20minutestilldawn.gptk" &
fi
port_log "controller mapping for the game: ${unity_mapping:-none}"

REAL_XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
pm_platform_helper "$GAMEDIR/box64/box64"
cd "$DATADIR"
port_log "starting the game"
$ESUDO env WRAPPED_LIBRARY_PATH="$GAMEDIR/glespass" GLESPASS_CTXFIX=1 \
  GLESPASS_VENDOR=Generic GLESPASS_RENDERER=GLES-device GLESPASS_FPSCAP="${MTD_FPS:-30}" \
  $weston_dir/westonwrap.sh headless noop kiosk crusty_glx \
  BOX64_LOG=1 BOX64_LD_LIBRARY_PATH="$GAMEDIR/box64/box64-x86_64-linux-gnu" \
  BOX64_DYNAREC_BLEEDING_EDGE=0 BOX64_DYNAREC_STRONGMEM=1 BOX64_DYNAREC_BIGBLOCK=2 \
  ${unity_mapping:+SDL_GAMECONTROLLERCONFIG="$unity_mapping"} XDG_RUNTIME_DIR="$REAL_XDG_RUNTIME_DIR" HOME="$GAMEDIR/conf" XDG_CONFIG_HOME="$GAMEDIR/conf" \
  "$GAMEDIR/box64/box64" ./MinutesTillDawn.x86_64 -screen-fullscreen 1 \
  -screen-width "$DISPLAY_WIDTH" -screen-height "$DISPLAY_HEIGHT" -logFile "$GAMEDIR/player.log"

if [ -f "$GAMEDIR/player.log" ]; then
  echo "--- end of player.log (full log: ports/20minutestilldawn/player.log)"
  tail -n 100 "$GAMEDIR/player.log"
fi

port_exit
$ESUDO $weston_dir/westonwrap.sh cleanup
if [[ "$PM_CAN_MOUNT" != "N" ]]; then
  $ESUDO umount "${weston_dir}"
fi
pm_finish
