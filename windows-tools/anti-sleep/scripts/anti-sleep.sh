#!/bin/bash
# Keeps Windows awake from WSL. The keep-awake process runs on the Windows
# side (detached via Start-Process) so it survives WSL shells and restarts.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PS1_SRC="${SCRIPT_DIR}/keepawake.ps1"
POWERSHELL="powershell.exe"

usage() {
  cat <<'EOF'
Usage:
  anti-sleep.sh start SECONDS [FLAGS...]
  anti-sleep.sh start-pid PID [FLAGS...]   # PID is a WSL process
  anti-sleep.sh verify
  anti-sleep.sh status
  anti-sleep.sh stop

FLAGS default to: -d -i
  -d  keep the display on (implies -i)
  -i  prevent system sleep; display may turn off
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

STATE_DIR_WIN="${LOCALAPPDATA}\\anti-sleep"
STATE_DIR=$(wslpath "$STATE_DIR_WIN")
PS1_WIN="${STATE_DIR_WIN}\\keepawake.ps1"
ASSERT_WIN="${STATE_DIR_WIN}\\asserted"
STATE="${STATE_DIR}/state"
ASSERT_FILE="${STATE_DIR}/asserted"
LOCK_DIR="${STATE_DIR}/lock"

release_lock() {
  rmdir "$LOCK_DIR" >/dev/null 2>&1 || true
}

acquire_lock() {
  local now
  local modified

  mkdir -p "$STATE_DIR"

  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    now=$(date +%s)
    modified=$(stat -c %Y "$LOCK_DIR" 2>/dev/null || echo "$now")
    if [[ "$modified" =~ ^[0-9]+$ ]] && (( now - modified > 30 )); then
      rmdir "$LOCK_DIR" 2>/dev/null ||
        die "another anti-sleep operation is in progress"
      mkdir "$LOCK_DIR" 2>/dev/null ||
        die "another anti-sleep operation is in progress"
    else
      die "another anti-sleep operation is in progress"
    fi
  fi

  trap release_lock EXIT
  trap 'exit 130' HUP INT TERM
}

state_value() {
  local key="$1"

  [[ -f "$STATE" ]] || return 1
  awk -F= -v key="$key" '
    $1 == key {
      sub(/^[^=]*=/, "")
      print
      exit
    }
  ' "$STATE"
}

format_epoch() {
  date -d "@$1" '+%Y-%m-%d %H:%M:%S %Z'
}

win_process_cmdline() {
  local pid="$1"

  "$POWERSHELL" -NoProfile -Command \
    "(Get-CimInstance Win32_Process -Filter \"ProcessId=$pid\").CommandLine" \
    2>/dev/null | tr -d '\r'
}

process_is_keepawake() {
  local pid="${1:-}"
  local cmdline

  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  cmdline=$(win_process_cmdline "$pid")
  [[ "$cmdline" == *keepawake.ps1* ]]
}

validate_flags() {
  local flag

  for flag in "$@"; do
    case "$flag" in
      -d|-i) ;;
      *) die "unsupported flag: $flag (allowed: -d -i)" ;;
    esac
  done
}

write_state() {
  local mode="$1"
  local target="$2"
  local flags="$3"
  local pid="$4"
  local start_epoch="$5"
  local expires_epoch="$6"
  local temp

  temp=$(mktemp "${STATE_DIR}/state.XXXXXX")
  {
    printf 'MODE=%s\n' "$mode"
    printf 'TARGET=%s\n' "$target"
    printf 'FLAGS=%s\n' "$flags"
    printf 'PID=%s\n' "$pid"
    printf 'START_EPOCH=%s\n' "$start_epoch"
    printf 'EXPIRES_EPOCH=%s\n' "$expires_epoch"
  } >"$temp"
  mv "$temp" "$STATE"
}

verify_running() {
  local pid

  pid=$(state_value PID) || return 1
  process_is_keepawake "$pid" || return 1
  grep -Fq 'ASSERTED=1' "$ASSERT_FILE" 2>/dev/null || return 1

  printf 'STATUS=running\n'
  printf 'PID=%s\n' "$pid"
  printf 'ASSERTIONS=active\n'
  printf 'MODE=%s\n' "$(state_value MODE)"
  printf 'FLAGS=%s\n' "$(state_value FLAGS)"
  if [[ "$(state_value MODE)" == "timer" ]]; then
    printf 'EXPIRES=%s\n' "$(format_epoch "$(state_value EXPIRES_EPOCH)")"
  else
    printf 'UNTIL_PID=%s\n' "$(state_value TARGET)"
  fi
}

start_job() {
  local mode="$1"
  local target="$2"
  shift 2
  local flags=("$@")
  local display="yes"
  local flags_text
  local existing_pid
  local arglist
  local pid
  local start_epoch
  local expires_epoch=0
  local attempt

  if [[ ${#flags[@]} -eq 0 ]]; then
    flags=(-d -i)
  fi
  validate_flags "${flags[@]}"
  [[ " ${flags[*]} " == *" -d "* ]] || display="no"

  acquire_lock

  existing_pid=$(state_value PID || true)
  if process_is_keepawake "$existing_pid"; then
    die "anti-sleep is already running as Windows PID ${existing_pid}; inspect it before replacing it"
  fi

  rm -f "$STATE" "$ASSERT_FILE"
  cp "$PS1_SRC" "${STATE_DIR}/keepawake.ps1"

  arglist="'-NoProfile','-ExecutionPolicy','Bypass','-File','${PS1_WIN}','-AssertFile','${ASSERT_WIN}'"
  if [[ "$mode" == "timer" ]]; then
    arglist+=",'-Seconds','${target}'"
  else
    arglist+=",'-WatchPid','${target}','-Distro','${WSL_DISTRO_NAME}'"
  fi
  if [[ "$display" == "yes" ]]; then
    arglist+=",'-Display'"
  fi

  start_epoch=$(date +%s)
  if [[ "$mode" == "timer" ]]; then
    expires_epoch=$((start_epoch + target))
  fi

  pid=$("$POWERSHELL" -NoProfile -ExecutionPolicy Bypass -Command \
    "(Start-Process -WindowStyle Hidden -PassThru powershell.exe -ArgumentList ${arglist}).Id" |
    tr -d '\r')
  [[ "$pid" =~ ^[0-9]+$ ]] ||
    die "Start-Process did not return a Windows PID"

  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    grep -Fq 'ASSERTED=1' "$ASSERT_FILE" 2>/dev/null && break
    sleep 0.5
  done

  if ! grep -Fq 'ASSERTED=1' "$ASSERT_FILE" 2>/dev/null; then
    "$POWERSHELL" -NoProfile -Command "Stop-Process -Id $pid -Force" >/dev/null 2>&1 || true
    rm -f "$STATE" "$ASSERT_FILE"
    die "keepawake.ps1 did not report an active power assertion"
  fi

  flags_text="${flags[*]}"
  write_state "$mode" "$target" "$flags_text" "$pid" "$start_epoch" "$expires_epoch"

  verify_running || {
    "$POWERSHELL" -NoProfile -Command "Stop-Process -Id $pid -Force" >/dev/null 2>&1 || true
    rm -f "$STATE" "$ASSERT_FILE"
    die "keep-awake process started but verification failed"
  }
}

status_job() {
  local now
  local mode
  local expires_epoch

  if verify_running; then
    return 0
  fi

  if [[ -f "$STATE" ]]; then
    mode=$(state_value MODE)
    if [[ "$mode" == "timer" ]]; then
      now=$(date +%s)
      expires_epoch=$(state_value EXPIRES_EPOCH)
      if [[ "$expires_epoch" =~ ^[0-9]+$ ]] && (( now >= expires_epoch )); then
        printf 'STATUS=expired\n'
        printf 'EXPIRED_AT=%s\n' "$(format_epoch "$expires_epoch")"
        return 0
      fi
    fi
    printf 'STATUS=failed\n'
    printf 'EXPECTED_PID=%s\n' "$(state_value PID)"
    return 1
  fi

  printf 'STATUS=stopped\n'
}

stop_job() {
  local pid

  acquire_lock
  pid=$(state_value PID || true)
  if process_is_keepawake "$pid"; then
    "$POWERSHELL" -NoProfile -Command "Stop-Process -Id $pid -Force" >/dev/null 2>&1 ||
      die "could not stop Windows PID ${pid}"
  fi
  rm -f "$STATE" "$ASSERT_FILE"
  printf 'STATUS=stopped\n'
}

command="${1:-}"
case "$command" in
  start)
    duration="${2:-}"
    [[ "$duration" =~ ^[0-9]+$ ]] ||
      die "duration must be an integer of at least 5 seconds"
    duration=$((10#$duration))
    (( duration >= 5 )) ||
      die "duration must be an integer of at least 5 seconds"
    shift 2
    start_job timer "$duration" "$@"
    ;;
  start-pid)
    target_pid="${2:-}"
    [[ "$target_pid" =~ ^[0-9]+$ ]] ||
      die "PID must be a positive integer"
    target_pid=$((10#$target_pid))
    (( target_pid >= 1 )) ||
      die "PID must be a positive integer"
    kill -0 "$target_pid" 2>/dev/null ||
      die "target WSL PID ${target_pid} is not running"
    shift 2
    start_job pid "$target_pid" "$@"
    ;;
  verify)
    verify_running || die "anti-sleep is not running with an active power assertion"
    ;;
  status)
    status_job
    ;;
  stop)
    stop_job
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
