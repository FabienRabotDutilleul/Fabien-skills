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
