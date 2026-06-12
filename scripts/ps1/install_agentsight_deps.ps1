# Install Python deps into AgentSight bin/lib using Splunk's Python (NOT system python).
# Usage (elevated PowerShell if D:\splunk is protected):
#   .\scripts\ps1\install_agentsight_deps.ps1
#   .\scripts\ps1\install_agentsight_deps.ps1 -SplunkHome D:\splunk

param(
    [string]$SplunkHome = ""
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_splunk_rest.ps1"
if (-not $SplunkHome) { $SplunkHome = Resolve-SplunkHome }

$repoApp = Join-Path $PSScriptRoot "..\..\apps\agentsight"
$deployedApp = Join-Path $SplunkHome "etc\apps\agentsight"
$reqFile = Join-Path $repoApp "requirements.txt"
$splunkExe = Join-Path $SplunkHome "bin\splunk.exe"

if (-not (Test-Path $splunkExe)) {
    throw "Splunk not found at $SplunkHome"
}
if (-not (Test-Path $reqFile)) {
    throw "requirements.txt not found at $reqFile"
}

# Install into deployed app (what splunkd runs)
$libDirs = @(
    (Join-Path $deployedApp "bin\lib"),
    (Join-Path $repoApp "bin\lib")
) | Select-Object -Unique

Write-Host "Splunk Python:"
& $splunkExe cmd python3 -c "import sys; print(sys.version)"

foreach ($libDir in $libDirs) {
    if (-not (Test-Path (Split-Path $libDir -Parent))) {
        Write-Host "SKIP: $($libDir) (app path missing)"
        continue
    }
    Write-Host ""
    Write-Host "Installing deps into $libDir ..."
    if (Test-Path $libDir) {
        Remove-Item -Recurse -Force $libDir
    }
    New-Item -ItemType Directory -Path $libDir -Force | Out-Null

    & $splunkExe cmd python3 -m pip install `
        --no-cache-dir `
        -r $reqFile `
        -t $libDir `
        --upgrade

    Write-Host "Verify imports in $libDir ..."
    & $splunkExe cmd python3 -c @"
import sys
sys.path.insert(0, r'$libDir')
import splunklib
import pydantic
print('OK: splunklib', splunklib.__file__)
print('OK: pydantic', pydantic.__version__)
"@
}

Write-Host ""
Write-Host "Done. Restart Splunk:"
Write-Host "  & '$splunkExe' restart"
