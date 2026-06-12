# Scripts

| Folder | Platform | Run from repo root |
|--------|----------|-------------------|
| [`sh/`](sh/) | Linux / macOS (bash) | `bash scripts/sh/<name>.sh` |
| [`ps1/`](ps1/) | Windows (PowerShell) | `.\scripts\ps1\<name>.ps1` |

**Shared:** [`build_app_icons.py`](build_app_icons.py) — regenerate Splunk launcher icons (requires Pillow).

## Quick start

**Linux**

```bash
bash scripts/sh/install_agentsight_deps.sh
bash scripts/sh/install_agentsight_app.sh
bash scripts/sh/mcp_smoke_test.sh
bash scripts/sh/demo_mcp_burst.sh
```

**Windows**

```powershell
.\scripts\ps1\sync_agentsight_to_splunk.ps1
.\scripts\ps1\install_agentsight_deps.ps1
$env:SPLUNK_MCP_TOKEN = "..."; $env:SPLUNK_PASSWORD = "..."
.\scripts\ps1\run_demo_loop.ps1 -SyncFirst -DemoMode -EnsureOllama
```

See the main [README](../README.md) for the full demo loop and judge quickstart.
