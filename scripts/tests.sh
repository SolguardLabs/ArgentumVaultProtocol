#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ ! -d ".venv" ]; then
  python -m venv .venv
fi
./.venv/bin/python -m pip install -r requirements.txt
./.venv/bin/pytest
