# Copyright © 2011-2026 Splunk, Inc.
# SPDX-License-Identifier: Apache-2.0

import logging
import logging.handlers
import os


def setup_logging(app_name: str) -> logging.Logger:
    """To see logs from this logger, run this SPL in Splunk:
    `index="_internal" source="*/<app_name>.log"`"""
    splunk_home = os.environ.get("SPLUNK_HOME", os.path.join("/opt", "splunk"))
    log_path = os.path.join(splunk_home, "var", "log", "splunk", f"{app_name}.log")

    logger = logging.getLogger(app_name)
    logger.setLevel(logging.DEBUG)

    handler = logging.handlers.RotatingFileHandler(
        log_path, maxBytes=1024 * 1024, backupCount=5
    )
    handler.setFormatter(
        logging.Formatter(f"%(asctime)s %(levelname)s [{app_name}] %(message)s")
    )
    logger.addHandler(handler)
    return logger
