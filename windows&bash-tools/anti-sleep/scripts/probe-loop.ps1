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
