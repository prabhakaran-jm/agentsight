# AgentSight

**Splunk watches the agents that use Splunk.**

Observability for the autonomous workforce touching your Splunk data — built for the [Splunk Agentic Ops Hackathon](https://splunk.devpost.com/) (**Security** track).

AgentSight ingests **real Splunk MCP Server audit telemetry**, detects agent/MCP-specific misbehavior, investigates with **`splunklib.ai`**, classifies via **`| ai`** (Ollama locally / Foundation-Sec on Cloud for demo), and supports async analyst approval plus **`| agentsight_explain`** in the search bar.

## What you can do with this

| You want to… | Where / how |
|--------------|-------------|
| See MCP agents querying Splunk | **AgentSight** app → dashboard → *MCP Activity Timeline* |
| Simulate a rogue agent (demo) | `bash scripts/demo_mcp_burst.sh` |
| Detect runaway tool loops | Saved search **AgentSight - MCP Tool Loop** |
| Auto-investigate with AI | Alert action **AgentSight Investigate** on detection searches |
| Approve or deny a proposed fix | Dashboard → *Approve / Deny Queued Action* (needs `case_id` + `action_id`) |
| Get a plain-English case summary | Search: `\| agentsight_explain case_id=case_XXXXXXXX` |

The dashboard shows live MCP traffic from `index=_internal sourcetype=mcp_server`. **Cases and approvals only appear after** you run a detection and the investigate alert action fires.

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for the system diagram and data flow.

## Prerequisites

| Component | Splunkbase / source |
|-----------|---------------------|
| Splunk Enterprise 9.x or 10.x | — |
| [Splunk MCP Server](https://splunkbase.splunk.com/app/7931) | MCP audit source |
| [Python for Scientific Computing](https://splunkbase.splunk.com/app/2882) | AI Toolkit dependency |
| [Splunk AI Toolkit](https://splunkbase.splunk.com/app/2890) 5.7+ | `\| ai` command |
| [Ollama](https://ollama.com) (local dev) | Chat + classify |
| `splunk-sdk[ai]` | Agent + tools (see below) |

## Install

```bash
git clone https://github.com/prabhakaran-jm/agentsight.git agentsight
cd agentsight

# Python deps — MUST use Splunk's Python, not system python3 (Fedora 3.14 ≠ Splunk 3.9/3.11)
bash scripts/install_agentsight_deps.sh

# Remove accidental self-symlink if present
rm -f apps/agentsight/agentsight
```

### Option A — Symlink (development; edit repo files live)

```bash
sudo ln -sf "$(pwd)/apps/agentsight" /opt/splunk/etc/apps/agentsight
sudo chown -h splunk:splunk /opt/splunk/etc/apps/agentsight

# Splunk runs as user "splunk" — it must traverse the path to your repo
chmod 711 "$HOME"
chmod -R a+rX "$(pwd)/apps/agentsight"

sudo systemctl restart Splunkd.service
```

### Option B — Copy (simplest; no home-directory permission issues)

```bash
sudo rm -rf /opt/splunk/etc/apps/agentsight
sudo cp -a apps/agentsight /opt/splunk/etc/apps/agentsight
sudo chown -R splunk:splunk /opt/splunk/etc/apps/agentsight
sudo systemctl restart Splunkd.service
```

### Verify install

```bash
sudo -u splunk /opt/splunk/bin/splunk list app | grep -i agentsight
```

Open: **http://localhost:8000/en-US/app/agentsight/agentsight_dashboard**

### Troubleshooting: app not in launcher

| Symptom | Fix |
|---------|-----|
| App missing from Apps list | Symlink target not readable by `splunk` user — use **Option B** or `chmod 711 $HOME` (Option A) |
| Dashboard panels say *Search is waiting for input* | Restart Splunk after dashboard update; timeline panels auto-run — approval fields are optional |
| Empty MCP timeline | No MCP traffic yet — run `bash scripts/demo_mcp_burst.sh` |
| Investigate / explain errors | Run `bash scripts/install_agentsight_deps.sh`; confirm Ollama is running |

## First demo (10 minutes)

Do these steps in order after install:

**1. Confirm MCP works**

```bash
export SPLUNK_MCP_TOKEN='your-encrypted-mcp-token'
export SPLUNK_MCP_URL='https://localhost:8089/services/mcp'
bash scripts/day0_mcp_call.sh
```

**2. Generate rogue-agent traffic**

```bash
bash scripts/demo_mcp_burst.sh
```

**3. Refresh the AgentSight dashboard** — *MCP Activity Timeline* should show `splunk_run_query` spikes in the last 30 minutes.

**4. Run the detection** — Splunk Web → **Settings → Searches, reports, and alerts** → open **AgentSight - MCP Tool Loop** → **Open in Search** → run. You should see a hit (≥5 calls in 10m).

**5. Investigate** — On that saved search, ensure alert action **AgentSight Investigate** is enabled. Run the search as an alert (or trigger manually). Then:

```spl
index=agentsight sourcetype=agentsight:case earliest=-1h
| table _time case_id trigger_rule severity status actor classification
```

**6. Approve** — Copy `case_id` and `action_id` from the case JSON into the dashboard approval form.

**7. Explain**

```spl
index=agentsight sourcetype=agentsight:case
| head 1
| agentsight_explain case_id=case_XXXXXXXX
```

## Day 0 verification

```bash
bash scripts/day0_discovery_mcp.sh
```

In Splunk Search, run queries from `scripts/day0_discovery_spl.txt`.

AI Toolkit pre-flight (Ollama):

```spl
| makeresults count=1
| eval prompt="Classify this MCP agent behavior: 15 identical splunk_run_query calls in 10 minutes."
| ai provider=Ollama model=llama3.2:latest connection=ollama_local prompt="'{prompt}'"
```

Field map: [docs/mcp-audit-fieldmap.md](docs/mcp-audit-fieldmap.md)

## Judge quickstart (live demo loop)

1. **MCP burst** — `bash scripts/demo_mcp_burst.sh`
2. **Normalize** (optional) — saved search **AgentSight - Normalize MCP Audit**
3. **Detect** — **AgentSight - MCP Tool Loop**
4. **Investigate** — alert action **AgentSight Investigate**
5. **Dashboard** — approve pending action
6. **Explain** — `| agentsight_explain case_id=...`
7. **Verify** — `index=agentsight sourcetype=agentsight:* earliest=-1h | stats count by sourcetype`

Saved searches ship with `enableSched = 0`. Enable schedules in **Settings → Searches** or set `enableSched = 1` in `local/savedsearches.conf` for hands-free alerts.

## Environment variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `SPLUNK_MCP_TOKEN` | — | MCP encrypted token |
| `SPLUNK_MCP_URL` | `https://localhost:8089/services/mcp` | MCP endpoint |
| `AGENTSIGHT_OLLAMA_URL` | `http://127.0.0.1:11434/v1` | Agent chat model |
| `AGENTSIGHT_OLLAMA_CHAT_MODEL` | `llama3.2:latest` | Agent chat model name |
| `AGENTSIGHT_AI_PROVIDER` | `Ollama` | `\| ai` in classify tool |
| `AGENTSIGHT_AI_MODEL` | `llama3.2:latest` | `\| ai` model |
| `AGENTSIGHT_AI_CONNECTION` | `ollama_local` | AI Toolkit connection name |

For Foundation-Sec demo on Splunk Cloud, set `AGENTSIGHT_AI_*` to Hosted Models / `foundation-sec-8b-instruct`.

## Synthetic fallback (offline judges only)

```bash
export SPLUNK_PASSWORD='...'
bash scripts/demo_event_generator.sh mcp_tool_loop
```

Events land in `sourcetype=agentsight:demo` — **not** a substitute for real MCP in the submission video.

## Splunk AI capabilities

- **Splunk MCP Server** — real audit ingest
- **`splunklib.ai`** — investigation + explain agents, local tools in `bin/tools.py`
- **`| ai`** — `classify_agent_behavior` (Ollama / Foundation-Sec)
- **Custom alert action** — `agentsight_investigate`
- **Custom commands** — `agentsight_approve`, `agentsight_explain`

## Documentation

| Doc | Description |
|-----|-------------|
| [ARCHITECTURE.md](ARCHITECTURE.md) | Architecture diagram (submission requirement) |
| [docs/agentsight-mvp-spec.md](docs/agentsight-mvp-spec.md) | Full MVP specification |
| [docs/mcp-audit-fieldmap.md](docs/mcp-audit-fieldmap.md) | Verified MCP audit schema |
| [docs/DEMO_VIDEO.md](docs/DEMO_VIDEO.md) | Video recording checklist |
| [apps/agentsight/README.md](apps/agentsight/README.md) | App-level details |

## License

MIT — see [LICENSE](LICENSE).
