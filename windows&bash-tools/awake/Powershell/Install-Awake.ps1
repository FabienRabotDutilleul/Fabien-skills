#Requires -Version 5.1
# Install-Awake.ps1 — installe la commande « awake » : empeche Windows de se
# mettre en veille. Version native Windows (aucun WSL requis).
#
# Usage :  powershell -ExecutionPolicy Bypass -File Install-Awake.ps1
#          powershell -ExecutionPolicy Bypass -File Install-Awake.ps1 -Uninstall
#
# Fichier genere par parts/Build-Installer.ps1 : les scripts sont embarques
# plus bas, ne pas editer a la main.
[CmdletBinding()]
param([switch]$Uninstall)

$ErrorActionPreference = 'Stop'

# PowerShell 5.1 ecrit par defaut dans la page de code OEM : sans cette ligne,
# le cadre et les puces de l installeur sortent en « ? ».
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$LibDir = Join-Path $env:LOCALAPPDATA 'Programs\awake'
$BinDir = Join-Path $LibDir 'bin'
$SrcDir = $PSScriptRoot

function Test-AnsiSupport {
  if ($env:WT_SESSION) { return $true }
  if ($PSVersionTable.PSVersion.Major -ge 6) { return $true }
  try { return [bool]$Host.UI.SupportsVirtualTerminal } catch { return $false }
}

$e = [char]27
if (Test-AnsiSupport) {
  $BOLD = "$e[1m"; $DIM = "$e[2m"; $GREEN = "$e[32m"
  $YELLOW = "$e[33m"; $RED = "$e[31m"; $RESET = "$e[0m"
} else {
  $BOLD = ''; $DIM = ''; $GREEN = ''; $YELLOW = ''; $RED = ''; $RESET = ''
}

function Write-Ok   { param([string]$Message) Write-Host ("  {0}✓{1} {2}" -f $GREEN, $RESET, $Message) }
function Write-Warn { param([string]$Message) Write-Host ("  {0}!{1} {2}" -f $YELLOW, $RESET, $Message) }
function Write-Step { param([string]$Message) Write-Host ''; Write-Host ("{0}{1}{2}" -f $BOLD, $Message, $RESET) }
function Write-Fail {
  param([string]$Message)
  [Console]::Error.WriteLine("  x $Message")
  exit 1
}

function Get-UserPath {
  $value = [Environment]::GetEnvironmentVariable('Path', 'User')
  if ($null -eq $value) { return '' }
  return $value
}

# ---------------------------------------------------------------- desinstall

if ($Uninstall) {
  Write-Step 'Desinstallation'

  $engine = Join-Path $LibDir 'AntiSleep.ps1'
  if (Test-Path -LiteralPath $engine) {
    try { & $engine stop | Out-Null } catch { }
  }

  $probe = Join-Path $LibDir 'SleepProbe.ps1'
  if (Test-Path -LiteralPath $probe) {
    try { & $probe stop | Out-Null } catch { }
  }

  if (Test-Path -LiteralPath $LibDir) {
    Remove-Item -LiteralPath $LibDir -Recurse -Force -ErrorAction SilentlyContinue
  }
  Write-Ok "awake retire de $LibDir"

  $entries = @(Get-UserPath -split ';' | Where-Object { $_ -and $_ -ne $BinDir })
  [Environment]::SetEnvironmentVariable('Path', ($entries -join ';'), 'User')
  Write-Ok 'entree PATH utilisateur retiree'

  Write-Warn "l etat resident dans $(Join-Path $env:LOCALAPPDATA 'anti-sleep') est laisse tel quel"
  exit 0
}

# ---------------------------------------------------------------- entete

Write-Host ("{0}╔══════════════════════════════════════════╗{1}" -f $BOLD, $RESET)
Write-Host ("{0}║   Installation de awake (anti-veille)    ║{1}" -f $BOLD, $RESET)
Write-Host ("{0}╚══════════════════════════════════════════╝{1}" -f $BOLD, $RESET)

# ---------------------------------------------------------------- 1. controles

Write-Step "1. Verification de l'environnement"

if (-not $env:LOCALAPPDATA) {
  Write-Fail 'ce script s installe sur Windows (%LOCALAPPDATA% est vide).'
}
Write-Ok ("Windows detecte : " + [Environment]::OSVersion.VersionString)

Write-Ok ("PowerShell " + $PSVersionTable.PSVersion.ToString())

# Modern Standby : Windows peut y geler les applications quand l ecran s eteint,
# ce que l assertion d alimentation n empeche pas toujours.
$modernStandby = $false
try {
  $states = (& powercfg /a 2>&1) -join "`n"
  if ($states -match 'S0|faible consommation|low power|Veille moderne|Modern Standby') {
    $modernStandby = $true
    Write-Warn 'machine en Modern Standby : voir la note en fin d installation'
  }
} catch {
  Write-Warn 'powercfg injoignable : etat de veille non determine'
}

# ---------------------------------------------------------------- 2. fichiers

Write-Step '2. Installation des fichiers'

New-Item -ItemType Directory -Force -Path $LibDir | Out-Null
New-Item -ItemType Directory -Force -Path $BinDir | Out-Null

function Write-Payload {
  param([string]$Name, [string]$Content)
  $path = Join-Path $LibDir $Name
  Set-Content -LiteralPath $path -Value $Content -Encoding UTF8
}

Write-Payload 'AntiSleep.ps1' @'
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
'@

Write-Payload 'keepawake.ps1' @'
# Porte une assertion d'alimentation Windows (SetThreadExecutionState) pendant
# une duree fixe ou tant qu'un processus vit, puis la relache. Lance detache par
# AntiSleep.ps1 via Start-Process, il survit au terminal qui l'a demarre.
#
# Note : la signature P/Invoke est passee en chaine simple plutot qu'en
# here-string, pour que ce fichier reste embarquable dans l'installeur.
param(
  [int]$Seconds = 0,
  [int]$WatchPid = 0,
  [switch]$Display,
  [Parameter(Mandatory = $true)][string]$AssertFile
)

$ErrorActionPreference = 'Stop'

$signature = '[DllImport("kernel32.dll", SetLastError = true)] public static extern uint SetThreadExecutionState(uint esFlags);'
Add-Type -Namespace AntiSleep -Name Power -MemberDefinition $signature

$ES_CONTINUOUS       = [uint32]'0x80000000'
$ES_SYSTEM_REQUIRED  = [uint32]'0x00000001'
$ES_DISPLAY_REQUIRED = [uint32]'0x00000002'

$flags = $ES_CONTINUOUS -bor $ES_SYSTEM_REQUIRED
if ($Display) { $flags = $flags -bor $ES_DISPLAY_REQUIRED }

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $AssertFile) | Out-Null

# Un retour a zero signifie que Windows a refuse la demande : on le signale au
# lanceur par le fichier temoin plutot que de faire croire a une protection.
$previous = [AntiSleep.Power]::SetThreadExecutionState($flags)
if ($previous -eq 0) {
  Set-Content -LiteralPath $AssertFile -Value 'ASSERTED=0' -Encoding ASCII
  exit 1
}
Set-Content -LiteralPath $AssertFile -Value 'ASSERTED=1' -Encoding ASCII

try {
  if ($Seconds -gt 0) {
    Start-Sleep -Seconds $Seconds
  }
  elseif ($WatchPid -gt 0) {
    while ($true) {
      Start-Sleep -Seconds 20
      if (-not (Get-Process -Id $WatchPid -ErrorAction SilentlyContinue)) { break }
    }
  }
}
finally {
  [AntiSleep.Power]::SetThreadExecutionState($ES_CONTINUOUS) | Out-Null
  Remove-Item -LiteralPath $AssertFile -Force -ErrorAction SilentlyContinue
}
'@

Write-Payload 'SleepProbe.ps1' @'
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
'@

Write-Payload 'probe-loop.ps1' @'
# Battement de coeur : un horodatage epoch toutes les -Interval secondes.
# Un trou dans le journal signifie que ce processus a ete gele ou que la machine
# s est suspendue. Lance detache par SleepProbe.ps1.
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
'@

Write-Payload 'awake.ps1' @'
#Requires -Version 5.1
# Menu interactif pour empecher Windows de se mettre en veille.
# Toute la logique vit dans AntiSleep.ps1 ; ce script n est qu une facade.
#
#   awake              menu interactif
#   awake 2h           demarre directement (2h, 90m, 1h30, 45 = minutes)
#   awake pid 12345    reste eveille tant que ce processus tourne
#   awake status       etat courant
#   awake stop         arrete la protection
#   awake probe start|report|stop
[CmdletBinding()]
param(
  [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
  [string[]]$Arguments = @()
)

$ErrorActionPreference = 'Stop'

# PowerShell 5.1 ecrit par defaut dans la page de code OEM : sans cette ligne,
# les caracteres de cadre et les puces du menu sortent en « ? ».
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# Le moteur est cherche dans l ordre : variable d environnement, installation
# standard (Install-Awake.ps1), puis a cote de ce script.
$candidates = @(
  $env:AWAKE_HOME
  (Join-Path $env:LOCALAPPDATA 'Programs\awake')
  $PSScriptRoot
  (Join-Path $PSScriptRoot 'parts')
)

$AwakeHome = $null
foreach ($candidate in $candidates) {
  if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
  if (Test-Path -LiteralPath (Join-Path $candidate 'AntiSleep.ps1')) {
    $AwakeHome = $candidate
    break
  }
}

if (-not $AwakeHome) {
  [Console]::Error.WriteLine('Moteur anti-veille introuvable.')
  [Console]::Error.WriteLine('Lancez Install-Awake.ps1, ou definissez AWAKE_HOME.')
  exit 1
}

$Engine = Join-Path $AwakeHome 'AntiSleep.ps1'
$Probe  = Join-Path $AwakeHome 'SleepProbe.ps1'

# Couleurs seulement la ou le terminal les comprend : sinon le menu se remplit
# de sequences d echappement illisibles dans la console heritee.
function Test-AnsiSupport {
  if ($env:WT_SESSION) { return $true }
  if ($PSVersionTable.PSVersion.Major -ge 6) { return $true }
  try { return [bool]$Host.UI.SupportsVirtualTerminal } catch { return $false }
}

$e = [char]27
if (Test-AnsiSupport) {
  $BOLD = "$e[1m"; $DIM = "$e[2m"; $GREEN = "$e[32m"; $YELLOW = "$e[33m"
  $RED = "$e[31m"; $CYAN = "$e[36m"; $RESET = "$e[0m"
} else {
  $BOLD = ''; $DIM = ''; $GREEN = ''; $YELLOW = ''
  $RED = ''; $CYAN = ''; $RESET = ''
}

function Invoke-Engine {
  param([string[]]$EngineArgs)
  $output = & $Engine @EngineArgs 2>&1
  return @($output | ForEach-Object { $_.ToString() })
}

function Get-EngineField {
  param([string[]]$Lines, [string]$Key)
  $pattern = '^' + [regex]::Escape($Key) + '=(.*)$'
  foreach ($line in $Lines) {
    if ($line -match $pattern) { return $Matches[1] }
  }
  return $null
}

# Traduit « 2h », « 90m », « 1h30 », « 45 », « 3600s » en secondes.
# 45 seul = 45 minutes, comme dans la version WSL.
function ConvertTo-Seconds {
  param([string]$Text)

  if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
  $rest = ($Text.ToLower() -replace '\s', '')
  if ($rest.Length -eq 0) { return $null }

  if ($rest -match '^(\d+)h(\d+)$') {
    return ([long]$Matches[1] * 3600 + [long]$Matches[2] * 60)
  }
  if ($rest -match '^\d+$') {
    return ([long]$rest * 60)
  }

  $seconds = [long]0
  $matched = $false
  while ($rest.Length -gt 0) {
    if ($rest -match '^(\d+)([hms])') {
      $value = [long]$Matches[1]
      switch ($Matches[2]) {
        'h' { $seconds += $value * 3600 }
        'm' { $seconds += $value * 60 }
        's' { $seconds += $value }
      }
      $rest = $rest.Substring($Matches[0].Length)
      $matched = $true
    } else {
      return $null
    }
  }

  if (-not $matched) { return $null }
  return $seconds
}

function Format-Duration {
  param([long]$Total)
  # [math]::Floor rend un double, et « {0:d2} » ne s applique qu aux entiers :
  # sans ce transtypage, la mise en forme leve « specificateur non valide ».
  $hours   = [int][math]::Floor($Total / 3600)
  $minutes = [int][math]::Floor(($Total % 3600) / 60)
  if ($hours -gt 0 -and $minutes -gt 0) { return ('{0}h{1:d2}' -f $hours, $minutes) }
  if ($hours -gt 0) { return "${hours}h" }
  return "$minutes min"
}

function Show-Status {
  $output = Invoke-Engine @('status')
  $status = Get-EngineField $output 'STATUS'

  switch ($status) {
    'running' {
      if ((Get-EngineField $output 'MODE') -eq 'pid') {
        Write-Host ("  {0}● ACTIF{1}   tant que le PID {2}{3}{4} tourne" -f
          $GREEN, $RESET, $BOLD, (Get-EngineField $output 'UNTIL_PID'), $RESET)
      } else {
        $expiresEpoch = Get-EngineField $output 'EXPIRES_EPOCH'
        $remaining = 0
        if ($expiresEpoch -match '^\d+$') {
          $remaining = [long]$expiresEpoch - [DateTimeOffset]::Now.ToUnixTimeSeconds()
          if ($remaining -lt 0) { $remaining = 0 }
        }
        Write-Host ("  {0}● ACTIF{1}   encore {2}{3}{4}, jusqu'a {5}" -f
          $GREEN, $RESET, $BOLD, (Format-Duration $remaining), $RESET,
          (Get-EngineField $output 'EXPIRES'))
      }
    }
    'expired' {
      Write-Host ("  {0}○ EXPIRE{1}  la protection est terminee" -f $YELLOW, $RESET)
    }
    'stopped' {
      Write-Host ("  {0}○ INACTIF{1} la machine peut se mettre en veille" -f $DIM, $RESET)
    }
    default {
      Write-Host ("  {0}● PROBLEME{1}" -f $RED, $RESET)
      $output | ForEach-Object { Write-Host $_ }
    }
  }
}

function Start-For {
  param([long]$Seconds)

  Invoke-Engine @('stop') | Out-Null
  Write-Host ''
  Write-Host ("  Demarrage pour {0}..." -f (Format-Duration $Seconds))

  $output = Invoke-Engine @('start', "$Seconds")
  if ((Get-EngineField $output 'STATUS') -eq 'running') {
    Write-Host ("  {0}✓ Protection active{1} jusqu'a {2}" -f
      $GREEN, $RESET, (Get-EngineField $output 'EXPIRES'))
  } else {
    Write-Host ("  {0}✗ Echec :{1}" -f $RED, $RESET)
    $output | ForEach-Object { Write-Host $_ }
  }
}

function Start-UntilPid {
  param([int]$TargetPid)

  if (-not (Get-Process -Id $TargetPid -ErrorAction SilentlyContinue)) {
    Write-Host ("  {0}✗ Le PID {1} ne tourne pas.{2}" -f $RED, $TargetPid, $RESET)
    return
  }

  Invoke-Engine @('stop') | Out-Null
  $output = Invoke-Engine @('start-pid', "$TargetPid")
  if ((Get-EngineField $output 'STATUS') -eq 'running') {
    Write-Host ("  {0}✓ Protection active{1} tant que le PID {2} tourne" -f $GREEN, $RESET, $TargetPid)
  } else {
    Write-Host ("  {0}✗ Echec :{1}" -f $RED, $RESET)
    $output | ForEach-Object { Write-Host $_ }
  }
}

function Read-CustomDuration {
  $answer  = Read-Host '  Duree (ex: 90m, 2h, 1h30, 45)'
  $seconds = ConvertTo-Seconds $answer

  if ($null -eq $seconds) {
    Write-Host ("  {0}✗ Format non compris.{1}" -f $RED, $RESET)
  } elseif ($seconds -lt 60) {
    Write-Host ("  {0}✗ Minimum une minute.{1}" -f $RED, $RESET)
  } else {
    Start-For $seconds
  }
}

function Read-TargetPid {
  Write-Host ("  {0}Processus les plus anciens :{1}" -f $DIM, $RESET)
  Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.StartTime } |
    Sort-Object StartTime |
    Select-Object -First 8 |
    ForEach-Object {
      Write-Host ("    {0,6}  {1:HH\:mm}  {2}" -f $_.Id, $_.StartTime, $_.ProcessName)
    }

  $answer = Read-Host '  PID a surveiller'
  if ($answer -match '^\d+$') {
    Start-UntilPid ([int]$answer)
  } else {
    Write-Host ("  {0}✗ PID invalide.{1}" -f $RED, $RESET)
  }
}

function Show-Menu {
  while ($true) {
    Write-Host ''
    Write-Host ("{0}┌─ Anti-veille Windows ─────────────────{1}" -f $BOLD, $RESET)
    Show-Status
    Write-Host ("{0}└───────────────────────────────────────{1}" -f $BOLD, $RESET)
    Write-Host ''
    Write-Host ("  {0}1{1}) 30 minutes      {0}4{1}) 4 heures"        -f $CYAN, $RESET)
    Write-Host ("  {0}2{1}) 1 heure         {0}5{1}) 8 heures (nuit)" -f $CYAN, $RESET)
    Write-Host ("  {0}3{1}) 2 heures        {0}6{1}) duree libre"     -f $CYAN, $RESET)
    Write-Host ''
    Write-Host ("  {0}p{1}) jusqu'a la fin d'un processus" -f $CYAN, $RESET)
    Write-Host ("  {0}s{1}) arreter la protection"         -f $CYAN, $RESET)
    Write-Host ("  {0}q{1}) quitter {2}(la protection continue en arriere-plan){3}" -f
      $CYAN, $RESET, $DIM, $RESET)
    Write-Host ''

    $choice = Read-Host '  Choix'
    switch ($choice) {
      '1' { Start-For 1800 }
      '2' { Start-For 3600 }
      '3' { Start-For 7200 }
      '4' { Start-For 14400 }
      '5' { Start-For 28800 }
      '6' { Read-CustomDuration }
      { $_ -in @('p', 'P') } { Read-TargetPid }
      { $_ -in @('s', 'S') } {
        Write-Host ''
        Invoke-Engine @('stop') | ForEach-Object { Write-Host "  $_" }
      }
      { $_ -in @('q', 'Q', '') } { Write-Host ''; return }
      default { Write-Host ("  {0}✗ Choix inconnu.{1}" -f $RED, $RESET) }
    }
  }
}

function Show-Help {
  @(
    'Usage:'
    '  awake              menu interactif'
    '  awake 2h           demarre directement (2h, 90m, 1h30, 45 = minutes)'
    '  awake pid 12345    reste eveille tant que ce processus tourne'
    '  awake status       etat courant'
    '  awake stop         arrete la protection'
    '  awake probe start|report|stop    mesure les gels de processus'
  ) | ForEach-Object { Write-Host $_ }
}

$first = ''
if ($Arguments.Count -gt 0) { $first = $Arguments[0] }

switch ($first) {
  '' { Show-Menu }

  'stop' { Invoke-Engine @('stop') | ForEach-Object { Write-Host $_ } }

  'status' { Show-Status }

  'probe' {
    if (-not (Test-Path -LiteralPath $Probe)) {
      [Console]::Error.WriteLine('SleepProbe.ps1 introuvable.')
      exit 1
    }
    $probeArgs = @('report')
    if ($Arguments.Count -gt 1) { $probeArgs = $Arguments[1..($Arguments.Count - 1)] }
    & $Probe @probeArgs
  }

  { $_ -in @('-h', '--help', 'help') } { Show-Help }

  'pid' {
    if ($Arguments.Count -gt 1 -and $Arguments[1] -match '^\d+$') {
      Start-UntilPid ([int]$Arguments[1])
    } else {
      [Console]::Error.WriteLine('PID invalide')
      exit 2
    }
  }

  default {
    $seconds = ConvertTo-Seconds $first
    if ($null -eq $seconds) {
      [Console]::Error.WriteLine("Duree non comprise : $first (essayez 2h, 90m, 1h30)")
      exit 2
    }
    if ($seconds -lt 60) {
      [Console]::Error.WriteLine('Minimum une minute')
      exit 2
    }
    Start-For $seconds
  }
}
'@

Write-Ok "moteur installe dans $LibDir"

# Un awake.ps1 pose a cote de l installeur a la priorite : il permet de
# distribuer une version corrigee sans regenerer l installeur.
$besideFacade = Join-Path $SrcDir 'awake.ps1'
if ((Test-Path -LiteralPath $besideFacade) -and
    ((Resolve-Path $SrcDir).Path -ne (Resolve-Path $LibDir).Path)) {
  Copy-Item -LiteralPath $besideFacade -Destination (Join-Path $LibDir 'awake.ps1') -Force
  Write-Ok 'facade awake.ps1 installee (depuis le fichier fourni a cote)'
} else {
  Write-Ok 'facade awake.ps1 installee (copie embarquee)'
}

# Le shim .cmd rend « awake » utilisable tel quel depuis cmd, PowerShell 5.1 et
# PowerShell 7, sans toucher aux profils ni a la politique d execution.
$shim = @(
  '@echo off'
  'powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\awake.ps1" %*'
  'exit /b %errorlevel%'
)
Set-Content -LiteralPath (Join-Path $BinDir 'awake.cmd') -Value $shim -Encoding ASCII
Write-Ok "commande awake installee dans $BinDir"

# ---------------------------------------------------------------- 3. PATH

Write-Step '3. Acces depuis le terminal'

$userPath = Get-UserPath
if (($userPath -split ';') -contains $BinDir) {
  Write-Ok "$BinDir est deja dans le PATH utilisateur"
} else {
  $updated = if ($userPath) { "$userPath;$BinDir" } else { $BinDir }
  [Environment]::SetEnvironmentVariable('Path', $updated, 'User')
  $env:Path = "$env:Path;$BinDir"
  Write-Ok 'PATH utilisateur mis a jour'
  Write-Warn 'ouvrez un nouveau terminal pour que « awake » soit reconnu'
}

# ---------------------------------------------------------------- 4. test reel

Write-Step '4. Test reel'

$engine  = Join-Path $LibDir 'AntiSleep.ps1'
$current = @(& $engine status 2>&1 | ForEach-Object { $_.ToString() })

if ($current -match 'STATUS=running') {
  Write-Warn 'une protection est deja active : test ignore pour ne pas l interrompre'
} else {
  & $engine stop 2>&1 | Out-Null
  $started = @(& $engine start 60 2>&1 | ForEach-Object { $_.ToString() })
  $checked = @(& $engine verify 2>&1 | ForEach-Object { $_.ToString() })
  & $engine stop 2>&1 | Out-Null

  if (($started -match 'STATUS=running') -and ($checked -match 'ASSERTIONS=active')) {
    Write-Ok 'test concluant : Windows a bien accepte de rester eveille'
  } else {
    Write-Fail ("le test a echoue : l assertion d alimentation n a pas pu etre posee.`n     Detail : " + ($started -join ' | '))
  }
}

# ---------------------------------------------------------------- 5. resume

Write-Step "C'est pret"

@(
  ''
  '  awake              menu interactif (choix de la duree)'
  '  awake 2h           demarrage direct — 2h, 90m, 1h30, ou 45 (= minutes)'
  '  awake pid 12345    reste eveille tant que ce processus tourne'
  '  awake status       etat courant'
  '  awake stop         arret immediat'
  ''
  '  La protection survit a la fermeture du terminal et au verrouillage de'
  '  la session : elle tourne dans un processus PowerShell detache.'
  ''
) | ForEach-Object { Write-Host $_ }

if ($modernStandby) {
  Write-Host ("{0}  Note — cette machine est en Modern Standby.{1}" -f $YELLOW, $RESET)
  Write-Host ("{0}  Windows peut y geler les applications quand l ecran s eteint.{1}" -f $DIM, $RESET)
  Write-Host ("{0}  Si des traitements longs s arretent malgre awake, mesurez-le avec :{1}" -f $DIM, $RESET)
  Write-Host ("{0}     awake probe start   puis   awake probe report{1}" -f $DIM, $RESET)
  Write-Host ''
}

Write-Host ("  Desinstallation : {0}powershell -ExecutionPolicy Bypass -File Install-Awake.ps1 -Uninstall{1}" -f $DIM, $RESET)
Write-Host ''
