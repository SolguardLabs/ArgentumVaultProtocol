#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [ ! -d ".venv" ]; then
  python -m venv .venv
fi

if [ -x ".venv/bin/python" ]; then
  PY=".venv/bin/python"
else
  PY=".venv/Scripts/python.exe"
fi

"$PY" -m pip install -r requirements.txt

while IFS= read -r -d '' contract; do
  echo "compiling ${contract}"
  "$PY" -m vyper -f abi "$contract" >/dev/null
done < <(find src -name '*.vy' -print0)

"$PY" -m pytest -q
