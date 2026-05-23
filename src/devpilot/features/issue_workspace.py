from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
import json
from pathlib import Path
import re

from devpilot.app_state import app_data_dir, read_state, update_state
from devpilot.config import AppConfig
from devpilot.features.dev_assistant import branch_name
from devpilot.features.issue_repositories import issue_repository_link_groups
from devpilot.features.issue_workflow import record_branch_ready, start_workflow
from devpilot.integrations.git_repos import (
    configured_repository_projects,
    current_branch,
    default_base_branch,
    fetch,
    git,
    git_result,
    require_clean_worktree,
    status_porcelain,
)


STATE_KEY = "issue_workspaces"


@dataclass(frozen=True)
class WorkspaceRepoPlan:
    source_path: Path
    repo_name: str
    base_branch: str
    work_branch: str
    worktree_path: Path


def prepare_issue_workspace(
    config: AppConfig,
    issue_key: str,
    *,
    repo_paths: list[str] | None = None,
    summary: str = "",
    prefix: str = "feature",
    base_branch: str = "",
    force: bool = False,
) -> str:
    key = _normalize_issue_key(issue_key)
    repos = _target_repositories(config, key, repo_paths or [])
    if not repos:
        raise RuntimeError("workspace에 배치할 repository가 없습니다. --repo를 지정하거나 Jira 일감에 repository를 연결해 주세요.")

    workspace = _workspace_root(key)
    repos_root = workspace / "repos"
    repos_root.mkdir(parents=True, exist_ok=True)
    plan = [_repo_plan(config, key, repo, summary=summary, prefix=prefix, base_branch=base_branch, repos_root=repos_root) for repo in repos]

    existing = _workspace_map(read_state()).get(key)
    if existing and not force:
        return format_issue_workspace(key, output_format="text")

    created: list[dict[str, str]] = []
    for item in plan:
        _prepare_repo_worktree(item, force=force)
        created.append(
            {
                "source_path": str(item.source_path),
                "repo_name": item.repo_name,
                "base_branch": item.base_branch,
                "work_branch": item.work_branch,
                "worktree_path": str(item.worktree_path),
            }
        )
        record_branch_ready(config, key, repo_path=str(item.worktree_path), branch=item.work_branch, summary=summary)

    context_path = _write_context(workspace, key, summary=summary, repos=created)
    now = _now()
    def mutate(state: dict) -> None:
        workspaces = _workspace_map(state)
        workspaces[key] = {
            "issue_key": key,
            "summary": summary.strip(),
            "workspace_path": str(workspace),
            "context_path": str(context_path),
            "created_at": now,
            "updated_at": now,
            "repositories": created,
        }
        state[STATE_KEY] = workspaces

    update_state(mutate)
    start_workflow(config, key, summary=summary, status="branch_ready")
    return _format_prepared(key, workspace, context_path, created)


def format_issue_workspace(issue_key: str, *, output_format: str = "text") -> str:
    key = _normalize_issue_key(issue_key)
    workspace = _workspace_map(read_state()).get(key)
    if output_format == "json":
        return json.dumps(workspace or {}, ensure_ascii=False, indent=2)
    if not workspace:
        return f"{key} issue workspace가 없습니다."
    return _format_workspace_detail(workspace)


def cleanup_issue_workspace(issue_key: str, *, force: bool = False) -> str:
    key = _normalize_issue_key(issue_key)
    state = read_state()
    workspaces = _workspace_map(state)
    workspace = workspaces.get(key)
    if not workspace:
        return f"{key} issue workspace가 없습니다."

    removed: list[str] = []
    for repo in _workspace_repositories(workspace):
        source = Path(repo.get("source_path") or "").expanduser()
        worktree = Path(repo.get("worktree_path") or "").expanduser()
        if not worktree.exists():
            removed.append(f"{repo.get('repo_name')}: 이미 없음")
            continue
        if not force:
            require_clean_worktree(worktree, action="workspace 정리")
        args = ["worktree", "remove", str(worktree)]
        if force:
            args.append("--force")
        result = git_result(source, *args)
        if result.returncode != 0:
            detail = (result.stderr or result.stdout or "").strip()
            raise RuntimeError(f"{repo.get('repo_name')} worktree 제거 실패: {detail}")
        removed.append(f"{repo.get('repo_name')}: 제거 완료")

    def mutate(state: dict) -> None:
        workspaces = _workspace_map(state)
        workspaces.pop(key, None)
        state[STATE_KEY] = workspaces

    update_state(mutate)
    return "\n".join([f"{key} issue workspace 정리 완료", *[f"- {line}" for line in removed]])


def _target_repositories(config: AppConfig, issue_key: str, repo_paths: list[str]) -> list[Path]:
    managed = {item.path.expanduser().resolve(): item for item in configured_repository_projects(config)}
    if repo_paths:
        targets = [Path(value).expanduser().resolve() for value in repo_paths if value.strip()]
    else:
        links = issue_repository_link_groups().get(issue_key) or []
        targets = [item.repo_path.expanduser().resolve() for item in links]
    invalid = [str(item) for item in targets if item not in managed]
    if invalid:
        raise RuntimeError("관리 대상 repository만 workspace에 배치할 수 있습니다:\n" + "\n".join(f"- {item}" for item in invalid))
    output: list[Path] = []
    for item in targets:
        if item not in output:
            output.append(item)
    return output


def _repo_plan(
    config: AppConfig,
    issue_key: str,
    repo: Path,
    *,
    summary: str,
    prefix: str,
    base_branch: str,
    repos_root: Path,
) -> WorkspaceRepoPlan:
    configured = {item.path.expanduser().resolve(): item for item in configured_repository_projects(config)}
    configured_repo = configured.get(repo)
    base = base_branch.strip() or (configured_repo.base_branch if configured_repo else "")
    base = base or default_base_branch(repo)
    return WorkspaceRepoPlan(
        source_path=repo,
        repo_name=repo.name,
        base_branch=base,
        work_branch=branch_name(issue_key, summary or repo.name, prefix=prefix),
        worktree_path=repos_root / _safe_repo_dir(repo.name),
    )


def _prepare_repo_worktree(plan: WorkspaceRepoPlan, *, force: bool) -> None:
    if not (plan.source_path / ".git").is_dir():
        raise RuntimeError(f"Git repository를 찾지 못했습니다: {plan.source_path}")
    require_clean_worktree(plan.source_path, action="workspace 준비")
    fetch(plan.source_path)
    _ensure_base_branch(plan.source_path, plan.base_branch)
    if plan.worktree_path.exists():
        if force:
            require_clean_worktree(plan.worktree_path, action="workspace 재생성")
            git(plan.source_path, "worktree", "remove", str(plan.worktree_path), "--force")
        else:
            return
    if _local_branch_exists(plan.source_path, plan.work_branch):
        git(plan.source_path, "worktree", "add", str(plan.worktree_path), plan.work_branch)
        return
    base_ref = f"origin/{plan.base_branch}" if _remote_branch_exists(plan.source_path, plan.base_branch) else plan.base_branch
    git(plan.source_path, "worktree", "add", "-b", plan.work_branch, str(plan.worktree_path), base_ref)


def _ensure_base_branch(repo: Path, base_branch: str) -> None:
    remote = f"origin/{base_branch}"
    if _local_branch_exists(repo, base_branch):
        current = current_branch(repo)
        if current != base_branch:
            git(repo, "checkout", base_branch)
        if _remote_branch_exists(repo, base_branch):
            git(repo, "merge", "--ff-only", remote)
        return
    if _remote_branch_exists(repo, base_branch):
        git(repo, "checkout", "-b", base_branch, "--track", remote)
        git(repo, "merge", "--ff-only", remote)
        return
    raise RuntimeError(f"{repo.name} 기준 브랜치를 찾지 못했습니다: {base_branch}")


def _local_branch_exists(repo: Path, branch: str) -> bool:
    return git_result(repo, "show-ref", "--verify", "--quiet", f"refs/heads/{branch}").returncode == 0


def _remote_branch_exists(repo: Path, branch: str) -> bool:
    return git_result(repo, "show-ref", "--verify", "--quiet", f"refs/remotes/origin/{branch}").returncode == 0


def _write_context(workspace: Path, issue_key: str, *, summary: str, repos: list[dict[str, str]]) -> Path:
    path = workspace / "context.md"
    lines = [
        f"# {issue_key} Issue Workspace",
        "",
        f"- 요약: {summary.strip() or '-'}",
        f"- 생성: {_now()}",
        "",
        "## Repositories",
        "",
    ]
    for repo in repos:
        lines.extend(
            [
                f"### {repo['repo_name']}",
                f"- source: {repo['source_path']}",
                f"- worktree: {repo['worktree_path']}",
                f"- base: {repo['base_branch']}",
                f"- branch: {repo['work_branch']}",
                "",
            ]
        )
    path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
    return path


def _format_prepared(issue_key: str, workspace: Path, context_path: Path, repos: list[dict[str, str]]) -> str:
    lines = [
        f"{issue_key} issue workspace 준비 완료",
        f"- workspace: {workspace}",
        f"- context: {context_path}",
        "",
        "[Repositories]",
    ]
    for repo in repos:
        lines.append(f"- {repo['repo_name']} | {repo['work_branch']} | {repo['worktree_path']}")
    return "\n".join(lines)


def _format_workspace_detail(workspace: dict) -> str:
    lines = [
        f"{workspace.get('issue_key')} issue workspace",
        f"- 요약: {workspace.get('summary') or '-'}",
        f"- 경로: {workspace.get('workspace_path') or '-'}",
        f"- context: {workspace.get('context_path') or '-'}",
        f"- 업데이트: {workspace.get('updated_at') or '-'}",
        "",
        "[Repositories]",
    ]
    for repo in _workspace_repositories(workspace):
        worktree = Path(str(repo.get("worktree_path") or "")).expanduser()
        dirty = len(status_porcelain(worktree)) if worktree.exists() else 0
        branch = current_branch(worktree) if worktree.exists() else repo.get("work_branch", "-")
        lines.append(f"- {repo.get('repo_name')} [{branch}] 변경 {dirty}개 | {worktree}")
    return "\n".join(lines)


def _workspace_repositories(workspace: dict) -> list[dict[str, str]]:
    value = workspace.get("repositories")
    return [item for item in value if isinstance(item, dict)] if isinstance(value, list) else []


def _workspace_map(state: dict) -> dict:
    value = state.get(STATE_KEY)
    return dict(value) if isinstance(value, dict) else {}


def _workspace_root(issue_key: str) -> Path:
    return app_data_dir() / "issue-workspaces" / issue_key


def _normalize_issue_key(value: str) -> str:
    key = value.strip().upper()
    if not re.fullmatch(r"[A-Z][A-Z0-9]+-\d+", key):
        raise RuntimeError("Jira 이슈 키 형식이 필요합니다. 예: LMS-123")
    return key


def _safe_repo_dir(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9._-]+", "-", value).strip("-") or "repo"


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()
