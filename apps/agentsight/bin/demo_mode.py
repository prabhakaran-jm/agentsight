# SPDX-License-Identifier: MIT
"""Fast demo mode: skip Ollama agent loops; keep | ai classify."""

import os

_BIN_DIR = os.path.dirname(os.path.abspath(__file__))


def _truthy(value: str | None) -> bool:
    return (value or "").strip().lower() in ("1", "true", "yes", "on")


def is_demo_mode() -> bool:
    flag = os.path.normpath(os.path.join(_BIN_DIR, "..", "local", "demo_mode"))
    return os.path.isfile(flag)


def scripted_investigation_enabled() -> bool:
    if is_demo_mode():
        return True
    return _truthy(os.environ.get("AGENTSIGHT_SCRIPTED_INVESTIGATION"))


def scripted_explain_enabled() -> bool:
    if is_demo_mode():
        return True
    return _truthy(os.environ.get("AGENTSIGHT_SCRIPTED_EXPLAIN"))
