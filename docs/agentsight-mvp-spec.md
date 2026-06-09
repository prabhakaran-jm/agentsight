# AgentSight MVP Spec (v2.1)

**Splunk watches the agents that use Splunk.**

> **Do this first, today (before any app code):** verify MCP audit schema + routability (Kill-switch #1) and run Foundation-Sec pre-flight (Kill-switch #2). The entire spec assumes both work. See [Day 0 gate](#day-0-gate-do-not-skip).

AgentSight is a native Splunk app that ingests **real MCP Server audit telemetry** and agent tool-call events, detects **agent/MCP-specific** misbehavior (not generic threat rules), investigates with a **`splunklib.ai` agent**, and lets analysts **re-run agent reasoning from the search bar** via `| agentsight_explain`.

Built for the **Splunk Agentic Ops Hackathon** — **Security track** (agentic-ops observability angle).

---

## Positioning (read this first)

### The meta-angle (your sharpest edge)

Most hackathon entries build **agents that query Splunk**. AgentSight inverts that: **Splunk observes the autonomous workforce hitting your data** — MCP clients, service-account agents, runaway tool loops, scope violations.

Lead every surface (title, video, Devpost, dashboard subtitle) with:

> **Observability for the autonomous workforce touching your Splunk data.**

### What changed from v1 (conscious tradeoffs)

| v1 (buried edge) | v2 (this spec) |
|------------------|----------------|
| Observability track, generic SOC triage framing | **Security track**, agent/MCP-native framing |
| All-synthetic `demo_event_generator` | **Real MCP audit logs** primary; generator = fallback only |
| Sync approval polling 30s inside alert action | **Async approval**: agent finishes → human approves on dashboard → follow-up runs |
| OpenAI fallback acceptable in demo | **Foundation-Sec live on camera** for `classify_agent_behavior` |
| Alert action only (option B) | Alert action **+** `\| agentsight_explain` hunt command (option A restored) |

**Verdict:** Buildability stays high. Novelty recovered via meta-framing + SPL-native agent command.

### v2.1 — execution risks (spec ≠ demo)

| Rank | Risk | Mitigation in this spec |
|------|------|-------------------------|
| **1** | Real MCP audit path **unverified** — load-bearing for credibility + Quality of Idea | [Day 0 gate](#day-0-gate-do-not-skip) |
| **2** | Rule 2 index extraction fragile on camera | Fixed with `rex` (below) |
| **3** | Design left at ★★★ (25% of score) | Hero panel: [MCP Activity Timeline](#hero-panel-mcp-activity-timeline-design-) |
| **4** | Alert action timeout (search jobs + `\| ai` latency) | Cap 5 tool calls; wall-clock test |
| **5** | Video rushed on Day 7 | **1.5 days** budget; rehearse [live loop](#video-the-live-self-observation-loop) |

**Top prize is reachable** — gated on Kill-switch #1 (real MCP data) and alert-action wall-clock (risk 4). Remaining work is execution, not design thinking.

---

## Day 0 gate (do not skip)

Everything downstream assumes this passes. **Day 1 app work starts only after Day 0 is green.**

### Kill-switch #1 — MCP audit schema + routability (biggest)

```bash
# 1. Install Splunk MCP Server app (Splunkbase 7931)
# 2. Make ONE authenticated MCP call (any client — splunklib.ai remote tool, curl, MCP Inspector)
# 3. Find where the audit event actually lands:
```

```spl
index=_* OR index=main OR index=_internal
  (sourcetype=*mcp* OR source=*mcp* OR "mcp" OR "run_splunk_search")
  earliest=-15m
| head 50
| table _time index sourcetype source _raw
```

**Document before proceeding:**

| Question | Your answer (fill in) |
|----------|----------------------|
| Which **index** holds MCP audit events? | |
| Which **sourcetype** / **source**? | |
| Field names for user, tool, query, outcome? | |
| Routable to `index=agentsight` / `agentsight:mcp_audit`? | yes / no — how? |

**If audit is not easily forwardable:** pivot ingest to whatever index/sourcetype MCP actually writes, run detections there, **then** optionally copy to `agentsight`. Do not invent field names — map real schema.

**Pass criteria:** At least one event in Splunk with real `spl_query` (or equivalent) from a live MCP call you made.

### Kill-switch #2 — Foundation-Sec pre-flight

```spl
| makeresults count=1
| eval prompt="Classify this MCP agent behavior: 15 identical run_splunk_search calls in 10 minutes."
| ai model=foundation-sec-8b-instruct
```

| Result | Action |
|--------|--------|
| Returns classification text | Proceed — demo uses Foundation-Sec on camera |
| Error / unavailable | Splunk Cloud + AI Toolkit, or hackathon Slack **today** — do not defer to Day 6 |

### Day 0 checklist

- [ ] MCP Server installed; one live MCP call made
- [ ] Audit event located; field map written in `docs/mcp-audit-fieldmap.md` (create after verification)
- [ ] Forward path to `agentsight:mcp_audit` chosen and tested
- [ ] Foundation-Sec pre-flight returns text
- [ ] **Go / no-go:** if MCP audit unreachable → use detected index/sourcetype in rules OR escalate before building on synthetic

---

## Project identity

| Field | Value |
|-------|--------|
| **App name** | AgentSight |
| **Splunk app ID** | `agentsight` |
| **Index** | `agentsight` |
| **Track** | **Security** (submit here; angle = agentic-ops observability) |
| **Tagline** | *Splunk watches the AI agents that query Splunk.* |
| **Elevator pitch** | *Who watches the MCP clients and autonomous agents touching your indexes? AgentSight does — inside Splunk.* |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  REAL DATA PATH (primary — show this in video)                   │
│  Splunk MCP Server → audit logs → HEC/modular input              │
│    → index=agentsight sourcetype=agentsight:mcp_audit            │
└─────────────────────────────────────────────────────────────────┘
                              ↓
        3 agent/MCP detection saved searches
                              ↓
        Custom alert action: agentsight_investigate (splunklib.ai)
          → Local tools (read-only SPL, log steps, queue actions, classify)
          → MCP remote tools (optional)
          → Foundation-Sec via | ai  ← MUST run live in demo
          → Case indexed (status=open | awaiting_approval)
                              ↓
        Dashboard: Approve proposed SPL → triggers follow-up search
                              ↓
        Analyst search bar: | agentsight_explain case_id=...
          → Agent re-explains case + cited sids in SPL output

Fallback: demo_event_generator.py (offline judges only — label clearly)
```

---

## Index and sourcetypes

| Sourcetype | Purpose | Key fields |
|------------|---------|------------|
| `agentsight:mcp_audit` | **Primary.** Real MCP Server audit events | `mcp_user`, `mcp_tool`, `spl_query`, `client_ip`, `outcome`, `bytes_returned`, `duration_ms`, `session_id` |
| `agentsight:agent_tool_call` | External agent telemetry (HEC); optional if MCP covers demo | `agent_id`, `session_id`, `tool_name`, `command`, `mcp_tool`, `duration_ms` |
| `agentsight:investigation_step` | AgentSight agent audit trail | `case_id`, `step_number`, `tool_name`, `tool_input`, `tool_output_summary`, `sid` |
| `agentsight:case` | Investigation case | `case_id`, `trigger_rule`, `severity`, `status`, `summary`, `mitre_techniques[]`, `cited_sids[]`, `pending_actions[]` |
| `agentsight:approval` | Human decisions (async) | `case_id`, `action_id`, `decision`, `actor`, `approved_spl`, `followup_sid` |
| `agentsight:demo` | Fallback generator only | `generator`, `scenario` |

### Ingest real MCP audit logs (required for credible demo)

1. Install [Splunk MCP Server app](https://splunkbase.splunk.com/app/7931) on your Splunk instance.
2. Route a real agent (or MCP client) through MCP — e.g. `splunklib.ai` agent with `RemoteToolSettings`, or any MCP-compatible client.
3. Forward MCP audit events to `index=agentsight` / `sourcetype=agentsight:mcp_audit` via:
   - HEC transform, **or**
   - Modular input tailing MCP audit log path, **or**
   - Saved search on MCP internal/audit index → output to agentsight index.

**Video must show at least one event with real `mcp_user` / `spl_query` from live MCP traffic.**

### Sample MCP audit event (illustrative — replace with Day 0 field map)

Field names below are **hypotheses**. After Day 0, update sourcetype extractions and detection SPL to match **actual** MCP audit fields.

```json
{
  "audit_id": "mcp_a91c",
  "timestamp": "2026-06-08T14:22:00Z",
  "mcp_user": "agent-svc-checkout",
  "mcp_tool": "run_splunk_search",
  "spl_query": "index=main | head 50",
  "client_ip": "10.0.4.22",
  "outcome": "success",
  "bytes_returned": 4820,
  "duration_ms": 890,
  "session_id": "mcp_sess_7f2a"
}
```

---

## Detection rules (agent/MCP-native — not generic SOC)

Each rule runs every **5 minutes**, triggers **`agentsight_investigate`**.  
Rule names and descriptions must say **agent/MCP** explicitly so judges don't skim "another auto-triage bot."

### Rule 1: AgentSight — MCP Tool Loop (Runaway Agent)

**Meta-intent:** An MCP client stuck in an autonomous tool loop — agentic ops failure mode, not a human attacker.

```spl
index=agentsight sourcetype=agentsight:mcp_audit earliest=-15m
| stats count as mcp_calls,
        dc(mcp_tool) as distinct_mcp_tools,
        values(mcp_user) as mcp_user,
        values(session_id) as session_id
  by session_id
| where mcp_calls >= 12 AND distinct_mcp_tools <= 2
| eval trigger_rule="mcp_tool_loop",
       severity="high",
       actor=mcp_user,
       description="MCP session ".session_id." (user=".mcp_user.") made ".mcp_calls." MCP calls with only ".distinct_mcp_tools." distinct tools — possible runaway agent"
```

### Rule 2: AgentSight — MCP Index Scope Violation

**Meta-intent:** An **agent** queried indexes outside its declared allowlist — governance for autonomous Splunk consumers, not generic "secrets access" alerting.

```spl
index=agentsight sourcetype=agentsight:mcp_audit earliest=-15m
| rex field=spl_query "index\s*=\s*\"?(?<queried_index>\w+)"
| eval queried_index=coalesce(queried_index, "unknown")
| lookup agent_index_allowlist mcp_user OUTPUT allowed_indexes
| eval allowed=if(isnull(allowed_indexes), "main,agentsight", allowed_indexes)
| eval scope_violation=if(queried_index!="unknown" AND NOT match(allowed, queried_index), 1, 0)
| where scope_violation=1 OR match(spl_query, "(?i)index=(secrets|credentials|prod_keys)")
| stats count as violations,
        values(spl_query) as queries,
        values(queried_index) as indexes
  by mcp_user
| eval trigger_rule="mcp_scope_violation",
       severity="critical",
       actor=mcp_user,
       description="MCP agent ".mcp_user." violated index scope ".violations." time(s) — autonomous workforce governance"
```

**Note:** `rex` handles typical `index=foo` patterns; multi-index queries may need `mvexpand` in v2.2. For demo, trigger scope violation with a single-index MCP query you control (e.g. `index=secrets | head 1`).

**MVP shortcut:** If lookup table isn't ready, use inline allowlist:

```spl
| eval allowed="main,agentsight"
| where scope_violation=1 OR match(spl_query, "(?i)index=(secrets|credentials)")
```

Ship `lookups/agent_index_allowlist.csv` with columns `mcp_user,allowed_indexes` for polish.

### Rule 3: AgentSight — MCP Off-Hours Burst

**Meta-intent:** Autonomous agent activity spike when humans aren't watching — agentic ops anomaly.

```spl
index=agentsight sourcetype=agentsight:mcp_audit earliest=-24h
| eval hour=strftime(_time, "%H"),
       is_off_hours=if(hour<6 OR hour>=22, 1, 0)
| where is_off_hours=1
| stats count as off_hours_mcp_calls,
        dc(session_id) as sessions,
        values(mcp_tool) as tools_used
  by mcp_user
| where off_hours_mcp_calls >= 8
| eval trigger_rule="mcp_off_hours_burst",
       severity="medium",
       actor=mcp_user,
       description="MCP agent ".mcp_user." made ".off_hours_mcp_calls." off-hours MCP calls — review autonomous schedule"
```

---

## Two agent surfaces (A + B)

### B — Custom alert action: `agentsight_investigate`

| Field | Value |
|-------|--------|
| **Script** | `bin/agentsight_investigate.py` |
| **Trigger** | 3 saved searches above |
| **Behavior** | Runs investigation agent **synchronously**; completes case; **does not block on human** |

**Alert inputs:** `trigger_rule`, `severity`, `description`, `actor`, `session_id`, `queries`

**Alert action constraints:** Finish within Splunk alert timeout (~5 min). **Hard cap: 5 tool calls** (not 8). Exactly **one** `classify_agent_behavior` / `\| ai` call. No polling.

### Alert action latency budget (risk 4)

| Step | Target wall-clock |
|------|-------------------|
| `get_alert_context` | ≤15s |
| `run_investigation_search` × 1–2 | ≤60s each (use oneshot, `row_limit=50`) |
| `classify_agent_behavior` (Foundation-Sec) | ≤90s |
| `queue_proposed_action` + `create_case` | ≤15s |
| **Total** | **≤4 min** (margin inside 5-min alert limit) |

**Test on Day 4:** fire alert manually; confirm case indexed before timeout. If `\| ai` is slow, reduce to 1 search + classify only.

**Agent loop (investigate prompt):** `get_alert_context` → one `run_investigation_search` → `classify_agent_behavior` → optional `queue_proposed_action` → `create_case`. Skip extra searches unless critical.

### A — Custom search command: `agentsight_explain` (novelty restore)

**Script:** `bin/agentsight_explain.py` (GeneratingCommand)

**Usage:**

```spl
index=agentsight sourcetype=agentsight:case case_id=case_a1b2c3d4
| agentsight_explain case_id=case_a1b2c3d4
```

**Behavior:**

1. Load case + `investigation_step` events for `case_id`.
2. Invoke same `splunklib.ai` agent with a **replay/explain** system prompt (shorter than investigate).
3. Emit one result row:

| Field | Description |
|-------|-------------|
| `case_id` | Case identifier |
| `explanation` | Plain-language narrative for analysts |
| `findings` | Multivalue finding strings with `[sid=...]` |
| `classification` | benign / suspicious / malicious |
| `cited_sids` | Search jobs referenced |
| `suggested_spl` | Up to 3 follow-up queries (not auto-run) |

**Why this matters:** Agent lives **in the search bar** — rare in hackathon submissions; recovers Quality-of-Idea points cheaply on top of existing tools.

**Video segment (15 sec):** Run `| agentsight_explain` after case is created; show explanation field in results table.

---

## Async human approval (fix architecture smell)

### Problem with v1

Polling 30s inside alert action → looks broken on demo; humans won't approve in time; alert execution limits.

### v2 flow

```
Alert fires
  → agentsight_investigate agent runs (read-only evidence gathering)
  → Agent calls queue_proposed_action() for any SPL it wants run later
  → Agent calls create_case(status="awaiting_approval", pending_actions=[...])
  → Alert action EXITS (case exists, approval pending)

Analyst opens dashboard
  → Reviews case + proposed SPL
  → Clicks Approve on action_id
  → bin/agentsight_approve.py:
       1. Writes agentsight:approval event (decision=approved)
       2. Runs approved SPL via read-only job
       3. Appends followup results to case (new investigation_step)
       4. Updates case status=open or closed
```

**Demo honesty:** Show case created **first** (awaiting approval), then cut to dashboard approval, then follow-up results. Don't fake instant approval inside the alert action.

---

## Agent system prompt (investigate)

```text
You are AgentSight Investigation Agent — Splunk's analyst for AI agents and MCP clients
that access this Splunk deployment. You investigate AGENT BEHAVIOR, not generic human
threats. Every alert is about an autonomous MCP client or agent service account.

## Meta mission
Splunk is watching the agents that use Splunk. Your job is to explain what an MCP/agent
did, whether it violated scope or autonomy norms, and produce an auditable case with
cited search job IDs (sids).

## When triggered
1. Call get_alert_context for the trigger_rule and actor/session.
2. Run read-only SPL against agentsight:mcp_audit (and agent_tool_call if present).
3. Call classify_agent_behavior — MUST use Foundation-Sec (| ai) when available.
4. For any SPL you want an analyst to run later, call queue_proposed_action — do NOT
   wait for approval; do NOT poll.
5. Log every step with log_investigation_step.
6. Call create_case with status="awaiting_approval" if pending actions exist, else "closed".

## Operating rules
- READ-ONLY only. No delete, collect, outputlookup append, script, sendemail.
- Summarize patterns and counts — never echo raw secrets from queries.
- Max 5 tool calls per investigation (hard cap for alert timeout).
- Cite evidence as [sid=<job_id>].
- Frame findings as agent/MCP governance: runaway loop, scope violation, off-hours burst.
- MITRE mapping is secondary — use only when agent behavior maps cleanly; don't force it.

## trigger_rule playbooks

### mcp_tool_loop
Timeline of MCP calls by session_id. Repeated identical mcp_tool or spl_query?
Classify: misconfiguration vs runaway autonomy vs prompt injection.

### mcp_scope_violation
Which indexes did mcp_user query vs allowlist? Bulk vs scoped reads?
Classify: policy misconfig vs autonomous overreach.

### mcp_off_hours_burst
Off-hours volume vs same mcp_user business-hours baseline. Scheduled job metadata?
Classify: expected automation vs suspicious timing.
```

### Agent system prompt (explain — for `| agentsight_explain`)

```text
You are AgentSight Explain Agent. Given an existing case_id and its investigation_step
audit trail, produce a concise analyst-facing explanation. Do not invent events. Cite sids
from the step log. Output structured fields: explanation, findings[], classification,
suggested_spl[] (max 3, read-only queries). Emphasize: this case is about an MCP/agent
client, not a human intruder.
```

---

## Tool signatures (`bin/tools.py`)

```python
from splunklib.ai.registry import ToolContext, ToolRegistry

registry = ToolRegistry()


@registry.tool()
def run_investigation_search(ctx: ToolContext, spl: str, earliest: str = "-1h",
                             latest: str = "now", row_limit: int = 100) -> dict:
    """Run read-only SPL; return sid, row_count, sample_rows (max 5). No mutating commands."""


@registry.tool()
def log_investigation_step(ctx: ToolContext, case_id: str, step_number: int,
                           tool_name: str, tool_input: str,
                           tool_output_summary: str, sid: str | None = None) -> dict:
    """Index auditable step to agentsight:investigation_step. Call after every tool use."""


@registry.tool()
def classify_agent_behavior(ctx: ToolContext, case_id: str,
                            evidence_summary: str, trigger_rule: str) -> dict:
    """
    Classify MCP/agent behavior. REQUIRED: use Foundation-Sec via SPL:
      | makeresults | eval prompt="<facts>" | ai model=foundation-sec-8b-instruct
    Returns classification, confidence, reasoning. MITRE optional.
    OpenAI fallback: dev/test only — not for submission demo.
    """


@registry.tool()
def queue_proposed_action(ctx: ToolContext, case_id: str, action_id: str,
                          proposed_spl: str, rationale: str) -> dict:
    """
    Queue a proposed read-only SPL for async human approval. Writes pending action to
    case metadata. Does NOT poll or block. Agent continues and finishes case.
    Returns action_id and status=queued.
    """


@registry.tool()
def create_case(ctx: ToolContext, case_id: str, trigger_rule: str, severity: str,
                actor: str, summary: str, findings: list[str],
                cited_sids: list[str], classification: str,
                status: str = "awaiting_approval",
                pending_actions: list[str] | None = None) -> dict:
    """
    Finalize case to agentsight:case. status: awaiting_approval | closed.
    pending_actions: list of action_id strings queued for dashboard approval.
    """


@registry.tool()
def get_alert_context(ctx: ToolContext, trigger_rule: str,
                      session_id: str | None = None,
                      actor: str | None = None) -> dict:
    """Load recent agentsight:mcp_audit events for alert context (max 20)."""
```

**Removed:** `request_human_approval` (sync poll) — replaced by `queue_proposed_action` + dashboard.

### Tool allowlist

```python
ToolSettings(
    local=LocalToolSettings(allowlist=ToolAllowlist(names=[
        "get_alert_context",
        "run_investigation_search",
        "log_investigation_step",
        "classify_agent_behavior",
        "queue_proposed_action",
        "create_case",
    ])),
    remote=RemoteToolSettings(
        allowlist=ToolAllowlist(names=["run_splunk_search"])
    ),
)
```

---

## Foundation-Sec pre-flight (kill-switch check)

Run **before** recording video:

```spl
| makeresults count=1
| eval prompt="Classify this MCP agent behavior: 15 identical run_splunk_search calls in 10 minutes."
| ai model=foundation-sec-8b-instruct
```

| Result | Action |
|--------|--------|
| Returns classification text | ✅ Demo uses Foundation-Sec on camera |
| Error / model unavailable | Escalate: Splunk Cloud trial, AI Toolkit, or contact hackathon Slack **before** submitting OpenAI-only demo |

**Submission rule:** `classify_agent_behavior` output in video **must** come from Foundation-Sec. OpenAI is local dev fallback only.

---

## Dashboard panels

| Panel | Content |
|-------|---------|
| **Subtitle** | *Splunk watches the agents that use Splunk* |
| **Hero — MCP Activity Timeline** | See below (Design ★★★→★★★★) |
| **Active Cases** | `sourcetype=agentsight:case` |
| **Pending Agent Actions** | Cases with `status=awaiting_approval` |
| **Approve / Deny** | Form → `bin/agentsight_approve.py` → runs follow-up SPL |
| **Try in Search** | Copy: `\| agentsight_explain case_id=$case_id$` |
| **SAIA Export** | Context prompt for Splunk AI Assistant |

### Hero panel: MCP Activity Timeline (Design ★★★→★★★★)

**One panel polished beats six mediocre.** This is the visual causality story for judges and video.

**Layout:** Full-width timechart at top of dashboard.

**Search:**

```spl
index=agentsight sourcetype=agentsight:mcp_audit earliest=-30m
| timechart span=1m count by mcp_tool
```

**Companion table (same panel row):**

```spl
index=agentsight sourcetype=agentsight:mcp_audit earliest=-30m
| sort - _time
| table _time mcp_user mcp_tool spl_query outcome session_id
| head 20
```

**Optional drilldown:** Click session_id → shows related `agentsight:case` if exists.

**Video use:** Split screen — timeline spikes as rogue MCP agent loops → cut to fired alert → case row appears. **Cause → detect → investigate** in one glance.

**Polish (≤1 day):** auto-refresh 30s, red threshold annotation when count >10/min, subtitle "Live MCP agent activity".

---

## Demo data strategy

| Priority | Source | When |
|----------|--------|------|
| **1 (required)** | Real MCP Server audit → `agentsight:mcp_audit` | Video + primary judge path |
| **2** | Live agent via MCP (splunklib.ai remote tools) | Prove end-to-end agent traffic |
| **3 (fallback)** | `demo_event_generator.py` | Offline judges; README labels "synthetic fallback" |

---

## Judge quickstart

```bash
# 1. Install Splunk MCP Server app + AgentSight app
# 2. Create index agentsight
# 3. Route MCP audit logs → sourcetype=agentsight:mcp_audit
# 4. Pre-flight Foundation-Sec (see above)
# 5. Run an MCP client/agent to generate real audit events
# 6. Enable 3 saved searches; wait for alert OR fire manually
# 7. Dashboard → review case (awaiting_approval) → Approve action
# 8. Search: | agentsight_explain case_id=<id>
```

---

## Execution plan (Day 0 + 7 build days)

| When | Deliverable | Gate |
|------|-------------|------|
| **Day 0 (today)** | MCP audit field map + Foundation-Sec pre-flight | **Go/no-go** |
| Day 1 | Fork `ai_custom_alert_app`; ingest from **verified** MCP path |
| Day 2 | 3 detection rules (Rule 2 uses `rex`) + allowlist lookup |
| Day 3 | `bin/tools.py` + async approval |
| Day 4 | Alert action + **wall-clock timeout test** (≤4 min) |
| Day 5 | `\| agentsight_explain` command |
| Day 6 | Hero timeline dashboard + E2E on real MCP; **start video B-roll** |
| Days 6–7 | **1.5 days video** — script, takes, edit; not a single evening |

### Video: the live self-observation loop

**Wow moment (rehearse until smooth):**

1. Run MCP agent live (or script burst of MCP calls) — **hero timeline panel** shows calls piling up
2. Detection fires — AgentSight investigates **itself watching that agent**
3. Case appears `awaiting_approval` → approve on dashboard
4. `| agentsight_explain case_id=...` in search bar

**Pitch in one sentence:** *An agent goes rogue live → Splunk watches itself watch that agent → explains it in SPL.*

Do not discover latency or MCP schema issues during this take — prove both by Day 4.

---

## MVP acceptance checklist

### Kill-switches (Day 0)

- [ ] MCP audit events located; field map documented
- [ ] Foundation-Sec pre-flight returns text

### Build

- [ ] Real MCP audit in `agentsight:mcp_audit` (generator not primary)
- [ ] 3 rules fire on real MCP traffic; Rule 2 uses `rex`
- [ ] Alert action completes in **≤4 min** wall-clock
- [ ] Case `awaiting_approval` → dashboard approve → follow-up step
- [ ] `\| agentsight_explain` works in search bar
- [ ] Hero MCP Activity Timeline panel live with auto-refresh

### Submission

- [ ] Architecture diagram in repo root
- [ ] Video: [live self-observation loop](#video-the-live-self-observation-loop) rehearsed
- [ ] Foundation-Sec visible on camera (not OpenAI)

---

## Expected judge scores (v2.1 — honest)

| Criterion | Score | Condition |
|-----------|-------|-----------|
| Technological Implementation | ★★★★ | SDK agent + async + two surfaces + timeout budget met |
| Potential Impact | ★★★★ | Meta narrative holds |
| Quality of Idea | ★★★★ **or ★★★** | ★★★★ **only if real MCP data in demo**; synthetic-only → ★★★ |
| Design | ★★★★ | **If hero timeline panel ships**; else ★★★ |

**Net:** Top-quartile spec. **Top prize** reachable if Kill-switch #1 passes and live loop video lands.

**Linchpin:** Real MCP audit path verified Day 0 — not Day 6.
