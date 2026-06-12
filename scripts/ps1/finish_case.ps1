# Approve + explain an existing case.
# Usage:
#   $env:SPLUNK_PASSWORD = 'admin-password'
#   .\scripts\ps1\finish_case.ps1 -CaseId case_abc123

param(
    [Parameter(Mandatory)][string]$CaseId,
    [string]$ActionId = "",
    [string]$SplunkHome = "",
    [string]$SplunkUrl = "https://127.0.0.1:8089"
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_splunk_rest.ps1"
if (-not $SplunkHome) { $SplunkHome = Resolve-SplunkHome }
if (-not $env:SPLUNK_PASSWORD) { throw "Set SPLUNK_PASSWORD" }

if (-not $ActionId) { $ActionId = "action_$CaseId" }

function Show-SplunkRows {
    param($Rows)
    if ($Rows -and $Rows.Count -gt 0) {
        $Rows | ForEach-Object { $_ | Format-List }
        return $true
    }
    return $false
}

function Test-AgentsightOutput {
    param([string]$Text)
    if (-not $Text) { return $false }
    if ($Text -match '(?i)FATAL:|Error in ''agentsight') { return $false }
    if ($Text -match '(?i)"status"\s*:\s*"ok"|status=ok|explanation') { return $true }
    if ($Text -match '(?i)Case not found|No case found') { return $true }
    return ($Text.Trim().Length -gt 40)
}

Write-Host "Case:    $CaseId"
Write-Host "Action:  $ActionId"
Write-Host ""

$key = Get-SplunkSessionKey -SplunkUrl $SplunkUrl

Write-Host "=== Verify case in index ==="
$verifySpl = "search index=agentsight sourcetype=`"agentsight:case`" case_id=$CaseId | head 3"
$verifyRows = Invoke-SplunkOneshotSearch -Search $verifySpl -SessionKey $key -SplunkUrl $SplunkUrl -Earliest "-7d"
if (-not (Show-SplunkRows $verifyRows)) {
    $verifyOut = Invoke-SplunkCliSearch -Search $verifySpl -SplunkHome $SplunkHome -Password $env:SPLUNK_PASSWORD
    Write-Host $verifyOut
    if (-not (Test-AgentsightOutput $verifyOut)) {
        throw "Case $CaseId not found in index=agentsight"
    }
}

Write-Host "=== agentsightapprove ==="
$approveSpl = "agentsightapprove case_id=$CaseId action_id=$ActionId decision=approved actor=admin"
$approveRows = Invoke-SplunkOneshotSearch -Search $approveSpl -SessionKey $key -SplunkUrl $SplunkUrl -Earliest "-1m"
$approveOk = Show-SplunkRows $approveRows
if (-not $approveOk) {
    Write-Host "REST returned no rows; trying Splunk CLI..." -ForegroundColor Yellow
    $approveOut = Invoke-SplunkCliSearch -Search $approveSpl -SplunkHome $SplunkHome -Password $env:SPLUNK_PASSWORD -TimeoutSec 120
    Write-Host $approveOut
    $approveOk = Test-AgentsightOutput $approveOut
}
if (-not $approveOk) {
    throw "agentsightapprove produced no output. Run in Splunk Search: | $approveSpl"
}
Write-Host "PASS: agentsightapprove" -ForegroundColor Green

Write-Host "=== agentsightexplain ==="
$explainSpl = "agentsightexplain case_id=$CaseId"
$explainRows = Invoke-SplunkOneshotSearch -Search $explainSpl -SessionKey $key -SplunkUrl $SplunkUrl -Earliest "-1m"
$explainOk = Show-SplunkRows $explainRows
if (-not $explainOk) {
    Write-Host "REST returned no rows; trying Splunk CLI..." -ForegroundColor Yellow
    $explainOut = Invoke-SplunkCliSearch -Search $explainSpl -SplunkHome $SplunkHome -Password $env:SPLUNK_PASSWORD -TimeoutSec 180
    Write-Host $explainOut
    $explainOk = Test-AgentsightOutput $explainOut
}
if (-not $explainOk) {
    throw "agentsightexplain produced no output. Run in Splunk Search: | $explainSpl"
}
Write-Host "PASS: agentsightexplain" -ForegroundColor Green
Write-Host ""
Write-Host "Done: $CaseId approved and explained" -ForegroundColor Green
