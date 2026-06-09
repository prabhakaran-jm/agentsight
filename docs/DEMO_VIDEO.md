# AgentSight Demo Video Checklist

Target: **under 3 minutes** for [Splunk Agentic Ops Hackathon](https://splunk.devpost.com/) submission.

**Pitch:** *An agent goes rogue live → Splunk watches itself watch that agent → explains it in SPL.*

## Pre-flight

- [ ] Splunk running (`sudo systemctl status Splunkd.service`)
- [ ] MCP Server app enabled; `SPLUNK_MCP_TOKEN` exported
- [ ] Ollama running; AI Toolkit `ollama_local` connection + `| ai` pre-flight pass
- [ ] AgentSight app installed (symlink to `etc/apps/agentsight`)
- [ ] `python3 -m pip install -r apps/agentsight/requirements.txt -t apps/agentsight/bin/lib`
- [ ] Dashboard open: `/app/agentsight/agentsight_dashboard`

## Recording script (~2:30)

| Time | Scene | Action |
|------|-------|--------|
| 0:00 | Title | "AgentSight — Splunk watches the agents that use Splunk" |
| 0:15 | Problem | MCP agents query Splunk autonomously; who watches them? |
| 0:30 | Live loop | `bash scripts/demo_mcp_burst.sh` — hero timeline spikes |
| 0:50 | Detect | Show **AgentSight - MCP Tool Loop** result or alert fired |
| 1:10 | Investigate | Case in `index=agentsight sourcetype=agentsight:case` |
| 1:30 | Approve | Dashboard: approve queued action |
| 1:50 | Explain | `\| agentsight_explain case_id=...` in search bar |
| 2:10 | Foundation-Sec | Clip from Splunk Cloud with `foundation-sec-8b-instruct` (if local Ollama only for build) |
| 2:30 | Close | Security track; MCP Server + splunklib.ai + Hosted Models |

## Foundation-Sec clip (optional splice)

```spl
| makeresults count=1
| eval prompt="Classify this MCP agent behavior: 15 identical splunk_run_query calls in 10 minutes."
| ai model=foundation-sec-8b-instruct prompt="'{prompt}'"
```

Record on Splunk Cloud if Enterprise dev license lacks Hosted Models.

## Submission

- [ ] Upload to YouTube/Vimeo (public)
- [ ] Devpost: repo URL, architecture diagram (`ARCHITECTURE.md`), video link
- [ ] Label synthetic path in README if judges lack MCP (`demo_event_generator.py`)
