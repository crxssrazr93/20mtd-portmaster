#!/bin/bash
# PORTMASTER: 20minutestilldawn.zip, 20 Minutes Till Dawn.sh

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

# the previous run's log is kept as log.prev.txt
mv -f "$GAMEDIR/log.txt" "$GAMEDIR/log.prev.txt" 2>/dev/null
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1
# Device, system and memory details for bug reports (tools/portlog.sh)
# The files a bug report needs; named in log.txt and on screen only when something fails
export PORT_REPORT_FILES="ports/20minutestilldawn/log.txt, setup_log.txt and player.log"
source "$GAMEDIR/tools/portlog.sh"
port_header "20 Minutes Till Dawn launcher"

if [ ! -f "$DATADIR/MinutesTillDawn.x86_64" ] && [ ! -d "$DATADIR/20MinutesTillDawn.app" ]; then
  pm_message "Game files missing. Copy 20MinutesTillDawn.app from the Steam (macOS) download into ports/20minutestilldawn/gamedata (see README)."
  sleep 5
  exit 1
fi
chmod a+x "$GAMEDIR/box64/box64"

# One time setup (again after a game update): Unity's Linux player for the game's engine version,
# the game data out of the macOS app, and OpenGL ES shaders in five files (see tools/patchscript).
# The stamp covers every file the setup creates or changes.
patch_stamp() { (cd "$DATADIR" && bash "$GAMEDIR/tools/stamp.sh"); }
# Compared sorted: the file order of the globs depends on the locale the script runs under
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
  # tools/patchscript writes the stamp only when every file checked out
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

# Fixed-offset edits of the level files (tools/level_edits.txt, made by setup/byte_edits.py from the
# supported Steam build; a location holding anything but the original or the new bytes is left
# alone), applied on every start so they follow the screen:
# * pool: smaller initial object pools (3000 damage numbers, 1000 bullet impacts, ...; every one of
#   them grows on demand), which cuts loading time and memory.
# * crop: the Pixel Perfect Cameras (reference resolution 800x450, 32 pixels per unit) crop the frame
#   to 16:9 and stretch it, which letterboxes 4:3 and square screens. On screens up to 800 pixels
#   wide the game draws at 1:1 scale anyway, so there the crop is turned off and the picture fills
#   the screen at the same scale; wider screens keep the game's own scaling.
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

# The input device a mapping line is for. By its SDL GUID first (bus, vendor, product and version,
# little endian; current SDL keeps a CRC of the name in bytes 2 and 3, so those are skipped): the
# mapping's name need not be the device's (muOS maps its "muOS-Keys" pad as "Deeplay-keys"). Only
# joysticks count, since key devices such as gpio-keys can report the same ids. Then by name, then
# the only joystick with buttons.
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
# The Unity player has an older SDL built in, which numbers a pad's buttons differently from the
# SDL that PortMaster's mapping (SDL_GAMECONTROLLERCONFIG) was written for: key codes from
# BTN_JOYSTICK (0x120) up first, then every lower code. Current SDL numbers them all in ascending
# order, so on pads that also report low codes (the H700 pads report 1, 114 and 115) every button
# index is off. This renumbers a mapping line for the old order, from the pad's key capabilities.
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
# The game reads the pad itself through the Unity player's SDL, with PortMaster's mapping for the
# built in pad renumbered for that SDL's button order. Other pads use the player's own database.
unity_mapping=""
while IFS= read -r line; do
  [ -n "$line" ] || continue
  unity_mapping="$(legacy_sdl_mapping "$line")"
  break
done <<< "$SDL_GAMECONTROLLERCONFIG"
# The game binds movement to the left stick only (the D-pad works in menus only), so the D-pad is
# mapped onto the left stick's half axes; menus also accept the left stick.
unity_mapping="$(sed -E 's/(^|,)dpup:/\1-lefty:/; s/(^|,)dpdown:/\1+lefty:/;
  s/(^|,)dpleft:/\1-leftx:/; s/(^|,)dpright:/\1+leftx:/' <<< "$unity_mapping")"
# The mapping goes to the game as a westonwrap VAR=value argument: westonwrap sources PortMaster's
# control.txt again, which on some firmwares (muOS) exports the original mapping over anything
# exported here. westonwrap evals its arguments, so the mapping is one line and the spaces in its
# name (only the GUID is matched) become dots.
unity_mapping="$(printf '%s' "$unity_mapping" | tr ' ' '.')"

mkdir -p "$GAMEDIR/conf"
if [ "$CFW_NAME" = "muOS" ] && [ -n "$GPTOKEYB2" ]; then
  $GPTOKEYB2 "MinutesTillDawn.x86_64" -c "$GAMEDIR/20minutestilldawn.gptk" &
else
  $GPTOKEYB "MinutesTillDawn.x86_64" -c "$GAMEDIR/20minutestilldawn.gptk" &
fi
port_log "controller mapping for the game: ${unity_mapping:-none}"

# westonwrap replaces XDG_RUNTIME_DIR; pass the real one on so the game's audio reaches PipeWire.
REAL_XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
pm_platform_helper "$GAMEDIR/box64/box64"
cd "$DATADIR"
port_log "starting the game"
# crusty_glx gives the Unity player an OpenGL ES 3 context through GLX; glespass is the libGL.so.1
# that box64's GL wrapper loads, passing the player's GL calls straight to the GLES driver.
# Unity renders on its own thread; GLESPASS_CTXFIX moves the EGL context to that thread when the
# player hands the GLX context over (crusty alone keeps it on the main thread).
# box64 runs libgcc_s.so.1 only as an x86_64 library (it has no native wrapper for it), so the
# port carries that one, as other box64 ports do.
# GLESPASS_VENDOR / GLESPASS_RENDERER hide the GPU name from the player: for a tile based GPU
# (Mali) Unity turns "don't care" camera target loads into clears, which can leave only the UI
# on screen.
# GLESPASS_FPSCAP holds the frame rate at a steady 30: uncapped it swings between 33 and 47 fps,
# with frames from 22 to 60 ms, which looks choppy on a 60 Hz screen. MTD_FPS overrides it (0 = off).
# box64's settings go to westonwrap as VAR=value arguments, which it puts on the game's command
# line: westonwrap sources PortMaster's control files first, and on ROCKNIX the game then started
# with the firmware's BOX64_LD_LIBRARY_PATH (/usr/share/box64/lib) instead of the port's, so box64
# could not find the game's libraries. BOX64_LOG=1 names a library that fails to load.
# box64 recognises the Mono runtime and then forces BOX64_DYNAREC_BIGBLOCK=0 and STRONGMEM=1,
# which overrides any dynarec setting given here; BLEEDING_EDGE=0 turns that off. On an RG35XX H
# (frame cap off) runs went from 27 to 31 fps to 37 to 41, and a run loads in 30 s instead of 39.
# STRONGMEM=1 keeps the safe memory ordering for Mono's threads.
$ESUDO env WRAPPED_LIBRARY_PATH="$GAMEDIR/glespass" GLESPASS_CTXFIX=1 \
  GLESPASS_VENDOR=Generic GLESPASS_RENDERER=GLES-device GLESPASS_FPSCAP="${MTD_FPS:-30}" \
  $weston_dir/westonwrap.sh headless noop kiosk crusty_glx \
  BOX64_LOG=1 BOX64_LD_LIBRARY_PATH="$GAMEDIR/box64/box64-x86_64-linux-gnu" \
  BOX64_DYNAREC_BLEEDING_EDGE=0 BOX64_DYNAREC_STRONGMEM=1 BOX64_DYNAREC_BIGBLOCK=2 \
  ${unity_mapping:+SDL_GAMECONTROLLERCONFIG="$unity_mapping"} XDG_RUNTIME_DIR="$REAL_XDG_RUNTIME_DIR" HOME="$GAMEDIR/conf" XDG_CONFIG_HOME="$GAMEDIR/conf" \
  "$GAMEDIR/box64/box64" ./MinutesTillDawn.x86_64 -screen-fullscreen 1 \
  -screen-width "$DISPLAY_WIDTH" -screen-height "$DISPLAY_HEIGHT" -logFile "$GAMEDIR/player.log"

# Unity writes its own messages to player.log; copy the end of it here so log.txt alone is enough
# for a bug report.
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
