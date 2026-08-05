#!/bin/bash
# install_awake.sh — installe la commande « awake » : empeche Windows de se
# mettre en veille, pilote depuis WSL.
#
# Usage :  bash install_awake.sh              installe ou met a jour
#          bash install_awake.sh --uninstall  desinstalle
#
# Fichier genere : les scripts sont embarques plus bas, ne pas editer a la main.
set -euo pipefail

BIN_DIR="${HOME}/.local/bin"
LIB_DIR="${HOME}/.local/share/awake"
SRC_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

BOLD=$'\e[1m'; DIM=$'\e[2m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'
RED=$'\e[31m'; RESET=$'\e[0m'

ok()   { printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '  %s!%s %s\n' "$YELLOW" "$RESET" "$*"; }
fail() { printf '  %s✗%s %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }
step() { printf '\n%s%s%s\n' "$BOLD" "$*" "$RESET"; }

if [[ "${1:-}" == "--uninstall" ]]; then
  step "Desinstallation"
  "${BIN_DIR}/awake" stop >/dev/null 2>&1 || true
  rm -f "${BIN_DIR}/awake"
  rm -rf "$LIB_DIR"
  ok "awake retire de ${BIN_DIR} et ${LIB_DIR}"
  warn "la ligne PATH ajoutee dans ~/.bashrc est laissee telle quelle"
  exit 0
fi

printf '%s╔══════════════════════════════════════════╗%s\n' "$BOLD" "$RESET"
printf '%s║   Installation de awake (anti-veille)    ║%s\n' "$BOLD" "$RESET"
printf '%s╚══════════════════════════════════════════╝%s\n' "$BOLD" "$RESET"

step "1. Verification de l'environnement"

grep -qiE "microsoft|wsl" /proc/version 2>/dev/null ||
  fail "ce script s'installe depuis WSL (Windows Subsystem for Linux)."
ok "WSL detecte : ${WSL_DISTRO_NAME:-distribution inconnue}"

command -v powershell.exe >/dev/null 2>&1 ||
  fail "powershell.exe est injoignable depuis WSL : l'interop Windows est desactive.
     Activez-le avec, dans /etc/wsl.conf :  [interop]  enabled=true"
ok "interop Windows disponible"

LOCALAPPDATA=$(powershell.exe -NoProfile -Command 'Write-Output $env:LOCALAPPDATA' </dev/null 2>/dev/null | tr -d '\r')
[[ -n "$LOCALAPPDATA" ]] ||
  fail "PowerShell ne repond pas correctement (%LOCALAPPDATA% vide)."
ok "PowerShell repond"

# Sortie capturee avant analyse : un « grep -q » en bout de tuyau fermerait le
# pipe trop tot et ferait tomber le script a cause de « pipefail ».
SLEEP_STATES=$(powershell.exe -NoProfile -Command 'powercfg /a' </dev/null 2>/dev/null | tr -d '\r' || true)
if grep -qiE "S0|faible consommation|low power" <<<"$SLEEP_STATES"; then
  warn "machine en Modern Standby : voir la note en fin d'installation"
  MODERN_STANDBY=1
else
  MODERN_STANDBY=0
fi

step "2. Installation des fichiers"

mkdir -p "$LIB_DIR" "$BIN_DIR"

write_file() {
  local name="$1" mode="$2"
  cat >"${LIB_DIR}/${name}"
  chmod "$mode" "${LIB_DIR}/${name}"
}

write_file 'anti-sleep.sh' '755' <<'PAYLOAD_anti_sleep_sh'
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
PAYLOAD_anti_sleep_sh

write_file 'keepawake.ps1' '644' <<'PAYLOAD_keepawake_ps1'
# Holds a Windows power assertion (SetThreadExecutionState) for a fixed duration
# or while a WSL process is alive, then releases it. Launched detached by
# anti-sleep.sh via Start-Process so it outlives the WSL shell that started it.
param(
  [int]$Seconds = 0,
  [int]$WatchPid = 0,
  [string]$Distro = "",
  [switch]$Display,
  [Parameter(Mandatory = $true)][string]$AssertFile
)

$ErrorActionPreference = 'Stop'

Add-Type -Namespace AntiSleep -Name Power -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)]
public static extern uint SetThreadExecutionState(uint esFlags);
'@

$ES_CONTINUOUS       = [uint32]'0x80000000'
$ES_SYSTEM_REQUIRED  = [uint32]'0x00000001'
$ES_DISPLAY_REQUIRED = [uint32]'0x00000002'

$flags = $ES_CONTINUOUS -bor $ES_SYSTEM_REQUIRED
if ($Display) { $flags = $flags -bor $ES_DISPLAY_REQUIRED }

$previous = [AntiSleep.Power]::SetThreadExecutionState($flags)
if ($previous -eq 0) {
  Set-Content -Path $AssertFile -Value 'ASSERTED=0'
  exit 1
}
Set-Content -Path $AssertFile -Value 'ASSERTED=1'

try {
  if ($Seconds -gt 0) {
    Start-Sleep -Seconds $Seconds
  }
  elseif ($WatchPid -gt 0) {
    # Poll the WSL-side PID; native stderr must not trip ErrorActionPreference.
    $ErrorActionPreference = 'Continue'
    while ($true) {
      Start-Sleep -Seconds 20
      & wsl.exe -d $Distro -e kill -0 $WatchPid 2>$null
      if ($LASTEXITCODE -ne 0) { break }
    }
  }
}
finally {
  [AntiSleep.Power]::SetThreadExecutionState($ES_CONTINUOUS) | Out-Null
  Remove-Item -Path $AssertFile -ErrorAction SilentlyContinue
}
PAYLOAD_keepawake_ps1

write_file 'sleep-probe.sh' '755' <<'PAYLOAD_sleep_probe_sh'
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
PAYLOAD_sleep_probe_sh

write_file 'probe-loop.sh' '755' <<'PAYLOAD_probe_loop_sh'
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
PAYLOAD_probe_loop_sh

write_file 'probe-loop.ps1' '644' <<'PAYLOAD_probe_loop_ps1'
# Heartbeat on the Windows side: one epoch timestamp every -Interval seconds.
# Compared against the WSL heartbeat, it separates "the whole machine froze"
# from "only the WSL VM was paused".
param(
  [Parameter(Mandatory = $true)][string]$Log,
  [int]$Interval = 10
)

$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Log) | Out-Null

while ($true) {
  [DateTimeOffset]::Now.ToUnixTimeSeconds() |
    Out-File -FilePath $Log -Append -Encoding ascii
  Start-Sleep -Seconds $Interval
}
PAYLOAD_probe_loop_ps1

write_file 'awake' '755' <<'PAYLOAD_awake'
#!/bin/bash
# Menu interactif pour empecher Windows de se mettre en veille depuis WSL.
# Toute la logique vit dans le skill anti-sleep ; ce script n'est qu'une facade.
set -uo pipefail

# Le moteur est cherche dans l'ordre : variable d'environnement, installation
# standard (install_awake.sh), puis le skill Claude sur les postes qui l'ont.
AWAKE_HOME="${AWAKE_HOME:-}"
for candidate in \
  "$AWAKE_HOME" \
  "${HOME}/.local/share/awake" \
  "${HOME}/.claude/skills/anti-sleep/scripts"
do
  [[ -n "$candidate" && -x "${candidate}/anti-sleep.sh" ]] || continue
  AWAKE_HOME="$candidate"
  break
done

ENGINE="${AWAKE_HOME}/anti-sleep.sh"
PROBE="${AWAKE_HOME}/sleep-probe.sh"

[[ -x "$ENGINE" ]] || {
  echo "Moteur anti-veille introuvable." >&2
  echo "Lancez install_awake.sh, ou definissez AWAKE_HOME." >&2
  exit 1
}

BOLD=$'\e[1m'; DIM=$'\e[2m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'
RED=$'\e[31m'; CYAN=$'\e[36m'; RESET=$'\e[0m'

# </dev/null est indispensable : powershell.exe, lance en cascade par le moteur,
# lit l'entree standard et volerait les reponses saisies dans le menu.
engine() { "$ENGINE" "$@" </dev/null 2>&1; }

# Traduit "2h", "90m", "1h30", "45", "3600s" en secondes. 45 seul = 45 minutes.
parse_duration() {
  local input="${1,,}"
  local seconds=0 matched=0 value

  input="${input// /}"
  [[ -n "$input" ]] || return 1

  if [[ "$input" =~ ^([0-9]+)h([0-9]+)$ ]]; then
    printf '%s' $(( BASH_REMATCH[1] * 3600 + BASH_REMATCH[2] * 60 ))
    return 0
  fi
  if [[ "$input" =~ ^[0-9]+$ ]]; then
    printf '%s' $(( input * 60 ))
    return 0
  fi

  while [[ -n "$input" ]]; do
    if [[ "$input" =~ ^([0-9]+)([hms]) ]]; then
      value="${BASH_REMATCH[1]}"
      case "${BASH_REMATCH[2]}" in
        h) seconds=$(( seconds + value * 3600 )) ;;
        m) seconds=$(( seconds + value * 60 )) ;;
        s) seconds=$(( seconds + value )) ;;
      esac
      input="${input#"${BASH_REMATCH[0]}"}"
      matched=1
    else
      return 1
    fi
  done

  (( matched )) || return 1
  printf '%s' "$seconds"
}

human_duration() {
  local total="$1" h m
  h=$(( total / 3600 )); m=$(( (total % 3600) / 60 ))
  if (( h && m )); then printf '%dh%02d' "$h" "$m"
  elif (( h )); then printf '%dh' "$h"
  else printf '%d min' "$m"; fi
}

show_status() {
  local output status expires remaining now

  output=$(engine status)
  status=$(awk -F= '/^STATUS=/ { print $2; exit }' <<<"$output")

  case "$status" in
    running)
      if grep -q '^MODE=pid' <<<"$output"; then
        printf '  %s● ACTIF%s   tant que le PID %s%s%s tourne\n' \
          "$GREEN" "$RESET" "$BOLD" \
          "$(awk -F= '/^UNTIL_PID=/ { print $2; exit }' <<<"$output")" "$RESET"
      else
        expires=$(awk -F= '/^EXPIRES=/ { sub(/^[^=]*=/, ""); print; exit }' <<<"$output")
        now=$(date +%s)
        remaining=$(( $(date -d "$expires" +%s 2>/dev/null || echo "$now") - now ))
        printf '  %s● ACTIF%s   encore %s%s%s, jusqu%s %s\n' \
          "$GREEN" "$RESET" "$BOLD" "$(human_duration $(( remaining > 0 ? remaining : 0 )))" \
          "$RESET" "'" "${expires%:* *}"
      fi
      ;;
    expired)
      printf '  %s○ EXPIRE%s  la protection est terminee\n' "$YELLOW" "$RESET" ;;
    stopped)
      printf '  %s○ INACTIF%s la machine peut se mettre en veille\n' "$DIM" "$RESET" ;;
    *)
      printf '  %s● PROBLEME%s\n%s\n' "$RED" "$RESET" "$output" ;;
  esac
}

start_for() {
  local seconds="$1" out

  engine stop >/dev/null 2>&1
  printf '\n  Demarrage pour %s...\n' "$(human_duration "$seconds")"
  out=$(engine start "$seconds")
  if grep -q '^STATUS=running' <<<"$out"; then
    printf '  %s✓ Protection active%s jusqu%s %s\n' "$GREEN" "$RESET" "'" \
      "$(awk -F= '/^EXPIRES=/ { sub(/^[^=]*=/, ""); print; exit }' <<<"$out")"
  else
    printf '  %s✗ Echec :%s\n%s\n' "$RED" "$RESET" "$out"
  fi
}

start_until_pid() {
  local pid="$1" out

  if ! kill -0 "$pid" 2>/dev/null; then
    printf '  %s✗ Le PID %s ne tourne pas.%s\n' "$RED" "$pid" "$RESET"
    return
  fi
  engine stop >/dev/null 2>&1
  out=$(engine start-pid "$pid")
  if grep -q '^STATUS=running' <<<"$out"; then
    printf '  %s✓ Protection active%s tant que le PID %s tourne\n' "$GREEN" "$RESET" "$pid"
  else
    printf '  %s✗ Echec :%s\n%s\n' "$RED" "$RESET" "$out"
  fi
}

ask_custom() {
  local answer seconds

  read -rp "  Duree (ex: 90m, 2h, 1h30, 45) : " answer
  if seconds=$(parse_duration "$answer"); then
    if (( seconds < 60 )); then
      printf '  %s✗ Minimum une minute.%s\n' "$RED" "$RESET"
    else
      start_for "$seconds"
    fi
  else
    printf '  %s✗ Format non compris.%s\n' "$RED" "$RESET"
  fi
}

ask_pid() {
  local answer

  printf '  %sProcessus WSL en cours :%s\n' "$DIM" "$RESET"
  ps -u "$USER" -o pid=,etime=,comm= --sort=-etime | head -8 | sed 's/^/    /'
  read -rp "  PID a surveiller : " answer
  [[ "$answer" =~ ^[0-9]+$ ]] && start_until_pid "$answer" ||
    printf '  %s✗ PID invalide.%s\n' "$RED" "$RESET"
}

menu() {
  local choice

  while true; do
    printf '\n%s┌─ Anti-veille Windows ─────────────────%s\n' "$BOLD" "$RESET"
    show_status
    printf '%s└───────────────────────────────────────%s\n\n' "$BOLD" "$RESET"
    printf '  %s1%s) 30 minutes      %s4%s) 4 heures\n' "$CYAN" "$RESET" "$CYAN" "$RESET"
    printf '  %s2%s) 1 heure         %s5%s) 8 heures (nuit)\n' "$CYAN" "$RESET" "$CYAN" "$RESET"
    printf '  %s3%s) 2 heures        %s6%s) duree libre\n' "$CYAN" "$RESET" "$CYAN" "$RESET"
    printf '\n  %sp%s) jusqu%s la fin d%sun processus\n' "$CYAN" "$RESET" "'" "'"
    printf '  %ss%s) arreter la protection\n' "$CYAN" "$RESET"
    printf '  %sq%s) quitter %s(la protection continue en arriere-plan)%s\n\n' \
      "$CYAN" "$RESET" "$DIM" "$RESET"

    read -rp "  Choix : " choice
    case "$choice" in
      1) start_for 1800 ;;
      2) start_for 3600 ;;
      3) start_for 7200 ;;
      4) start_for 14400 ;;
      5) start_for 28800 ;;
      6) ask_custom ;;
      p|P) ask_pid ;;
      s|S) printf '\n'; engine stop | sed 's/^/  /' ;;
      q|Q|"") printf '\n'; exit 0 ;;
      *) printf '  %s✗ Choix inconnu.%s\n' "$RED" "$RESET" ;;
    esac
  done
}

# Usage direct sans menu : awake 2h | awake stop | awake status | awake probe ...
case "${1:-}" in
  "")       menu ;;
  stop)     engine stop ;;
  status)   show_status ;;
  probe)    shift; exec "$PROBE" "${@:-report}" ;;
  -h|--help|help)
    cat <<'EOF'
Usage:
  awake              menu interactif
  awake 2h           demarre directement (2h, 90m, 1h30, 45 = minutes)
  awake pid 12345    reste eveille tant que ce PID WSL tourne
  awake status       etat courant
  awake stop         arrete la protection
  awake probe start|report|stop    mesure les gels de processus
EOF
    ;;
  pid)
    [[ "${2:-}" =~ ^[0-9]+$ ]] && start_until_pid "$2" ||
      { echo "PID invalide" >&2; exit 2; }
    ;;
  *)
    if seconds=$(parse_duration "$1"); then
      (( seconds >= 60 )) && start_for "$seconds" ||
        { echo "Minimum une minute" >&2; exit 2; }
    else
      echo "Duree non comprise : $1 (essayez 2h, 90m, 1h30)" >&2
      exit 2
    fi
    ;;
esac
PAYLOAD_awake

ok "moteur installe dans ${LIB_DIR}"

# Un fichier « awake » pose a cote de l'installeur a la priorite : il permet de
# distribuer une version corrigee sans regenerer l'installeur.
if [[ -f "${SRC_DIR}/awake" ]]; then
  install -m 755 "${SRC_DIR}/awake" "${BIN_DIR}/awake"
  install -m 755 "${SRC_DIR}/awake" "${LIB_DIR}/awake"
  ok "commande awake installee (depuis le fichier fourni a cote)"
else
  install -m 755 "${LIB_DIR}/awake" "${BIN_DIR}/awake"
  ok "commande awake installee (copie embarquee)"
fi

step "3. Acces depuis le terminal"

if [[ ":${PATH}:" == *":${BIN_DIR}:"* ]]; then
  ok "${BIN_DIR} est deja dans le PATH"
else
  LINE='export PATH="$HOME/.local/bin:$PATH"'
  for rc in "${HOME}/.bashrc" "${HOME}/.zshrc"; do
    [[ -f "$rc" ]] || continue
    if grep -qF "$LINE" "$rc"; then
      ok "PATH deja configure dans $(basename "$rc")"
    else
      printf '\n# ajoute par install_awake.sh\n%s\n' "$LINE" >>"$rc"
      ok "PATH ajoute dans $(basename "$rc")"
    fi
  done
  warn "ouvrez un nouveau terminal (ou : source ~/.bashrc) pour que « awake » soit reconnu"
fi

step "4. Test reel"

ENGINE="${LIB_DIR}/anti-sleep.sh"
CURRENT=$("$ENGINE" status </dev/null 2>&1 || true)

if grep -q '^STATUS=running' <<<"$CURRENT"; then
  warn "une protection est deja active : test ignore pour ne pas l'interrompre"
else
  "$ENGINE" stop </dev/null >/dev/null 2>&1 || true
  STARTED=$("$ENGINE" start 60 </dev/null 2>&1 || true)
  CHECKED=$("$ENGINE" verify </dev/null 2>&1 || true)
  "$ENGINE" stop </dev/null >/dev/null 2>&1 || true

  if grep -q '^STATUS=running' <<<"$STARTED" &&
     grep -q '^ASSERTIONS=active' <<<"$CHECKED"; then
    ok "test concluant : Windows a bien accepte de rester eveille"
  else
    fail "le test a echoue : PowerShell n'a pas pu poser l'assertion d'alimentation.
     Detail : ${STARTED}"
  fi
fi

step "C'est pret"

cat <<'USAGE'

  awake              menu interactif (choix de la duree)
  awake 2h           demarrage direct — 2h, 90m, 1h30, ou 45 (= minutes)
  awake pid 12345    reste eveille tant que ce processus WSL tourne
  awake status       etat courant
  awake stop         arret immediat

  La protection survit a la fermeture du terminal et au verrouillage de
  la session : elle tourne dans un processus Windows detache.

USAGE

if [[ "$MODERN_STANDBY" == "1" ]]; then
  printf '%s  Note — cette machine est en Modern Standby.%s\n' "$YELLOW" "$RESET"
  printf '%s  Windows peut y geler les applications quand l ecran s eteint.%s\n' "$DIM" "$RESET"
  printf '%s  Si des traitements longs s arretent malgre awake, mesurez-le avec :%s\n' "$DIM" "$RESET"
  printf '%s     awake probe start   puis   awake probe report%s\n\n' "$DIM" "$RESET"
fi

printf '  Desinstallation : %sbash install_awake.sh --uninstall%s\n\n' "$DIM" "$RESET"
