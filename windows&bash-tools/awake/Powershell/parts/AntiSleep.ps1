#Requires -Version 5.1
# Moteur anti-veille, cote Windows natif.
#
# Pose une assertion d'alimentation portee par un processus PowerShell detache,
# qui survit au terminal l'ayant lance et au verrouillage de la session.
# N'ecrit que des lignes CLE=valeur : la facade awake.ps1 les lit.
#
# Usage :
#   AntiSleep.ps1 start SECONDES [-NoDisplay]
#   AntiSleep.ps1 start-pid PID  [-NoDisplay]
#   AntiSleep.ps1 verify
#   AntiSleep.ps1 status
#   AntiSleep.ps1 stop
[CmdletBinding()]
param(
  [Parameter(Position = 0)][string]$Command = '',
  [Parameter(Position = 1)][string]$Target = '',
  [switch]$NoDisplay
)

$ErrorActionPreference = 'Stop'

$ScriptDir  = $PSScriptRoot
$StateDir   = Join-Path $env:LOCALAPPDATA 'anti-sleep'
$StateFile  = Join-Path $StateDir 'state'
$AssertFile = Join-Path $StateDir 'asserted'
$LockDir    = Join-Path $StateDir 'lock'
$EngineSrc  = Join-Path $ScriptDir 'keepawake.ps1'
$EngineDst  = Join-Path $StateDir  'keepawake.ps1'

$script:LockHeld = $false
$script:ExitCode = 0

function Exit-Lock {
  if ($script:LockHeld) {
    Remove-Item -LiteralPath $LockDir -Recurse -Force -ErrorAction SilentlyContinue
    $script:LockHeld = $false
  }
}

function Die([string]$Message) {
  [Console]::Error.WriteLine("ERROR=$Message")
  Exit-Lock
  exit 1
}

function Show-Usage {
  @(
    'Usage:'
    '  AntiSleep.ps1 start SECONDS [-NoDisplay]'
    '  AntiSleep.ps1 start-pid PID [-NoDisplay]'
    '  AntiSleep.ps1 verify'
    '  AntiSleep.ps1 status'
    '  AntiSleep.ps1 stop'
    ''
    'Par defaut l ecran est maintenu allume. -NoDisplay empeche seulement la'
    'mise en veille du systeme et laisse l ecran s eteindre.'
  )
}

# Relance le meme hote que celui en cours (powershell.exe ou pwsh.exe), pour ne
# pas dependre d une installation particuliere.
function Get-HostExecutable {
  try {
    $path = (Get-Process -Id $PID).Path
    if ($path -and (Test-Path -LiteralPath $path)) { return $path }
  } catch { }
  return 'powershell.exe'
}

function Enter-Lock {
  New-Item -ItemType Directory -Force -Path $StateDir | Out-Null

  try {
    New-Item -ItemType Directory -Path $LockDir -ErrorAction Stop | Out-Null
    $script:LockHeld = $true
    return
  } catch { }

  # Verrou perime : un processus tue avant d avoir pu le liberer.
  $age = 999
  try {
    $age = ((Get-Date) - (Get-Item -LiteralPath $LockDir).LastWriteTime).TotalSeconds
  } catch { }
  if ($age -le 30) { Die 'another anti-sleep operation is in progress' }

  Remove-Item -LiteralPath $LockDir -Recurse -Force -ErrorAction SilentlyContinue
  try {
    New-Item -ItemType Directory -Path $LockDir -ErrorAction Stop | Out-Null
    $script:LockHeld = $true
  } catch {
    Die 'another anti-sleep operation is in progress'
  }
}

function Get-Epoch {
  return [DateTimeOffset]::Now.ToUnixTimeSeconds()
}

function Format-Epoch([long]$Epoch) {
  return [DateTimeOffset]::FromUnixTimeSeconds($Epoch).ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss')
}

function Get-StateValue([string]$Key) {
  if (-not (Test-Path -LiteralPath $StateFile)) { return $null }
  $pattern = '^' + [regex]::Escape($Key) + '=(.*)$'
  foreach ($line in (Get-Content -LiteralPath $StateFile -ErrorAction SilentlyContinue)) {
    if ($line -match $pattern) { return $Matches[1] }
  }
  return $null
}

function Write-State($Mode, $TargetValue, $Flags, $ProcessId, $StartEpoch, $ExpiresEpoch) {
  $temp = Join-Path $StateDir ('state.' + [guid]::NewGuid().ToString('N').Substring(0, 8))
  $lines = @(
    "MODE=$Mode"
    "TARGET=$TargetValue"
    "FLAGS=$Flags"
    "PID=$ProcessId"
    "START_EPOCH=$StartEpoch"
    "EXPIRES_EPOCH=$ExpiresEpoch"
  )
  Set-Content -LiteralPath $temp -Value $lines -Encoding ASCII
  Move-Item -LiteralPath $temp -Destination $StateFile -Force
}

function Test-KeepAwakeProcess([string]$ProcessId) {
  if ([string]::IsNullOrWhiteSpace($ProcessId)) { return $false }
  if ($ProcessId -notmatch '^\d+$') { return $false }

  $proc = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction SilentlyContinue
  if (-not $proc) { return $false }
  if (-not $proc.CommandLine) { return $false }
  return ($proc.CommandLine -like '*keepawake.ps1*')
}

function Test-Asserted {
  if (-not (Test-Path -LiteralPath $AssertFile)) { return $false }
  $content = Get-Content -LiteralPath $AssertFile -ErrorAction SilentlyContinue
  if (-not $content) { return $false }
  return (($content -join "`n") -match 'ASSERTED=1')
}

# Rend les lignes du rapport si la protection tourne vraiment, $null sinon.
# Deux conditions : le processus attendu existe ET il a confirme l assertion.
function Get-RunningReport {
  $processId = Get-StateValue 'PID'
  if (-not (Test-KeepAwakeProcess $processId)) { return $null }
  if (-not (Test-Asserted)) { return $null }

  $mode  = Get-StateValue 'MODE'
  $lines = @(
    'STATUS=running'
    "PID=$processId"
    'ASSERTIONS=active'
    "MODE=$mode"
    ('FLAGS=' + (Get-StateValue 'FLAGS'))
  )
  if ($mode -eq 'timer') {
    $expires = Get-StateValue 'EXPIRES_EPOCH'
    $lines += "EXPIRES_EPOCH=$expires"
    if ($expires -match '^\d+$') {
      $lines += ('EXPIRES=' + (Format-Epoch ([long]$expires)))
    }
  } else {
    $lines += ('UNTIL_PID=' + (Get-StateValue 'TARGET'))
  }
  return $lines
}

function Start-KeepAwake([string]$Mode, [string]$TargetValue, [bool]$Display) {
  Enter-Lock

  $existing = Get-StateValue 'PID'
  if (Test-KeepAwakeProcess $existing) {
    Die "anti-sleep is already running as Windows PID $existing; inspect it before replacing it"
  }

  Remove-Item -LiteralPath $StateFile, $AssertFile -Force -ErrorAction SilentlyContinue
  if (-not (Test-Path -LiteralPath $EngineSrc)) {
    Die "keepawake.ps1 not found next to AntiSleep.ps1 ($EngineSrc)"
  }
  Copy-Item -LiteralPath $EngineSrc -Destination $EngineDst -Force

  # Les chemins sont cites un par un : %LOCALAPPDATA% contient un espace des
  # que le nom d utilisateur en contient un.
  $argList = @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass',
    '-File', ('"' + $EngineDst + '"'),
    '-AssertFile', ('"' + $AssertFile + '"')
  )
  if ($Mode -eq 'timer') { $argList += @('-Seconds',  $TargetValue) }
  else                   { $argList += @('-WatchPid', $TargetValue) }
  if ($Display) { $argList += '-Display' }

  $startEpoch   = Get-Epoch
  $expiresEpoch = 0
  if ($Mode -eq 'timer') { $expiresEpoch = $startEpoch + [long]$TargetValue }

  $proc = $null
  try {
    $proc = Start-Process -FilePath (Get-HostExecutable) -ArgumentList $argList `
              -WindowStyle Hidden -PassThru
  } catch {
    Die ('Start-Process failed: ' + $_.Exception.Message)
  }
  if (-not $proc -or -not $proc.Id) { Die 'Start-Process did not return a Windows PID' }

  for ($attempt = 0; $attempt -lt 10; $attempt++) {
    if (Test-Asserted) { break }
    Start-Sleep -Milliseconds 500
  }

  if (-not (Test-Asserted)) {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $StateFile, $AssertFile -Force -ErrorAction SilentlyContinue
    Die 'keepawake.ps1 did not report an active power assertion'
  }

  $flags = 'system'
  if ($Display) { $flags = 'display,system' }
  Write-State $Mode $TargetValue $flags $proc.Id $startEpoch $expiresEpoch

  $report = Get-RunningReport
  if (-not $report) {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $StateFile, $AssertFile -Force -ErrorAction SilentlyContinue
    Die 'keep-awake process started but verification failed'
  }
  Write-Output $report
}

function Show-Status {
  $report = Get-RunningReport
  if ($report) { Write-Output $report; return }

  if (Test-Path -LiteralPath $StateFile) {
    if ((Get-StateValue 'MODE') -eq 'timer') {
      $expires = Get-StateValue 'EXPIRES_EPOCH'
      if ($expires -match '^\d+$' -and (Get-Epoch) -ge [long]$expires) {
        Write-Output 'STATUS=expired'
        Write-Output ('EXPIRED_AT=' + (Format-Epoch ([long]$expires)))
        return
      }
    }
    # Etat present mais processus absent : mort inattendue, pas une expiration.
    Write-Output 'STATUS=failed'
    Write-Output ('EXPECTED_PID=' + (Get-StateValue 'PID'))
    $script:ExitCode = 1
    return
  }

  Write-Output 'STATUS=stopped'
}

function Stop-KeepAwake {
  Enter-Lock
  $processId = Get-StateValue 'PID'
  if (Test-KeepAwakeProcess $processId) {
    try {
      Stop-Process -Id ([int]$processId) -Force -ErrorAction Stop
    } catch {
      Die "could not stop Windows PID $processId"
    }
  }
  Remove-Item -LiteralPath $StateFile, $AssertFile -Force -ErrorAction SilentlyContinue
  Write-Output 'STATUS=stopped'
}

try {
  switch ($Command) {
    'start' {
      if ($Target -notmatch '^\d+$' -or [long]$Target -lt 5) {
        Die 'duration must be an integer of at least 5 seconds'
      }
      Start-KeepAwake 'timer' $Target (-not $NoDisplay)
    }
    'start-pid' {
      if ($Target -notmatch '^\d+$' -or [long]$Target -lt 1) {
        Die 'PID must be a positive integer'
      }
      if (-not (Get-Process -Id ([int]$Target) -ErrorAction SilentlyContinue)) {
        Die "target PID $Target is not running"
      }
      Start-KeepAwake 'pid' $Target (-not $NoDisplay)
    }
    'verify' {
      $report = Get-RunningReport
      if (-not $report) { Die 'anti-sleep is not running with an active power assertion' }
      Write-Output $report
    }
    'status' { Show-Status }
    'stop'   { Stop-KeepAwake }
    { $_ -in @('-h', '--help', 'help') } { Show-Usage }
    default {
      Show-Usage | ForEach-Object { [Console]::Error.WriteLine($_) }
      $script:ExitCode = 2
    }
  }
}
finally {
  Exit-Lock
}

exit $script:ExitCode
