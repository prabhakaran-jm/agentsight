<div align="center">

# AgentSight

**Splunk watches the agents that use Splunk.**

Observability for MCP agents and autonomous clients hitting your Splunk data — built for the [Splunk Agentic Ops Hackathon](https://splunk.devpost.com/) (**Security** track).

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](LICENSE)
[![Hackathon](https://img.shields.io/badge/Splunk-Agentic%20Ops%20Hackathon-65A637?style=flat-square&logo=splunk&logoColor=white)](https://splunk.devpost.com/)
[![Track](https://img.shields.io/badge/Track-Security-FF4B4B?style=flat-square)](https://splunk.devpost.com/)
[![Splunk Enterprise](https://img.shields.io/badge/Splunk-Enterprise%209%2B-65A637?style=flat-square&logo=splunk&logoColor=white)](https://www.splunk.com/)
[![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20Windows-4A5568?style=flat-square)](#install)
[![MCP Server](https://img.shields.io/badge/MCP-Server%20audit-5865F2?style=flat-square)](https://splunkbase.splunk.com/app/7931)
[![splunklib.ai](https://img.shields.io/badge/splunklib.ai-investigation-0078D4?style=flat-square)](#splunk-ai-capabilities)
[![Splunk AI Toolkit](https://img.shields.io/badge/%7C%20ai-Foundation--Sec%20%2F%20Ollama-9333EA?style=flat-square)](#foundation-sec-path-a--do-this-first)

[Architecture](#architecture) · [Install](#install) · [First demo](#first-demo-10-minutes) · [Judge quickstart](#judge-quickstart-live-demo-loop) · [Scripts](scripts/README.md)

</div>

---

AgentSight ingests **real Splunk MCP Server audit telemetry**, detects agent/MCP-specific misbehavior, investigates with **`splunklib.ai`**, classifies via **`| ai`** with **Foundation-Sec open weights in Ollama** (Path A — one-machine demo), and supports async analyst approval plus **`| agentsightexplain`** in the search bar.

## Table of contents

- [What you can do](#what-you-can-do-with-this)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Install](#install)
- [Foundation-Sec (Path A)](#foundation-sec-path-a--do-this-first)
- [First demo](#first-demo-10-minutes)
- [MCP audit discovery](#mcp-audit-discovery)
- [Judge quickstart](#judge-quickstart-live-demo-loop)
- [Environment variables](#environment-variables)
- [Splunk AI capabilities](#splunk-ai-capabilities)
- [Detect → investigate → contain](#detect--investigate--contain)
- [Scripts](#scripts)
- [Documentation](#documentation)
- [License](#license)

## What you can do with this

| You want to… | Where / how |
|--------------|-------------|
| See MCP agents querying Splunk | **AgentSight** app → dashboard → *MCP Activity Timeline* |
| Simulate a rogue agent (demo) | `bash scripts/sh/demo_mcp_burst.sh` |
| Detect runaway tool loops | Saved search **AgentSight - MCP Tool Loop** |
| Detect MCP data exfiltration SPL | Saved search **AgentSight - MCP Data Exfiltration** |
| Detect prompt-injection payloads | Saved search **AgentSight - MCP Prompt Injection** |
| Auto-investigate with AI | Alert action **AgentSight Investigate** on detection searches |
| Approve or deny a proposed fix | **Approve Actions** view → click queued row → Submit |
| Quarantine a rogue agent (revoke tokens) | Approve a `quarantine` action → `agentsightapprove` revokes the agent's Splunk tokens |
| Get a plain-English case summary | Search: `\| agentsightexplain case_id=case_XXXXXXXX` |

The dashboard shows live MCP traffic from `index=_internal sourcetype=mcp_server`. **Cases and approvals only appear after** you run a detection and the investigate alert action fires.

### Judges: detection rules are not scheduled by default

All five detection saved searches ship with **`enableSched = 0`** so installs stay quiet. To see an alert in under two minutes:

1. Run `bash scripts/sh/demo_mcp_burst.sh` (or any MCP activity).
2. **Settings → Searches, reports, and alerts** → open **AgentSight - MCP Tool Loop** → **Open in Search** → **Run**.
3. Enable alert action **AgentSight Investigate** on that search, then trigger the alert (or run **AgentSight Investigate** manually via the saved search alert).

To run hands-free during a demo, enable the schedule on each detection rule in Settings, or set `enableSched = 1` in `$SPLUNK_HOME/etc/apps/agentsight/local/savedsearches.conf` and restart Splunk.

## Architecture

See [architecture_diagram.md](architecture_diagram.md) for the system diagram and data flow.

```text
MCP agents ──► Splunk MCP Server audit ──► AgentSight detections
      │                                              │
      └──────────────────────────────────► splunklib.ai investigate
                                                      │
                                              analyst approve / explain
                                                      │
                                              agentsight index + dashboard
```

## Prerequisites

| Component | Splunkbase / source |
|-----------|---------------------|
| Splunk Enterprise 9.x or 10.x | — |
| [Splunk MCP Server](https://splunkbase.splunk.com/app/7931) | MCP audit source |
| [Python for Scientific Computing](https://splunkbase.splunk.com/app/2882) | AI Toolkit dependency |
| [Splunk AI Toolkit](https://splunkbase.splunk.com/app/2890) 5.7+ | `\| ai` command |
| [Splunk AI Assistant](https://splunkbase.splunk.com/app/7245) (recommended) | Analyst NL → SPL after a case opens (video beat: read-only follow-up queries) |
| [Ollama](https://ollama.com) + [Foundation-Sec GGUF](https://huggingface.co/gabriellarson/Foundation-Sec-8B-Instruct-GGUF) | Chat + classify (Path A) |
| `splunk-sdk[ai]` | Agent + tools (see below) |

## Install

```bash
git clone https://github.com/prabhakaran-jm/agentsight.git agentsight
cd agentsight

# Python deps — MUST use Splunk's Python, not system python3 (Fedora 3.14 ≠ Splunk 3.9/3.11)
bash scripts/sh/install_agentsight_deps.sh

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

### Windows (Splunk Enterprise on localhost)

```powershell
# Recommended: sync from repo (preserves bin/lib after pip install)
.\scripts\ps1\sync_agentsight_to_splunk.ps1
.\scripts\ps1\install_agentsight_deps.ps1
& "$env:SPLUNK_HOME\bin\splunk.exe" restart
```

Or copy manually:

```powershell
$SPLUNK_HOME = "D:\splunk"   # or set $env:SPLUNK_HOME if installed elsewhere
$REPO = "C:\path\to\agentsight\apps\agentsight"

Remove-Item -Recurse -Force "$SPLUNK_HOME\etc\apps\agentsight" -ErrorAction SilentlyContinue
Copy-Item -Recurse $REPO "$SPLUNK_HOME\etc\apps\agentsight"
.\scripts\ps1\install_agentsight_deps.ps1 -SplunkHome $SPLUNK_HOME
& "$SPLUNK_HOME\bin\splunk.exe" restart
```

Open: **http://localhost:8000/en-US/app/agentsight/agentsight_dashboard** — then **http://localhost:8000/en-US/_bump** after icon updates.

Rebuild launcher icons: `python scripts/build_app_icons.py` → redeploy app → restart → `_bump`.

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
| Empty MCP timeline | No MCP traffic yet — run `bash scripts/sh/demo_mcp_burst.sh` |
| Investigate / explain errors | Run `bash scripts/sh/install_agentsight_deps.sh`; confirm Ollama is running |
| `Unknown search command 'agentsightapprove'` | Run `bash scripts/sh/install_agentsight_app.sh` and `bash scripts/sh/verify_commands.sh`; restart Splunk |
| Stretched / white launcher icon | Run `python scripts/build_app_icons.py` and redeploy `static/` |

## Foundation-Sec (Path A — do this first)

Hosted Foundation-Sec runs on **Splunk Cloud only**. For a single-machine submission demo, pull open weights into Ollama:

```bash
bash scripts/sh/setup_foundation_sec_ollama.sh
```

Then set classify model (defaults in `apps/agentsight/default/ai.conf`):

```bash
export AGENTSIGHT_AI_MODEL='hf.co/gabriellarson/Foundation-Sec-8B-Instruct-GGUF:Q8_0'
export AGENTSIGHT_AI_PROVIDER='Ollama'
export AGENTSIGHT_AI_CONNECTION='ollama_local'
```

**Two-model split:** `splunklib.ai` investigation agent needs **tool calling** → default `AGENTSIGHT_OLLAMA_CHAT_MODEL=llama3.2:latest`. Foundation-Sec runs in **`classify_agent_behavior`** via `| ai` (not as the tool-orchestration chat model).

Optional **Path B** (≤1 day): Splunk Cloud trial clip with **Splunk Hosted Models** visible — same prompt, ~15 seconds.

## First demo (10 minutes)

**Windows automation:**

```powershell
$env:SPLUNK_MCP_TOKEN = "mcp-demo-agent-token"
$env:SPLUNK_PASSWORD  = "admin-password"
.\scripts\ps1\demo_mode.ps1 -Enable              # optional: fast investigate + explain
.\scripts\ps1\run_demo_loop.ps1                  # burst → detect → investigate → approve → explain
# prep: .\scripts\ps1\run_demo_loop.ps1 -SyncFirst -DemoMode -EnsureOllama
```

**1. Confirm MCP works**

```bash
export SPLUNK_MCP_TOKEN='your-encrypted-mcp-token'
export SPLUNK_MCP_URL='https://localhost:8089/services/mcp'
bash scripts/sh/mcp_smoke_test.sh
```

**2. Generate rogue-agent traffic**

```bash
bash scripts/sh/demo_mcp_burst.sh
```

**3. Refresh the AgentSight dashboard** — *MCP Activity Timeline* should show `splunk_run_query` spikes in the last 30 minutes.

**4. Run the detection** — Splunk Web → **Settings → Searches, reports, and alerts** → open **AgentSight - MCP Tool Loop** → **Open in Search** → run. You should see a hit (≥5 calls in 10m).

**5. Investigate** — On that saved search, ensure alert action **AgentSight Investigate** is enabled. Run the search as an alert (or trigger manually). Then:

```spl
index=agentsight sourcetype=agentsight:case earliest=-1h
| table _time case_id trigger_rule severity status actor classification
```

**6. Approve** — **AgentSight → Approve Actions** → click a row in *Queued actions* → **Submit**.

**7. Explain**

```spl
| agentsightexplain case_id=case_XXXXXXXX
```

## MCP audit discovery

```bash
bash scripts/sh/discover_mcp_audit.sh
```

In Splunk Search, run queries from `scripts/sh/discover_mcp_audit.spl.txt`.

AI Toolkit pre-flight (Foundation-Sec classify model):

```spl
| makeresults count=1
| eval prompt="Classify this MCP agent behavior: 15 identical splunk_run_query calls in 10 minutes."
| ai provider=Ollama model="hf.co/gabriellarson/Foundation-Sec-8B-Instruct-GGUF:Q8_0" connection=ollama_local prompt="'$prompt$'"
```

Audit fields: `index=_internal sourcetype=mcp_server` — `username`, `tool_name`, `rpc_method`, `status`, `request_id` (via `| spath`).

## Judge quickstart (live demo loop)

1. **MCP burst** — `bash scripts/sh/demo_mcp_burst.sh`
2. **Normalize** (optional) — saved search **AgentSight - Normalize MCP Audit**
3. **Detect** — **AgentSight - MCP Tool Loop**
4. **Investigate** — alert action **AgentSight Investigate**
5. **Dashboard** — approve pending action
6. **Explain** — `| agentsightexplain case_id=...`
7. **Verify** — `index=agentsight sourcetype=agentsight:* earliest=-1h | stats count by sourcetype`

Saved searches ship with `enableSched = 0`. Enable schedules in **Settings → Searches** or set `enableSched = 1` in `local/savedsearches.conf` for hands-free alerts.

## Environment variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `SPLUNK_MCP_TOKEN` | — | MCP encrypted token |
| `SPLUNK_MCP_URL` | `https://localhost:8089/services/mcp` | MCP endpoint |
| `AGENTSIGHT_OLLAMA_URL` | `http://127.0.0.1:11434/v1` | Agent chat model |
| `AGENTSIGHT_OLLAMA_CHAT_MODEL` | `llama3.2:latest` | `splunklib.ai` agent (must support tools) |
| `AGENTSIGHT_AI_PROVIDER` | `Ollama` | `\| ai` in classify tool |
| `AGENTSIGHT_AI_MODEL` | `hf.co/gabriellarson/Foundation-Sec-8B-Instruct-GGUF:Q8_0` | `\| ai` classify model |
| `AGENTSIGHT_AI_CONNECTION` | `ollama_local` | AI Toolkit connection name |

For Path B (Splunk Cloud clip), set `AGENTSIGHT_AI_*` to Hosted Models / `foundation-sec-8b-instruct`. Path A (Ollama + Foundation-Sec GGUF) is the primary end-to-end demo.

## Synthetic fallback (offline judges only)

```bash
export SPLUNK_PASSWORD='...'
bash scripts/sh/demo_event_generator.sh mcp_tool_loop
```

Events land in `sourcetype=agentsight:demo` — **not** a substitute for real MCP in the submission video.

## Splunk AI capabilities

- **Splunk MCP Server** — real audit ingest (`saia_*` tools when SAIA is installed)
- **`splunklib.ai`** — investigation + explain agents, local tools in `bin/tools.py`
- **`| ai`** — `classify_agent_behavior` (Ollama / Foundation-Sec)
- **Splunk AI Assistant** — human analyst copilot for ad-hoc SPL after AgentSight opens a case
- **Custom alert action** — `agentsight_investigate`
- **Custom commands** — `agentsightapprove`, `agentsightexplain`
- **Automated response** — `revoke_user_tokens` (Splunk REST `authorization/tokens`) quarantines a rogue agent on analyst approval

## Detect → investigate → contain

AgentSight is not detection-only. Five agent-native detections feed one investigation agent, and critical cases (scope violation, data exfiltration, prompt injection) queue a **quarantine** action. On analyst approval, `agentsightapprove` calls Splunk's `authorization/tokens` REST endpoint to revoke the rogue agent's tokens — its next MCP call fails auth, visible live on the MCP Activity Timeline. Containment **never** runs without human approval (governance by design), mirroring the `_FORBIDDEN_SPL` guard the investigation agent applies to itself.

**Quarantine safety:** never approve quarantine on `admin` — you will revoke your own session tokens. Use a dedicated Splunk user such as `mcp-demo-agent` for quarantine demos.

## Scripts

Layout: **`scripts/sh/`** (Linux/macOS bash) · **`scripts/ps1/`** (Windows PowerShell) · **`scripts/build_app_icons.py`** (cross-platform).

### Install and verify

| Script | Purpose |
|--------|---------|
| `scripts/sh/install_agentsight_deps.sh` | Python deps into Splunk app (Linux) |
| `scripts/ps1/install_agentsight_deps.ps1` | Python deps into Splunk app (Windows) |
| `scripts/ps1/sync_agentsight_to_splunk.ps1` | Deploy app to `$SPLUNK_HOME` (Windows) |
| `scripts/sh/install_agentsight_app.sh` | Copy app to `/opt/splunk` (Linux) |
| `scripts/sh/verify_commands.sh` | Custom SPL commands registered |
| `scripts/sh/setup_foundation_sec_ollama.sh` | Pull Foundation-Sec into Ollama |

### Demo traffic and loop

| Script | Purpose |
|--------|---------|
| `scripts/sh/demo_mcp_burst.sh` / `scripts/ps1/demo_mcp_burst.ps1` | Rule 1 — MCP Tool Loop |
| `scripts/sh/demo_mcp_scope_violation.sh` | Rule 2 — scope violation (quarantine) |
| `scripts/sh/demo_mcp_exfil_probe.sh` | Rule 4 — data exfiltration SPL |
| `scripts/sh/demo_mcp_injection_probe.sh` | Rule 5 — prompt-injection signatures |
| `scripts/sh/mcp_smoke_test.sh` / `scripts/ps1/mcp_smoke_test.ps1` | Single MCP call smoke test |
| `scripts/ps1/run_demo_loop.ps1` | Full Windows loop (burst → explain) |
| `scripts/sh/run_investigate.sh` / `scripts/ps1/run_investigate.ps1` | Trigger investigate |
| `scripts/ps1/finish_case.ps1` | Approve + explain an existing case |
| `scripts/ps1/demo_mode.ps1` | Enable/disable fast demo mode |
| `scripts/sh/demo_event_generator.sh` | Synthetic offline events (not for video) |

## Documentation

| Doc | Description |
|-----|-------------|
| [architecture_diagram.md](architecture_diagram.md) | Architecture diagram (submission requirement) |
| [apps/agentsight/README.md](apps/agentsight/README.md) | App-level details |

## License

<div align="center">

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

MIT — see [LICENSE](LICENSE).

</div>
