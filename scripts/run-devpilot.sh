#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

export PYTHONPATH="$PROJECT_ROOT/src"
if [[ -z "${PYTHON_BIN:-}" && -x "$PROJECT_ROOT/.venv/bin/python" ]]; then
  PYTHON_BIN="$PROJECT_ROOT/.venv/bin/python"
else
  PYTHON_BIN="${PYTHON_BIN:-python3.13}"
fi

if [[ -n "${DEVPILOT_BIN:-}" ]]; then
  exec "$DEVPILOT_BIN" --template-dir "$PROJECT_ROOT" "$@"
fi

if [[ -x "$PROJECT_ROOT/bin/devpilot" ]]; then
  exec "$PROJECT_ROOT/bin/devpilot" --template-dir "$PROJECT_ROOT" "$@"
fi

exec "$PYTHON_BIN" -m devpilot.cli \
  --template-dir "$PROJECT_ROOT" \
  "$@"
