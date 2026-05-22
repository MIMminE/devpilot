from __future__ import annotations

from dataclasses import asdict
import json

from devpilot.integrations.codex_app_server import list_codex_projects


def format_codex_threads(*, output_format: str = "text") -> str:
    projects = list_codex_projects()
    payload = [
        {
            "project_name": project.project_name,
            "cwd": project.cwd,
            "thread_count": len(project.threads),
            "threads": [asdict(thread) for thread in project.threads],
        }
        for project in projects
    ]
    if output_format == "json":
        return json.dumps(payload, ensure_ascii=False, indent=2)
    if not payload:
        return "Codex 스레드가 없습니다."

    lines = [f"Codex 프로젝트 {len(payload)}개"]
    for project in payload:
        lines.append("")
        lines.append(f"[{project['project_name']}] {project['thread_count']}개")
        lines.append(f"- 경로: {project['cwd']}")
        for thread in project["threads"]:
            title = thread.get("name") or "(제목 없음)"
            lines.append(f"  - {title}")
            lines.append(f"    id: {thread.get('thread_id') or '-'}")
            if thread.get("updated_at"):
                lines.append(f"    updated: {thread['updated_at']}")
            if thread.get("source"):
                lines.append(f"    source: {thread['source']}")
    return "\n".join(lines).strip()
