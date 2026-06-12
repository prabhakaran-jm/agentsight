#!/usr/bin/env bash
# MCP handshake + one splunk_run_query call.
set -euo pipefail

: "${SPLUNK_MCP_URL:=https://localhost:8089/services/mcp}"
: "${SPLUNK_MCP_TOKEN:?Set SPLUNK_MCP_TOKEN to your encrypted MCP app token}"

echo "=== Step 1: initialize ==="
curl -sk -X POST "${SPLUNK_MCP_URL}" \
  -H "Authorization: Bearer ${SPLUNK_MCP_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"agentsight-smoke","version":"1.0"}}}'
echo

echo "=== Step 2: notifications/initialized ==="
curl -sk -X POST "${SPLUNK_MCP_URL}" \
  -H "Authorization: Bearer ${SPLUNK_MCP_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"notifications/initialized"}'
echo

echo "=== Step 3: tools/call splunk_run_query ==="
curl -sk -X POST "${SPLUNK_MCP_URL}" \
  -H "Authorization: Bearer ${SPLUNK_MCP_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
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
  }'
echo
echo "=== Done. Verify: index=_internal sourcetype=mcp_server tool_name=splunk_run_query | head 5 ==="
