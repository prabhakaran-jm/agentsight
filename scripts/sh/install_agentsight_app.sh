#!/usr/bin/env bash
# Copy AgentSight into $SPLUNK_HOME/etc/apps (avoids symlink/home permission issues for custom commands).
set -euo pipefail

: "${SPLUNK_HOME:=/opt/splunk}"
REPO_APP="$(cd "$(dirname "$0")/../../apps/agentsight" && pwd)"
DEST="${SPLUNK_HOME}/etc/apps/agentsight"

echo "Installing AgentSight app (copy) to ${DEST}"
sudo rm -rf "${DEST}"
sudo cp -a "${REPO_APP}" "${DEST}"
sudo chown -R splunk:splunk "${DEST}"
sudo find "${DEST}" -type d -exec chmod 755 {} +
sudo find "${DEST}" -type f -exec chmod 644 {} +
sudo chmod 755 "${DEST}/bin/"*.py 2>/dev/null || true

echo "Restarting Splunk..."
sudo systemctl restart Splunkd.service

echo "Wait 30s for splunkd..."
sleep 30

echo "Verify commands (merged):"
sudo -u splunk env SPLUNK_HOME="${SPLUNK_HOME}" "${SPLUNK_HOME}/bin/splunk" cmd btool commands list \
  | grep -E '^\[agentsight' || echo "WARN: run bash scripts/sh/verify_commands.sh"

echo "Done. Test in Search (no underscores in command name):"
echo "  | agentsightapprove case_id=case_a3d79928 action_id=action_case_a3d79928 decision=approved actor=admin"
