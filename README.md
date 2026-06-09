# AgentSight

**Splunk watches the agents that use Splunk.**

Observability for the autonomous workforce touching your Splunk data — built for the [Splunk Agentic Ops Hackathon](https://splunk.devpost.com/) (**Security** track).

AgentSight ingests **real Splunk MCP Server audit telemetry**, detects agent/MCP-specific misbehavior, investigates with **`splunklib.ai`**, classifies via **`| ai`** (Ollama locally / Foundation-Sec on Cloud for demo), and supports async analyst approval plus **`| agentsight_explain`** in the search bar.

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

## Quick install

```bash
git clone <your-repo-url> agentsight
cd agentsight

# Install app (symlink recommended for development)
sudo ln -sf "$(pwd)/apps/agentsight" /opt/splunk/etc/apps/agentsight
sudo chown -h splunk:splunk /opt/splunk/etc/apps/agentsight

# Python deps for splunklib.ai in custom commands / alert action
python3 -m pip install -r apps/agentsight/requirements.txt -t apps/agentsight/bin/lib

# Restart Splunk (systemd-managed installs)
sudo systemctl restart Splunkd.service
```

## Day 0 verification

```bash
export SPLUNK_MCP_TOKEN='your-encrypted-mcp-token'
export SPLUNK_MCP_URL='https://localhost:8089/services/mcp'

bash scripts/day0_mcp_call.sh
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

1. **MCP burst** — generate real audit traffic:

   ```bash
   export SPLUNK_MCP_TOKEN='...'
   bash scripts/demo_mcp_burst.sh
   ```

2. **Normalize** (optional) — run saved search **AgentSight - Normalize MCP Audit**

3. **Detect** — run **AgentSight - MCP Tool Loop** (or wait for scheduled alert)

4. **Investigate** — enable alert action **AgentSight Investigate** on the detection search

5. **Dashboard** — open **AgentSight** app → approve pending action

6. **Explain**:

   ```spl
   index=agentsight sourcetype=agentsight:case
   | head 1
   | agentsight_explain case_id=case_XXXXXXXX
   ```

7. **Verify**:

   ```spl
   index=agentsight sourcetype=agentsight:* earliest=-1h
   | stats count by sourcetype
   ```

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
python3 apps/agentsight/bin/demo_event_generator.py mcp_tool_loop
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
