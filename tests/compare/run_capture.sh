#!/bin/bash
# One deterministic capture run (see README.md), following tests/localtest.sh: the game's x86_64
# player under an offscreen Xvfb (no window on the desktop) at 640x480, with a virtual gamepad
# inside bwrap (no real input devices). PortCapture.cs (in both copies) fixes the simulation step and the
# random seeds and writes the frames; the run ends when it logs "PortCapture: done".
#
# Usage: tests/compare/run_capture.sh <ref|port> <idle|shoot> <tag> [WxH]
#   ref   cmp-ref with desktop GL (NOGLES), the game's original shaders
#   port  cmp-port with tests/pc/gles_force.so (a GLES 3.2 context, as on the device)
#   idle  no input during the run; shoot  the right trigger is held from before the run starts
#         (both press A through the menus at fixed title frames, see NAV_START and NAV_GAP)
# Env:   FRAMES  PORTCAP_FRAMES, default "TitleScreen:120,300,600;Battle:30,60,90,120,150,200,250,300,350,400,450,500,550,600,650,700,800,1000,1500"
#        WS      workspace holding cmp-ref and cmp-port (default ~/Games/steam-ports/20mtd)
#        DISP    X display number (default 9)
#        TRACE   1 = per frame trace file (frames/trace.txt); DUMP=380-386 adds the 2D bodies of those frames
#        (the player runs under setarch -R: no address space randomisation, so Mono's address based
#         object hashes, and every Dictionary/HashSet order built on them, repeat from run to run)
#        SEED    PORTCAP_SEED (default 1234)
# Output: tests/compare/runs/<tag>/frames/*.png (+ .txt state), player.log
set -u
ulimit -c 0
C="$(cd "$(dirname "$0")" && pwd)"; R="$(cd "$C/../.." && pwd)"; T="$R/tests"
FLAVOR="$1"; SCEN="$2"; TAG="$3"; RES="${4:-640x480}"; D=${DISP:-9}
WS="${WS:-$HOME/Games/steam-ports/20mtd}"
FRAMES="${FRAMES:-TitleScreen:120,300,600;Battle:30,60,90,120,150,200,250,300,350,400,450,500,550,600,650,700,800,1000,1500}"
case "$FLAVOR" in ref) G="$WS/cmp-ref"; PRE=;; port) G="$WS/cmp-port"; PRE="$T/pc/gles_force.so";; *) echo "ref or port"; exit 2;; esac
case "$SCEN" in idle) HOLD="";; shoot) HOLD="on RT;";; *) echo "idle or shoot"; exit 2;; esac
[ -f "$T/pc/gles_force.so" ] || gcc -shared -fPIC -O2 -o "$T/pc/gles_force.so" "$T/pc/gles_force.c" -ldl
OUT="$C/runs/$TAG"; rm -rf "$OUT"; mkdir -p "$OUT/frames"
H="$OUT/home"; mkdir -p "$H"                                   # always a fresh home: no saves
# a lock left by a killed Xvfb is stale when its process is gone
if [ -e "/tmp/.X$D-lock" ] && ! kill -0 "$(tr -d ' ' < /tmp/.X$D-lock)" 2>/dev/null; then rm -f "/tmp/.X$D-lock" "/tmp/.X11-unix/X$D"; fi
while [ -e "/tmp/.X$D-lock" ]; do sleep 0.5; done
unset WAYLAND_DISPLAY; export SDL_VIDEODRIVER=x11 XDG_RUNTIME_DIR=/tmp/xdg-offscreen; mkdir -p -m 700 /tmp/xdg-offscreen
# FMOD crashes enumerating the host's ALSA plugins; one null device is all the game needs
export ALSA_CONFIG_PATH="$C/alsa_null.conf"
Xvfb :$D -screen 0 "$RES"x24 -nolisten tcp >/dev/null 2>&1 & XPID=$!
for i in $(seq 40); do DISPLAY=:$D xdpyinfo >/dev/null 2>&1 && break; sleep 0.5; done
DISPLAY=:$D xdpyinfo >/dev/null 2>&1 || { echo "offscreen X server :$D did not start"; kill -9 $XPID 2>/dev/null; exit 1; }
# Input comes from PortCapture's own virtual gamepad, fed by scene frame number (PORTCAP_INPUT): title
# (the intro takes about 15 s of game time), then Play, character, weapon, mode, map, start.
S=${NAV_START:-900}; GAP=${NAV_GAP:-120}
INPUT="TitleScreen:$((S - 60)):+RT"; [ "$SCEN" = idle ] && INPUT=""
for k in 0 1 2 3 4; do INPUT="${INPUT:+$INPUT;}TitleScreen:$((S + k * GAP)):A"; done
# shoot: the trigger is released and pressed again every 60 frames (an action only fires for a press
# that begins after its input map is enabled, and the game starts accepting input at a varying point), the stick walks a square (90 frames a side) so
# the camera and the crowd move. The player dies after about 800 frames (or an upgrade menu opens);
# the game then stands still on that screen, which later frames capture as well.
if [ "$SCEN" = shoot ]; then
  for k in $(seq 0 60); do INPUT="$INPUT;Battle:$((40 + k * 60)):-RT;Battle:$((45 + k * 60)):+RT"; done
  dirs=(RIGHT DOWN LEFT UP); prev=
  for k in $(seq 0 40); do
    f=$((60 + k * 90)); d=${dirs[$((k % 4))]}
    INPUT="$INPUT;Battle:$f:${prev:+-$prev;Battle:$f:}+$d"; prev=$d
  done
fi
( sleep 10; while true; do
    W=$(DISPLAY=:$D xdotool search --name "Minutes" 2>/dev/null | head -1)
    [ -n "$W" ] && DISPLAY=:$D xdotool windowfocus "$W" 2>/dev/null; sleep 2; done ) & FPID=$!
cd "$G"
W=${RES%x*}; Hh=${RES#*x}
PORTCAP_DIR="$OUT/frames" PORTCAP_FRAMES="$FRAMES" PORTCAP_SEED="${SEED:-1234}" PORTCAP_STATE=1 PORTCAP_TRACE="${TRACE:-0}" PORTCAP_DUMP="${DUMP:-}" PORTCAP_INPUT="$INPUT" \
DISPLAY=:$D HOME="$H" XDG_CONFIG_HOME="$H/.config" LD_PRELOAD="$PRE" \
  bwrap --die-with-parent --dev-bind / / --tmpfs /dev/input \
  setarch "$(uname -m)" -R ./MinutesTillDawn.x86_64 -screen-width "$W" -screen-height "$Hh" -screen-fullscreen 1 -logFile "$OUT/player.log" \
  > "$OUT/game.out" 2>&1 & GPID=$!
status=timeout
for i in $(seq 360); do                                          # up to 6 minutes
  grep -q "PortCapture: done" "$OUT/player.log" 2>/dev/null && { status=done; break; }
  kill -0 $GPID 2>/dev/null || { status=exited; break; }
  sleep 1
done
P=$(pgrep -P $GPID | head -1)
kill -9 $FPID $P $GPID 2>/dev/null; wait $FPID $GPID 2>/dev/null
kill -9 $XPID 2>/dev/null; wait $XPID 2>/dev/null; rm -f "/tmp/.X$D-lock" "/tmp/.X11-unix/X$D"
echo "$TAG: $status, $(ls "$OUT/frames" | grep -c png) frames"
[ "$status" = done ]
