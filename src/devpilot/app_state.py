from __future__ import annotations

from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import sqlite3
import time
import uuid

from devpilot.metadata import APP_DATA_ENV, APP_NAME, REPORT_AGENT_TEMPLATE

STATE_VERSION = 1
DB_VERSION = 1


def app_data_dir() -> Path:
    override = os.environ.get(APP_DATA_ENV)
    if override:
        return Path(override).expanduser().resolve()

    return Path.home() / "Library" / "Application Support" / APP_NAME


def init_app_data(*, template_dir: str | Path | None = None) -> Path:
    target = app_data_dir()
    target.mkdir(parents=True, exist_ok=True)
    (target / "logs").mkdir(exist_ok=True)
    (target / "snapshots").mkdir(exist_ok=True)

    templates = _template_dir(Path(template_dir).resolve() if template_dir else Path.cwd())
    _copy_if_missing(templates / "config.example.toml", target / "config.toml")
    _copy_if_missing(templates / "assignees.example.json", target / "assignees.json")
    _copy_if_missing(templates / REPORT_AGENT_TEMPLATE, target / "report-agent.md")
    _create_json_if_missing(target / "assignees.json", {})
    _create_text_if_missing(target / "report-agent.md", "# DevPilot Report Agent\n\n- 간결한 한국어 보고서로 작성한다.\n")
    _create_state_if_missing(target / "state.json")
    return target


def default_config_path() -> Path:
    return app_data_dir() / "config.toml"


def default_env_path() -> Path:
    return app_data_dir() / ".env"


def default_assignees_path() -> Path:
    return app_data_dir() / "assignees.json"


def default_state_path() -> Path:
    return app_data_dir() / "state.json"


def default_db_path() -> Path:
    return app_data_dir() / "devpilot.db"


def default_report_agent_path() -> Path:
    return app_data_dir() / "report-agent.md"


def read_state() -> dict:
    _ensure_db()
    loaded = _read_state_from_db()
    if loaded is not None:
        return loaded
    path = default_state_path()
    if not path.exists():
        _create_state_if_missing(path)
    try:
        state = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        state = {"version": STATE_VERSION, "last_runs": {}}
    write_state(state)
    return state


def write_state(state: dict) -> None:
    _ensure_db()
    _write_state_to_db(state)
    path = default_state_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    _write_json(path, state)


def update_state(mutator) -> dict:
    _ensure_db()
    for attempt in range(5):
        try:
            with _connect() as conn:
                conn.execute("BEGIN IMMEDIATE")
                state = _read_state_from_connection(conn) or _initial_state()
                result = mutator(state)
                _write_state_to_connection(conn, state)
                conn.commit()
            break
        except sqlite3.OperationalError as exc:
            if "locked" not in str(exc).lower() or attempt == 4:
                raise
            time.sleep(0.15 * (attempt + 1))
    _write_json(default_state_path(), state)
    return result if result is not None else state


def _copy_if_missing(source: Path, destination: Path) -> None:
    if destination.exists() or not source.exists():
        return
    shutil.copyfile(source, destination)


def _template_dir(base: Path) -> Path:
    if (base / "config.example.toml").exists():
        return base
    examples = base / "examples"
    if (examples / "config.example.toml").exists():
        return examples
    return base


def _create_state_if_missing(destination: Path) -> None:
    if destination.exists():
        return
    payload = _initial_state()
    _write_json(destination, payload)


def _create_json_if_missing(destination: Path, payload: dict) -> None:
    if destination.exists():
        return
    _write_json(destination, payload)


def _create_text_if_missing(destination: Path, payload: str) -> None:
    if destination.exists():
        return
    destination.write_text(payload, encoding="utf-8")


def _write_json(destination: Path, payload: dict) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    serialized = json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
    tmp = destination.with_name(f"{destination.name}.{os.getpid()}.{uuid.uuid4().hex}.tmp")
    tmp.write_text(serialized, encoding="utf-8")
    tmp.replace(destination)


def _initial_state() -> dict:
    return {
        "version": STATE_VERSION,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "last_runs": {},
        "issue_repositories": {},
        "issue_workflows": {},
    }


def _connect() -> sqlite3.Connection:
    path = default_db_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(path, timeout=15, isolation_level=None)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA busy_timeout=15000")
    conn.execute("PRAGMA foreign_keys=ON")
    return conn


def _ensure_db() -> None:
    for attempt in range(3):
        try:
            with _connect() as conn:
                conn.execute(
                    """
                    CREATE TABLE IF NOT EXISTS app_meta (
                        key TEXT PRIMARY KEY,
                        value TEXT NOT NULL
                    )
                    """
                )
                conn.execute(
                    """
                    CREATE TABLE IF NOT EXISTS app_state (
                        key TEXT PRIMARY KEY,
                        payload TEXT NOT NULL,
                        updated_at TEXT NOT NULL
                    )
                    """
                )
                conn.execute(
                    """
                    CREATE TABLE IF NOT EXISTS issue_events (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        issue_key TEXT NOT NULL,
                        event_type TEXT NOT NULL,
                        payload TEXT NOT NULL,
                        created_at TEXT NOT NULL
                    )
                    """
                )
                conn.execute("INSERT OR REPLACE INTO app_meta(key, value) VALUES('db_version', ?)", (str(DB_VERSION),))
                if _read_state_from_connection(conn) is None:
                    conn.execute("BEGIN IMMEDIATE")
                    _write_state_to_connection(conn, _read_json_state_file() or _initial_state())
                    conn.commit()
            return
        except sqlite3.OperationalError:
            if attempt == 2:
                raise
            time.sleep(0.15)


def _read_json_state_file() -> dict | None:
    path = default_state_path()
    if not path.exists():
        return None
    try:
        loaded = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None
    return loaded if isinstance(loaded, dict) else None


def _read_state_from_db() -> dict | None:
    with _connect() as conn:
        return _read_state_from_connection(conn)


def _read_state_from_connection(conn: sqlite3.Connection) -> dict | None:
    row = conn.execute("SELECT payload FROM app_state WHERE key = 'state'").fetchone()
    if not row:
        return None
    try:
        loaded = json.loads(str(row[0]))
    except json.JSONDecodeError:
        return None
    return loaded if isinstance(loaded, dict) else None


def _write_state_to_db(state: dict) -> None:
    for attempt in range(5):
        try:
            with _connect() as conn:
                conn.execute("BEGIN IMMEDIATE")
                _write_state_to_connection(conn, state)
                conn.commit()
            return
        except sqlite3.OperationalError as exc:
            if "locked" not in str(exc).lower() or attempt == 4:
                raise
            time.sleep(0.15 * (attempt + 1))


def _write_state_to_connection(conn: sqlite3.Connection, state: dict) -> None:
    conn.execute(
        """
        INSERT INTO app_state(key, payload, updated_at)
        VALUES('state', ?, ?)
        ON CONFLICT(key) DO UPDATE SET payload = excluded.payload, updated_at = excluded.updated_at
        """,
        (json.dumps(state, ensure_ascii=False), datetime.now(timezone.utc).isoformat()),
    )
