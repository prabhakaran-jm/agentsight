# Trigger agentsight_investigate with a detection row (Windows).
# Usage:
#   $env:SPLUNK_PASSWORD = 'admin-password'
#   .\scripts\ps1\run_investigate.ps1 -Actor mcp-demo-agent -McpCalls 6

param(
    [string]$SplunkHome = "",
    [string]$SplunkUrl = "https://127.0.0.1:8089",
    [string]$TriggerRule = "mcp_tool_loop",
    [string]$Severity = "high",
    [string]$Actor = "mcp-demo-agent",
    [string]$SessionId = "demo_sess_001",
    [string]$Description = "",
    [int]$McpCalls = 6,
    [switch]$Scripted
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_splunk_rest.ps1"
if (-not $SplunkHome) { $SplunkHome = Resolve-SplunkHome }

if (-not $Description) {
    $Description = "MCP agent $Actor made $McpCalls splunk_run_query calls in 10m"
}

$splunkExe = Join-Path $SplunkHome "bin\splunk.exe"
$investigate = Join-Path $SplunkHome "etc\apps\agentsight\bin\agentsight_investigate.py"
if (-not (Test-Path $investigate)) {
    $investigate = Join-Path $PSScriptRoot "..\..\apps\agentsight\bin\agentsight_investigate.py"
}
if (-not (Test-Path $investigate)) {
    throw "agentsight_investigate.py not found. Deploy app to $SplunkHome\etc\apps\agentsight first."
}

$key = Get-SplunkSessionKey -SplunkUrl $SplunkUrl
$tmpdir = New-TemporaryFile | ForEach-Object { Remove-Item $_; New-Item -ItemType Directory -Path $_.FullName }
$resultsGz = Join-Path $tmpdir.FullName "results.csv.gz"
$payloadJson = Join-Path $tmpdir.FullName "payload.json"

$row = @{
    trigger_rule = $TriggerRule
    severity     = $Severity
    actor        = $Actor
    username     = $Actor
    mcp_user     = $Actor
    session_id   = $SessionId
    description  = $Description
}
$headers = @("trigger_rule", "severity", "actor", "username", "mcp_user", "session_id", "description")
Write-GzipCsv -Path $resultsGz -Headers $headers -Rows @($row)

$payload = @{
    search_name  = "AgentSight - MCP Tool Loop"
    results_file = $resultsGz
    server_uri   = $SplunkUrl
    session_key  = $key
} | ConvertTo-Json -Compress
Set-Content -Path $payloadJson -Value $payload -Encoding UTF8

if ($Scripted -or (Test-Path (Join-Path $SplunkHome "etc\apps\agentsight\local\demo_mode"))) {
    $env:AGENTSIGHT_SCRIPTED_INVESTIGATION = "1"
    Write-Host 'Scripted investigate (demo mode) - skips Ollama tool agent, keeps | ai classify'
} else {
    Write-Host "Running agentsight_investigate (may take 1-4 min if Ollama agent runs)..."
}
$payloadRaw = Get-Content -Path $payloadJson -Raw -Encoding UTF8
$payloadRaw | & $splunkExe cmd python3 $investigate --execute
if ($LASTEXITCODE -ne 0) {
    Write-Host "Investigate exited $LASTEXITCODE. Check log:" -ForegroundColor Yellow
    Write-Host "  $SplunkHome\var\log\splunk\agentsight.log"
    exit $LASTEXITCODE
}

Write-Host "Investigate complete. Checking for case..."
$caseSearch = 'search index=agentsight sourcetype="agentsight:case" | sort -_time | head 1'
$cases = $null
foreach ($attempt in 1..12) {
    Start-Sleep -Seconds 5
    $cases = Invoke-SplunkOneshotSearch -Search $caseSearch -SessionKey $key -SplunkUrl $SplunkUrl -Earliest "-7d"
    if ($cases -and $cases.Count -gt 0) { break }
    Write-Host "  waiting for case in index=agentsight (attempt $attempt/12)..."
}
if ($cases -and $cases.Count -gt 0) {
    $rawRow = $cases[0]
    if ($rawRow._raw -and $rawRow._raw.StartsWith('{')) {
        $c = $rawRow._raw | ConvertFrom-Json
    } else {
        $c = $rawRow
    }
    $foundId = Get-SplunkField $c.case_id
    Write-Host "PASS: Case created case_id=$foundId status=$(Get-SplunkField $c.status)" -ForegroundColor Green
    Write-Host "  pending_actions=$(Get-SplunkField $c.pending_actions)"
    $foundId
} else {
    $logCaseId = Get-LatestAgentsightCaseId -SplunkHome $SplunkHome
    if ($logCaseId) {
        Write-Host "PASS: Case found in agentsight.log (index search empty): $logCaseId" -ForegroundColor Yellow
        Write-Host "  Tip: sync app and restart Splunk if index=agentsight is empty"
        $logCaseId
    } else {
        Write-Host "WARN: No case in index=agentsight or agentsight.log" -ForegroundColor Yellow
        exit 1
    }
}

Remove-Item -Recurse -Force $tmpdir.FullName -ErrorAction SilentlyContinue
