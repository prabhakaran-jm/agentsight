#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Generating command: re-explain an AgentSight case from the search bar."""

import asyncio
import json
import os
import sys
from datetime import datetime
from typing import Any, Iterator, Literal

_BIN_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _BIN_DIR)
sys.path.insert(0, os.path.join(_BIN_DIR, "lib"))

from splunklib.results import JSONResultsReader
from splunklib.searchcommands import Configuration, GeneratingCommand, Option, dispatch
from pydantic import BaseModel, Field

_INDEX = "agentsight"

EXPLAIN_SYSTEM_PROMPT = """You are AgentSight Explain Agent. Given an existing case_id and its
investigation_step audit trail, produce a concise analyst-facing explanation. Do not invent events.
Cite sids from the step log. Emphasize: this case is about an MCP/agent client, not a human intruder.

Output structured fields: explanation, findings (list with [sid=...] where applicable),
classification (benign/suspicious/malicious), cited_sids, suggested_spl (max 3 read-only queries).
"""


class ExplainOutput(BaseModel):
    explanation: str = Field(description="Plain-language narrative for analysts")
    findings: list[str] = Field(description="Finding strings, cite sids when possible")
    classification: Literal["benign", "suspicious", "malicious"]
    cited_sids: list[str] = Field(default_factory=list)
    suggested_spl: list[str] = Field(
        default_factory=list,
        description="Up to 3 read-only follow-up SPL queries",
    )


def _load_ollama_model():
    from splunklib.ai import OpenAIModel

    base_url = os.environ.get("AGENTSIGHT_OLLAMA_URL", "http://127.0.0.1:11434/v1")
    model = os.environ.get("AGENTSIGHT_OLLAMA_CHAT_MODEL", "llama3.2:latest")
    return OpenAIModel(model=model, base_url=base_url, api_key="ollama")


def _parse_json_event(row: dict[str, Any]) -> dict[str, Any]:
    raw = row.get("_raw", "")
    if isinstance(raw, str) and raw.startswith("{"):
        return json.loads(raw)
    return dict(row)


def _load_case(service: Any, case_id: str) -> dict[str, Any] | None:
    spl = (
        f'search index={_INDEX} sourcetype=agentsight:case case_id="{case_id}" '
        "| sort - _time | head 1"
    )
    rows = [r for r in JSONResultsReader(service.jobs.oneshot(spl, output_mode="json")) if isinstance(r, dict)]
    return _parse_json_event(rows[0]) if rows else None


def _load_investigation_steps(service: Any, case_id: str) -> list[dict[str, Any]]:
    spl = (
        f'search index={_INDEX} sourcetype=agentsight:investigation_step case_id="{case_id}" '
        "| sort step_number | head 50"
    )
    steps: list[dict[str, Any]] = []
    for row in JSONResultsReader(service.jobs.oneshot(spl, output_mode="json")):
        if isinstance(row, dict):
            steps.append(_parse_json_event(row))
    return steps


def _scripted_explain(case: dict[str, Any], steps: list[dict[str, Any]]) -> ExplainOutput:
    cited: list[str] = []
    findings: list[str] = []
    for step in steps:
        sid = step.get("sid") or ""
        if sid:
            cited.append(sid)
        findings.append(
            f"Step {step.get('step_number', '?')}: {step.get('tool_name', '')} — "
            f"{step.get('tool_output_summary', '')[:200]}"
            + (f" [sid={sid}]" if sid else "")
        )
    if not findings:
        findings = list(case.get("findings") or [])
    cited = cited or list(case.get("cited_sids") or [])

    classification = case.get("classification", "suspicious")
    if classification not in ("benign", "suspicious", "malicious"):
        classification = "suspicious"

    actor = case.get("actor", "unknown")
    trigger = case.get("trigger_rule", "unknown")
    suggested = [
        f'index=_internal sourcetype=mcp_server username="{actor}" earliest=-24h | spath | stats count by tool_name',
        f"index=agentsight sourcetype=agentsight:investigation_step case_id=\"{case.get('case_id', '')}\" | sort step_number",
    ]

    return ExplainOutput(
        explanation=case.get("summary", f"MCP agent case for {actor} ({trigger})."),
        findings=findings[:10],
        classification=classification,
        cited_sids=cited[:10],
        suggested_spl=suggested[:3],
    )


async def _agent_explain(
    service: Any,
    case: dict[str, Any],
    steps: list[dict[str, Any]],
    logger: Any,
) -> ExplainOutput:
    from splunklib.ai import Agent
    from splunklib.ai.limits import AgentLimits
    from splunklib.ai.tool_settings import ToolSettings

    model = _load_ollama_model()
    limits = AgentLimits(timeout=120.0, max_steps=8, max_tokens=60_000)

    async with Agent(
        model=model,
        system_prompt=EXPLAIN_SYSTEM_PROMPT,
        service=service,
        output_schema=ExplainOutput,
        tool_settings=ToolSettings(local=False, remote=None),
        logger=logger,
        limits=limits,
    ) as agent:
        result = await agent.invoke_with_data(
            instructions="Explain this AgentSight MCP/agent case for a SOC analyst.",
            data={"case": case, "investigation_steps": steps},
        )
        if result.structured_output is not None:
            return result.structured_output
        return ExplainOutput(
            explanation=result.final_message.content or case.get("summary", ""),
            findings=list(case.get("findings") or []),
            classification="suspicious",
            cited_sids=list(case.get("cited_sids") or []),
            suggested_spl=[],
        )


@Configuration()
class AgentSightExplainCommand(GeneratingCommand):
    """Re-explain an AgentSight case using the investigation audit trail."""

    case_id = Option(require=True)

    def generate(self) -> Iterator[dict[str, Any]]:
        service = self.service
        if service is None:
            yield {
                "_time": datetime.now().timestamp(),
                "case_id": str(self.case_id),
                "explanation": "Splunk service unavailable",
                "classification": "suspicious",
            }
            return

        case_id = str(self.case_id)
        case = _load_case(service, case_id)
        if not case:
            yield {
                "_time": datetime.now().timestamp(),
                "case_id": case_id,
                "explanation": f"No case found for case_id={case_id}",
                "classification": "suspicious",
                "findings": [],
                "cited_sids": [],
                "suggested_spl": [],
            }
            return

        steps = _load_investigation_steps(service, case_id)

        try:
            output = asyncio.run(_agent_explain(service, case, steps, self.logger))
        except Exception as exc:
            self.logger.warning("agentsight_explain agent failed, using scripted fallback: %s", exc)
            output = _scripted_explain(case, steps)

        yield {
            "_time": datetime.now().timestamp(),
            "case_id": case_id,
            "explanation": output.explanation,
            "findings": output.findings,
            "classification": output.classification,
            "cited_sids": output.cited_sids,
            "suggested_spl": output.suggested_spl[:3],
        }


dispatch(AgentSightExplainCommand, sys.argv, sys.stdin, sys.stdout, __name__)
