#!/usr/bin/env bash
# Fire repeated splunk_run_query MCP calls to trigger AgentSight - MCP Tool Loop (>=5 in 10m).
set -euo pipefail

: "${SPLUNK_MCP_URL:=https://localhost:8089/services/mcp}"
: "${SPLUNK_MCP_TOKEN:?Set SPLUNK_MCP_TOKEN to your encrypted MCP token}"
: "${BURST_COUNT:=6}"

echo "MCP burst: ${BURST_COUNT} splunk_run_query calls to ${SPLUNK_MCP_URL}"

curl -sk -X POST "${SPLUNK_MCP_URL}" \
  -H "Authorization: Bearer ${SPLUNK_MCP_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"agentsight-burst","version":"1.0"}}}' \
  >/dev/null

curl -sk -X POST "${SPLUNK_MCP_URL}" \
  -H "Authorization: Bearer ${SPLUNK_MCP_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
  >/dev/null

for i in $(seq 1 "${BURST_COUNT}"); do
  echo "  call ${i}/${BURST_COUNT}"
  curl -sk -X POST "${SPLUNK_MCP_URL}" \
    -H "Authorization: Bearer ${SPLUNK_MCP_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$(cat <<EOF
{
  "jsonrpc": "2.0",
  "id": ${i},
  "method": "tools/call",
  "params": {
    "name": "splunk_run_query",
    "arguments": {
      "query": "| makeresults count=1 | eval agentsight_burst=${i} | table agentsight_burst",
      "earliest_time": "-15m",
      "latest_time": "now",
      "row_limit": 10
    }
  }
}
EOF
)" >/dev/null
  sleep 1
done

echo "Done. Run saved search: AgentSight - MCP Tool Loop"
