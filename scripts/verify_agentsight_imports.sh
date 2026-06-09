#!/usr/bin/env bash
# Verify alert-action Python imports using Splunk's interpreter.
set -euo pipefail

: "${SPLUNK_HOME:=/opt/splunk}"
BIN="$(cd "$(dirname "$0")/../apps/agentsight/bin" && pwd)"
LIB="${BIN}/lib"

splunk_cmd() {
  if id splunk &>/dev/null; then
    sudo -u splunk "${SPLUNK_HOME}/bin/splunk" "$@"
  else
    "${SPLUNK_HOME}/bin/splunk" "$@"
  fi
}

echo "=== Splunk Python ==="
splunk_cmd cmd python3 -c "import sys; print(sys.version)"

echo "=== Import test ==="
splunk_cmd cmd python3 -c "
import sys
sys.path.insert(0, '${BIN}')
sys.path.insert(0, '${LIB}')
import splunklib
import pydantic
from tools import run_scripted_investigation, register_tools
print('OK: splunklib, pydantic, tools (no registry at import)')
register_tools()
print('OK: register_tools()')
"

echo "=== agentsight.log (last 20 lines) ==="
sudo tail -20 /opt/splunk/var/log/splunk/agentsight.log 2>/dev/null || echo "(no log file yet)"
