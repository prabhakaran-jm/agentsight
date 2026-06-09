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

## App structure

```
apps/agentsight/
├── default/
│   ├── app.conf
│   ├── indexes.conf          # index=agentsight
│   ├── props.conf            # sourcetype definitions
│   ├── savedsearches.conf    # detections + normalization (upcoming)
│   ├── alert_actions.conf    # agentsight_investigate (upcoming)
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
