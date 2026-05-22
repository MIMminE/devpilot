from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
import json
import select
import shutil
import subprocess
import time


@dataclass(frozen=True)
class CodexThreadResult:
    thread_id: str
    thread_name: str
    thread_path: str
    cwd: str
    response: str


@dataclass(frozen=True)
class CodexThreadSummary:
    thread_id: str
    name: str
    cwd: str
    path: str
    source: str
    created_at: str
    updated_at: str


@dataclass(frozen=True)
class CodexProjectSummary:
    project_name: str
    cwd: str
    threads: list[CodexThreadSummary]


def create_codex_thread(
    *,
    workspace_path: str | Path,
    thread_name: str,
    prompt: str,
    timeout_seconds: int = 180,
) -> CodexThreadResult:
    workspace = Path(workspace_path).expanduser().resolve()
    workspace.mkdir(parents=True, exist_ok=True)
    codex = _codex_executable()
    started_at = time.monotonic()
    process = subprocess.Popen(
        [str(codex), "app-server", "--listen", "stdio://"],
        cwd=str(workspace),
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        bufsize=1,
    )
    try:
        _send(process, 1, "initialize", {"clientInfo": {"name": "devpilot", "version": "0.1.0"}, "capabilities": {"experimentalApi": True}})
        _read_until_response(process, 1, started_at=started_at, timeout_seconds=timeout_seconds)

        _send(
            process,
            2,
            "thread/start",
            {
                "cwd": str(workspace),
                "experimentalRawEvents": False,
                "persistExtendedHistory": False,
                "sessionStartSource": "startup",
                "threadSource": "user",
                "sandbox": "read-only",
                "approvalPolicy": "never",
            },
        )
        start_response, _ = _read_until_response(process, 2, started_at=started_at, timeout_seconds=timeout_seconds)
        thread = ((start_response.get("result") or {}).get("thread") or {}) if isinstance(start_response, dict) else {}
        thread_id = str(thread.get("id") or "")
        if not thread_id:
            raise RuntimeError("Codex thread/start 응답에서 thread id를 찾지 못했습니다.")

        _send(process, 3, "thread/name/set", {"threadId": thread_id, "name": thread_name})
        _read_until_response(process, 3, started_at=started_at, timeout_seconds=timeout_seconds)

        _send(
            process,
            4,
            "turn/start",
            {
                "threadId": thread_id,
                "input": [{"type": "text", "text": prompt, "text_elements": []}],
                "approvalPolicy": "never",
                "sandboxPolicy": {"type": "readOnly", "networkAccess": False},
            },
        )
        _, response = _read_until_turn_completed(process, thread_id, started_at=started_at, timeout_seconds=timeout_seconds)
        return CodexThreadResult(
            thread_id=thread_id,
            thread_name=thread_name,
            thread_path=str(thread.get("path") or ""),
            cwd=str(workspace),
            response=response.strip(),
        )
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()


def list_codex_projects(*, timeout_seconds: int = 20) -> list[CodexProjectSummary]:
    codex = _codex_executable()
    started_at = time.monotonic()
    process = subprocess.Popen(
        [str(codex), "app-server", "--listen", "stdio://"],
        cwd=str(Path.home()),
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        bufsize=1,
    )
    try:
        _send(process, 1, "initialize", {"clientInfo": {"name": "devpilot", "version": "0.1.0"}, "capabilities": {"experimentalApi": True}})
        _read_until_response(process, 1, started_at=started_at, timeout_seconds=timeout_seconds)
        _send(process, 2, "thread/list", {})
        response, _ = _read_until_response(process, 2, started_at=started_at, timeout_seconds=timeout_seconds)
        threads = [_thread_summary(item) for item in _thread_items(response)]
        return _group_projects([item for item in threads if item.thread_id])
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()


def _codex_executable() -> Path:
    candidate = shutil.which("codex")
    if candidate:
        return Path(candidate)
    bundled = Path("/Applications/Codex.app/Contents/Resources/codex")
    if bundled.is_file():
        return bundled
    raise RuntimeError("Codex CLI를 찾지 못했습니다.")


def _thread_items(response: dict) -> list[dict]:
    result = response.get("result")
    if isinstance(result, list):
        return [item for item in result if isinstance(item, dict)]
    if not isinstance(result, dict):
        return []
    for key in ("data", "threads", "items", "entries"):
        value = result.get(key)
        if isinstance(value, list):
            return [item for item in value if isinstance(item, dict)]
    return []


def _thread_summary(item: dict) -> CodexThreadSummary:
    thread = item.get("thread") if isinstance(item.get("thread"), dict) else item
    metadata = thread.get("metadata") if isinstance(thread.get("metadata"), dict) else {}
    cwd = _first_text(thread, metadata, keys=("cwd", "workspace", "workspacePath", "projectPath"))
    path = _first_text(thread, metadata, keys=("path", "sessionPath", "threadPath"))
    name = _first_text(thread, metadata, keys=("name", "title", "displayName"))
    source = _first_text(thread, metadata, keys=("source", "threadSource", "sessionStartSource"))
    created_at = _first_text(thread, metadata, keys=("createdAt", "created_at", "created"))
    updated_at = _first_text(thread, metadata, keys=("updatedAt", "updated_at", "updated", "lastActivityAt"))
    thread_id = _first_text(thread, metadata, keys=("id", "threadId", "sessionId"))
    return CodexThreadSummary(
        thread_id=thread_id,
        name=name or "(제목 없음)",
        cwd=cwd,
        path=path,
        source=source,
        created_at=created_at,
        updated_at=updated_at,
    )


def _first_text(*values: dict, keys: tuple[str, ...]) -> str:
    for value in values:
        for key in keys:
            item = value.get(key)
            if item is not None:
                if key.lower().endswith("at") or key in {"created", "updated"}:
                    return _timestamp_text(item)
                return str(item)
    return ""


def _timestamp_text(value: object) -> str:
    if isinstance(value, (int, float)):
        return datetime.fromtimestamp(value, timezone.utc).astimezone().isoformat(timespec="minutes")
    return str(value)


def _group_projects(threads: list[CodexThreadSummary]) -> list[CodexProjectSummary]:
    grouped: dict[str, list[CodexThreadSummary]] = {}
    for thread in threads:
        key = thread.cwd or "(프로젝트 없음)"
        grouped.setdefault(key, []).append(thread)
    projects = [
        CodexProjectSummary(project_name=_project_name(cwd), cwd=cwd, threads=_sort_threads(items))
        for cwd, items in grouped.items()
    ]
    return sorted(projects, key=lambda item: item.project_name.lower())


def _sort_threads(threads: list[CodexThreadSummary]) -> list[CodexThreadSummary]:
    return sorted(threads, key=lambda item: item.updated_at or item.created_at or item.name, reverse=True)


def _project_name(cwd: str) -> str:
    if not cwd or cwd == "(프로젝트 없음)":
        return "프로젝트 없음"
    return Path(cwd).name or cwd


def _send(process: subprocess.Popen[str], request_id: int, method: str, params: dict) -> None:
    if process.stdin is None:
        raise RuntimeError("Codex app-server stdin이 열려 있지 않습니다.")
    process.stdin.write(json.dumps({"id": request_id, "method": method, "params": params}, ensure_ascii=False, separators=(",", ":")) + "\n")
    process.stdin.flush()


def _read_until_response(
    process: subprocess.Popen[str],
    request_id: int,
    *,
    started_at: float,
    timeout_seconds: int,
) -> tuple[dict, str]:
    response_text: list[str] = []
    while time.monotonic() - started_at < timeout_seconds:
        line = _read_line(process)
        if not line:
            continue
        payload = _json_line(line)
        if not payload:
            continue
        response_text.extend(_agent_delta(payload))
        if payload.get("id") == request_id:
            if "error" in payload:
                raise RuntimeError(f"Codex app-server 요청 실패: {payload['error']}")
            return payload, "".join(response_text)
    raise RuntimeError("Codex app-server 응답 대기 시간이 초과되었습니다.")


def _read_until_turn_completed(
    process: subprocess.Popen[str],
    thread_id: str,
    *,
    started_at: float,
    timeout_seconds: int,
) -> tuple[dict, str]:
    response_text: list[str] = []
    last_payload: dict = {}
    while time.monotonic() - started_at < timeout_seconds:
        line = _read_line(process)
        if not line:
            continue
        payload = _json_line(line)
        if not payload:
            continue
        last_payload = payload
        response_text.extend(_agent_delta(payload))
        if payload.get("method") == "item/completed":
            item = ((payload.get("params") or {}).get("item") or {}) if isinstance(payload.get("params"), dict) else {}
            if item.get("type") == "agentMessage" and not response_text:
                text = str(item.get("text") or "")
                if text:
                    response_text.append(text)
        if payload.get("method") == "turn/completed" and ((payload.get("params") or {}).get("threadId") == thread_id):
            return payload, "".join(response_text)
    raise RuntimeError("Codex turn 완료 대기 시간이 초과되었습니다.")


def _read_line(process: subprocess.Popen[str]) -> str:
    if process.stdout is None:
        return ""
    ready, _, _ = select.select([process.stdout], [], [], 0.25)
    if not ready:
        if process.poll() is not None:
            raise RuntimeError("Codex app-server가 예상보다 먼저 종료되었습니다.")
        return ""
    line = process.stdout.readline()
    if not line and process.poll() is not None:
        raise RuntimeError("Codex app-server가 예상보다 먼저 종료되었습니다.")
    return line.strip()


def _json_line(line: str) -> dict | None:
    if not line.startswith("{"):
        return None
    try:
        payload = json.loads(line)
    except json.JSONDecodeError:
        return None
    return payload if isinstance(payload, dict) else None


def _agent_delta(payload: dict) -> list[str]:
    if payload.get("method") != "item/agentMessage/delta":
        return []
    params = payload.get("params") if isinstance(payload.get("params"), dict) else {}
    delta = params.get("delta")
    return [str(delta)] if delta else []
