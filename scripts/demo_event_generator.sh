#!/usr/bin/env bash
# Index synthetic demo events via Splunk's Python (must run as splunk user).
set -euo pipefail

: "${SPLUNK_HOME:=/opt/splunk}"
: "${SPLUNK_PASSWORD:?Set SPLUNK_PASSWORD for admin login}"

SCENARIO="${1:-mcp_tool_loop}"
APP_BIN="$(cd "$(dirname "$0")/../apps/agentsight/bin" && pwd)"
GENERATOR="${APP_BIN}/demo_event_generator.py"

run_as_splunk() {
  if id splunk &>/dev/null; then
    sudo -u splunk env SPLUNK_PASSWORD="${SPLUNK_PASSWORD}" \
      "${SPLUNK_HOME}/bin/splunk" cmd python3 "${GENERATOR}" "${SCENARIO}"
  else
    env SPLUNK_PASSWORD="${SPLUNK_PASSWORD}" \
      "${SPLUNK_HOME}/bin/splunk" cmd python3 "${GENERATOR}" "${SCENARIO}"
  fi
}

run_as_splunk
