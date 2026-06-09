#!/usr/bin/env bash
# Run Day 0 MCP call then print discovery SPL for manual run in Splunk Search.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "${SCRIPT_DIR}/day0_mcp_call.sh"

echo
echo "=== Run these SPL queries in Splunk Search (see scripts/day0_discovery_spl.txt) ==="
grep -v '^#' "${SCRIPT_DIR}/day0_discovery_spl.txt" | awk 'NF{print}'
