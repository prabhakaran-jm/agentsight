#!/usr/bin/env bash
# Verify agentsight custom search commands are registered and importable.
set -euo pipefail

: "${SPLUNK_HOME:=/opt/splunk}"
APP_DIR="${SPLUNK_HOME}/etc/apps/agentsight"
FAIL=0

splunk_cmd() {
  sudo -u splunk env SPLUNK_HOME="${SPLUNK_HOME}" "${SPLUNK_HOME}/bin/splunk" "$@"
}

echo "=== App installed ==="
if [[ -f "${APP_DIR}/default/commands.conf" ]]; then
  echo "OK: ${APP_DIR}/default/commands.conf"
else
  echo "FAIL: agentsight app not at ${APP_DIR}" >&2
  exit 1
fi
if grep -q 'state = enabled' "${APP_DIR}/default/app.conf" 2>/dev/null; then
  echo "OK: app.conf state = enabled"
else
  echo "WARN: check app is enabled in Splunk UI" >&2
fi

echo ""
echo "=== SPL command names (no underscores) ==="
if grep -q '^\[agentsightapprove\]' "${APP_DIR}/default/commands.conf"; then
  echo "OK: stanza [agentsightapprove] (not agentsight_approve — underscores break SPL parsing)"
else
  echo "FAIL: expected [agentsightapprove] in commands.conf" >&2
  FAIL=1
fi

echo ""
echo "=== Python for Scientific Computing (required for custom commands) ==="
if splunk_cmd list app 2>/dev/null | grep -qiE 'scientific|python'; then
  splunk_cmd list app 2>/dev/null | grep -iE 'scientific|python' || true
else
  echo "WARN: install Splunkbase app 2882 (Python for Scientific Computing)" >&2
fi

echo ""
echo "=== commands.conf (app-scoped) ==="
splunk_cmd cmd btool commands list --app=agentsight | grep -E '^\[agentsight|^filename'

echo ""
echo "=== commands.conf (merged / global) ==="
if splunk_cmd cmd btool commands list 2>/dev/null | grep -qE '^\[agentsight'; then
  splunk_cmd cmd btool commands list 2>/dev/null | grep -E '^\[agentsight'
  echo "OK: exported globally (export = system)"
else
  echo "WARN: not in merged list — restart Splunk after metadata changes:" >&2
  echo "  sudo systemctl restart Splunkd.service" >&2
  echo "  Then run searches from the AgentSight app, or retry merged check." >&2
fi

echo ""
echo "=== Runtime import test (Python modules in bin/) ==="
IMPORT_TEST=$(sudo -u splunk env SPLUNK_HOME="${SPLUNK_HOME}" \
  "${SPLUNK_HOME}/bin/python3" - <<'PYEOF' 2>&1
import sys, os
bin_dir = '/opt/splunk/etc/apps/agentsight/bin'
sys.path.insert(0, bin_dir)
sys.path.insert(0, os.path.join(bin_dir, 'lib'))

errors = []
for script in ['agentsight_approve', 'agentsight_explain']:
    try:
        __import__(script)
        print(f"OK: {script}.py imported successfully")
    except Exception as e:
        errors.append(f"FAIL: {script}: {e}")
        print(f"FAIL: {script}: {e}", file=sys.stderr)

sys.exit(1 if errors else 0)
PYEOF
)
echo "${IMPORT_TEST}"
if echo "${IMPORT_TEST}" | grep -q '^FAIL:'; then
  FAIL=1
fi

echo ""
echo "=== Test in Search (AgentSight app context) ==="
echo "  Open: http://localhost:8000/en-US/app/agentsight/search"
echo "  Run:  | agentsightapprove case_id=case_a3d79928 action_id=action_case_a3d79928 decision=approved actor=admin"
echo ""
echo "  Or REST: export SPLUNK_PASSWORD=... && bash scripts/test_approve.sh"
echo ""
echo "If unknown command 'agentsight' (truncated), you used the old name with underscore."
echo "Use agentsightapprove / agentsightexplain — not agentsight_approve / agentsight_explain."

echo ""
if [[ $FAIL -eq 0 ]]; then
  echo "=== ALL CHECKS PASSED ==="
else
  echo "=== SOME CHECKS FAILED — see FAIL lines above ===" >&2
  exit 1
fi
