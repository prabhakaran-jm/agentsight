# SPDX-License-Identifier: MIT
"""AgentSight local tools for splunklib.ai investigation agent."""

from __future__ import annotations

import json
import os
import re
import uuid
from datetime import datetime, timezone
from typing import Any

from splunklib.ai.registry import ToolContext, ToolRegistry
from splunklib.results import JSONResultsReader

registry = ToolRegistry()

# In-process pending actions keyed by case_id (alert action is single-process).
_PENDING_ACTIONS: dict[str, list[dict[str, str]]] = {}

_FORBIDDEN_SPL = re.compile(
    r"\b("
    r"collect|outputlookup|inputlookup|delete|sendemail|script|runshellscript|"
    r"meventcollect|tscollect|dbxquery|run\s|multisearch"
    r")\b",
    re.IGNORECASE,
)

_INDEX = "agentsight"


def _utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _escape_spl_string(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def _load_ai_config() -> dict[str, str]:
    return {
        "provider": os.environ.get("AGENTSIGHT_AI_PROVIDER", "Ollama"),
        "model": os.environ.get("AGENTSIGHT_AI_MODEL", "llama3.2:latest"),
        "connection": os.environ.get("AGENTSIGHT_AI_CONNECTION", "ollama_local"),
    }


def _submit_event(ctx: ToolContext, sourcetype: str, event: dict[str, Any]) -> None:
    payload = json.dumps(event, default=str)
    ctx.service.indexes[_INDEX].submit(payload, sourcetype=f"agentsight:{sourcetype}")


def _oneshot_json(
    ctx: ToolContext,
    spl: str,
    earliest: str = "-1h",
    latest: str = "now",
) -> tuple[str | None, list[dict[str, Any]]]:
    """Run oneshot search; return (sid if available, result rows)."""
    job = ctx.service.jobs.oneshot(
        spl,
        earliest_time=earliest,
        latest_time=latest,
        output_mode="json",
    )
    rows: list[dict[str, Any]] = []
    for item in JSONResultsReader(job):
        if isinstance(item, dict):
            rows.append(item)
    sid = rows[0].get("sid") if rows else None
    return sid, rows


def _validate_readonly_spl(spl: str) -> None:
    if _FORBIDDEN_SPL.search(spl):
        raise ValueError("SPL contains disallowed mutating or unsafe commands")


@registry.tool()
def get_alert_context(
    ctx: ToolContext,
    trigger_rule: str,
    session_id: str | None = None,
    actor: str | None = None,
) -> dict[str, Any]:
    """Load recent MCP audit events for alert context (max 20 rows)."""
    filters: list[str] = []
    if actor:
        filters.append(f'username="{_escape_spl_string(actor)}"')
    if session_id:
        filters.append(f'request_id="{_escape_spl_string(session_id)}"')
    filter_clause = " OR ".join(filters) if filters else "username=*"

    mcp_spl = (
        "index=_internal sourcetype=mcp_server rpc_method=tools/call earliest=-1h "
        "| spath "
        f"| search {filter_clause} "
        "| head 20 "
        "| table _time username tool_name status execution_time_seconds request_id source_ip message"
    )
    _, mcp_rows = _oneshot_json(ctx, mcp_spl)

    norm_spl = (
        f"index={_INDEX} sourcetype=agentsight:mcp_audit earliest=-1h "
        f"| search mcp_user=\"{_escape_spl_string(actor or '*')}\" "
        "| head 20 "
        "| table _time mcp_user mcp_tool session_id spl_query outcome duration_ms"
    )
    _, norm_rows = _oneshot_json(ctx, norm_spl)

    return {
        "trigger_rule": trigger_rule,
        "actor": actor,
        "session_id": session_id,
        "mcp_server_events": mcp_rows,
        "normalized_events": norm_rows,
        "event_count": len(mcp_rows) + len(norm_rows),
    }


@registry.tool()
def run_investigation_search(
    ctx: ToolContext,
    spl: str,
    earliest: str = "-1h",
    latest: str = "now",
    row_limit: int = 100,
) -> dict[str, Any]:
    """Run read-only SPL; return sid, row_count, sample_rows (max 5). No mutating commands."""
    _validate_readonly_spl(spl)
    row_limit = max(1, min(int(row_limit), 50))
    trimmed = spl.strip()
    if not re.search(r"\bhead\b", trimmed, re.IGNORECASE):
        trimmed = f"{trimmed} | head {row_limit}"

    sid, rows = _oneshot_json(ctx, trimmed, earliest=earliest, latest=latest)
    return {
        "sid": sid,
        "row_count": len(rows),
        "sample_rows": rows[:5],
    }


@registry.tool()
def log_investigation_step(
    ctx: ToolContext,
    case_id: str,
    step_number: int,
    tool_name: str,
    tool_input: str,
    tool_output_summary: str,
    sid: str | None = None,
) -> dict[str, Any]:
    """Index auditable step to agentsight:investigation_step. Call after every tool use."""
    event = {
        "case_id": case_id,
        "step_number": step_number,
        "tool_name": tool_name,
        "tool_input": tool_input[:4000],
        "tool_output_summary": tool_output_summary[:4000],
        "sid": sid or "",
        "timestamp": _utc_now(),
    }
    _submit_event(ctx, "investigation_step", event)
    ctx.logger.info("Logged investigation step %s for case %s", step_number, case_id)
    return {"status": "logged", "case_id": case_id, "step_number": step_number}


@registry.tool()
def classify_agent_behavior(
    ctx: ToolContext,
    case_id: str,
    evidence_summary: str,
    trigger_rule: str,
) -> dict[str, Any]:
    """
    Classify MCP/agent behavior via Splunk | ai command (Ollama locally, Foundation-Sec on Cloud).
    Returns classification, confidence, reasoning, and raw model output.
    """
    ai_cfg = _load_ai_config()
    prompt = (
        f"Classify this MCP agent behavior for case {case_id}. "
        f"Trigger rule: {trigger_rule}. "
        f"Evidence: {evidence_summary}. "
        "Respond with: classification (benign, suspicious, or malicious), "
        "confidence (0.0-1.0), and a one-paragraph reasoning."
    )
    prompt_escaped = _escape_spl_string(prompt)

    connection = ai_cfg.get("connection", "").strip()
    connection_arg = f' connection={connection}' if connection else ""
    provider = ai_cfg["provider"]
    model = ai_cfg["model"]

    classify_spl = (
        "| makeresults count=1 "
        f'| eval prompt="{prompt_escaped}" '
        f'| ai provider="{provider}" model="{model}"{connection_arg} '
        """prompt="'{prompt}'" """
    )

    ctx.logger.info("Running classify_agent_behavior via | ai for case %s", case_id)
    _, rows = _oneshot_json(ctx, classify_spl)

    raw = ""
    if rows:
        raw = str(rows[0].get("ai_result_1") or rows[0].get("result") or "")

    classification = "suspicious"
    confidence = 0.5
    lower = raw.lower()
    if "malicious" in lower:
        classification = "malicious"
    elif "benign" in lower:
        classification = "benign"
    elif "suspicious" in lower:
        classification = "suspicious"

    conf_match = re.search(r"confidence[:\s]+([0-9.]+)", raw, re.IGNORECASE)
    if conf_match:
        try:
            confidence = float(conf_match.group(1))
        except ValueError:
            pass

    return {
        "case_id": case_id,
        "classification": classification,
        "confidence": confidence,
        "reasoning": raw[:2000],
        "raw_model_output": raw,
        "ai_provider": provider,
        "ai_model": model,
    }


@registry.tool()
def queue_proposed_action(
    ctx: ToolContext,
    case_id: str,
    action_id: str,
    proposed_spl: str,
    rationale: str,
) -> dict[str, Any]:
    """
    Queue a proposed read-only SPL for async human approval.
    Does NOT poll or block. Agent continues and finishes case.
    """
    _validate_readonly_spl(proposed_spl)
    entry = {
        "action_id": action_id or f"action_{uuid.uuid4().hex[:8]}",
        "proposed_spl": proposed_spl,
        "rationale": rationale[:2000],
        "status": "queued",
        "queued_at": _utc_now(),
    }
    _PENDING_ACTIONS.setdefault(case_id, []).append(entry)
    ctx.logger.info("Queued action %s for case %s", entry["action_id"], case_id)
    return {"action_id": entry["action_id"], "status": "queued", "case_id": case_id}


@registry.tool()
def create_case(
    ctx: ToolContext,
    case_id: str,
    trigger_rule: str,
    severity: str,
    actor: str,
    summary: str,
    findings: list[str],
    cited_sids: list[str],
    classification: str,
    status: str = "awaiting_approval",
    pending_actions: list[str] | None = None,
) -> dict[str, Any]:
    """Finalize case to agentsight:case. status: awaiting_approval | closed."""
    queued = _PENDING_ACTIONS.pop(case_id, [])
    pending_ids = pending_actions or [a["action_id"] for a in queued]

    event = {
        "case_id": case_id,
        "trigger_rule": trigger_rule,
        "severity": severity,
        "status": status,
        "actor": actor,
        "summary": summary[:4000],
        "findings": findings,
        "cited_sids": cited_sids,
        "classification": classification,
        "pending_actions": pending_ids,
        "pending_action_details": queued,
        "created_at": _utc_now(),
    }
    _submit_event(ctx, "case", event)
    ctx.logger.info("Created case %s status=%s", case_id, status)
    return {
        "case_id": case_id,
        "status": status,
        "pending_actions": pending_ids,
        "indexed": True,
    }


def new_case_id() -> str:
    """Generate a case id for investigations."""
    return f"case_{uuid.uuid4().hex[:8]}"


def clear_pending_actions(case_id: str | None = None) -> None:
    """Clear in-memory pending queue (testing helper)."""
    if case_id:
        _PENDING_ACTIONS.pop(case_id, None)
    else:
        _PENDING_ACTIONS.clear()


class SimpleToolContext:
    """Minimal context for direct tool calls outside the MCP tool server."""

    def __init__(self, service: Any, logger: Any) -> None:
        self._service = service
        self._logger = logger

    @property
    def service(self) -> Any:
        return self._service

    @property
    def logger(self) -> Any:
        return self._logger


def _investigation_spl_for_rule(trigger_rule: str, actor: str) -> str:
    actor_esc = _escape_spl_string(actor or "*")
    if trigger_rule == "mcp_scope_violation":
        return (
            f"index=_audit sourcetype=audittrail action=search user=\"{actor_esc}\" earliest=-1h "
            "| rex field=search \"index\\s*=\\s*\\\"?(?<queried_index>[a-zA-Z0-9_*-]+)\" "
            "| stats count by queried_index search"
        )
    if trigger_rule == "mcp_off_hours_burst":
        return (
            "index=_internal sourcetype=mcp_server rpc_method=tools/call "
            f"username=\"{actor_esc}\" earliest=-24h "
            "| spath | eval hour=strftime(_time, \"%H\") "
            "| stats count by hour tool_name"
        )
    return (
        "index=_internal sourcetype=mcp_server rpc_method=tools/call "
        f"username=\"{actor_esc}\" earliest=-1h "
        "| spath | stats count by tool_name request_id"
    )


def run_scripted_investigation(service: Any, logger: Any, alert_row: dict[str, str]) -> str:
    """
    Deterministic investigation loop (<=5 tool equivalents) when the LLM agent
    is unavailable or times out. Returns case_id.
    """
    ctx = SimpleToolContext(service, logger)
    case_id = new_case_id()
    clear_pending_actions(case_id)

    trigger_rule = alert_row.get("trigger_rule", "unknown")
    severity = alert_row.get("severity", "medium")
    actor = (
        alert_row.get("actor")
        or alert_row.get("username")
        or alert_row.get("mcp_user")
        or alert_row.get("user")
        or "unknown"
    )
    session_id = alert_row.get("session_id") or alert_row.get("request_id") or ""
    description = alert_row.get("description", f"AgentSight alert: {trigger_rule}")

    step = 1
    context = get_alert_context(ctx, trigger_rule, session_id or None, actor)
    log_investigation_step(
        ctx,
        case_id,
        step,
        "get_alert_context",
        json.dumps({"trigger_rule": trigger_rule, "actor": actor}),
        json.dumps({"event_count": context.get("event_count", 0)})[:4000],
    )
    step += 1

    inv_spl = _investigation_spl_for_rule(trigger_rule, actor)
    search_result = run_investigation_search(ctx, inv_spl, earliest="-1h", row_limit=50)
    sid = search_result.get("sid") or ""
    log_investigation_step(
        ctx,
        case_id,
        step,
        "run_investigation_search",
        inv_spl,
        json.dumps(search_result.get("sample_rows", []))[:4000],
        sid=sid or None,
    )
    step += 1

    evidence = (
        f"{description}. Context events: {context.get('event_count', 0)}. "
        f"Search rows: {search_result.get('row_count', 0)}. "
        f"Sample: {json.dumps(search_result.get('sample_rows', [])[:3])}"
    )
    classification_result = classify_agent_behavior(ctx, case_id, evidence, trigger_rule)
    log_investigation_step(
        ctx,
        case_id,
        step,
        "classify_agent_behavior",
        evidence[:2000],
        json.dumps(classification_result)[:4000],
    )
    step += 1

    followup_spl = _investigation_spl_for_rule(trigger_rule, actor) + " | head 20"
    queue_proposed_action(
        ctx,
        case_id,
        f"action_{case_id}",
        followup_spl,
        "Analyst-approved read-only follow-up for MCP agent timeline review.",
    )
    log_investigation_step(
        ctx,
        case_id,
        step,
        "queue_proposed_action",
        followup_spl,
        "queued",
    )

    findings = [
        f"[sid={sid}] MCP investigation search returned {search_result.get('row_count', 0)} rows"
        if sid
        else f"MCP investigation search returned {search_result.get('row_count', 0)} rows",
        description,
    ]
    create_case(
        ctx,
        case_id,
        trigger_rule,
        severity,
        actor,
        description,
        findings,
        [sid] if sid else [],
        classification_result.get("classification", "suspicious"),
        status="awaiting_approval",
    )
    return case_id


if __name__ == "__main__":
    registry.run()
