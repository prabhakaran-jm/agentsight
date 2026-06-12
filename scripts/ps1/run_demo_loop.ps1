# End-to-end demo: burst -> detect -> investigate -> approve -> explain (Windows).
#
# Usage:
#   $env:SPLUNK_MCP_TOKEN = 'mcp-demo-agent-token'
#   $env:SPLUNK_PASSWORD  = 'admin-password'
#   .\scripts\ps1\run_demo_loop.ps1
#   .\scripts\ps1\run_demo_loop.ps1 -SkipBurst
#   .\scripts\ps1\run_demo_loop.ps1 -SyncFirst -DemoMode -EnsureOllama

param(
    [string]$SplunkHome = "",
    [string]$SplunkUrl = "https://127.0.0.1:8089",
    [string]$ExpectedUser = "mcp-demo-agent",
    [string]$DetectionEarliest = "",
    [switch]$SkipBurst,
    [switch]$SkipInvestigate,
    [switch]$SyncFirst,
    [switch]$DemoMode,
    [switch]$EnsureOllama
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_splunk_rest.ps1"
if (-not $SplunkHome) { $SplunkHome = Resolve-SplunkHome }

function Write-Step([string]$Msg) {
    Write-Host ""
    Write-Host ">>> $Msg" -ForegroundColor Cyan
}

$rule1Search = @'
search index=_internal sourcetype=mcp_server rpc_method=tools/call tool_name=splunk_run_query
| spath
| bin _time span=10m
| stats count as mcp_calls dc(tool_name) as distinct_mcp_tools values(request_id) as request_ids by _time username
| where mcp_calls >= 5 AND distinct_mcp_tools <= 2
| eval trigger_rule="mcp_tool_loop", severity="high", actor=username, mcp_user=username, session_id=mvindex(request_ids, 0), description="MCP agent ".username." made ".mcp_calls." splunk_run_query calls in 10m with only ".distinct_mcp_tools." distinct tools - possible runaway agent"
'@

Write-Host "========================================"
Write-Host " AgentSight demo loop"
Write-Host " SPLUNK_HOME: $SplunkHome"
Write-Host "========================================"

if ($SyncFirst) {
    Write-Step "Sync app to Splunk"
    & "$PSScriptRoot\sync_agentsight_to_splunk.ps1" -SplunkHome $SplunkHome
}

if ($DemoMode) {
    Write-Step "Enable demo mode"
    & "$PSScriptRoot\demo_mode.ps1" -Enable -SplunkHome $SplunkHome
}

if ($EnsureOllama) {
    Write-Step "Ensure Ollama"
    & "$PSScriptRoot\ensure_ollama.ps1"
}

if (-not $SkipBurst) {
    Write-Step "1/6 MCP burst"
    & "$PSScriptRoot\demo_mcp_burst.ps1"
    Write-Host "Waiting 15s for audit indexing..."
    Start-Sleep -Seconds 15
} else {
    Write-Step "1/6 Skipping burst (-SkipBurst)"
}

Write-Step "Verify MCP audit username"
& "$PSScriptRoot\verify_mcp_user.ps1" -ExpectedUser $ExpectedUser -SplunkUrl $SplunkUrl -Earliest "-1h"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$key = Get-SplunkSessionKey -SplunkUrl $SplunkUrl

if (-not $DetectionEarliest) {
    $DetectionEarliest = if ($SkipBurst) { "-24h" } else { "-30m" }
}

Write-Step "2/6 Run detection - MCP Tool Loop"
Write-Host "Detection window: $DetectionEarliest to now"
$detections = Invoke-SplunkOneshotSearch -Search $rule1Search -SessionKey $key -SplunkUrl $SplunkUrl -Earliest $DetectionEarliest
if (-not $detections -or $detections.Count -eq 0) {
    Write-Host "FAIL: Rule 1 returned no hits." -ForegroundColor Red
    Write-Host "  Run without -SkipBurst, or: -DetectionEarliest '-7d'"
    exit 1
}
$hit = $detections[0]
Write-Host "PASS: Detection hit actor=$($hit.actor) mcp_calls=$($hit.mcp_calls)" -ForegroundColor Green

if (-not $SkipInvestigate) {
    Write-Step "3/6 Investigate"
    $sess = if ($hit.session_id) { $hit.session_id } else { "demo_sess" }
    $calls = if ($hit.mcp_calls) { [int]$hit.mcp_calls } else { 6 }
    $invArgs = @{
        SplunkHome  = $SplunkHome
        SplunkUrl   = $SplunkUrl
        Actor       = $hit.actor
        SessionId   = $sess
        McpCalls    = $calls
        Description = $hit.description
    }
    if ($DemoMode -or (Test-Path (Join-Path $SplunkHome "etc\apps\agentsight\local\demo_mode"))) {
        $invArgs.Scripted = $true
    }
    & "$PSScriptRoot\run_investigate.ps1" @invArgs
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    Start-Sleep -Seconds 5
} else {
    Write-Step "3/6 Skipping investigate (-SkipInvestigate)"
}

Write-Step "4/6 Load case + pending action"
$caseSearch = 'search index=agentsight sourcetype="agentsight:case" | sort -_time | head 1'
$cases = Invoke-SplunkOneshotSearch -Search $caseSearch -SessionKey $key -SplunkUrl $SplunkUrl -Earliest "-7d"
$caseId = $null
$case = $null
if ($cases -and $cases.Count -gt 0) {
    $rawRow = $cases[0]
    if ($rawRow._raw -and $rawRow._raw.StartsWith('{')) {
        $case = $rawRow._raw | ConvertFrom-Json
    } else {
        $case = $rawRow
    }
    $caseId = Get-SplunkField $case.case_id
}
if (-not $caseId) {
    $caseId = Get-LatestAgentsightCaseId -SplunkHome $SplunkHome
}
if (-not $caseId) {
    Write-Host "FAIL: No case in index=agentsight or agentsight.log" -ForegroundColor Red
    exit 1
}
if ($case) {
    Write-Host "Case: $caseId status=$(Get-SplunkField $case.status) actor=$(Get-SplunkField $case.actor)"
} else {
    Write-Host "Case: $caseId (from agentsight.log)"
}

$actionId = $null
$details = $case.pending_action_details
if ($details -is [string]) {
    try { $details = $details | ConvertFrom-Json } catch { $details = $null }
}
if ($details -and @($details).Count -gt 0) {
    $actionId = @($details)[0].action_id
}
if (-not $actionId -and $case.pending_actions) {
    $pa = $case.pending_actions
    if ($pa -is [array]) { $actionId = $pa[0] }
    else { $actionId = ($pa -split ';|,|\s+')[0].Trim() }
}
if (-not $actionId) {
    $actionId = "action_$caseId"
    Write-Host "Using default action_id $actionId" -ForegroundColor Yellow
}
Write-Host "Action to approve: $actionId"

Write-Step "5/6 Approve"
$approveSpl = "agentsightapprove case_id=$caseId action_id=$actionId decision=approved actor=admin"
$approveRows = Invoke-SplunkOneshotSearch -Search $approveSpl -SessionKey $key -SplunkUrl $SplunkUrl -Earliest "-1m"
$approveOk = $false
if ($approveRows -and $approveRows.Count -gt 0) {
    $approveRows | ForEach-Object { $_ | Format-List }
    $approveOk = $true
} else {
    Write-Host "REST returned no rows; trying Splunk CLI..." -ForegroundColor Yellow
    $cliOut = Invoke-SplunkCliSearch -Search $approveSpl -SplunkHome $SplunkHome -Password $env:SPLUNK_PASSWORD
    Write-Host $cliOut
    if ($cliOut -notmatch 'FATAL:' -and $cliOut -match '(?i)status|approved|message') { $approveOk = $true }
}
if ($approveOk) {
    Write-Host "PASS: agentsightapprove" -ForegroundColor Green
} else {
    Write-Host "WARN: approve may have failed - use Approve Actions dashboard or finish_case.ps1" -ForegroundColor Yellow
}

Write-Step "6/6 Explain"
$explainSpl = "agentsightexplain case_id=$caseId"
$explainRows = Invoke-SplunkOneshotSearch -Search $explainSpl -SessionKey $key -SplunkUrl $SplunkUrl -Earliest "-1m"
$explainOk = $false
if ($explainRows -and $explainRows.Count -gt 0) {
    $explainRows | ForEach-Object {
        Write-Host "--- explanation ---"
        if ($_.explanation) { Write-Host $_.explanation }
        else { $_ | Format-List }
    }
    $explainOk = $true
} else {
    Write-Host "REST returned no rows; trying Splunk CLI..." -ForegroundColor Yellow
    $cliOut = Invoke-SplunkCliSearch -Search $explainSpl -SplunkHome $SplunkHome -Password $env:SPLUNK_PASSWORD -TimeoutSec 120
    Write-Host $cliOut
    if ($cliOut -and $cliOut.Length -gt 20) { $explainOk = $true }
}
if ($explainOk) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host " DEMO LOOP COMPLETE  case_id=$caseId" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
} else {
    Write-Host "FAIL: agentsightexplain returned no output" -ForegroundColor Red
    Write-Host "  | agentsightexplain case_id=$caseId"
    exit 1
}
