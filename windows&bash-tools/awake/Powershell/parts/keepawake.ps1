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
