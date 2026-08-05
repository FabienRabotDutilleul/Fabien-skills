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
