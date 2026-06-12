# Verify MCP audit shows expected username in index=_internal sourcetype=mcp_server.
# Usage:
#   $env:SPLUNK_PASSWORD = 'admin-password'
#   .\scripts\ps1\verify_mcp_user.ps1 -ExpectedUser mcp-demo-agent

param(
    [string]$ExpectedUser = "mcp-demo-agent",
    [string]$SplunkUrl = "https://127.0.0.1:8089",
    [string]$Earliest = "-24h"
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_splunk_rest.ps1"

Write-Host "=== Verify MCP audit username ==="
Write-Host "Expected user: $ExpectedUser"
Write-Host "Time window:  $Earliest to now"
Write-Host ""

$key = Get-SplunkSessionKey -SplunkUrl $SplunkUrl
$search = @"
index=_internal sourcetype=mcp_server rpc_method=tools/call tool_name=splunk_run_query
| spath
| eval username=mvindex(username,0), tool_name=mvindex(tool_name,0), status=mvindex(status,0)
| table _time username tool_name status request_id
| sort -_time
| head 10
"@

$rows = Invoke-SplunkOneshotSearch -Search $search -SessionKey $key -SplunkUrl $SplunkUrl -Earliest $Earliest

if (-not $rows -or $rows.Count -eq 0) {
    Write-Host "FAIL: No mcp_server events in window ($Earliest)." -ForegroundColor Red
    Write-Host "  1. Run .\scripts\ps1\mcp_smoke_test.ps1 with SPLUNK_MCP_TOKEN set"
    Write-Host "  2. Retry with -Earliest '-7d'"
    Write-Host "  3. Confirm Splunk MCP Server app is installed"
    exit 1
}

Write-Host "Recent MCP tool calls:"
$rows | ForEach-Object {
    $t = Get-SplunkField $_._time
    $u = Get-SplunkField $_.username
    $tool = Get-SplunkField $_.tool_name
    $st = Get-SplunkField $_.status
    Write-Host "  $t  user=$u  tool=$tool  status=$st"
}

$match = @($rows | Where-Object { (Get-SplunkField $_.username) -eq $ExpectedUser })
if ($match.Count -gt 0) {
    Write-Host ""
    Write-Host "PASS: Found username=$ExpectedUser in mcp_server audit ($($match.Count) row(s))." -ForegroundColor Green
    exit 0
}

$users = ($rows | ForEach-Object { Get-SplunkField $_.username } | Select-Object -Unique) -join ", "
Write-Host ""
Write-Host "FAIL: No events with username=$ExpectedUser (saw: $users)." -ForegroundColor Red
Write-Host "  - MCP token must be issued for user '$ExpectedUser' in Splunk MCP Server"
Write-Host "  - Role needs mcp_tool_execute + search on required indexes"
exit 1
