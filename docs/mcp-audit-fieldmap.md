# MCP Audit Field Map (Day 0 deliverable)

Verified from live Splunk MCP Server 1.2.0 on `localhost:8089`.

**Platform:** Fedora Linux · Splunk Enterprise at `/opt/splunk` (systemd `Splunkd.service`)

**Status:** MCP call **Verified** | Audit discovery **Verified** (2026-06-09) | `\| ai` **Pass (Ollama)** | Foundation-Sec **deferred** (Splunk Cloud / activation token)

---

## Day 0 MCP integration (verified)

| Property | Value |
|----------|--------|
| **MCP endpoint** | `https://localhost:8089/services/mcp` |
| **Server** | `Splunk_MCP_Server` v1.2.0 |
| **Protocol** | `2025-06-18` Streamable HTTP |
| **Session mode** | **Stateless** (no `Mcp-Session-Id` header returned) |
| **Handshake** | `initialize` -> `notifications/initialized` -> `tools/*` |
| **Primary search tool** | `splunk_run_query` (args: `query`, `earliest_time`, `latest_time`, `row_limit`) |
| **Live call result** | `agentsight_day0=hello from MCP` (1 row) |

### Verified tools (from `tools/list`)

`splunk_get_info`, `splunk_get_indexes`, `splunk_get_index_info`, `splunk_get_user_list`, `splunk_get_user_info`, **`splunk_run_query`**, `splunk_get_metadata`, `splunk_get_kv_store_collections`, `splunk_get_knowledge_objects`, `splunk_run_saved_search`

### Example `tools/call` payload (working)

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "tools/call",
  "params": {
    "name": "splunk_run_query",
    "arguments": {
      "query": "| makeresults count=1 | eval agentsight_day0=\"hello from MCP\" | table agentsight_day0",
      "earliest_time": "-15m",
      "latest_time": "now",
      "row_limit": 10
    }
  }
}
```

### Reproduce

```bash
export SPLUNK_MCP_TOKEN='your-encrypted-token'
export SPLUNK_MCP_URL='https://localhost:8089/services/mcp'
bash scripts/day0_mcp_call.sh
```

### Discovery via MCP (automated)

Same token/session as above; runs Query 1-4 from `scripts/day0_discovery_spl.txt`:

```bash
bash scripts/day0_discovery_mcp.sh
```

Re-run anytime after MCP activity:

```bash
bash scripts/day0_discovery_mcp.sh
```

---

## Where MCP audit lands (verified)

MCP activity splits across **three native landing zones**. No custom `agentsight:mcp_audit` sourcetype exists until you forward or extract.

| Priority | Index | Sourcetype | Source | Use for AgentSight |
|----------|-------|------------|--------|-------------------|
| **Primary** | `_internal` | `mcp_server` | `/opt/splunk/var/log/splunk/mcp_server.log` | Tool calls, user, duration, request_id, RPC method — **best detection source** |
| Secondary | `_internal` | `mcp_monitoring_dashboard` | `/opt/splunk/var/log/splunk/mcp_monitoring_dashboard.log` | `tool_call_complete` telemetry (`is_success`, `execution_time_seconds`) |
| Secondary | `_internal` | `splunkd_access` | `/opt/splunk/var/log/splunk/splunkd_access.log` | HTTP layer; user-agent `Splunk_MCP_Server/1.2.0`; endpoints `/services/mcp`, `/services/search/jobs/export` |
| Complement | `_audit` | `audittrail` | platform audit | Full SPL in `search` field when `action=search` and `info=granted\|completed` |

**Sample `_time` (verified):** `2026-06-08 23:41:11.421 GMT Daylight Time`

### Verified hunt SPL (copy to Search)

**Hero panel — MCP tool calls (recommended primary):**

```spl
index=_internal sourcetype=mcp_server rpc_method=tools/call tool_name=*
| spath
| table _time username tool_name status execution_time_seconds request_id source_ip message
```

**SPL audit trail (complement for query text):**

```spl
index=_audit sourcetype=audittrail action=search (info=completed OR info=granted)
| search search=*splunk_run_query* OR search=*makeresults* OR search=*agentsight_day0*
| table _time user action info search
```

**HTTP / endpoint access:**

```spl
index=_internal sourcetype=splunkd_access "Splunk_MCP_Server"
| rex field=_raw "\"(?<http_method>\w+) (?<uri>[^ ]+) HTTP"
| table _time user http_method uri _raw
```

---

## Field mapping -> `agentsight:mcp_audit`

Verified native fields (normalize at ingest or alias in detections):

| AgentSight field | Primary source | Native field(s) | Verified example |
|------------------|----------------|-----------------|------------------|
| `mcp_user` | `mcp_server` / `_audit` / `splunkd_access` | `username` or `user` | `admin` |
| `mcp_tool` | `mcp_server` | `tool_name` | `splunk_run_query` |
| `spl_query` | `mcp_server` (message) or `_audit` (`search`) | `message` contains `Executing SPL query:`; or `search` | `'search (index=_audit OR index=_internal) ...'` |
| `client_ip` | `mcp_server` / `splunkd_access` | `source_ip` or parse `_raw` | `127.0.0.1` |
| `outcome` | `mcp_server` / `_audit` | `status`, `info`, `is_success` | `200`, `granted`, `completed` |
| `bytes_returned` | `mcp_server` log message | parse `total_rows` from message | `Exact total_rows=20` |
| `duration_ms` | `mcp_server` | `execution_time_seconds` * 1000 | `1452` (from `1.452`) |
| `session_id` | `mcp_server` | `request_id` | `749d98256e81` |
| `rpc_method` | `mcp_server` | `rpc_method` | `tools/call` |
| `auth_method` | `mcp_server` | `auth_method` | `token` |

**Extract SPL from `mcp_server` message:**

```spl
index=_internal sourcetype=mcp_server message="Executing SPL query:*"
| rex field=message "Executing SPL query: (?<spl_query>.+?) \\("
| table _time username tool_name spl_query execution_time_seconds request_id
```

---

## Ingest path to `index=agentsight`

| Method | Config location | Tested? |
|--------|-----------------|---------|
| Search directly on `_internal` `mcp_server` | Detection saved searches | **Recommended MVP (primary)** |
| Search on `_audit` `audittrail` for SPL text | Complement / correlation | Verified |
| Saved search \| output | `savedsearches.conf` -> `index=agentsight` | Not yet |
| HEC forward normalized events | HEC token + transform | Not yet |

**Chosen path (hackathon MVP):** Run AgentSight detections on **`index=_internal sourcetype=mcp_server`** (tool-level) plus **`index=_audit sourcetype=audittrail action=search`** (SPL text). Normalize to `agentsight:mcp_audit` later via saved search output — do not block build on custom index.

---

## Starter detection SPL (verified fields)

**Rule 1 — MCP query burst (hero demo):**

```spl
index=_internal sourcetype=mcp_server rpc_method=tools/call tool_name=splunk_run_query
| spath
| bin _time span=10m
| stats count as tool_calls by _time username tool_name
| where tool_calls >= 5
```

**Rule 2 — sensitive index probe via MCP (needs `_audit` join or parallel search):**

```spl
index=_audit sourcetype=audittrail action=search info=completed
| rex field=search "index=(?<target_index>[a-zA-Z0-9_*-]+)"
| search target_index=_audit OR target_index=_internal OR target_index=*password*
| stats count by user target_index search
```

**Hero timeline panel:**

```spl
index=_internal sourcetype=mcp_server rpc_method=tools/call
| spath
| eval duration_ms=round(execution_time_seconds*1000,0)
| table _time username tool_name status duration_ms request_id source_ip
| sort - _time
```

---

## Kill-switch #2 — Foundation-Sec pre-flight

**Symptom:** `Unknown search command 'ai'` — the `| ai` command is **not built into Splunk**. It comes from the **AI Toolkit** app (Splunkbase). Your MCP path is fine; this is a separate install.

### Fix (on-prem Splunk Enterprise)

1. **Install prerequisites** (Splunkbase, match your Splunk version):
   - [Python for Scientific Computing (PSC)](https://splunkbase.splunk.com/app/2882) add-on
   - [Splunk AI Toolkit](https://splunkbase.splunk.com/app/2890) **5.7.0 or higher** (for `| ai` + Splunk Hosted Models / Foundation-Sec)
2. **Restart Splunk** after install.
3. **Grant capability** to `admin` (or your user):
   - Settings → Users and Authentication → Roles → **admin** → Capabilities
   - Enable **`apply_ai_commander_command`** (or inherit **mltk_admin** role)
4. **Configure LLM connection** (AI Toolkit app → **Connections** → Add connection):
   - Provider: **Splunk Hosted Models** (AI Toolkit 5.7+)
   - Model: **Llama-3.1-FoundationAI-SecurityLLM-base-1.1-8B** (Foundation-Sec)
   - On-prem may require **Splunk AI Assistant** cloud activation / tenant token — see hackathon Slack if Hosted Models is unavailable locally.

### "Splunk Hosted Models" → No providers found

This is expected on many **on-prem dev licenses** until cloud services are linked.

| Step | Action |
|------|--------|
| 1 | Clear the search box — click **+ Connection → LLM** and browse the full provider list (OpenAI, Ollama, Groq, …). Do not type in the filter first. |
| 2 | Settings → Roles → **admin** → add **`list_tokens_scs`** (required to *see* Splunk Hosted Models). Log out/in. |
| 3 | If Hosted Models still missing: your stack is not SCS-linked. **Hackathon demo** → Splunk **Cloud** trial with Hosted Models; **local build** → use Ollama or OpenAI below. |
| 4 | **Custom LLM connection** only if you have an OpenAI-compatible endpoint URL + key — not the same as Splunk Hosted Models. |

**Local dev unblock (Ollama — not for final Foundation-Sec demo):**

1. Install [Ollama](https://ollama.com) → `ollama pull llama3.2`
2. AI Toolkit → **+ Connection → LLM → Ollama** → base URL `http://127.0.0.1:11434`
3. Pre-flight:

```spl
| makeresults count=1
| eval prompt="Classify this MCP agent behavior: 15 identical splunk_run_query calls in 10 minutes."
| ai provider=Ollama model=llama3.2 prompt="$prompt$"
```

**Recommended hackathon split:** build AgentSight detections on **local** Splunk (MCP verified); record **Foundation-Sec** classification on **Splunk Cloud** where Hosted Models is native.

### "Failed to fetch config metadata" (Create Connection modal empty)

The UI calls a backend REST/KV endpoint to load provider field schemas. When that fails, **Connection settings** and **Model** dropdowns stay blank.

**Fix checklist (in order):**

1. **Inherit `mltk_admin` on admin** (not just one capability):
   - Settings → Users → Roles → **admin** → **Inherited roles** → add **`mltk_admin`** → Save
   - Log out and back in
2. **Confirm PSC installed** — [Python for Scientific Computing](https://splunkbase.splunk.com/app/2882) matching your Splunk version (AI Toolkit requires it).
3. **Restart Splunk** after installing/upgrading AI Toolkit or PSC.
4. **Verify backend from Search** (as admin):

```spl
| rest splunk_server=local /servicesNS/nobody/Splunk_ML_Toolkit/storage/collections/data/mltk_ai_commander_collection count=0
| table title
```

| Result | Meaning |
|--------|---------|
| Row returned | KV collection OK — retry Connections UI |
| 403 / permission | Add `edit_ai_commander_config` + inherit `mltk_admin` |
| 404 / empty | AI Toolkit incomplete — reinstall MLTK 5.7+ and restart |

5. **Check logs** on the Splunk host:
   - `/opt/splunk/var/log/splunk/mlspl.log`
   - `/opt/splunk/var/log/splunk/splunkd.log` (grep `mltk`, `ai_commander`, `metadata`)

6. **Avoid Custom LLM first** — after fix, use **+ Connection → LLM → Ollama** (or OpenAI) from the provider list, not Custom, until metadata loads.

**If `mltk_admin` is inherited and error persists** — this is almost always **PSC missing/mismatched** or **KV Store broken** on Windows (not permissions).

Run diagnostics in [`scripts/day0_mltk_diagnose.spl`](../scripts/day0_mltk_diagnose.spl). Expected:

| Check | Good | Bad → fix |
|-------|------|-----------|
| PSC app in apps/local | `Splunk_SA_Scientific_Python_linux_x86_64` enabled | Install PSC matching Splunk version from Splunkbase into `/opt/splunk/etc/apps/` |
| KV Store status | `status=ready` | Settings → Server settings → KV Store; restart Splunk; check `splunkd.log` for mongod |
| `mltk_ai_commander_collection` | Returns `_key` row | Reinstall AI Toolkit 5.7+; restart |
| Browser Network tab on Create Connection | 200 on metadata REST call | Note failing URL + status; grep same path in `mlspl.log` |

**Windows PSC fix (Splunk doc):** if PSC was upgraded 3.1→3.2+, run from MLTK app dir:

```text
python rename_old_psc_conflicts.py "/opt/splunk"
```

Then `splunk restart`.

**Do not stay blocked:** AgentSight MCP detections are **Go**. Use **Splunk Cloud** for Foundation-Sec demo if local Connections cannot be fixed in ~1 hour.

**If still broken after restart:** proceed with AgentSight MCP detections locally; use **Splunk Cloud** for `\| ai` / Foundation-Sec demo (hackathon Slack for trial stack).
5. **Verify** the command exists:

```spl
| rest /servicesNS/nobody/Splunk_ML_Toolkit/configs/conf-commands/ai
| table title disabled
```

### Pre-flight SPL (correct model name — **sec**, not smc)

```spl
| makeresults count=1
| eval prompt="Classify this MCP agent behavior: 15 identical splunk_run_query calls in 10 minutes."
| ai provider="Splunk Hosted Models" model="Llama-3.1-FoundationAI-SecurityLLM-base-1.1-8B" prompt="$prompt$"
```

Shorthand (if your AI Toolkit maps the alias):

```spl
| makeresults count=1
| eval prompt="Classify this MCP agent behavior: 15 identical splunk_run_query calls in 10 minutes."
| ai model=foundation-sec-8b-instruct prompt="$prompt$"
```

| Result | Action |
|--------|--------|
| Returns classification text | **Pass** — use same model in AgentSight alert action / `\| agentsight_explain` demo |
| Still `Unknown search command 'ai'` | AI Toolkit not installed or Splunk not restarted |
| `You do not have permission...` | Add `apply_ai_commander_command` to role |
| Provider / model error | Configure Connections tab; try Splunk Cloud trial stack for hackathon demo |
| Hosted Models unavailable on-prem | Escalate via hackathon Slack **or** dev-only Ollama fallback (not for final demo) |

**Parallel path:** AgentSight **`splunklib.ai` alert action** can call Foundation-Sec from Python without `\| ai` in the search bar — but judges expect live `\| ai` or equivalent in demo; still install AI Toolkit.

---

## Go / no-go

| Check | Pass? |
|-------|-------|
| MCP Server app installed | Yes |
| Live MCP initialize + tools/list | Yes |
| Live `splunk_run_query` call | Yes |
| Stateless mode documented | Yes |
| Audit event visible in `_audit` / `_internal` | Yes |
| `tool_name` / `splunk_run_query` in `mcp_server` | Yes |
| SPL text in `_audit.search` or `mcp_server.message` | Yes |
| Foundation-Sec pre-flight | **Deferred** — use **Ollama** locally (`ollama_local`); Foundation-Sec on Splunk Cloud for video |
| `\| ai` Ollama pre-flight | **Pass** (2026-06-09) — use `prompt="'{prompt}'"` syntax |
| AgentSight app | **Built** — detections, investigate, dashboard, explain |

**Decision:** **Go** — build and demo on Fedora with Ollama; splice Foundation-Sec clip from Cloud for submission (see [docs/DEMO_VIDEO.md](DEMO_VIDEO.md)).

---

## Sample raw event

### MCP tools/call response (verified Step 4)

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": {
    "content": [{
      "type": "text",
      "text": "{\"results\":[{\"agentsight_day0\":\"hello from MCP\"}],\"truncated\":false,\"total_rows\":1}"
    }],
    "structuredContent": {
      "results": [{"agentsight_day0": "hello from MCP"}],
      "truncated": false,
      "total_rows": 1
    }
  }
}
```

### `mcp_server` tool call complete (verified Query 3)

```json
{
  "time": "2026-06-08T22:41:11.421Z",
  "level": "INFO",
  "logger": "pschand__mcp_server__in_D__splunk_etc_apps_Splunk_MCP_Server_bin",
  "pid": 17264,
  "message": "Response sent, status=200",
  "source_ip": "127.0.0.1",
  "request_id": "749d98256e81",
  "app_version": "1.2.0",
  "auth_method": "token",
  "rpc_method": "tools/call",
  "rpc_id": 10,
  "operation_type": "rpc_request",
  "operation_phase": "end",
  "username": "admin",
  "user_id": "8c6976e5b5410415",
  "tool_name": "splunk_run_query",
  "status": 200,
  "execution_time_seconds": 1.452
}
```

### `_audit` search granted with SPL (verified Query 2 / 4)

| Field | Value |
|-------|-------|
| `_time` | `2026-06-08 23:41:10.258 GMT Daylight Time` |
| `index` | `_audit` |
| `sourcetype` | `audittrail` |
| `user` | `admin` |
| `action` | `search` |
| `info` | `granted` |
| `search` | `'search (index=_audit OR index=_internal OR index=main) (mcp OR MCP OR "services/mcp" OR splunk_run_query OR "Splunk_MCP" OR agentsight_day0) \| head 20 \| table _time index sourcetype source user action info search \| head 1001 \| export ...'` |

### `splunkd_access` MCP HTTP (verified Query 3)

```
127.0.0.1 - admin [08/Jun/2026:23:41:10.170 +0100] "POST /services/search/jobs/export HTTP/1.1" 200 4137 "-" "Splunk_MCP_Server/1.2.0" - - - 1242ms
```
