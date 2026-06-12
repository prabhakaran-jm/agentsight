# Toggle fast demo mode (scripted investigate + explain; still uses | ai classify).
# Usage:
#   .\scripts\ps1\demo_mode.ps1 -Enable
#   .\scripts\ps1\demo_mode.ps1 -Disable
#   .\scripts\ps1\demo_mode.ps1 -Enable -SyncFirst

param(
    [string]$SplunkHome = "",
    [switch]$Enable,
    [switch]$Disable,
    [switch]$SyncFirst
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_splunk_rest.ps1"
if (-not $SplunkHome) { $SplunkHome = Resolve-SplunkHome }

if (-not $Enable -and -not $Disable) { $Enable = $true }

if ($SyncFirst) {
    & "$PSScriptRoot\sync_agentsight_to_splunk.ps1" -SplunkHome $SplunkHome
}

$flag = Join-Path $SplunkHome "etc\apps\agentsight\local\demo_mode"

if ($Disable) {
    if (Test-Path $flag) {
        Remove-Item $flag -Force
        Write-Host "Demo mode OFF" -ForegroundColor Yellow
    } else {
        Write-Host "Demo mode was not enabled." -ForegroundColor DarkGray
    }
    return
}

$localDir = Split-Path $flag -Parent
New-Item -ItemType Directory -Force -Path $localDir | Out-Null
Set-Content -Path $flag -Value "enabled $(Get-Date -Format o)" -Encoding ASCII
Write-Host "Demo mode ON: $flag" -ForegroundColor Green
Write-Host '  - Investigate skips Ollama tool agent (uses scripted path + | ai classify)'
Write-Host "  - Explain returns instantly from case + investigation steps"
Write-Host "  - No Splunk restart needed"
