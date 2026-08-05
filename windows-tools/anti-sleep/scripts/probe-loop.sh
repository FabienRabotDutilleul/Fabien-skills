#!/bin/bash
# Heartbeat inside WSL: one epoch timestamp every INTERVAL seconds.
# A gap in the log means this process was frozen or the WSL VM was paused.
set -u

LOG="${1:?usage: probe-loop.sh LOGFILE [INTERVAL]}"
INTERVAL="${2:-10}"

mkdir -p "$(dirname "$LOG")"
while true; do
  date +%s >>"$LOG"
  sleep "$INTERVAL"
done
