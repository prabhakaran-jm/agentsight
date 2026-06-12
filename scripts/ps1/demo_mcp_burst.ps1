# Fire repeated splunk_run_query MCP calls to trigger AgentSight - MCP Tool Loop (>=5 in 10m).
# Usage:
#   $env:SPLUNK_MCP_TOKEN = 'your-token'
#   .\scripts\ps1\demo_mcp_burst.ps1

param(
    [string]$McpUrl = $(if ($env:SPLUNK_MCP_URL) { $env:SPLUNK_MCP_URL } else { "https://localhost:8089/services/mcp" }),
    [string]$McpToken = $env:SPLUNK_MCP_TOKEN,
    [int]$BurstCount = $(if ($env:BURST_COUNT) { [int]$env:BURST_COUNT } else { 6 })
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_splunk_rest.ps1"

if (-not $McpToken) {
    Write-Error "Set SPLUNK_MCP_TOKEN to your encrypted MCP token."
}

$headers = @{
    Authorization  = "Bearer $McpToken"
    "Content-Type" = "application/json"
}

Write-Host "MCP burst: $BurstCount splunk_run_query calls to $McpUrl"

function Invoke-McpSilent {
    param([string]$Body)
    Invoke-SplunkRestMethod -Uri $McpUrl -Method Post -Headers $headers -Body $Body | Out-Null
}

Invoke-McpSilent '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"agentsight-burst","version":"1.0"}}}'
Invoke-McpSilent '{"jsonrpc":"2.0","method":"notifications/initialized"}'

for ($i = 1; $i -le $BurstCount; $i++) {
    Write-Host "  call $i/$BurstCount"
    $body = @"
{
  "jsonrpc": "2.0",
  "id": $i,
  "method": "tools/call",
  "params": {
    "name": "splunk_run_query",
    "arguments": {
      "query": "| makeresults count=1 | eval agentsight_burst=$i | table agentsight_burst",
      "earliest_time": "-15m",
      "latest_time": "now",
      "row_limit": 10
    }
  }
}
"@
    Invoke-McpSilent $body
    Start-Sleep -Seconds 1
}

Write-Host ""
Write-Host "Done. Next: run saved search 'AgentSight - MCP Tool Loop' in Splunk."
Write-Host "Rule 1 is severity=high - quarantine is NOT queued."
