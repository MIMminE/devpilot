from __future__ import annotations

from pathlib import Path
import json

from devpilot.app_state import app_data_dir
from devpilot.config import AppConfig
from devpilot.features.issue_workflow import get_workflow, record_analysis_request
from devpilot.features.jira_issues import issue_detail
from devpilot.integrations.codex_app_server import create_codex_thread


def draft_issue_analysis(config: AppConfig, issue_key: str, *, output_format: str = "text", codex_thread: bool = False) -> str:
    key = issue_key.strip().upper()
    if not key:
        raise RuntimeError("일감 키가 필요합니다.")

    detail = _issue_detail(config, key)
    prompt = _build_codex_analysis_prompt(detail)
    prompt_path = _write_analysis_prompt(key, prompt)
    summary = str(detail.get("summary") or "")
    thread = None
    response_path = None
    if codex_thread:
        thread_name = _thread_name(key, summary)
        workspace = _issue_workspace(key)
        _write_workspace_context(workspace, key, prompt)
        thread = create_codex_thread(workspace_path=workspace, thread_name=thread_name, prompt=prompt)
        response_path = _write_analysis_response(key, thread.response)

    record_analysis_request(
        config,
        key,
        prompt_path=str(prompt_path),
        summary=summary,
        thread_id=thread.thread_id if thread else "",
        thread_name=thread.thread_name if thread else "",
        thread_path=thread.thread_path if thread else "",
        response_path=str(response_path) if response_path else "",
    )

    if output_format == "json":
        payload = {
            "issue_key": key,
            "summary": summary,
            "prompt_path": str(prompt_path),
            "prompt": prompt,
        }
        if thread:
            payload.update(
                {
                    "codex_thread_id": thread.thread_id,
                    "codex_thread_name": thread.thread_name,
                    "codex_thread_path": thread.thread_path,
                    "codex_workspace": thread.cwd,
                    "response_path": str(response_path),
                    "response": thread.response,
                }
            )
        return json.dumps(payload, ensure_ascii=False, indent=2)

    lines = [
        f"{key} 1차 분석 요청서를 준비했습니다.",
        f"- 요약: {summary or '-'}",
        f"- Codex 프롬프트: {prompt_path}",
    ]
    if thread:
        lines.extend(
            [
                f"- Codex 스레드: {thread.thread_name}",
                f"- thread id: {thread.thread_id}",
                f"- workspace: {thread.cwd}",
                f"- 분석 결과: {response_path}",
                "",
                thread.response or "-",
            ]
        )
    else:
        lines.extend(["", prompt])
    return "\n".join(lines).strip()


def _write_analysis_prompt(issue_key: str, prompt: str) -> Path:
    directory = app_data_dir() / "issue-analysis"
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / f"{issue_key.lower()}-analysis-prompt.md"
    path.write_text(prompt.rstrip() + "\n", encoding="utf-8")
    return path


def _write_analysis_response(issue_key: str, response: str) -> Path:
    directory = app_data_dir() / "issue-analysis"
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / f"{issue_key.lower()}-analysis-result.md"
    path.write_text(response.rstrip() + "\n", encoding="utf-8")
    return path


def _issue_workspace(issue_key: str) -> Path:
    return app_data_dir() / "codex-workspaces" / issue_key


def _write_workspace_context(workspace: Path, issue_key: str, prompt: str) -> None:
    workspace.mkdir(parents=True, exist_ok=True)
    (workspace / f"{issue_key}-analysis.md").write_text(prompt.rstrip() + "\n", encoding="utf-8")


def _thread_name(issue_key: str, summary: str) -> str:
    suffix = summary.strip()
    if len(suffix) > 50:
        suffix = suffix[:47].rstrip() + "..."
    return f"[{issue_key}] 1차 분석" + (f" - {suffix}" if suffix else "")


def _issue_detail(config: AppConfig, issue_key: str) -> dict:
    if config.features.jira:
        try:
            return json.loads(issue_detail(config, issue_key, output_format="json"))
        except Exception:
            workflow = get_workflow(issue_key)
            if workflow:
                return _workflow_detail(issue_key, workflow)
            raise
    workflow = get_workflow(issue_key)
    if workflow:
        return _workflow_detail(issue_key, workflow)
    return {
        "key": issue_key,
        "url": "",
        "summary": "",
        "status": "assigned",
        "issue_type": "Manual",
        "priority": "",
        "project": "Inbox",
        "assignee": "",
        "reporter": "",
        "created": "",
        "updated": "",
        "due": "",
        "description": "Jira 연동이 꺼져 있어 로컬 수동 일감 정보만 기준으로 분석합니다.",
        "attachments": [],
        "comments": [],
    }


def _workflow_detail(issue_key: str, workflow: dict) -> dict:
    return {
        "key": issue_key,
        "url": "",
        "summary": str(workflow.get("summary") or ""),
        "status": str(workflow.get("status") or "assigned"),
        "issue_type": "Manual",
        "priority": "",
        "project": str(workflow.get("project") or "Inbox"),
        "assignee": "",
        "reporter": "",
        "created": str(workflow.get("created_at") or ""),
        "updated": str(workflow.get("updated_at") or ""),
        "due": "",
        "description": _workflow_description(workflow),
        "attachments": [],
        "comments": [],
    }


def _workflow_description(workflow: dict) -> str:
    parts = []
    summary = str(workflow.get("summary") or "").strip()
    if summary:
        parts.append(summary)
    next_actions = [str(item).strip() for item in workflow.get("next_actions", []) if str(item).strip()]
    if next_actions:
        parts.extend(["", "다음 행동:", *[f"- {item}" for item in next_actions[-5:]]])
    blockers = [str(item).strip() for item in workflow.get("blockers", []) if str(item).strip()]
    if blockers:
        parts.extend(["", "막힘:", *[f"- {item}" for item in blockers[-5:]]])
    return "\n".join(parts).strip() or "로컬 수동 일감입니다. 제목과 현재 워크플로우 기록을 기준으로 분석합니다."


def _build_codex_analysis_prompt(detail: dict) -> str:
    comments = detail.get("comments") if isinstance(detail.get("comments"), list) else []
    attachments = detail.get("attachments") if isinstance(detail.get("attachments"), list) else []
    comment_lines = [
        f"- {item.get('author') or '-'} ({item.get('created') or '-'}): {item.get('body') or '-'}"
        for item in comments
        if isinstance(item, dict)
    ]
    attachment_lines = [
        f"- {item.get('filename') or '-'} ({item.get('mime_type') or '-'})"
        for item in attachments
        if isinstance(item, dict)
    ]
    return "\n".join(
        [
            "# 일감 1차 분석 요청",
            "",
            "너는 내 개발 매니저이자 구현 파트너다. 아래 일감을 먼저 파악하고, 바로 작업에 들어가기 전에 판단 가능한 범위와 확인이 필요한 범위를 분리해서 정리해줘.",
            "",
            "## 출력 형식",
            "",
            "다음 섹션을 한국어로 작성해줘.",
            "",
            "1. 일감 유형: 신규 기능, 기능 개선, 버그 수정, 리팩토링, 운영 대응, 조사 중 가장 가까운 유형과 판단 근거",
            "2. As-Is: 기존 동작/문제/제약이 보이면 정리하고, 신규 기능이라 As-Is가 약하면 '신규 기능으로 명확한 기존 상태 없음'처럼 표시",
            "3. To-Be: 완료 후 기대 동작과 사용자/업무 흐름",
            "4. 작업 범위 후보: 프론트엔드, 백엔드, 데이터, 설정, 문서, 테스트 등 예상 영향 범위",
            "5. 우선 확인 질문: 구현 전에 물어봐야 할 질문을 최대 5개",
            "6. 리스크와 의존성: 불명확한 요구사항, 외부 연동, 배포/권한/데이터 위험",
            "7. 추천 다음 행동: 브랜치 생성, 코드 탐색, 설계 보강, 담당자 확인 등 바로 할 일",
            "",
            "## 일감",
            "",
            f"- 키: {detail.get('key') or '-'}",
            f"- 링크: {detail.get('url') or '-'}",
            f"- 제목: {detail.get('summary') or '-'}",
            f"- 상태: {detail.get('status') or '-'}",
            f"- 유형: {detail.get('issue_type') or '-'}",
            f"- 우선순위: {detail.get('priority') or '-'}",
            f"- 프로젝트: {detail.get('project') or '-'}",
            f"- 담당자: {detail.get('assignee') or '-'}",
            f"- 보고자: {detail.get('reporter') or '-'}",
            f"- 생성일: {detail.get('created') or '-'}",
            f"- 수정일: {detail.get('updated') or '-'}",
            f"- 마감일: {detail.get('due') or '-'}",
            "",
            "## 설명",
            "",
            str(detail.get("description") or "-"),
            "",
            f"## 첨부 {len(attachment_lines)}개",
            "",
            "\n".join(attachment_lines) if attachment_lines else "-",
            "",
            f"## 최근 댓글 {len(comment_lines)}개",
            "",
            "\n".join(comment_lines) if comment_lines else "-",
        ]
    ).strip()
