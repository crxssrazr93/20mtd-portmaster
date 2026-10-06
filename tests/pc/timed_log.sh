#!/bin/bash
# Timestamps each new line of the player log: timed_log.sh <player.log> <out>
until [ -f "$1" ]; do sleep 0.2; done
tail -n +1 -F "$1" 2>/dev/null | while IFS= read -r l; do echo "$(date +%s.%N | cut -c1-14) $l"; done > "$2"
