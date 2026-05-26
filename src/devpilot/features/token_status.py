from __future__ import annotations

from datetime import date, datetime
import json
import shutil
import subprocess
from typing import Any

from devpilot.app_state import read_state
from devpilot.config import AppConfig


def token_status(config: AppConfig, *, output_format: str = "text") -> str:
    metadata = _token_metadata()
    openai_required = config.features.ai and config.openai.provider in {"openai", "openai-api"}
    rows = [
        _token_row(
            "jira",
            "Jira API Token",
            bool(config.jira.base_url and config.jira.email and config.jira.api_token),
            config.jira.api_token,
            metadata,
            required=False,
            enabled=config.features.jira,
        ),
        _token_row(
            "slack",
            "Slack Bot Token",
            bool(config.slack.bot_token),
            config.slack.bot_token,
            metadata,
            required=False,
            enabled=config.features.notifications,
        ),
        _token_row(
            "openai",
            "OpenAI API Key",
            bool(config.openai.api_key),
            config.openai.api_key,
            metadata,
            required=openai_required,
            enabled=config.features.ai,
        ),
        _github_row(metadata),
        _github_ssh_row(),
    ]
    if output_format == "json":
        return json.dumps(rows, ensure_ascii=False, indent=2)
    return _format_text(rows)


def _token_row(
    key: str,
    name: str,
    configured: bool,
    secret: str,
    metadata: dict[str, dict[str, Any]],
    *,
    required: bool = True,
    enabled: bool = True,
) -> dict[str, Any]:
    meta = metadata.get(key, {})
    expires_at = str(meta.get("expires_at") or "").strip()
    days_remaining = _days_remaining(expires_at)
    if not enabled:
        return {
            "id": key,
            "name": name,
            "configured": configured,
            "required": False,
            "status": "optional",
            "detail": "선택 기능 비활성화. 수동 일감 등록과 Git 중심 흐름은 그대로 사용할 수 있습니다.",
            "expires_at": expires_at,
            "days_remaining": days_remaining,
            "source": str(meta.get("source") or "config.toml"),
            "token_hint": "",
        }
    status, detail = _status(configured, expires_at, days_remaining, required=required)
    if configured and not expires_at:
        detail = "설정됨. 만료일은 자동 확인이 어려워 별도 등록이 필요합니다."
    return {
        "id": key,
        "name": name,
        "configured": configured,
        "required": required,
        "status": status,
        "detail": detail,
        "expires_at": expires_at,
        "days_remaining": days_remaining,
        "source": str(meta.get("source") or "config.toml"),
        "token_hint": _mask_secret(secret),
    }


def _github_row(metadata: dict[str, dict[str, Any]]) -> dict[str, Any]:
    meta = metadata.get("github", {})
    gh_path = shutil.which("gh")
    configured = False
    detail = "gh CLI가 설치되어 있지 않습니다."
    if gh_path:
        try:
            result = subprocess.run([gh_path, "auth", "status"], capture_output=True, text=True, timeout=8, check=False)
            configured = result.returncode == 0
            detail = "gh auth status 정상" if configured else "gh auth login이 필요합니다."
        except Exception as exc:
            detail = f"gh 상태 확인 실패: {exc}"
    expires_at = str(meta.get("expires_at") or "").strip()
    days_remaining = _days_remaining(expires_at)
    status, expiry_detail = _status(configured, expires_at, days_remaining, required=True)
    if configured and not expires_at:
        expiry_detail = "설정됨. gh 토큰 만료일은 별도 등록이 필요합니다."
    if not configured:
        expiry_detail = detail
    return {
        "id": "github",
        "name": "GitHub CLI",
        "configured": configured,
        "required": True,
        "status": status,
        "detail": expiry_detail,
        "expires_at": expires_at,
        "days_remaining": days_remaining,
        "source": str(meta.get("source") or "gh auth"),
        "token_hint": "gh" if configured else "",
    }


def _github_ssh_row() -> dict[str, Any]:
    alias = "github-personal"
    configured = False
    detail = f"~/.ssh/config에 {alias} alias가 있으면 개인계정 push에 사용할 수 있습니다."
    try:
        result = subprocess.run(["ssh", "-G", alias], capture_output=True, text=True, timeout=5, check=False)
        output = result.stdout.lower()
        configured = result.returncode == 0 and "hostname github.com" in output
        if configured:
            identity = _first_ssh_value(result.stdout, "identityfile")
            detail = f"{alias} SSH alias 설정됨" + (f": {identity}" if identity else "")
        else:
            detail = f"{alias} SSH alias 확인 실패"
    except Exception as exc:
        detail = f"SSH alias 확인 실패: {exc}"
    return {
        "id": "github_ssh_personal",
        "name": "GitHub SSH Personal",
        "configured": configured,
        "required": False,
        "status": "ok" if configured else "optional",
        "detail": detail,
        "expires_at": "",
        "days_remaining": None,
        "source": "~/.ssh/config",
        "token_hint": alias if configured else "",
    }


def _first_ssh_value(output: str, key: str) -> str:
    prefix = key.lower() + " "
    for line in output.splitlines():
        if line.lower().startswith(prefix):
            return line[len(prefix) :].strip()
    return ""


def _token_metadata() -> dict[str, dict[str, Any]]:
    state = read_state()
    raw = state.get("token_metadata") or {}
    return raw if isinstance(raw, dict) else {}


def _status(configured: bool, expires_at: str, days_remaining: int | None, *, required: bool) -> tuple[str, str]:
    if not configured:
        if not required:
            return "optional", "선택 연동 미설정. 핵심 Git/수동 일감 흐름은 그대로 사용할 수 있습니다."
        return "missing", "토큰 또는 필수 설정이 없습니다."
    if days_remaining is None:
        return "unknown", "만료일 미등록"
    if days_remaining < 0:
        return "expired", f"{abs(days_remaining)}일 전에 만료되었습니다."
    if days_remaining <= 7:
        return "warning", f"{days_remaining}일 남았습니다."
    return "ok", f"{days_remaining}일 남았습니다."


def _days_remaining(value: str) -> int | None:
    if not value:
        return None
    try:
        expires = datetime.fromisoformat(value.replace("Z", "+00:00")).date()
    except ValueError:
        try:
            expires = date.fromisoformat(value)
        except ValueError:
            return None
    return (expires - date.today()).days


def _mask_secret(value: str) -> str:
    token = value.strip()
    if not token:
        return ""
    if len(token) <= 8:
        return "설정됨"
    return f"{token[:4]}...{token[-4:]}"


def _format_text(rows: list[dict[str, Any]]) -> str:
    lines = ["DevPilot 토큰 상태"]
    for row in rows:
        expires = row["expires_at"] or "만료일 미등록"
        hint = f" / {row['token_hint']}" if row["token_hint"] else ""
        lines.append(f"- [{row['status']}] {row['name']}: {row['detail']} ({expires}){hint}")
    return "\n".join(lines)
