#!/usr/bin/env bash
# Print the submission demo sequence (does not run Splunk/Ollama).
set -euo pipefail

cat <<'EOF'
=== AgentSight demo rehearsal ===

Pre-flight:
  bash scripts/install_agentsight_deps.sh
  bash scripts/setup_foundation_sec_ollama.sh
  bash scripts/verify_commands.sh
  export SPLUNK_MCP_TOKEN='your-token'
  export SPLUNK_MCP_URL='https://localhost:8089/services/mcp'

Primary loop (tool loop — severity high, no quarantine):
  bash scripts/demo_mcp_burst.sh
  → Splunk: run saved search "AgentSight - MCP Tool Loop"
  → Trigger alert action "AgentSight Investigate"
  → index=agentsight sourcetype=agentsight:case earliest=-1h
  → Approve spl action on dashboard (Approve view)
  → | agentsightexplain case_id=case_XXXXXXXX

Quarantine loop (use mcp-demo-agent token — see scripts/DEMO_AGENT_SETUP.md):
  bash scripts/demo_mcp_scope_violation.sh
  → Run "AgentSight - MCP Index Scope Violation"
  → Investigate → approve quarantine_* action (NOT on admin)
  → bash scripts/day0_mcp_call.sh  # should fail auth

Full checklist: SUBMISSION_CHECKLIST.md
EOF
