python := env_var_or_default("PYTHON_BIN", ".venv/bin/python")
py := python

default:
    just --list

check:
    PYTHONPYCACHEPREFIX=.pycache {{py}} -m compileall -q src

[unix]
smoke:
    PYTHONPATH=src DEVPILOT_APP_DATA_DIR=.devpilot-smoke {{py}} -m devpilot.cli --template-dir examples --config examples/config.example.toml slack test --dry-run
    PYTHONPATH=src DEVPILOT_APP_DATA_DIR=.devpilot-smoke {{py}} -m devpilot.cli --template-dir examples --config examples/config.example.toml jira today --dry-run

clean:
    find . -type d -name __pycache__ -prune -exec rm -rf {} +
    rm -rf .pycache build dist .devpilot-smoke *.spec

status:
    git status --short --ignored

setup:
    python3.13 -m venv .venv

install-dev:
    .venv/bin/python -m pip install --upgrade pip
    .venv/bin/python -m pip install -e .
    .venv/bin/python -m pip install pyinstaller

package-local:
    {{py}} -m PyInstaller --clean --onefile --paths src --name devpilot src/devpilot/cli.py

[unix]
macos-app-build:
    swift build -c release --package-path apps/macos/DevPilotMenuBar
