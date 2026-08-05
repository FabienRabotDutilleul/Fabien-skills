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

@@PAYLOADS@@

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
