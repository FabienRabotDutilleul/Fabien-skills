#Requires -Version 5.1
# Mesure si les processus continuent vraiment de tourner quand la machine est
# verrouillee ou inactive. Un battement toutes les 10 s : un trou dans le
# journal est une preuve directe de gel.
#
# La version WSL de cet outil comparait deux battements (WSL et Windows) pour
# distinguer une pause de la VM WSL d une suspension de toute la machine. En
# natif cette distinction n existe plus ; a la place, les trous sont confrontes
# au journal d evenements Kernel-Power, qui dit si Windows s est reellement
# endormi et pour combien de temps.
#
# Usage :
#   SleepProbe.ps1 start    Demarre le battement
#   SleepProbe.ps1 report   Affiche les trous enregistres
#   SleepProbe.ps1 stop     Arrete le battement
#   SleepProbe.ps1 reset    Arrete et efface les journaux
[CmdletBinding()]
param(
  [Parameter(Position = 0)][string]$Command = ''
)

$ErrorActionPreference = 'Stop'

$Interval     = 10
$GapThreshold = 45   # 4 battements manques : bien au-dela de la gigue d ordonnancement

$ScriptDir = $PSScriptRoot
$ProbeDir  = Join-Path $env:LOCALAPPDATA 'anti-sleep\probe'
$LogFile   = Join-Path $ProbeDir 'heartbeat.log'
$StateFile = Join-Path $ProbeDir 'probe-state'
$LoopSrc   = Join-Path $ScriptDir 'probe-loop.ps1'
$LoopDst   = Join-Path $ProbeDir  'probe-loop.ps1'
$Engine    = Join-Path $ScriptDir 'AntiSleep.ps1'

$script:ExitCode = 0

function Die([string]$Message) {
  [Console]::Error.WriteLine("ERROR=$Message")
  exit 1
}

function Show-Usage {
  @(
    'Usage:'
    '  SleepProbe.ps1 start     Demarre le battement'
    '  SleepProbe.ps1 report    Affiche les trous enregistres'
    '  SleepProbe.ps1 stop      Arrete le battement'
    '  SleepProbe.ps1 reset     Arrete et efface les journaux'
  )
}

function Get-HostExecutable {
  try {
    $path = (Get-Process -Id $PID).Path
    if ($path -and (Test-Path -LiteralPath $path)) { return $path }
  } catch { }
  return 'powershell.exe'
}

function Get-StateValue([string]$Key) {
  if (-not (Test-Path -LiteralPath $StateFile)) { return $null }
  $pattern = '^' + [regex]::Escape($Key) + '=(.*)$'
  foreach ($line in (Get-Content -LiteralPath $StateFile -ErrorAction SilentlyContinue)) {
    if ($line -match $pattern) { return $Matches[1] }
  }
  return $null
}

function Test-ProbeProcess([string]$ProcessId) {
  if ([string]::IsNullOrWhiteSpace($ProcessId)) { return $false }
  if ($ProcessId -notmatch '^\d+$') { return $false }
  $proc = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction SilentlyContinue
  if (-not $proc) { return $false }
  if (-not $proc.CommandLine) { return $false }
  return ($proc.CommandLine -like '*probe-loop.ps1*')
}

function Start-Probe {
  if (Test-ProbeProcess (Get-StateValue 'PROBE_PID')) {
    Die "probe already running; use 'report' or 'stop'"
  }

  New-Item -ItemType Directory -Force -Path $ProbeDir | Out-Null
  if (-not (Test-Path -LiteralPath $LoopSrc)) {
    Die "probe-loop.ps1 not found next to SleepProbe.ps1 ($LoopSrc)"
  }
  Copy-Item -LiteralPath $LoopSrc -Destination $LoopDst -Force

  $argList = @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass',
    '-File', ('"' + $LoopDst + '"'),
    '-Log',  ('"' + $LogFile + '"'),
    '-Interval', $Interval
  )

  $proc = $null
  try {
    $proc = Start-Process -FilePath (Get-HostExecutable) -ArgumentList $argList `
              -WindowStyle Hidden -PassThru
  } catch {
    Die ('could not start the heartbeat: ' + $_.Exception.Message)
  }
  if (-not $proc -or -not $proc.Id) { Die 'could not start the heartbeat' }

  Set-Content -LiteralPath $StateFile -Encoding ASCII -Value @(
    ("PROBE_PID=" + $proc.Id)
    ("STARTED="   + [DateTimeOffset]::Now.ToUnixTimeSeconds())
  )

  Write-Output 'STATUS=probing'
  Write-Output "INTERVAL=${Interval}s"
  Write-Output ("PROBE_PID=" + $proc.Id)
}

function Get-Beats {
  if (-not (Test-Path -LiteralPath $LogFile)) { return @() }
  $beats = @()
  foreach ($line in (Get-Content -LiteralPath $LogFile -ErrorAction SilentlyContinue)) {
    $trimmed = $line.Trim()
    if ($trimmed -match '^\d+$') { $beats += [long]$trimmed }
  }
  return $beats
}

function Show-Gaps {
  $beats = Get-Beats
  if ($beats.Count -eq 0) {
    Write-Output 'Sonde : aucun battement enregistre'
    return
  }

  $gaps  = @()
  $worst = 0
  for ($i = 1; $i -lt $beats.Count; $i++) {
    $delta = $beats[$i] - $beats[$i - 1]
    if ($delta -gt $GapThreshold) {
      $gaps += [pscustomobject]@{ From = $beats[$i - 1]; To = $beats[$i]; Seconds = $delta }
      if ($delta -gt $worst) { $worst = $delta }
    }
  }

  $first = [DateTimeOffset]::FromUnixTimeSeconds($beats[0]).ToLocalTime().ToString('HH:mm:ss')
  $last  = [DateTimeOffset]::FromUnixTimeSeconds($beats[-1]).ToLocalTime().ToString('HH:mm:ss')
  Write-Output ("Sonde : {0} battements, de {1} a {2}" -f $beats.Count, $first, $last)

  foreach ($gap in $gaps) {
    Write-Output ("  TROU {0,5} s  de {1} a {2}" -f
      $gap.Seconds,
      [DateTimeOffset]::FromUnixTimeSeconds($gap.From).ToLocalTime().ToString('HH:mm:ss'),
      [DateTimeOffset]::FromUnixTimeSeconds($gap.To).ToLocalTime().ToString('HH:mm:ss'))
  }

  if ($gaps.Count -gt 0) {
    Write-Output ("  => {0} trou(s), le plus long {1} s" -f $gaps.Count, $worst)
  } else {
    Write-Output '  => aucun trou : le processus a tourne sans interruption'
  }

  $now = [DateTimeOffset]::Now.ToUnixTimeSeconds()
  if (($now - $beats[-1]) -gt $GapThreshold) {
    Write-Output ''
    Write-Output ("ATTENTION : la sonde est muette depuis {0} s (arretee ou gelee a l instant)" -f ($now - $beats[-1]))
  }
}

# Confronte les trous au journal Windows : un trou double d un evenement
# Kernel-Power est une vraie suspension ; un trou sans evenement est un gel de
# processus, ce que « awake » est justement cense empecher.
function Show-PowerEvents {
  $started = Get-StateValue 'STARTED'
  $since   = if ($started -match '^\d+$') {
    [DateTimeOffset]::FromUnixTimeSeconds([long]$started).LocalDateTime
  } else {
    (Get-Date).AddDays(-1)
  }

  try {
    $events = Get-WinEvent -ErrorAction Stop -FilterHashtable @{
      LogName      = 'System'
      ProviderName = @('Microsoft-Windows-Kernel-Power', 'Microsoft-Windows-Power-Troubleshooter')
      StartTime    = $since
    }
  } catch {
    Write-Output 'Journal Windows : aucun evenement d alimentation depuis le demarrage de la sonde'
    return
  }

  $relevant = @($events | Where-Object { $_.Id -in @(42, 107, 1) })
  if ($relevant.Count -eq 0) {
    Write-Output 'Journal Windows : aucun evenement de mise en veille'
    return
  }

  Write-Output ("Journal Windows : {0} evenement(s) d alimentation" -f $relevant.Count)
  foreach ($event in ($relevant | Sort-Object TimeCreated)) {
    $label = switch ($event.Id) {
      42      { 'mise en veille' }
      107     { 'reprise' }
      1       { 'retour d un etat basse consommation' }
      default { "id $($event.Id)" }
    }
    Write-Output ("  {0}  {1}" -f $event.TimeCreated.ToString('HH:mm:ss'), $label)
  }
}

function Show-Report {
  Write-Output '=== anti-sleep ==='
  if (Test-Path -LiteralPath $Engine) {
    & $Engine status
  } else {
    Write-Output 'moteur AntiSleep.ps1 introuvable'
  }

  Write-Output ''
  Write-Output '=== sonde ==='
  Show-Gaps

  Write-Output ''
  Show-PowerEvents
}

function Stop-Probe {
  $processId = Get-StateValue 'PROBE_PID'
  if (Test-ProbeProcess $processId) {
    Stop-Process -Id ([int]$processId) -Force -ErrorAction SilentlyContinue
  }
  Remove-Item -LiteralPath $StateFile -Force -ErrorAction SilentlyContinue
  Write-Output 'STATUS=stopped'
}

switch ($Command) {
  'start'  { Start-Probe }
  'report' { Show-Report }
  'stop'   { Stop-Probe }
  'reset'  {
    Stop-Probe
    Remove-Item -LiteralPath $LogFile -Force -ErrorAction SilentlyContinue
    Write-Output 'LOGS=cleared'
  }
  { $_ -in @('-h', '--help', 'help') } { Show-Usage }
  default {
    Show-Usage | ForEach-Object { [Console]::Error.WriteLine($_) }
    $script:ExitCode = 2
  }
}

exit $script:ExitCode
