#!/usr/bin/env bash
# Install Python deps into apps/agentsight/bin/lib using Splunk's Python (not system python3).
set -euo pipefail

: "${SPLUNK_HOME:=/opt/splunk}"
APP_DIR="$(cd "$(dirname "$0")/../apps/agentsight" && pwd)"
LIB_DIR="${APP_DIR}/bin/lib"

# Splunk CLI must run as the splunk boot-start user on systemd installs.
splunk_cmd() {
  if id splunk &>/dev/null; then
    sudo -u splunk "${SPLUNK_HOME}/bin/splunk" "$@"
  else
    "${SPLUNK_HOME}/bin/splunk" "$@"
  fi
}

echo "Splunk Python version:"
splunk_cmd cmd python3 -c "import sys; print(sys.version)"

echo "Removing stale bin/lib (may have been built for wrong Python version)..."
sudo rm -rf "${LIB_DIR}" 2>/dev/null || rm -rf "${LIB_DIR}"
mkdir -p "${LIB_DIR}"

# pip runs as splunk — target dir must be writable by that user
if id splunk &>/dev/null; then
  sudo chown -R splunk:splunk "${LIB_DIR}"
fi

echo "Installing with Splunk Python into ${LIB_DIR}..."
splunk_cmd cmd python3 -m pip install \
  --no-cache-dir \
  -r "${APP_DIR}/requirements.txt" \
  -t "${LIB_DIR}" \
  --upgrade

if id splunk &>/dev/null; then
  sudo chmod -R a+rX "${LIB_DIR}"
else
  chmod -R a+rX "${LIB_DIR}"
fi

echo "Verify splunklib import:"
splunk_cmd cmd python3 -c "
import sys
sys.path.insert(0, '${LIB_DIR}')
import splunklib
print('splunklib OK:', splunklib.__file__)
"

echo "Done. Restart Splunk: sudo systemctl restart Splunkd.service"
