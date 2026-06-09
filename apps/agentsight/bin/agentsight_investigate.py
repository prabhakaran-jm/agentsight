#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Stub alert action — full splunklib.ai investigation implemented in Task 5."""

import sys

from setup_logging import setup_logging

logger = setup_logging("agentsight")


def handle_alert() -> None:
    payload = sys.stdin.read()
    logger.warning(
        "agentsight_investigate received alert (stub). "
        "Full investigation agent not yet implemented. payload_bytes=%s",
        len(payload),
    )


if __name__ == "__main__":
    handle_alert()
