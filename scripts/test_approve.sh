#!/usr/bin/env bash
# Run agentsightapprove via Splunk REST (validates registration + runtime).
set -euo pipefail

: "${SPLUNK_HOME:=/opt/splunk}"
: "${SPLUNK_PASSWORD:?Set SPLUNK_PASSWORD to your Splunk admin password}"
: "${CASE_ID:=case_a3d79928}"
: "${ACTION_ID:=action_case_a3d79928}"

SPL="| agentsightapprove case_id=${CASE_ID} action_id=${ACTION_ID} decision=approved actor=admin"

echo "=== Search: ${SPL} ==="
curl -sk -u "admin:${SPLUNK_PASSWORD}" \
  "https://127.0.0.1:8089/services/search/jobs/export" \
  --data-urlencode "search=${SPL}" \
  -d output_mode=json \
  -d earliest_time=-1m \
  -d latest_time=now \
  | head -80

echo ""
echo "=== If you see 'Unknown search command', reinstall and restart: ==="
echo "  bash scripts/install_agentsight_app.sh"
echo "  bash scripts/verify_commands.sh"
