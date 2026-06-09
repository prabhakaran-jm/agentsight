#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""
SYNTHETIC FALLBACK ONLY — for offline judges without MCP Server access.

Generates labeled demo events into index=agentsight / sourcetype=agentsight:demo.
Do NOT use as the primary demo path when real MCP audit is available.
"""

from __future__ import annotations

import json
import os
import sys
import uuid
from datetime import datetime, timezone

from splunklib import client
from splunklib.binding import connect

INDEX = "agentsight"
GENERATOR = "agentsight_demo_event_generator"


def _utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _connect() -> client.Service:
    host = os.environ.get("SPLUNK_HOST", "localhost")
    port = int(os.environ.get("SPLUNK_PORT", "8089"))
    token = os.environ.get("SPLUNK_TOKEN")
    username = os.environ.get("SPLUNK_USER", "admin")
    password = os.environ.get("SPLUNK_PASSWORD")
    if token:
        return connect(scheme="https", host=host, port=port, token=token, autologin=True)
    return connect(
        scheme="https",
        host=host,
        port=port,
        username=username,
        password=password,
        autologin=True,
    )


def generate_demo_events(scenario: str = "mcp_tool_loop") -> list[dict]:
    session = f"demo_sess_{uuid.uuid4().hex[:6]}"
    base = {
        "generator": GENERATOR,
        "scenario": scenario,
        "timestamp": _utc_now(),
        "synthetic": True,
        "mcp_user": "demo-agent-svc",
        "mcp_tool": "splunk_run_query",
        "session_id": session,
        "client_ip": "127.0.0.1",
        "outcome": "200",
    }
    if scenario == "mcp_tool_loop":
        return [
            {
                **base,
                "spl_query": "| makeresults count=1 | eval n=$i$ | table n".replace("$i$", str(i)),
            }
            for i in range(1, 14)
        ]
    if scenario == "mcp_scope_violation":
        return [{**base, "spl_query": "index=secrets | head 5"}]
    return [{**base, "spl_query": "| makeresults count=1 | eval off_hours=1"}]


def main() -> None:
    scenario = sys.argv[1] if len(sys.argv) > 1 else "mcp_tool_loop"
    service = _connect()
    index = service.indexes[INDEX]
    for event in generate_demo_events(scenario):
        index.submit(json.dumps(event), sourcetype="agentsight:demo")
    print(f"Indexed {len(generate_demo_events(scenario))} synthetic demo events (scenario={scenario})")


if __name__ == "__main__":
    main()
