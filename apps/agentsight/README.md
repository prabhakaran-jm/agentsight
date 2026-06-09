# AgentSight Splunk App

**Splunk watches the agents that use Splunk.**

Native Splunk app for the [Splunk Agentic Ops Hackathon](https://splunk.devpost.com/) — Security track.

## What it does

- Ingests **real MCP Server audit telemetry** (`index=_internal sourcetype=mcp_server`)
- Detects agent/MCP-specific misbehavior (tool loops, scope violations, off-hours bursts)
- Investigates with a **`splunklib.ai` agent** and `| ai` classification
- Async analyst approval on dashboard
- Re-run agent reasoning from the search bar via `| agentsight_explain`

## Install

```bash
# Symlink or copy into Splunk apps directory
ln -sf "$(pwd)" /opt/splunk/etc/apps/agentsight
/opt/splunk/bin/splunk restart
```

## Prerequisites

- Splunk Enterprise with MCP Server app (Splunkbase 7931)
- Splunk AI Toolkit 5.7+ and Python for Scientific Computing
- Ollama (local dev) or Splunk Hosted Models / Foundation-Sec (demo video)

See [docs/agentsight-mvp-spec.md](../../docs/agentsight-mvp-spec.md) and [docs/mcp-audit-fieldmap.md](../../docs/mcp-audit-fieldmap.md).

## Normalization saved search

After MCP activity, run or schedule **AgentSight - Normalize MCP Audit**:

```spl
index=agentsight sourcetype=agentsight:mcp_audit
| head 20
| table _time mcp_user mcp_tool session_id spl_query outcome duration_ms
```

To enable automatic normalization every 5 minutes:

```bash
/opt/splunk/bin/splunk btool saved-searches list AgentSight\ -\ Normalize\ MCP\ Audit --debug
# In Splunk Web: Settings > Searches, reports, and alerts > enable schedule on the search
# Or set enableSched = 1 in local/savedsearches.conf and restart.
```

## Detection rules

| Saved search | Source | Trigger |
|--------------|--------|---------|
| **AgentSight - MCP Tool Loop** | `_internal` / `mcp_server` | ≥5 `splunk_run_query` calls in 10m, ≤2 distinct tools |
| **AgentSight - MCP Index Scope Violation** | `_audit` / `audittrail` | Index outside `lookups/agent_index_allowlist.csv` |
| **AgentSight - MCP Off-Hours Burst** | `_internal` / `mcp_server` | ≥8 calls between 22:00–06:00 |

**Note:** Splunk MCP Server runs **stateless** — each call gets a new `request_id`, so detections group by `username` + time window, not session ID.

### Demo: trigger Rule 1

```bash
export SPLUNK_MCP_TOKEN='your-token'
bash scripts/demo_mcp_burst.sh
# Then in Splunk Web run: AgentSight - MCP Tool Loop
```

### Demo: trigger Rule 2

Run an MCP query targeting a forbidden index, e.g. `index=secrets | head 1`, via `splunk_run_query`.
```

## App structure

```
apps/agentsight/
├── default/
│   ├── app.conf
│   ├── indexes.conf          # index=agentsight
│   ├── props.conf            # sourcetype definitions
│   ├── savedsearches.conf    # normalization + 3 detection rules
│   ├── alert_actions.conf    # agentsight_investigate (stub handler; full agent Task 5)
│   └── commands.conf         # agentsight_explain (upcoming)
├── bin/
│   ├── setup_logging.py
│   ├── tools.py              # (upcoming)
│   ├── agentsight_investigate.py
│   ├── agentsight_explain.py
│   └── agentsight_approve.py
└── lookups/
    └── agent_index_allowlist.csv
```
