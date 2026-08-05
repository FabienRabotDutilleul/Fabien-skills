#!/bin/bash
# Measures whether processes actually keep running while the machine is locked
# or idle. Two heartbeats tick every 10 s — one inside WSL, one on Windows — so
# a gap in the logs is direct evidence of a freeze, and comparing the two tells
# a whole-system suspend apart from a WSL-only pause.
#
# Both loops are launched detached from the Windows side, so they outlive the
# shell that started them.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
POWERSHELL="powershell.exe"
INTERVAL=10
GAP_THRESHOLD=45   # 4+ missed beats: well past scheduling jitter

usage() {
  cat <<'EOF'
Usage:
  sleep-probe.sh start     Start both heartbeats
  sleep-probe.sh report    Show gaps recorded so far
  sleep-probe.sh stop      Stop both heartbeats
  sleep-probe.sh reset     Stop and erase the logs
EOF
}

die() {
  echo "ERROR=$*" >&2
  exit 1
}

command -v "$POWERSHELL" >/dev/null 2>&1 ||
  die "powershell.exe not reachable from WSL (interop disabled?)"

LOCALAPPDATA=$("$POWERSHELL" -NoProfile -Command 'Write-Output $env:LOCALAPPDATA' 2>/dev/null | tr -d '\r')
[[ -n "$LOCALAPPDATA" ]] || die "could not resolve %LOCALAPPDATA%"

WIN_DIR_WIN="${LOCALAPPDATA}\\anti-sleep\\probe"
WIN_DIR=$(wslpath "$WIN_DIR_WIN")
WIN_LOG_WIN="${WIN_DIR_WIN}\\win-heartbeat.log"
WIN_LOG="${WIN_DIR}/win-heartbeat.log"
WIN_PS1_WIN="${WIN_DIR_WIN}\\probe-loop.ps1"
STATE="${WIN_DIR}/probe-state"

WSL_DIR="${HOME}/.cache/anti-sleep"
WSL_LOG="${WSL_DIR}/wsl-heartbeat.log"

start_detached() {
  local arglist="$1"
  local exe="$2"

  "$POWERSHELL" -NoProfile -ExecutionPolicy Bypass -Command \
    "(Start-Process -WindowStyle Hidden -PassThru ${exe} -ArgumentList ${arglist}).Id" |
    tr -d '\r'
}

win_process_alive() {
  local pid="${1:-}"

  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  "$POWERSHELL" -NoProfile -Command \
    "if (Get-Process -Id $pid -ErrorAction SilentlyContinue) { 'yes' }" 2>/dev/null |
    tr -d '\r' | grep -q yes
}

state_value() {
  local key="$1"

  [[ -f "$STATE" ]] || return 1
  awk -F= -v key="$key" '$1 == key { print $2; exit }' "$STATE"
}

start_probe() {
  local win_pid
  local wsl_pid

  if [[ -f "$STATE" ]] && win_process_alive "$(state_value WIN_PID || true)"; then
    die "probe already running; use 'report' or 'stop'"
  fi

  mkdir -p "$WIN_DIR" "$WSL_DIR"
  cp "${SCRIPT_DIR}/probe-loop.ps1" "${WIN_DIR}/probe-loop.ps1"

  win_pid=$(start_detached \
    "'-NoProfile','-ExecutionPolicy','Bypass','-File','${WIN_PS1_WIN}','-Log','${WIN_LOG_WIN}','-Interval','${INTERVAL}'" \
    "powershell.exe")
  [[ "$win_pid" =~ ^[0-9]+$ ]] || die "could not start the Windows heartbeat"

  wsl_pid=$(start_detached \
    "'-d','${WSL_DISTRO_NAME}','-e','${SCRIPT_DIR}/probe-loop.sh','${WSL_LOG}','${INTERVAL}'" \
    "wsl.exe")
  [[ "$wsl_pid" =~ ^[0-9]+$ ]] || die "could not start the WSL heartbeat"

  {
    printf 'WIN_PID=%s\n' "$win_pid"
    printf 'WSL_PID=%s\n' "$wsl_pid"
    printf 'STARTED=%s\n' "$(date +%s)"
  } >"$STATE"

  printf 'STATUS=probing\n'
  printf 'INTERVAL=%ss\n' "$INTERVAL"
  printf 'WIN_PID=%s\n' "$win_pid"
  printf 'WSL_PID=%s\n' "$wsl_pid"
}

analyse_log() {
  local label="$1"
  local log="$2"

  if [[ ! -s "$log" ]]; then
    printf '%s: aucun battement enregistré\n' "$label"
    return
  fi

  awk -v label="$label" -v threshold="$GAP_THRESHOLD" '
    { sub(/\r$/, "") }   # the Windows heartbeat writes CRLF
    /^[0-9]+$/ {
      if (previous && $1 - previous > threshold) {
        gaps++
        printf "  TROU %5d s  de %s a %s\n", $1 - previous,
          strftime("%H:%M:%S", previous), strftime("%H:%M:%S", $1)
        if ($1 - previous > worst) worst = $1 - previous
      }
      if (!first) first = $1
      previous = $1
      beats++
    }
    END {
      if (!beats) {
        printf "%s : aucun battement lisible\n", label
        exit
      }
      printf "%s : %d battements, de %s a %s\n", label, beats,
        strftime("%H:%M:%S", first), strftime("%H:%M:%S", previous)
      if (gaps) {
        printf "  => %d trou(s), le plus long %d s\n", gaps, worst
      } else {
        printf "  => aucun trou : le processus a tourne sans interruption\n"
      }
    }
  ' "$log"
}

report_probe() {
  local now
  local last

  printf '=== anti-sleep ===\n'
  "${SCRIPT_DIR}/anti-sleep.sh" status || true

  printf '\n=== sondes ===\n'
  analyse_log "WSL    " "$WSL_LOG"
  analyse_log "Windows" "$WIN_LOG"

  now=$(date +%s)
  if [[ -s "$WSL_LOG" ]]; then
    last=$(tail -n 1 "$WSL_LOG")
    if [[ "$last" =~ ^[0-9]+$ ]] && (( now - last > GAP_THRESHOLD )); then
      printf '\nATTENTION : la sonde WSL est muette depuis %d s (arretee ou gelee a l instant)\n' \
        "$((now - last))"
    fi
  fi
}

stop_probe() {
  local pid

  for key in WIN_PID WSL_PID; do
    pid=$(state_value "$key" || true)
    if [[ "$pid" =~ ^[0-9]+$ ]]; then
      "$POWERSHELL" -NoProfile -Command "Stop-Process -Id $pid -Force" >/dev/null 2>&1 || true
    fi
  done
  pkill -f "probe-loop.sh ${WSL_LOG}" >/dev/null 2>&1 || true
  rm -f "$STATE"
  printf 'STATUS=stopped\n'
}

case "${1:-}" in
  start)  start_probe ;;
  report) report_probe ;;
  stop)   stop_probe ;;
  reset)
    stop_probe
    rm -f "$WSL_LOG" "$WIN_LOG"
    printf 'LOGS=cleared\n'
    ;;
  -h|--help|help) usage ;;
  *) usage >&2; exit 2 ;;
esac
