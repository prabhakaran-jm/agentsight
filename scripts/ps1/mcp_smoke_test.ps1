# MCP handshake + one splunk_run_query call (Windows).
# Usage:
#   $env:SPLUNK_MCP_TOKEN = 'your-encrypted-mcp-token'
#   .\scripts\ps1\mcp_smoke_test.ps1

param(
    [string]$McpUrl = $(if ($env:SPLUNK_MCP_URL) { $env:SPLUNK_MCP_URL } else { "https://localhost:8089/services/mcp" }),
    [string]$McpToken = $env:SPLUNK_MCP_TOKEN
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_splunk_rest.ps1"

if (-not $McpToken) {
    Write-Error "Set SPLUNK_MCP_TOKEN to your encrypted MCP app token."
}

$headers = @{
    Authorization  = "Bearer $McpToken"
    "Content-Type" = "application/json"
}

function Invoke-Mcp {
    param([string]$Label, [string]$Body)
    Write-Host "=== $Label ==="
    $resp = Invoke-SplunkRestMethod -Uri $McpUrl -Method Post -Headers $headers -Body $Body
    $resp | ConvertTo-Json -Depth 8
    Write-Host ""
}

Invoke-Mcp "initialize" '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"agentsight-smoke","version":"1.0"}}}'
Invoke-Mcp "notifications/initialized" '{"jsonrpc":"2.0","method":"notifications/initialized"}'
Invoke-Mcp "tools/call splunk_run_query" @'
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "tools/call",
  "params": {
    "name": "splunk_run_query",
    "arguments": {
      "query": "| makeresults count=1 | eval agentsight_smoke=\"hello from MCP\" | table agentsight_smoke",
      "earliest_time": "-15m",
      "latest_time": "now",
      "row_limit": 10
    }
  }
}
'@

Write-Host "=== Done ==="
Write-Host 'Verify: index=_internal sourcetype=mcp_server tool_name=splunk_run_query earliest=-15m | table _time username tool_name status'
