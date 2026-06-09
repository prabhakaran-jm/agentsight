#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Custom alert action: splunklib.ai investigation agent for MCP/agent alerts."""

from __future__ import annotations

import asyncio
import csv
import gzip
import json
import os
import sys
from typing import Any
from urllib.parse import urlsplit

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "lib"))

from pydantic import BaseModel, Field
from setup_logging import setup_logging

from splunklib import client

logger = setup_logging("agentsight")

# Splunk may set SSL_CERT_FILE to a missing bundle on some installs.
_CA_TRUST_STORE = "/opt/splunk/openssl/cert.pem"
if os.environ.get("SSL_CERT_FILE") == _CA_TRUST_STORE and not os.path.exists(_CA_TRUST_STORE):
    del os.environ["SSL_CERT_FILE"]

SYSTEM_PROMPT = """You are AgentSight Investigation Agent — Splunk's analyst for AI agents and MCP clients
that access this Splunk deployment. You investigate AGENT BEHAVIOR, not generic human threats.
Every alert is about an autonomous MCP client or agent service account.

## Meta mission
Splunk is watching the agents that use Splunk. Explain what an MCP/agent did, whether it violated
scope or autonomy norms, and produce an auditable case with cited search job IDs (sids).

## Required workflow (max 5 tool calls)
1. get_alert_context(trigger_rule, actor, session_id)
2. run_investigation_search — one read-only SPL on mcp_server or agentsight:mcp_audit
3. classify_agent_behavior — uses | ai (Ollama/Foundation-Sec)
4. queue_proposed_action — optional read-only SPL for analyst approval (do not wait)
5. log_investigation_step after every tool
6. create_case — use the provided case_id; status=awaiting_approval if you queued actions

## Rules
- READ-ONLY SPL only. Max 5 tool calls total then create_case.
- Cite evidence as [sid=...]. Never echo secrets from queries.
- Frame findings as MCP/agent governance: runaway loop, scope violation, off-hours burst.
"""

TOOL_ALLOWLIST = [
    "get_alert_context",
    "run_investigation_search",
    "log_investigation_step",
    "classify_agent_behavior",
    "queue_proposed_action",
    "create_case",
]


class AlertInvestigationInput(BaseModel):
    case_id: str
    trigger_rule: str
    severity: str
    actor: str
    session_id: str = ""
    description: str
    search_name: str = ""
    alert_row: dict[str, str] = Field(default_factory=dict)


def _load_ollama_model():
    from splunklib.ai import OpenAIModel

    base_url = os.environ.get("AGENTSIGHT_OLLAMA_URL", "http://127.0.0.1:11434/v1")
    model = os.environ.get("AGENTSIGHT_OLLAMA_CHAT_MODEL", "llama3.2:latest")
    return OpenAIModel(model=model, base_url=base_url, api_key="ollama")


def read_results_from_file(results_file_path: str) -> list[dict[str, str]]:
    with gzip.open(results_file_path, "rt") as results_file:
        return list(csv.DictReader(results_file))


def connect_service(alert_payload: dict[str, Any]) -> client.Service:
    server_uri = alert_payload.get("server_uri", "")
    session_key = alert_payload.get("session_key", "")
    splunk_uri = urlsplit(server_uri, scheme="https")
    return client.connect(
        scheme=splunk_uri.scheme,
        token=session_key,
        host=splunk_uri.hostname,
        port=splunk_uri.port,
        autologin=True,
    )


def parse_alert_row(row: dict[str, str]) -> AlertInvestigationInput:
    from tools import new_case_id

    actor = row.get("actor") or row.get("username") or row.get("mcp_user") or row.get("user") or ""
    session_id = row.get("session_id") or row.get("request_id") or ""
    return AlertInvestigationInput(
        case_id=new_case_id(),
        trigger_rule=row.get("trigger_rule", "unknown"),
        severity=row.get("severity", "medium"),
        actor=actor,
        session_id=session_id,
        description=row.get("description", "AgentSight MCP/agent alert"),
        alert_row=row,
    )


async def invoke_investigation_agent(
    service: client.Service,
    investigation: AlertInvestigationInput,
) -> None:
    from splunklib.ai import Agent
    from splunklib.ai.limits import AgentLimits
    from splunklib.ai.tool_settings import LocalToolSettings, ToolAllowlist, ToolSettings

    from tools import clear_pending_actions

    clear_pending_actions(investigation.case_id)

    model = _load_ollama_model()
    limits = AgentLimits(timeout=240.0, max_steps=14, max_tokens=80_000)

    async with Agent(
        model=model,
        system_prompt=SYSTEM_PROMPT,
        service=service,
        tool_settings=ToolSettings(
            local=LocalToolSettings(allowlist=ToolAllowlist(names=TOOL_ALLOWLIST)),
            remote=None,
        ),
        logger=logger,
        limits=limits,
    ) as agent:
        instructions = (
            f"Investigate MCP agent alert and create case {investigation.case_id}. "
            f"trigger_rule={investigation.trigger_rule}, actor={investigation.actor}, "
            f"session_id={investigation.session_id}. "
            "You MUST call create_case with this exact case_id before finishing."
        )
        result = await agent.invoke_with_data(
            instructions=instructions,
            data=investigation.model_dump(),
        )
        logger.info(
            "Agent investigation complete case_id=%s content_len=%s",
            investigation.case_id,
            len(result.final_message.content or ""),
        )


def handle_alert() -> None:
    from tools import run_scripted_investigation

    alert_payload = json.loads(sys.stdin.read())
    results_file_path = alert_payload.get("results_file", "")
    if not results_file_path:
        logger.error("No results file in alert payload")
        sys.exit(1)

    try:
        rows = read_results_from_file(results_file_path)
        if not rows:
            logger.error("Alert results file empty")
            sys.exit(1)

        service = connect_service(alert_payload)
        investigation = parse_alert_row(rows[0])
        investigation.search_name = alert_payload.get("search_name", "")

        logger.info(
            "Starting investigation case_id=%s trigger=%s actor=%s",
            investigation.case_id,
            investigation.trigger_rule,
            investigation.actor,
        )

        try:
            asyncio.run(invoke_investigation_agent(service, investigation))
        except Exception as agent_error:
            logger.exception(
                "Agent investigation failed, using scripted fallback: %s", agent_error
            )
            case_id = run_scripted_investigation(service, logger, investigation.alert_row)
            logger.info("Scripted fallback created case %s", case_id)

    except Exception as exc:
        logger.exception("agentsight_investigate failed: %s", exc)
        sys.exit(1)


if __name__ == "__main__":
    handle_alert()
