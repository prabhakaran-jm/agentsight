#!/usr/bin/env bash
# Run agentsight_investigate with a test detection payload (Linux).
set -euo pipefail

: "${SPLUNK_HOME:=/opt/splunk}"
: "${SPLUNK_PASSWORD:?Set SPLUNK_PASSWORD}"

APP_BIN="${SPLUNK_HOME}/etc/apps/agentsight/bin"
BIN="$(cd "$(dirname "$0")/../../apps/agentsight/bin" && pwd)"
INVESTIGATE="${APP_BIN}/agentsight_investigate.py"
if [[ ! -x "${INVESTIGATE}" ]]; then
  INVESTIGATE="${BIN}/agentsight_investigate.py"
fi
TMP="$(mktemp -d)"
RESULTS="${TMP}/results.csv.gz"
PAYLOAD="${TMP}/payload.json"
trap 'rm -rf "${TMP}"' EXIT

# mktemp dirs are 700 — splunk user must read results_file when run via sudo -u splunk
chmod a+rX "${TMP}"

# Minimal detection row
printf '%s\n' \
  'trigger_rule,severity,actor,username,mcp_user,session_id,description' \
  'mcp_tool_loop,high,admin,admin,admin,test_sess_001,MCP agent admin made 6 splunk_run_query calls in 10m' \
  | gzip -c > "${RESULTS}"
chmod a+r "${RESULTS}"

# Get session key for local Splunk (admin password — same as Splunk Web login)
LOGIN_RESPONSE="$(
  curl -sk -u "admin:${SPLUNK_PASSWORD}" \
    https://localhost:8089/services/auth/login \
    -d username=admin \
    -d password="${SPLUNK_PASSWORD}"
)"
SESSION_KEY="$(printf '%s' "${LOGIN_RESPONSE}" | sed -n 's/.*<sessionKey>\(.*\)<\/sessionKey>.*/\1/p')"

if [[ -z "${SESSION_KEY}" ]]; then
  echo "Failed to obtain Splunk session key" >&2
  LOGIN_ERR="$(printf '%s' "${LOGIN_RESPONSE}" | sed -n 's/.*<msg[^>]*>\(.*\)<\/msg>.*/\1/p' | head -1)"
  if [[ -n "${LOGIN_ERR}" ]]; then
    echo "Splunk login error: ${LOGIN_ERR}" >&2
  fi
  echo "Hint: export SPLUNK_PASSWORD to your Splunk admin password (Splunk Web login)." >&2
  exit 1
fi

cat > "${PAYLOAD}" <<EOF
{
  "search_name": "AgentSight - MCP Tool Loop",
  "results_file": "${RESULTS}",
  "server_uri": "https://localhost:8089",
  "session_key": "${SESSION_KEY}"
}
EOF

echo "Running agentsight_investigate with test payload..."
if id splunk &>/dev/null; then
  sudo -u splunk "${SPLUNK_HOME}/bin/splunk" cmd python3 \
    "${INVESTIGATE}" --execute < "${PAYLOAD}"
else
  "${SPLUNK_HOME}/bin/splunk" cmd python3 \
    "${INVESTIGATE}" --execute < "${PAYLOAD}"
fi

echo ""
echo "Check case:"
echo "  index=agentsight sourcetype=agentsight:case earliest=-15m"
echo "Check log:"
echo "  sudo tail -30 /opt/splunk/var/log/splunk/agentsight.log"
