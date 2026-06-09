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

## Agent tools (`bin/tools.py`)

Registered for `splunklib.ai`:

| Tool | Purpose |
|------|---------|
| `get_alert_context` | Recent `mcp_server` + `agentsight:mcp_audit` events |
| `run_investigation_search` | Read-only oneshot SPL (max 50 rows) |
| `log_investigation_step` | Audit trail to `agentsight:investigation_step` |
| `classify_agent_behavior` | `\| ai` via Ollama (`default/ai.conf`) |
| `queue_proposed_action` | Async approval queue (in-memory per alert run) |
| `create_case` | Index case to `agentsight:case` |

Override AI provider for Cloud demo:

```bash
export AGENTSIGHT_AI_PROVIDER="Splunk Hosted Models"
export AGENTSIGHT_AI_MODEL="foundation-sec-8b-instruct"
export AGENTSIGHT_AI_CONNECTION=""
```

## Investigation alert action

Saved detections trigger **`agentsight_investigate`** (max 5m). The handler runs a `splunklib.ai` agent
with local tools; on failure it falls back to a scripted investigation loop.

Install Python dependencies into the app (if `splunklib.ai` is not on the Splunk Python path):

```bash
python3 -m pip install -r apps/agentsight/requirements.txt -t apps/agentsight/bin/lib
sudo systemctl restart Splunkd.service
```

Ollama chat model for the agent (separate from `| ai` classify in tools):

```bash
export AGENTSIGHT_OLLAMA_URL="http://127.0.0.1:11434/v1"
export AGENTSIGHT_OLLAMA_CHAT_MODEL="llama3.2:latest"
```

### Test alert action

1. Run `scripts/demo_mcp_burst.sh`
2. **Settings → Searches → AgentSight - MCP Tool Loop → Run**
3. Enable alert action **AgentSight Investigate** on the search → **Trigger Actions**
4. Verify: `index=agentsight sourcetype=agentsight:case | head 5`
5. Logs: `index=_internal source="*/agentsight.log"`

## Dashboard and async approval

Open **AgentSight** in the app nav (or `/app/agentsight/agentsight_dashboard`).

1. **MCP Activity Timeline** — live `mcp_server` tool calls (30s refresh)
2. **Active Cases** / **Pending Agent Actions** — `agentsight:case` events
3. **Approve / Deny** — enter `case_id` + `action_id`, run:

```spl
| agentsight_approve case_id=case_abc123 action_id=action_case_abc123 decision=approved
```

Verify approval:

```spl
index=agentsight (sourcetype=agentsight:approval OR sourcetype=agentsight:case) case_id=case_abc123
| sort - _time
| table _time sourcetype status decision new_case_status
```
```

## App structure

```
apps/agentsight/
├── default/
│   ├── app.conf
│   ├── indexes.conf          # index=agentsight
│   ├── props.conf            # sourcetype definitions
│   ├── savedsearches.conf    # normalization + 3 detection rules
│   ├── alert_actions.conf    # agentsight_investigate custom alert action
│   ├── ai.conf               # Ollama / Foundation-Sec | ai settings
│   ├── commands.conf         # agentsight_approve (+ agentsight_explain Task 7)
│   └── data/ui/views/agentsight_dashboard.xml
├── bin/
│   ├── setup_logging.py
│   ├── tools.py              # splunklib.ai local tools (6 tools)
│   ├── agentsight_investigate.py
│   ├── agentsight_explain.py
│   └── agentsight_approve.py
└── lookups/
    └── agent_index_allowlist.csv
```
