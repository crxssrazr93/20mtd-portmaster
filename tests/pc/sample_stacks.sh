#!/bin/bash
# Poor man's profiler for the PC test runs: waits for the game, then samples its main thread's
# stack with eu-stack every 0.2 s. Needs the game started with tests/pc/ptracer_any.so preloaded
# (EXTRA_PRELOAD) and UnityPlayer_s.debug from the Unity installer next to UnityPlayer.so.
# Usage: sample_stacks.sh <delay s> <samples> <out file>
DELAY=$1; N=$2; OUT=$3
until P=$(pgrep -x MinutesTillDawn | head -1) && [ -n "$P" ]; do sleep 0.2; done
sleep "$DELAY"
: > "$OUT"
for i in $(seq "$N"); do
  echo "=== sample $i" >> "$OUT"
  eu-stack -p "$P" -1 -i 2>/dev/null | awk '/^TID/{t=$2; sub(":","",t)} t==P' P="$P" | head -60 >> "$OUT"
  sleep 0.2
done
