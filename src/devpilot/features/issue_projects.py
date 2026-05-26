from __future__ import annotations

from datetime import datetime, timezone
import json

from devpilot.app_state import read_state, update_state
from devpilot.config import AppConfig
from devpilot.features.issue_workflow import start_workflow
from devpilot.integrations.jira import JiraClient


def add_issue_project(name: str, *, jira_project_key: str = "") -> dict:
    normalized = _normalize_project_name(name)
    now = datetime.now(timezone.utc).isoformat()

    def mutate(state: dict) -> dict:
        projects = _project_map(state)
        project = projects.get(normalized) or {
            "name": normalized,
            "created_at": now,
        }
        project["updated_at"] = now
        if jira_project_key.strip():
            project["jira_project_key"] = jira_project_key.strip().upper()
        projects[normalized] = project
        state["issue_projects"] = projects
        return project

    return update_state(mutate)


def issue_projects(*, include_workflows: bool = True) -> list[dict]:
    state = read_state()
    projects = _project_map(state)
    if include_workflows:
        for workflow in (state.get("issue_workflows") or {}).values():
            if not isinstance(workflow, dict):
                continue
            name = str(workflow.get("project") or "").strip()
            if name and name not in projects:
                projects[name] = {
                    "name": name,
                    "created_at": "",
                    "updated_at": "",
                    "jira_project_key": "",
                    "implicit": True,
                }
    return sorted(projects.values(), key=lambda item: str(item.get("name") or "").lower())


def format_issue_projects(output_format: str = "text") -> str:
    projects = issue_projects()
    if output_format == "json":
        return json.dumps(projects, ensure_ascii=False, indent=2)
    if not projects:
        return "등록된 프로젝트가 없습니다."
    lines = ["등록된 프로젝트"]
    for project in projects:
        jira_key = str(project.get("jira_project_key") or "").strip()
        suffix = f" | Jira: {jira_key}" if jira_key else ""
        lines.append(f"- {project.get('name')}{suffix}")
    return "\n".join(lines)


def import_jira_project_issues(config: AppConfig, project: str, *, max_results: int = 20) -> str:
    project_name = _normalize_project_name(project)
    jira_project = _jira_project_key(project_name) or project_name
    client = JiraClient(config.jira)
    jql = f'project = "{jira_project}" AND statusCategory != Done ORDER BY priority DESC, updated DESC'
    issues = client.search(jql, max_results=max_results)
    if not issues:
        return f"{project_name} 프로젝트에서 가져올 Jira 일감이 없습니다."

    imported = []
    for issue in issues:
        key = str(issue.get("key") or "").strip().upper()
        fields = issue.get("fields") if isinstance(issue.get("fields"), dict) else {}
        summary = str(fields.get("summary") or "").strip()
        if not key:
            continue
        start_workflow(config, key, summary=summary, project=project_name, source="jira")
        imported.append((key, summary))
    if not imported:
        return f"{project_name} 프로젝트에서 가져온 Jira 일감이 없습니다."
    lines = [f"{project_name} Jira 일감 {len(imported)}개를 가져왔습니다."]
    lines.extend(f"- {key}: {summary or '-'}" for key, summary in imported)
    return "\n".join(lines)


def _project_map(state: dict) -> dict[str, dict]:
    raw = state.get("issue_projects") or {}
    if not isinstance(raw, dict):
        return {}
    projects: dict[str, dict] = {}
    for key, value in raw.items():
        if not isinstance(value, dict):
            continue
        name = str(value.get("name") or key).strip()
        if name:
            projects[name] = dict(value, name=name)
    return projects


def _normalize_project_name(value: str) -> str:
    name = value.strip()
    if not name:
        raise RuntimeError("프로젝트 이름이 필요합니다.")
    return name


def _jira_project_key(project_name: str) -> str:
    for project in issue_projects(include_workflows=False):
        if str(project.get("name") or "") == project_name:
            return str(project.get("jira_project_key") or "").strip().upper()
    return ""
