# AgentSight Architecture

**Splunk watches the agents that use Splunk.**

AgentSight is a native Splunk app for the [Splunk Agentic Ops Hackathon](https://splunk.devpost.com/) (Security track). It observes MCP clients and autonomous agents that query Splunk, detects agent-specific misbehavior, investigates with `splunklib.ai`, and supports async analyst approval.

## System diagram

```mermaid
flowchart TD
    subgraph ingest [Data path]
        MCP[Splunk_MCP_Server]
        Internal["index=_internal sourcetype=mcp_server"]
        Audit["index=_audit sourcetype=audittrail"]
        NormSS[Normalize_saved_search]
        AgentsightIdx["index=agentsight"]
        MCP --> Internal
        MCP --> Audit
        Internal --> NormSS
        NormSS --> AgentsightIdx
    end

    subgraph detect [Detection 5 rules]
        R1[MCP_Tool_Loop]
        R2[MCP_Scope_Violation]
        R3[MCP_Off_Hours_Burst]
        R4[MCP_Data_Exfiltration]
        R5[MCP_Prompt_Injection]
        Internal --> R1
        Internal --> R3
        Internal --> R5
        Audit --> R2
        Audit --> R4
        Internal --> R4
    end

    subgraph investigate [Investigation]
        Alert[agentsight_investigate]
        Tools[bin/tools.py]
        AIAgent["splunklib.ai Agent"]
        PipeAI["| ai classify Foundation-Sec via Ollama Path A"]
        R1 --> Alert
        R2 --> Alert
        R3 --> Alert
        R4 --> Alert
        R5 --> Alert
        Alert --> AIAgent
        AIAgent --> Tools
        Tools --> PipeAI
        Tools --> AgentsightIdx
    end

    subgraph analyst [Analyst surfaces and response]
        Dash[agentsight_dashboard]
        Approve["| agentsightapprove"]
        Explain["| agentsightexplain"]
        Quarantine["revoke_user_tokens REST authorization/tokens"]
        AgentsightIdx --> Dash
        Dash --> Approve
        Approve -->|quarantine approved| Quarantine
        Quarantine --> MCP
        AgentsightIdx --> Explain
    end
```

## Splunk AI capabilities used

| Capability | Role in AgentSight |
|------------|-------------------|
| **Splunk MCP Server** (Splunkbase 7931) | Source of real audit telemetry (`mcp_server`, `audittrail`) |
| **`splunklib.ai` Agent** | Investigation and explain agents with local tools |
| **`| ai` command** (AI Toolkit) | `classify_agent_behavior` via Foundation-Sec open weights in Ollama (Path A); optional Splunk Hosted Models clip (Path B) |
| **Custom alert action** | `agentsight_investigate` on detection saved searches |
| **Custom search commands** | `agentsightapprove`, `agentsightexplain` |

## Data flow

1. **MCP clients** call `splunk_run_query` via Streamable HTTP (`POST /services/mcp`).
2. **Audit logs** land in `_internal`/`mcp_server` and `_audit`/`audittrail`.
3. **Normalization** saved search copies events to `index=agentsight` / `agentsight:mcp_audit`.
4. **Detection** saved searches fire on runaway loops, scope violations, off-hours bursts, MCP-attributed data-export SPL, and prompt-injection signatures in tool arguments.
5. **`agentsight_investigate`** runs an AI agent (max ~6 tool calls, 4 min budget) → indexes `agentsight:case`. For critical findings it queues a **quarantine** action alongside any read-only follow-up.
6. **Dashboard** shows live MCP timeline + KPIs; analyst **approves** a queued SPL or **quarantine** via `agentsightapprove`.
7. **Quarantine** (on approval only) calls `revoke_user_tokens` → Splunk REST `authorization/tokens` to revoke the rogue agent's tokens; case status → `contained`.
8. **`| agentsightexplain`** re-explains the case in the search bar.

## Index and sourcetypes

| Sourcetype | Purpose |
|------------|---------|
| `agentsight:mcp_audit` | Normalized MCP audit events |
| `agentsight:case` | Investigation cases |
| `agentsight:investigation_step` | Agent tool audit trail |
| `agentsight:approval` | Human approve/deny decisions |
| `agentsight:demo` | Synthetic fallback only |

## Repository layout

```
agentsight/
├── architecture_diagram.md  # this file (Devpost-required filename)
├── README.md                # judge quickstart
├── LICENSE
├── scripts/
│   ├── sh/                  # bash helpers (Linux / macOS)
│   ├── ps1/                 # PowerShell helpers (Windows)
│   └── build_app_icons.py
└── apps/agentsight/         # Splunk app (install to $SPLUNK_HOME/etc/apps/)
```

## Demo path (video)

1. `scripts/sh/demo_mcp_burst.sh` → hero timeline spikes
2. Detection fires → `agentsight_investigate` → case `awaiting_approval`
3. Dashboard approve → read-only SPL follow-up (or **quarantine** on `mcp-demo-agent` only — never on `admin`)
4. `| agentsightexplain case_id=...`

