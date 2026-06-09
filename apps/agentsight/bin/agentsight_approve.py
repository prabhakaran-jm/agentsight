#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Generating command: approve or deny queued MCP agent actions."""

from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timezone
from typing import Any, Iterator

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "lib"))

from splunklib.results import JSONResultsReader
from splunklib.searchcommands import (
    Configuration,
    GeneratingCommand,
    Option,
    dispatch,
    validators,
)

from tools import (
    SimpleToolContext,
    _validate_readonly_spl,
    log_investigation_step,
    revoke_user_tokens,
)

_INDEX = "agentsight"


def _utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _load_case(service: Any, case_id: str) -> dict[str, Any] | None:
    spl = (
        f'search index={_INDEX} sourcetype=agentsight:case case_id="{case_id}" '
        "| sort - _time | head 1"
    )
    rows = list(JSONResultsReader(service.jobs.oneshot(spl, output_mode="json")))
    if not rows:
        return None
    raw = rows[0].get("_raw", "")
    if isinstance(raw, str) and raw.startswith("{"):
        return json.loads(raw)
    return dict(rows[0])


def _submit(service: Any, sourcetype: str, event: dict[str, Any]) -> None:
    service.indexes[_INDEX].submit(
        json.dumps(event, default=str), sourcetype=f"agentsight:{sourcetype}"
    )


def _find_pending_action(case: dict[str, Any], action_id: str) -> dict[str, Any] | None:
    details = case.get("pending_action_details") or []
    if isinstance(details, str):
        try:
            details = json.loads(details)
        except json.JSONDecodeError:
            details = []
    for item in details:
        if item.get("action_id") == action_id:
            return item
    return None


def _run_readonly_search(service: Any, spl: str) -> tuple[str | None, list[dict[str, Any]]]:
    _validate_readonly_spl(spl)
    rows = list(
        JSONResultsReader(
            service.jobs.oneshot(
                spl,
                earliest_time="-1h",
                latest_time="now",
                output_mode="json",
            )
        )
    )
    parsed = [r for r in rows if isinstance(r, dict)]
    sid = parsed[0].get("sid") if parsed else None
    return sid, parsed[:5]


@Configuration()
class AgentSightApproveCommand(GeneratingCommand):
    """Approve or deny a queued MCP agent action for a case."""

    case_id = Option(require=True)
    action_id = Option(require=True)
    decision = Option(require=True, validate=validators.Match("(?i)^(approved|denied)$"))
    actor = Option(require=False, default="admin")

    def generate(self) -> Iterator[dict[str, Any]]:
        service = self.service
        if service is None:
            yield {
                "_time": datetime.now().timestamp(),
                "status": "error",
                "message": "Splunk service unavailable for agentsight_approve",
            }
            return

        case_id = str(self.case_id)
        action_id = str(self.action_id)
        decision = str(self.decision).lower()
        actor = str(self.actor or "admin")

        case = _load_case(service, case_id)
        if not case:
            yield {
                "_time": datetime.now().timestamp(),
                "status": "error",
                "case_id": case_id,
                "message": f"Case not found: {case_id}",
            }
            return

        pending = _find_pending_action(case, action_id)
        approved_spl = (pending or {}).get("proposed_spl", "")
        action_type = (pending or {}).get("action_type", "spl")
        target_user = (pending or {}).get("target_user", "")

        approval_event = {
            "case_id": case_id,
            "action_id": action_id,
            "action_type": action_type,
            "decision": decision,
            "actor": actor,
            "approved_spl": approved_spl,
            "target_user": target_user,
            "followup_sid": "",
            "timestamp": _utc_now(),
        }

        followup_sid = None
        followup_sample: list[dict[str, Any]] = []
        quarantine_result: dict[str, Any] = {}
        new_status = "closed" if decision == "denied" else "open"

        if decision == "approved" and action_type == "quarantine":
            if not target_user:
                yield {
                    "_time": datetime.now().timestamp(),
                    "status": "error",
                    "case_id": case_id,
                    "action_id": action_id,
                    "message": "Quarantine action has no target_user",
                }
                return
            try:
                quarantine_result = revoke_user_tokens(service, target_user)
                approval_event["quarantine_result"] = quarantine_result
                new_status = "contained"
            except Exception as exc:
                yield {
                    "_time": datetime.now().timestamp(),
                    "status": "error",
                    "case_id": case_id,
                    "action_id": action_id,
                    "message": f"Failed to revoke tokens for {target_user}: {exc}",
                }
                return
        elif decision == "approved" and approved_spl:
            try:
                followup_sid, followup_sample = _run_readonly_search(service, approved_spl)
                approval_event["followup_sid"] = followup_sid or ""
            except Exception as exc:
                yield {
                    "_time": datetime.now().timestamp(),
                    "status": "error",
                    "case_id": case_id,
                    "action_id": action_id,
                    "message": f"Failed to run approved SPL: {exc}",
                }
                return

        _submit(service, "approval", approval_event)

        ctx = SimpleToolContext(service, self.logger)
        step_output = (
            json.dumps(quarantine_result)
            if action_type == "quarantine"
            else json.dumps(followup_sample)
        )
        log_investigation_step(
            ctx,
            case_id,
            100,
            "agentsight_approve",
            json.dumps(
                {"action_id": action_id, "action_type": action_type, "decision": decision}
            ),
            step_output[:4000],
            sid=followup_sid,
        )

        # Drop only the decided action; leave any other queued actions pending.
        remaining = [
            item
            for item in (case.get("pending_action_details") or [])
            if isinstance(item, dict) and item.get("action_id") != action_id
        ]
        updated_case = {
            **case,
            "status": new_status,
            "updated_at": _utc_now(),
            "last_decision": decision,
            "last_action_id": action_id,
            "pending_actions": [item.get("action_id") for item in remaining],
            "pending_action_details": remaining,
        }
        _submit(service, "case", updated_case)

        yield {
            "_time": datetime.now().timestamp(),
            "status": "ok",
            "case_id": case_id,
            "action_id": action_id,
            "action_type": action_type,
            "decision": decision,
            "new_case_status": new_status,
            "followup_sid": followup_sid or "",
            "followup_row_count": len(followup_sample),
            "tokens_revoked": quarantine_result.get("revoked_count", 0),
            "message": (
                f"Quarantined {target_user}: revoked "
                f"{quarantine_result.get('revoked_count', 0)} token(s); case {case_id} contained"
                if action_type == "quarantine" and decision == "approved"
                else f"Case {case_id} updated to {new_status}"
            ),
        }


dispatch(AgentSightApproveCommand, sys.argv, sys.stdin, sys.stdout, __name__)
