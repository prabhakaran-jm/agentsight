#!/usr/bin/env bash
# Trigger Rule 2 (MCP Index Scope Violation) — severity=critical → quarantine action queued.
# Use mcp-demo-agent MCP token, NOT admin. Never approve quarantine on admin.

set -euo pipefail

: "${SPLUNK_MCP_URL:=https://localhost:8089/services/mcp}"
: "${SPLUNK_MCP_TOKEN:?Set SPLUNK_MCP_TOKEN (use mcp-demo-agent token for safe quarantine demo)}"

echo "MCP scope violation probe: query index=secrets via splunk_run_query"
echo "Endpoint: ${SPLUNK_MCP_URL}"
echo "WARNING: approve quarantine only for non-admin actors (use mcp-demo-agent)."

curl -sk -X POST "${SPLUNK_MCP_URL}" \
  -H "Authorization: Bearer ${SPLUNK_MCP_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"agentsight-scope-probe","version":"0.1"}}}' \
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
      "query": "index=secrets | head 5",
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
echo '  index=_audit sourcetype=audittrail action=search search=*index=secrets* earliest=-15m'
echo "Then run saved search: AgentSight - MCP Index Scope Violation"
