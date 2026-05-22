from __future__ import annotations

from dataclasses import dataclass
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


def _codex_executable() -> Path:
    candidate = shutil.which("codex")
    if candidate:
        return Path(candidate)
    bundled = Path("/Applications/Codex.app/Contents/Resources/codex")
    if bundled.is_file():
        return bundled
    raise RuntimeError("Codex CLI를 찾지 못했습니다.")


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
