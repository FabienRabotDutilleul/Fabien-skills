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
