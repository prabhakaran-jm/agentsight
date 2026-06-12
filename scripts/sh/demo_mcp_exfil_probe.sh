#!/usr/bin/env bash
# Trigger Rule 4 (MCP Data Exfiltration): one MCP splunk_run_query whose SPL contains outputlookup.
# The query may fail at runtime; _audit still records the granted search with the exfil command.

set -euo pipefail

: "${SPLUNK_MCP_URL:=https://localhost:8089/services/mcp}"
: "${SPLUNK_MCP_TOKEN:?Set SPLUNK_MCP_TOKEN to your encrypted MCP token}"

echo "MCP exfil probe: splunk_run_query with outputlookup in SPL"
echo "Endpoint: ${SPLUNK_MCP_URL}"
echo "Tip: use mcp-demo-agent token for critical-rule demos (never quarantine admin)."

curl -sk -X POST "${SPLUNK_MCP_URL}" \
  -H "Authorization: Bearer ${SPLUNK_MCP_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"agentsight-exfil-probe","version":"0.1"}}}' \
  >/dev/null

curl -sk -X POST "${SPLUNK_MCP_URL}" \
  -H "Authorization: Bearer ${SPLUNK_MCP_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
  >/dev/null

curl -sk -X POST "${SPLUNK_MCP_URL}" \
  -H "Authorization: Bearer ${SPLUNK_MCP_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$(cat <<'EOF'
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/call",
  "params": {
    "name": "splunk_run_query",
    "arguments": {
      "query": "| makeresults count=1 | eval x=1 | outputlookup agentsight_exfil_probe_test",
      "earliest_time": "-15m",
      "latest_time": "now",
      "row_limit": 10
    }
  }
}
EOF
)"

echo ""
echo "Done. Verify _audit:"
echo '  index=_audit sourcetype=audittrail action=search search=*outputlookup* earliest=-15m'
echo "Then run saved search: AgentSight - MCP Data Exfiltration"
