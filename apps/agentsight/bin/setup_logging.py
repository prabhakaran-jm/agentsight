# Copyright © 2011-2026 Splunk, Inc.
# SPDX-License-Identifier: Apache-2.0

import logging
import logging.handlers
import os
import sys


def setup_logging(app_name: str) -> logging.Logger:
    """Logs to $SPLUNK_HOME/var/log/splunk/<app_name>.log and stderr (modalert).

    View on disk: sudo tail -f /opt/splunk/var/log/splunk/<app_name>.log
    """
    splunk_home = os.environ.get("SPLUNK_HOME", os.path.join("/opt", "splunk"))
    log_path = os.path.join(splunk_home, "var", "log", "splunk", f"{app_name}.log")

    logger = logging.getLogger(app_name)
    logger.setLevel(logging.DEBUG)
    if logger.handlers:
        return logger

    formatter = logging.Formatter(
        f"%(asctime)s %(levelname)s [{app_name}] %(message)s"
    )

    try:
        file_handler = logging.handlers.RotatingFileHandler(
            log_path, maxBytes=1024 * 1024, backupCount=5
        )
        file_handler.setFormatter(formatter)
        logger.addHandler(file_handler)
    except OSError as exc:
        sys.stderr.write(f"WARN [{app_name}] cannot open log file {log_path}: {exc}\n")

    stderr_handler = logging.StreamHandler(sys.stderr)
    stderr_handler.setFormatter(formatter)
    logger.addHandler(stderr_handler)
    return logger
