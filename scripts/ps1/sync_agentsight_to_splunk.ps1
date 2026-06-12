# Copy repo AgentSight app into $SPLUNK_HOME/etc/apps/agentsight (preserves bin/lib).
# Usage: .\scripts\ps1\sync_agentsight_to_splunk.ps1

param([string]$SplunkHome = "")

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_splunk_rest.ps1"
if (-not $SplunkHome) { $SplunkHome = Resolve-SplunkHome }

$src = Join-Path $PSScriptRoot "..\..\apps\agentsight"
$dest = Join-Path $SplunkHome "etc\apps\agentsight"
$libBackup = $null

if (Test-Path (Join-Path $dest "bin\lib")) {
    $libBackup = Join-Path $env:TEMP ("agentsight-lib-" + [guid]::NewGuid().ToString())
    Copy-Item -Recurse (Join-Path $dest "bin\lib") $libBackup
}

Write-Host "Syncing $src -> $dest"
robocopy $src $dest /MIR /XD bin\lib local /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy failed with exit $LASTEXITCODE" }

if ($libBackup) {
    Copy-Item -Recurse $libBackup (Join-Path $dest "bin\lib")
    Remove-Item -Recurse -Force $libBackup
}

Write-Host "Done. Restart Splunk if commands were renamed: & '$SplunkHome\bin\splunk.exe' restart"
