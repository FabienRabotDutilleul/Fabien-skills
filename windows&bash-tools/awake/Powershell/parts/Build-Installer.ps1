#Requires -Version 5.1
# Genere ../Install-Awake.ps1 : le gabarit, avec les scripts de parts/ embarques
# a la place du marqueur @@PAYLOADS@@.
#
# Les fichiers PowerShell produits sont ecrits en UTF-8 *avec BOM* et en CRLF :
# sans BOM, PowerShell 5.1 lit un .ps1 UTF-8 avec la page de code ANSI et
# massacre les caracteres de cadre du menu.
#
# Ce fichier-ci est volontairement en ASCII pur : c'est le seul du lot qui doive
# pouvoir tourner avant que le traitement d'encodage ait ete applique, donc le
# seul qui ne puisse pas compter dessus.
#
# Usage :  powershell -ExecutionPolicy Bypass -File .\Build-Installer.ps1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$PartsDir = $PSScriptRoot
$DistDir  = Split-Path -Parent $PartsDir
$Template = Join-Path $PartsDir 'Install-Awake.template.ps1'
$Output   = Join-Path $DistDir  'Install-Awake.ps1'
$Facade   = Join-Path $DistDir  'awake.ps1'

# Les delimiteurs de here-string sont assembles a l'execution : ecrits tels
# quels dans une chaine, PowerShell prendrait le @' pour une vraie ouverture.
$HereOpen  = '@' + "'"
$HereClose = "'" + '@'

# awake.ps1 est a la fois une part embarquee et un fichier livre : il vit a la
# racine de la distribution, pas dans parts/.
$Payloads = @(
  @{ Name = 'AntiSleep.ps1';  Path = (Join-Path $PartsDir 'AntiSleep.ps1')  }
  @{ Name = 'keepawake.ps1';  Path = (Join-Path $PartsDir 'keepawake.ps1')  }
  @{ Name = 'SleepProbe.ps1'; Path = (Join-Path $PartsDir 'SleepProbe.ps1') }
  @{ Name = 'probe-loop.ps1'; Path = (Join-Path $PartsDir 'probe-loop.ps1') }
  @{ Name = 'awake.ps1';      Path = $Facade                                }
)

function Fail {
  param([string]$Message)
  [Console]::Error.WriteLine("ERREUR : $Message")
  exit 1
}

# -Encoding UTF8 en lecture accepte les fichiers avec et sans BOM ; sans lui,
# PowerShell 5.1 relit un fichier UTF-8 sans BOM avec la page de code ANSI.
function Read-Text {
  param([string]$Path)
  return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8)
}

# Set-Content -Encoding UTF8 pose un BOM en 5.1 mais pas en PowerShell 7 :
# l'appel .NET rend le resultat identique quelle que soit la version.
function Write-Utf8Bom {
  param([string]$Path, [string]$Text)
  $crlf = ($Text -replace "`r`n", "`n") -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $crlf, (New-Object System.Text.UTF8Encoding $true))
}

if (-not (Test-Path -LiteralPath $Template)) { Fail "gabarit manquant : $Template" }

# Une ligne commencant par le delimiteur de fermeture refermerait le
# here-string qui la porte et couperait l'installeur en deux. On refuse de
# generer dans ce cas plutot que de produire un fichier casse.
foreach ($payload in $Payloads) {
  if (-not (Test-Path -LiteralPath $payload.Path)) {
    Fail ('payload manquant : ' + $payload.Path)
  }
  $lines = @(Get-Content -LiteralPath $payload.Path -Encoding UTF8)
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i].StartsWith($HereClose)) {
      Fail ('{0} ligne {1} commence par le delimiteur de fermeture : non embarquable.' -f $payload.Name, ($i + 1))
    }
  }
}

$blocks = foreach ($payload in $Payloads) {
  $content = (Read-Text $payload.Path) -replace '[\r\n]+$', ''
  "Write-Payload '" + $payload.Name + "' " + $HereOpen + "`n" +
    $content + "`n" + $HereClose + "`n"
}

$text = Read-Text $Template
if (-not $text.Contains('@@PAYLOADS@@')) { Fail 'marqueur @@PAYLOADS@@ absent du gabarit.' }

# String.Replace et non -replace : l'operateur traiterait les signes dollar du
# remplacement comme des references de groupe, et les scripts en sont pleins.
$text = $text.Replace('@@PAYLOADS@@', (($blocks -join "`n") -replace '[\r\n]+$', ''))

Write-Utf8Bom -Path $Output -Text $text

# La facade distribuee subit le meme traitement : elle porte les caracteres de
# cadre du menu.
if (Test-Path -LiteralPath $Facade) {
  Write-Utf8Bom -Path $Facade -Text (Read-Text $Facade)
}

$size = (Get-Item -LiteralPath $Output).Length
Write-Output ('genere : {0} ({1} octets, {2} payloads)' -f $Output, $size, $Payloads.Count)
