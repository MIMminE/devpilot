from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
import json
from pathlib import Path
from zoneinfo import ZoneInfo

from devpilot.app_state import read_state, write_state
from devpilot.config import AppConfig
from devpilot.features.issue_repositories import issue_repository_link_groups
from devpilot.integrations.git_repos import ahead_behind, current_branch, status_porcelain


STATUS_ORDER = [
    "assigned",
    "branch_ready",
    "in_progress",
    "implemented",
    "tested",
    "pr_ready",
    "reviewing",
    "merged",
    "reported",
    "done",
    "blocked",
]

STATUS_LABELS = {
    "assigned": "할당됨",
    "branch_ready": "브랜치 준비",
    "in_progress": "작업 중",
    "implemented": "구현 기록됨",
    "tested": "테스트 기록됨",
    "pr_ready": "PR 준비",
    "reviewing": "리뷰 중",
    "merged": "머지됨",
    "reported": "보고 등록",
    "done": "완료",
    "blocked": "막힘",
}

ACTIVE_STATUSES = {"assigned", "branch_ready", "in_progress", "implemented", "tested", "pr_ready", "reviewing", "blocked"}


@dataclass(frozen=True)
class WorkflowRepoState:
    repo_path: Path
    repo_name: str
    branch: str
    dirty_count: int
    ahead: int | None
    behind: int | None


def start_workflow(
    config: AppConfig,
    issue_key: str,
    *,
    summary: str = "",
    project: str = "",
    repo_path: str | None = None,
    branch: str = "",
    status: str = "assigned",
) -> dict:
    key = _normalize_issue_key(issue_key)
    now = _now(config)
    state = read_state()
    workflows = _workflow_map(state)
    workflow = _ensure_workflow(workflows, key, summary=summary, now=now)
    workflow["summary"] = summary.strip() or workflow.get("summary", "")
    workflow["project"] = _project_name(project, key, workflow)
    workflow["status"] = _advance_status(str(workflow.get("status") or "assigned"), status)
    workflow["updated_at"] = now
    if repo_path:
        _upsert_repository(workflow, repo_path, branch=branch)
    _append_event(workflow, "workflow_started", "일감 워크플로우를 시작했습니다.", now, repo_path=repo_path)
    state["issue_workflows"] = workflows
    write_state(state)
    return workflow


def record_branch_ready(config: AppConfig, issue_key: str, *, repo_path: str, branch: str, summary: str = "") -> dict:
    key = _normalize_issue_key(issue_key)
    now = _now(config)
    state = read_state()
    workflows = _workflow_map(state)
    workflow = _ensure_workflow(workflows, key, summary=summary, now=now)
    workflow["summary"] = summary.strip() or workflow.get("summary", "")
    workflow["status"] = _advance_status(str(workflow.get("status") or "assigned"), "branch_ready")
    workflow["updated_at"] = now
    _upsert_repository(workflow, repo_path, branch=branch, branch_started_at=now)
    _append_event(workflow, "branch_ready", f"작업 브랜치를 준비했습니다: {branch}", now, repo_path=repo_path)
    state["issue_workflows"] = workflows
    write_state(state)
    return workflow


def update_workflow_status(
    config: AppConfig,
    issue_key: str,
    *,
    status: str,
    summary: str = "",
    note: str = "",
    next_action: str = "",
    blocker: str = "",
) -> dict:
    _validate_status(status)
    key = _normalize_issue_key(issue_key)
    now = _now(config)
    state = read_state()
    workflows = _workflow_map(state)
    workflow = _ensure_workflow(workflows, key, summary=summary, now=now)
    workflow["summary"] = summary.strip() or workflow.get("summary", "")
    workflow["status"] = status
    workflow["updated_at"] = now
    if note.strip():
        _append_event(workflow, "status_note", note.strip(), now)
    if next_action.strip():
        _append_unique(workflow, "next_actions", next_action.strip())
    if blocker.strip():
        _append_unique(workflow, "blockers", blocker.strip())
    _append_event(workflow, "status_changed", f"상태를 {STATUS_LABELS[status]}(으)로 변경했습니다.", now)
    state["issue_workflows"] = workflows
    write_state(state)
    return workflow


def record_test_result(
    config: AppConfig,
    issue_key: str,
    *,
    command: str,
    result: str,
    summary: str = "",
    repo_path: str = "",
) -> dict:
    key = _normalize_issue_key(issue_key)
    normalized_result = result.strip().lower()
    if normalized_result not in {"pass", "fail", "skip"}:
        raise RuntimeError("테스트 결과는 pass, fail, skip 중 하나여야 합니다.")

    now = _now(config)
    state = read_state()
    workflows = _workflow_map(state)
    workflow = _ensure_workflow(workflows, key, summary="", now=now)
    tests = [item for item in workflow.get("tests", []) if isinstance(item, dict)]
    tests.append(
        {
            "command": command.strip() or "-",
            "result": normalized_result,
            "summary": summary.strip(),
            "repo_path": str(Path(repo_path).expanduser().resolve()) if repo_path.strip() else "",
            "recorded_at": now,
        }
    )
    workflow["tests"] = tests[-50:]
    if normalized_result == "pass":
        workflow["status"] = _advance_status(str(workflow.get("status") or "assigned"), "tested")
    elif normalized_result == "fail":
        workflow["status"] = "blocked"
    workflow["updated_at"] = now
    _append_event(workflow, "test_recorded", f"테스트 결과를 기록했습니다: {normalized_result}", now, repo_path=repo_path or None)
    state["issue_workflows"] = workflows
    write_state(state)
    return workflow


def record_analysis_request(
    config: AppConfig,
    issue_key: str,
    *,
    prompt_path: str,
    summary: str = "",
    thread_id: str = "",
    thread_name: str = "",
    thread_path: str = "",
    response_path: str = "",
) -> dict:
    key = _normalize_issue_key(issue_key)
    now = _now(config)
    state = read_state()
    workflows = _workflow_map(state)
    workflow = _ensure_workflow(workflows, key, summary=summary, now=now)
    workflow["summary"] = summary.strip() or workflow.get("summary", "")
    workflow["status"] = _advance_status(str(workflow.get("status") or "assigned"), "assigned")
    analysis = {
        "prompt_path": str(Path(prompt_path).expanduser()),
        "requested_at": now,
    }
    if thread_id.strip():
        analysis["thread_id"] = thread_id.strip()
    if thread_name.strip():
        analysis["thread_name"] = thread_name.strip()
    if thread_path.strip():
        analysis["thread_path"] = thread_path.strip()
    if response_path.strip():
        analysis["response_path"] = str(Path(response_path).expanduser())
        analysis["completed_at"] = now
    workflow["analysis"] = analysis
    workflow["updated_at"] = now
    _append_unique(workflow, "next_actions", "Codex 1차 분석 결과를 확인하고 작업 범위를 확정")
    event_message = "Codex 1차 분석 스레드를 생성했습니다." if thread_id.strip() else "Codex 1차 분석 요청서를 준비했습니다."
    _append_event(workflow, "analysis_requested", event_message, now)
    state["issue_workflows"] = workflows
    write_state(state)
    return workflow


def record_work_report(
    config: AppConfig,
    issue_key: str,
    *,
    summary: str,
    next_action: str = "",
    done: bool = False,
) -> dict:
    key = _normalize_issue_key(issue_key)
    now = _now(config)
    state = read_state()
    workflows = _workflow_map(state)
    workflow = _ensure_workflow(workflows, key, summary="", now=now)
    reports = [item for item in workflow.get("reports", []) if isinstance(item, dict)]
    reports.append({"summary": summary.strip(), "recorded_at": now})
    workflow["reports"] = reports[-50:]
    workflow["status"] = "done" if done else _advance_status(str(workflow.get("status") or "assigned"), "reported")
    workflow["updated_at"] = now
    if next_action.strip():
        _append_unique(workflow, "next_actions", next_action.strip())
    _append_event(workflow, "report_recorded", "일감 보고를 기록했습니다.", now)
    state["issue_workflows"] = workflows
    write_state(state)
    return workflow


def format_workflow(config: AppConfig, issue_key: str) -> str:
    key = _normalize_issue_key(issue_key)
    workflow = get_workflow(key)
    if not workflow:
        return f"{key} 일감 워크플로우 기록이 없습니다."
    return _format_workflow_detail(config, key, workflow)


def issue_director_briefing(config: AppConfig, issue_key: str, *, output_format: str = "text") -> str:
    key = _normalize_issue_key(issue_key)
    workflow = get_workflow(key)
    if not workflow:
        raise RuntimeError(f"{key} 일감 워크플로우 기록이 없습니다.")
    payload = _director_payload(config, key, workflow)
    if output_format == "json":
        return json.dumps(payload, ensure_ascii=False, indent=2)
    return _format_director_payload(payload)


def format_workflow_list(config: AppConfig, *, active_only: bool = True, output_format: str = "text") -> str:
    workflows = _workflow_map(read_state())
    rows = [
        (key, workflow)
        for key, workflow in sorted(workflows.items(), key=lambda item: str(item[1].get("updated_at") or ""), reverse=True)
        if not active_only or str(workflow.get("status") or "assigned") in ACTIVE_STATUSES
    ]
    if output_format == "json":
        return json.dumps({key: workflow for key, workflow in rows}, ensure_ascii=False, indent=2)
    if not rows:
        return "진행 중인 일감 워크플로우가 없습니다." if active_only else "일감 워크플로우 기록이 없습니다."
    lines = ["진행 중인 일감 워크플로우" if active_only else "일감 워크플로우"]
    for key, workflow in rows:
        lines.append(_format_workflow_summary(config, key, workflow))
    return "\n".join(lines)


def morning_workflow_briefing(config: AppConfig) -> str:
    workflows = _active_workflows()
    if not workflows:
        return "이어갈 일감 워크플로우가 없습니다."
    lines = ["이어갈 일감 워크플로우"]
    for key, workflow in workflows:
        lines.append(_format_routine_item(config, key, workflow, morning=True))
    return "\n".join(lines)


def evening_workflow_briefing(config: AppConfig) -> str:
    workflows = _workflow_map(read_state())
    if not workflows:
        return "오늘 정리할 일감 워크플로우가 없습니다."
    active = [(key, workflow) for key, workflow in workflows.items() if str(workflow.get("status") or "assigned") in ACTIVE_STATUSES]
    completed = [(key, workflow) for key, workflow in workflows.items() if str(workflow.get("status") or "") in {"reported", "done", "merged"}]
    lines = ["일감 워크플로우 정리"]
    if completed:
        lines.append("[완료/보고]")
        for key, workflow in sorted(completed, key=lambda item: str(item[1].get("updated_at") or ""), reverse=True)[:8]:
            lines.append(_format_routine_item(config, key, workflow, morning=False))
    if active:
        lines.append("[진행 중/막힘]")
        for key, workflow in sorted(active, key=lambda item: str(item[1].get("updated_at") or ""), reverse=True)[:10]:
            lines.append(_format_routine_item(config, key, workflow, morning=False))
    if len(lines) == 1:
        lines.append("오늘 정리할 진행 중 일감이 없습니다.")
    return "\n".join(lines)


def get_workflow(issue_key: str) -> dict | None:
    return _workflow_map(read_state()).get(_normalize_issue_key(issue_key))


def _format_workflow_detail(config: AppConfig, key: str, workflow: dict) -> str:
    lines = [
        f"{key} 일감 워크플로우",
        f"- 프로젝트: {_project_name('', key, workflow)}",
        f"- 요약: {workflow.get('summary') or '-'}",
        f"- 상태: {_status_label(str(workflow.get('status') or 'assigned'))}",
        f"- 진행도: {_progress_label(workflow)}",
        f"- 업데이트: {workflow.get('updated_at') or '-'}",
        "",
        "[Repository]",
    ]
    repos = _repository_items(workflow)
    if repos:
        lines.extend(f"- {item.get('repo_name')} | {item.get('repo_path')} | branch: {item.get('branch') or '-'}" for item in repos)
    else:
        lines.append("- 연결 repository 없음")
    analysis = workflow.get("analysis") if isinstance(workflow.get("analysis"), dict) else {}
    lines.extend(["", "[1차 분석]"])
    if analysis:
        lines.append(f"- 요청: {analysis.get('requested_at') or '-'}")
        lines.append(f"- Codex 프롬프트: {analysis.get('prompt_path') or '-'}")
        if analysis.get("thread_id"):
            lines.append(f"- Codex 스레드: {analysis.get('thread_name') or '-'} ({analysis.get('thread_id')})")
        if analysis.get("response_path"):
            lines.append(f"- 분석 결과: {analysis.get('response_path')}")
    else:
        lines.append("- 기록 없음")
    lines.extend(["", "[테스트]"])
    tests = [item for item in workflow.get("tests", []) if isinstance(item, dict)]
    if tests:
        lines.extend(f"- {item.get('result')} | {item.get('command')} | {item.get('summary') or '-'}" for item in tests[-5:])
    else:
        lines.append("- 기록 없음")
    lines.extend(["", "[다음 행동]"])
    next_actions = [str(item) for item in workflow.get("next_actions", []) if str(item).strip()]
    lines.extend(f"- {item}" for item in next_actions[-5:]) if next_actions else lines.append("- 없음")
    blockers = [str(item) for item in workflow.get("blockers", []) if str(item).strip()]
    if blockers:
        lines.extend(["", "[막힘]", *[f"- {item}" for item in blockers[-5:]]])
    lines.extend(["", "[현재 Git 신호]"])
    repo_states = _repo_states(config, workflow)
    if repo_states:
        for item in repo_states:
            sync = _sync_label(item.ahead, item.behind)
            dirty = f"변경 {item.dirty_count}개" if item.dirty_count else "변경 없음"
            lines.append(f"- {item.repo_name} [{item.branch}] {dirty}, {sync}")
    else:
        lines.append("- 확인 가능한 연결 repository 없음")
    return "\n".join(lines)


def _director_payload(config: AppConfig, key: str, workflow: dict) -> dict:
    repos = _repository_items(workflow)
    repo_states = _repo_states(config, workflow)
    tests = [item for item in workflow.get("tests", []) if isinstance(item, dict)]
    reports = [item for item in workflow.get("reports", []) if isinstance(item, dict)]
    blockers = [str(item) for item in workflow.get("blockers", []) if str(item).strip()]
    next_actions = [str(item) for item in workflow.get("next_actions", []) if str(item).strip()]
    status = str(workflow.get("status") or "assigned")
    summary = str(workflow.get("summary") or "").strip()
    issue_type = _director_issue_type(summary, blockers)
    branch_name = _director_branch_name(key, summary)
    risks = _director_risks(repos, repo_states, tests, blockers)

    sections = [
        {
            "id": "analysis",
            "title": "분석",
            "status": "완료" if workflow.get("analysis") else "필요",
            "body": _director_analysis_body(key, summary, issue_type, workflow),
            "items": [
                f"유형: {issue_type}",
                f"진행도: {_progress_label(workflow)}",
                f"현재 상태: {_status_label(status)}",
            ],
        },
        {
            "id": "plan",
            "title": "작업 계획",
            "status": "진행",
            "body": "현재 상태 기준으로 다음 승인 지점을 먼저 처리합니다.",
            "items": _director_plan(status, bool(workflow.get("analysis")), bool(repos), bool(repo_states), bool(tests), bool(reports)),
        },
        {
            "id": "repositories",
            "title": "Repository 후보",
            "status": "확정" if repos else "필요",
            "body": "연결된 repository와 로컬 Git 신호를 기준으로 작업 범위를 판단합니다.",
            "items": _director_repository_items(repos, repo_states),
        },
        {
            "id": "branch",
            "title": "브랜치 전략",
            "status": "준비" if repo_states else "대기",
            "body": "일감 키를 유지한 작업 브랜치와 worktree 기준으로 진행합니다.",
            "items": _director_branch_items(branch_name, repos, repo_states),
        },
        {
            "id": "tests",
            "title": "테스트 추천",
            "status": "기록됨" if tests else "추천",
            "body": "변경 repository가 확정되면 좁은 테스트부터 실행하고 결과를 일감에 기록합니다.",
            "items": _director_test_items(tests, repo_states),
        },
        {
            "id": "report",
            "title": "보고 초안",
            "status": "작성됨" if reports else "초안",
            "body": "오늘 한 일에 바로 붙일 수 있는 형태로 정리합니다.",
            "items": _director_report_items(key, summary, repos, repo_states, tests, reports, next_actions),
        },
    ]
    return {
        "issue_key": key,
        "project": _project_name("", key, workflow),
        "summary": summary,
        "issue_type": issue_type,
        "progress": _progress_label(workflow),
        "current_focus": _director_focus(status, workflow, repos, tests, reports),
        "next_approval": _director_next_approval(workflow, repos, tests, reports),
        "risks": risks,
        "sections": sections,
        "generated_at": _now(config),
        "mode": "local-director",
    }


def _format_director_payload(payload: dict) -> str:
    lines = [
        f"{payload['issue_key']} AI 작업 지휘관",
        f"- 프로젝트: {payload['project']}",
        f"- 유형: {payload['issue_type']}",
        f"- 현재 초점: {payload['current_focus']}",
        f"- 다음 승인: {payload['next_approval']}",
        "",
    ]
    for section in payload.get("sections", []):
        lines.append(f"[{section.get('title')}] {section.get('status')}")
        if section.get("body"):
            lines.append(f"- {section['body']}")
        for item in section.get("items", []):
            lines.append(f"- {item}")
        lines.append("")
    risks = payload.get("risks") or []
    if risks:
        lines.append("[리스크]")
        lines.extend(f"- {item}" for item in risks)
    return "\n".join(lines).strip()


def _director_issue_type(summary: str, blockers: list[str]) -> str:
    text = summary.lower()
    if blockers:
        return "막힘/지원 필요"
    if any(word in text for word in ("bug", "error", "fix", "오류", "버그", "장애", "실패")):
        return "버그 수정"
    if any(word in text for word in ("refactor", "리팩토링", "정리", "개선")):
        return "개선/리팩토링"
    if any(word in text for word in ("운영", "배포", "장애", "문의")):
        return "운영 요청"
    if any(word in text for word in ("추가", "신규", "기능", "feat")):
        return "신규 기능"
    return "일반 작업"


def _director_analysis_body(key: str, summary: str, issue_type: str, workflow: dict) -> str:
    if workflow.get("analysis"):
        return "Codex 1차 분석 기록이 있습니다. 분석 결과를 기준으로 repository와 테스트 범위를 확정하세요."
    subject = summary or key
    return f"{subject}은 현재 {issue_type} 성격으로 보입니다. 먼저 As-Is/To-Be와 영향 repository를 확정하는 승인이 필요합니다."


def _director_plan(status: str, has_analysis: bool, has_repos: bool, has_workspace: bool, has_tests: bool, has_reports: bool) -> list[str]:
    items: list[str] = []
    if not has_analysis:
        items.append("AI 1차 분석을 승인해 요구사항과 변경 범위를 정리")
    if not has_repos:
        items.append("변경 가능성이 있는 repository를 확정")
    if has_repos and not has_workspace:
        items.append("일감 전용 worktree와 작업 브랜치 생성 승인")
    if status not in {"implemented", "tested", "reported", "done", "merged"}:
        items.append("준비된 workspace에서 구현 진행 후 구현 완료 표시")
    if not has_tests:
        items.append("변경 범위에 맞는 테스트 실행 및 결과 기록")
    if not has_reports:
        items.append("테스트 근거를 포함해 오늘 한 일 보고 등록")
    return items or ["완료 처리와 workspace 정리 여부 확인"]


def _director_repository_items(repos: list[dict], repo_states: list[WorkflowRepoState]) -> list[str]:
    if not repos:
        return ["연결 repository 없음", "일감 본문과 키워드를 기준으로 후보 repository를 먼저 선택하세요."]
    state_by_path = {str(item.repo_path): item for item in repo_states}
    items: list[str] = []
    for repo in repos[:6]:
        path = str(Path(str(repo.get("repo_path") or "")).expanduser().resolve())
        state = state_by_path.get(path)
        if state:
            items.append(f"{state.repo_name}: {state.branch}, 변경 {state.dirty_count}개, {_sync_label(state.ahead, state.behind)}")
        else:
            items.append(f"{repo.get('repo_name') or Path(path).name}: Git 상태 확인 대기")
    return items


def _director_branch_items(branch_name: str, repos: list[dict], repo_states: list[WorkflowRepoState]) -> list[str]:
    if repo_states:
        return [f"{item.repo_name}: 현재 {item.branch}, {_sync_label(item.ahead, item.behind)}" for item in repo_states[:6]]
    if repos:
        return [f"권장 브랜치명: {branch_name}", "workspace 생성 승인 후 repository별 worktree에서 분기"]
    return [f"권장 브랜치명: {branch_name}", "repository 확정 전까지 브랜치 생성 대기"]


def _director_test_items(tests: list[dict], repo_states: list[WorkflowRepoState]) -> list[str]:
    if tests:
        latest = tests[-1]
        return [
            f"최근 기록: {latest.get('result') or '-'} / {latest.get('command') or '-'}",
            latest.get("summary") or "테스트 요약을 보강하면 보고 품질이 좋아집니다.",
        ]
    items = ["변경 파일 기준 단위 테스트 또는 가장 가까운 모듈 테스트 실행"]
    if repo_states:
        items.append("영향 repository별 빌드/린트/스모크 테스트 중 최소 1개 기록")
    else:
        items.append("repository 확정 후 테스트 명령을 추천받아 기록")
    return items


def _director_report_items(
    key: str,
    summary: str,
    repos: list[dict],
    repo_states: list[WorkflowRepoState],
    tests: list[dict],
    reports: list[dict],
    next_actions: list[str],
) -> list[str]:
    if reports:
        latest = reports[-1]
        return [latest.get("summary") or "보고 등록됨", f"등록 시각: {latest.get('recorded_at') or '-'}"]
    repo_text = ", ".join(item.repo_name for item in repo_states[:3])
    if not repo_text:
        repo_text = ", ".join(str(item.get("repo_name") or "").strip() for item in repos[:3] if str(item.get("repo_name") or "").strip())
    repo_text = repo_text or "repository 확정 전"
    test_text = f"테스트 {tests[-1].get('result')}" if tests else "테스트 기록 전"
    action = next_actions[-1] if next_actions else "다음 단계 승인 대기"
    return [
        f"{key} {summary or '일감'} 작업 진행",
        f"대상: {repo_text}",
        f"검증: {test_text}",
        f"다음: {action}",
    ]


def _director_risks(repos: list[dict], repo_states: list[WorkflowRepoState], tests: list[dict], blockers: list[str]) -> list[str]:
    risks: list[str] = []
    risks.extend(blockers[-3:])
    if not repos:
        risks.append("변경 repository가 확정되지 않았습니다.")
    if any((item.behind or 0) > 0 for item in repo_states):
        risks.append("원격 변경 반영 또는 rebase 확인이 필요합니다.")
    if any(item.dirty_count > 0 for item in repo_states):
        risks.append("커밋 전 로컬 미커밋 변경을 검토해야 합니다.")
    if not tests:
        risks.append("테스트 결과가 아직 기록되지 않았습니다.")
    return risks[:6]


def _director_focus(status: str, workflow: dict, repos: list[dict], tests: list[dict], reports: list[dict]) -> str:
    if workflow.get("analysis") is None:
        return "AI 1차 분석 승인"
    if not repos:
        return "repository 확정"
    if status in {"assigned", "branch_ready", "in_progress"}:
        return "구현 진행과 브랜치 상태 안정화"
    if not tests:
        return "테스트 실행과 결과 기록"
    if not reports:
        return "작업 보고 등록"
    return "완료 처리 확인"


def _director_next_approval(workflow: dict, repos: list[dict], tests: list[dict], reports: list[dict]) -> str:
    if workflow.get("analysis") is None:
        return "AI 분석 승인"
    if not repos:
        return "repository 확정 승인"
    if not any("issue-workspaces" in str(item.get("repo_path") or "") for item in repos):
        return "workspace 생성 승인"
    if not tests:
        return "테스트 결과 승인"
    if not reports:
        return "보고 등록 승인"
    return "완료 승인"


def _director_branch_name(key: str, summary: str) -> str:
    words = "".join(ch.lower() if ch.isascii() and ch.isalnum() else "-" for ch in summary).strip("-")
    slug = "-".join(part for part in words.split("-") if part)[:42] or "work"
    return f"feature/{key}-{slug}"


def _format_workflow_summary(config: AppConfig, key: str, workflow: dict) -> str:
    repo_states = _repo_states(config, workflow)
    repo_hint = ", ".join(f"{item.repo_name}:{item.branch}" for item in repo_states[:3]) or "-"
    return (
        f"- {_project_name('', key, workflow)} / {key} [{_status_label(str(workflow.get('status') or 'assigned'))}] "
        f"{workflow.get('summary') or '-'} | 진행도 {_progress_label(workflow)} | {repo_hint}"
    )


def _format_routine_item(config: AppConfig, key: str, workflow: dict, *, morning: bool) -> str:
    repo_states = _repo_states(config, workflow)
    status = str(workflow.get("status") or "assigned")
    lines = [f"- {_project_name('', key, workflow)} / {key} [{_status_label(status)}] {workflow.get('summary') or '-'}"]
    lines.append(f"  - 진행도: {_progress_label(workflow)}")
    for item in repo_states[:2]:
        dirty = f", 변경 {item.dirty_count}개" if item.dirty_count else ""
        lines.append(f"  - repository: {item.repo_name} / {item.branch}{dirty}")
    analysis = workflow.get("analysis") if isinstance(workflow.get("analysis"), dict) else {}
    if analysis:
        lines.append(f"  - 1차 분석: 요청 완료 / {analysis.get('prompt_path') or '-'}")
    next_actions = [str(item) for item in workflow.get("next_actions", []) if str(item).strip()]
    blockers = [str(item) for item in workflow.get("blockers", []) if str(item).strip()]
    tests = [item for item in workflow.get("tests", []) if isinstance(item, dict)]
    if blockers:
        lines.append(f"  - 막힘: {blockers[-1]}")
    elif next_actions:
        lines.append(f"  - 다음 행동: {next_actions[-1]}")
    elif morning:
        lines.append(f"  - 추천 다음 행동: {_recommended_next_action(status, bool(tests))}")
    elif tests:
        last = tests[-1]
        lines.append(f"  - 테스트: {last.get('result')} / {last.get('command')}")
    return "\n".join(lines)


def _recommended_next_action(status: str, has_tests: bool) -> str:
    if status == "assigned":
        return "repository 연결 후 Jira 키 포함 작업 브랜치 생성"
    if status == "branch_ready":
        return "Codex 작업 프롬프트로 구현 시작"
    if status in {"in_progress", "implemented"} and not has_tests:
        return "테스트 실행 후 결과 기록"
    if status == "tested":
        return "PR 작성 또는 작업 보고 등록"
    if status == "blocked":
        return "막힘 사유 해소 또는 공유"
    return "상태 확인 후 다음 작업 기록"


def _repo_states(config: AppConfig, workflow: dict) -> list[WorkflowRepoState]:
    managed = {item.path.expanduser().resolve(): item.path.expanduser().resolve() for item in config.repo_projects}
    states: list[WorkflowRepoState] = []
    for item in _repository_items(workflow):
        repo = Path(str(item.get("repo_path") or "")).expanduser().resolve()
        is_managed_source = repo in managed
        is_git_worktree = (repo / ".git").exists()
        if not is_git_worktree or (not is_managed_source and "issue-workspaces" not in str(repo)):
            continue
        try:
            branch = current_branch(repo)
            dirty_count = len(status_porcelain(repo))
            ahead, behind = ahead_behind(repo)
        except RuntimeError:
            continue
        states.append(WorkflowRepoState(repo, repo.name, branch, dirty_count, ahead, behind))
    return states


def _active_workflows() -> list[tuple[str, dict]]:
    workflows = _workflow_map(read_state())
    rows = [(key, workflow) for key, workflow in workflows.items() if str(workflow.get("status") or "assigned") in ACTIVE_STATUSES]
    return sorted(rows, key=lambda item: str(item[1].get("updated_at") or ""), reverse=True)


def _ensure_workflow(workflows: dict[str, dict], key: str, *, summary: str, now: str) -> dict:
    workflow = workflows.get(key)
    if not isinstance(workflow, dict):
        workflow = {
            "issue_key": key,
            "summary": summary.strip(),
            "project": _project_name("", key, {}),
            "status": "assigned",
            "created_at": now,
            "updated_at": now,
            "repositories": [],
            "events": [],
            "tests": [],
            "reports": [],
            "next_actions": [],
            "blockers": [],
        }
        workflows[key] = workflow
    _hydrate_linked_repositories(key, workflow)
    workflow["project"] = _project_name("", key, workflow)
    return workflow


def _project_name(project: str, key: str, workflow: dict) -> str:
    explicit = project.strip()
    if explicit:
        return explicit
    existing = str(workflow.get("project") or "").strip()
    if existing:
        return existing
    if "-" in key:
        prefix = key.split("-", 1)[0].strip()
        if prefix and prefix != "LOCAL":
            return prefix
    return "Inbox"


def _hydrate_linked_repositories(key: str, workflow: dict) -> None:
    links = issue_repository_link_groups().get(key, [])
    for link in links:
        _upsert_repository(workflow, str(link.repo_path), summary=link.summary)


def _upsert_repository(
    workflow: dict,
    repo_path: str,
    *,
    branch: str = "",
    summary: str = "",
    branch_started_at: str = "",
) -> None:
    repo = Path(repo_path).expanduser().resolve()
    repos = _repository_items(workflow)
    existing = None
    for item in repos:
        if Path(str(item.get("repo_path") or "")).expanduser().resolve() == repo:
            existing = item
            break
    if existing is None:
        existing = {
            "repo_path": str(repo),
            "repo_name": repo.name,
            "summary": summary.strip(),
            "branch": "",
            "linked_at": datetime.now().isoformat(timespec="seconds"),
        }
        repos.append(existing)
    if branch:
        existing["branch"] = branch
    if summary.strip():
        existing["summary"] = summary.strip()
    if branch_started_at:
        existing["branch_started_at"] = branch_started_at
    workflow["repositories"] = repos


def _repository_items(workflow: dict) -> list[dict]:
    return [item for item in workflow.get("repositories", []) if isinstance(item, dict)]


def _append_event(workflow: dict, event_type: str, message: str, now: str, *, repo_path: str | None = None) -> None:
    events = [item for item in workflow.get("events", []) if isinstance(item, dict)]
    events.append(
        {
            "type": event_type,
            "message": message,
            "repo_path": str(Path(repo_path).expanduser().resolve()) if repo_path else "",
            "created_at": now,
        }
    )
    workflow["events"] = events[-100:]


def _append_unique(workflow: dict, key: str, value: str) -> None:
    values = [str(item) for item in workflow.get(key, []) if str(item).strip()]
    if value not in values:
        values.append(value)
    workflow[key] = values[-20:]


def _workflow_map(state: dict) -> dict[str, dict]:
    raw = state.get("issue_workflows") or {}
    if not isinstance(raw, dict):
        return {}
    return {str(key).strip().upper(): value for key, value in raw.items() if isinstance(value, dict)}


def _normalize_issue_key(issue_key: str) -> str:
    key = issue_key.strip().upper()
    if not key:
        raise RuntimeError("Issue key is required.")
    return key


def _advance_status(current: str, target: str) -> str:
    _validate_status(target)
    if current == "blocked" and target not in {"done", "reported"}:
        return target
    try:
        return target if STATUS_ORDER.index(target) > STATUS_ORDER.index(current) else current
    except ValueError:
        return target


def _validate_status(status: str) -> None:
    if status not in STATUS_ORDER:
        raise RuntimeError(f"지원하지 않는 워크플로우 상태입니다: {status}")


def _status_label(status: str) -> str:
    return STATUS_LABELS.get(status, status)


def _progress_label(workflow: dict) -> str:
    status = str(workflow.get("status") or "assigned")
    if status == "blocked":
        return "확인 필요"
    try:
        index = STATUS_ORDER.index(status)
    except ValueError:
        index = 0
    total = STATUS_ORDER.index("done")
    percent = min(100, round(index / total * 100))
    return f"{percent}%"


def _sync_label(ahead: int | None, behind: int | None) -> str:
    parts = []
    if ahead:
        parts.append(f"ahead {ahead}")
    if behind:
        parts.append(f"behind {behind}")
    return ", ".join(parts) if parts else "동기화 특이사항 없음"


def _now(config: AppConfig) -> str:
    return datetime.now(ZoneInfo(config.general.timezone)).isoformat(timespec="seconds")
