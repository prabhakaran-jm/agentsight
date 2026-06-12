#!/usr/bin/env bash
# Run MCP smoke test then print audit discovery SPL for Splunk Search.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "${SCRIPT_DIR}/mcp_smoke_test.sh"

echo
echo "=== Run these SPL queries in Splunk Search (scripts/sh/discover_mcp_audit.spl.txt) ==="
grep -v '^#' "${SCRIPT_DIR}/discover_mcp_audit.spl.txt" | awk 'NF{print}'
