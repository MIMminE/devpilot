from __future__ import annotations

import json

from devpilot.config import AppConfig
from devpilot.integrations.jira import JiraClient


def create_issue(
    config: AppConfig,
    *,
    summary: str,
    description: str = "",
    issue_type: str = "Task",
    assignee: str = "",
    priority: str = "",
    due_date: str = "",
    labels: list[str] | None = None,
    project_key: str = "",
    dry_run: bool = False,
) -> str:
    summary = summary.strip()
    if not summary:
        raise RuntimeError("Jira 일감 제목이 필요합니다.")

    project = (project_key or config.jira.default_project).strip()
    if not project:
        raise RuntimeError("Jira project key가 필요합니다.")

    cleaned_labels = [item.strip() for item in labels or [] if item.strip()]
    if dry_run:
        return "\n".join(
            [
                "[dry-run] Jira 일감 생성",
                f"- project: {project}",
                f"- type: {issue_type or 'Task'}",
                f"- summary: {summary}",
                f"- assignee: {assignee or '-'}",
                f"- priority: {priority or '-'}",
                f"- due: {due_date or '-'}",
                f"- labels: {', '.join(cleaned_labels) if cleaned_labels else '-'}",
            ]
        )

    client = JiraClient(config.jira)
    payload = client.create_issue(
        project_key=project,
        summary=summary,
        issue_type=issue_type or "Task",
        description=description.strip(),
        assignee=assignee.strip(),
        priority=priority.strip(),
        due_date=due_date.strip(),
        labels=cleaned_labels,
    )
    key = str(payload.get("key") or "")
    if not key:
        return f"Jira 일감을 생성했습니다.\n{payload}"
    return "\n".join(
        [
            "Jira 일감을 생성했습니다.",
            f"- key: {key}",
            f"- url: {config.jira.base_url}/browse/{key}",
        ]
    )


def issue_detail(config: AppConfig, issue_key: str, *, output_format: str = "json") -> str:
    key = issue_key.strip().upper()
    if not key:
        raise RuntimeError("Jira 이슈 키가 필요합니다.")

    issue = JiraClient(config.jira).issue(key)
    fields = issue.get("fields", {}) or {}
    comments = ((fields.get("comment") or {}).get("comments") or [])[-5:]
    attachments = fields.get("attachment") or []
    detail = {
        "key": str(issue.get("key") or key),
        "url": f"{config.jira.base_url}/browse/{issue.get('key') or key}",
        "summary": str(fields.get("summary") or ""),
        "status": _name(fields.get("status")),
        "priority": _name(fields.get("priority")),
        "issue_type": _name(fields.get("issuetype")),
        "project": _name(fields.get("project")),
        "assignee": _display_name(fields.get("assignee")),
        "reporter": _display_name(fields.get("reporter")),
        "created": str(fields.get("created") or "")[:10],
        "updated": str(fields.get("updated") or "")[:10],
        "due": str(fields.get("duedate") or ""),
        "description": _jira_doc_to_text(fields.get("description")),
        "attachments": [_attachment(item) for item in attachments if isinstance(item, dict)],
        "comments": [_comment(item) for item in comments if isinstance(item, dict)],
    }
    if output_format == "text":
        return _issue_detail_text(detail)
    return json.dumps(detail, ensure_ascii=False)


def _issue_detail_text(detail: dict) -> str:
    lines = [
        f"{detail['key']} {detail['summary']}",
        f"- 상태: {detail['status'] or '-'} | 우선순위: {detail['priority'] or '-'} | 담당: {detail['assignee'] or '-'}",
        f"- 링크: {detail['url']}",
        "",
        "설명",
        detail["description"] or "-",
        "",
        f"첨부 {len(detail['attachments'])}개",
    ]
    lines.extend(f"- {item['filename']} ({item['mime_type'] or '-'})" for item in detail["attachments"])
    lines.append("")
    lines.append(f"최근 댓글 {len(detail['comments'])}개")
    lines.extend(f"- {item['author'] or '-'}: {item['body']}" for item in detail["comments"])
    return "\n".join(lines).strip()


def _name(value: object) -> str:
    if isinstance(value, dict):
        return str(value.get("name") or value.get("key") or "")
    return ""


def _display_name(value: object) -> str:
    if isinstance(value, dict):
        return str(value.get("displayName") or value.get("emailAddress") or value.get("accountId") or "")
    return ""


def _attachment(value: dict) -> dict:
    return {
        "id": str(value.get("id") or ""),
        "filename": str(value.get("filename") or ""),
        "mime_type": str(value.get("mimeType") or ""),
        "size": int(value.get("size") or 0),
        "content_url": str(value.get("content") or ""),
        "thumbnail_url": str(value.get("thumbnail") or ""),
        "created": str(value.get("created") or "")[:10],
        "author": _display_name(value.get("author")),
    }


def _comment(value: dict) -> dict:
    return {
        "id": str(value.get("id") or ""),
        "author": _display_name(value.get("author")),
        "created": str(value.get("created") or "")[:10],
        "updated": str(value.get("updated") or "")[:10],
        "body": _jira_doc_to_text(value.get("body")),
    }


def _jira_doc_to_text(value: object) -> str:
    if value is None:
        return ""
    if isinstance(value, str):
        return value
    if isinstance(value, dict):
        text = value.get("text")
        if isinstance(text, str):
            return text
        return " ".join(_jira_doc_to_text(item) for item in value.get("content", []) if item).strip()
    if isinstance(value, list):
        return " ".join(_jira_doc_to_text(item) for item in value).strip()
    return json.dumps(value, ensure_ascii=False)
