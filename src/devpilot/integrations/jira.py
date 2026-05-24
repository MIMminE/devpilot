from __future__ import annotations

from urllib.parse import quote

from devpilot.config import JiraConfig
from devpilot.http import basic_auth_header, json_request


class JiraClient:
    def __init__(self, config: JiraConfig) -> None:
        token = config.api_token
        if not config.base_url:
            raise RuntimeError("Jira Base URL이 설정되어 있지 않습니다. config.toml의 [jira].base_url 값을 입력해 주세요.")
        if not config.email:
            raise RuntimeError("Jira 이메일이 설정되어 있지 않습니다. config.toml의 [jira].email 값을 입력해 주세요.")
        if not token:
            raise RuntimeError("Jira API 토큰이 설정되어 있지 않습니다. config.toml의 [jira].api_token 값을 입력해 주세요.")
        self.config = config
        self.headers = {"Authorization": basic_auth_header(config.email, token)}

    def search(self, jql: str, *, max_results: int = 25) -> list[dict]:
        if not jql.strip():
            raise RuntimeError("Jira JQL이 비어 있습니다.")
        url = f"{self.config.base_url}/rest/api/3/search/jql"
        payload = json_request(
            "POST",
            url,
            headers=self.headers,
            payload={
                "jql": jql,
                "maxResults": max_results,
                "fields": [
                    "summary",
                    "status",
                    "priority",
                    "assignee",
                    "duedate",
                    "description",
                    "subtasks",
                    "created",
                    "updated",
                    "reporter",
                    "issuetype",
                    "project",
                ],
            },
        )
        if not isinstance(payload, dict):
            raise RuntimeError("Jira search 응답 형식이 올바르지 않습니다.")
        return payload.get("issues", [])

    def issue(self, issue_key: str) -> dict:
        if not issue_key.strip():
            raise RuntimeError("Jira 이슈 키가 필요합니다.")
        url = f"{self.config.base_url}/rest/api/3/issue/{quote(issue_key)}"
        payload = json_request(
            "GET",
            url,
            headers=self.headers,
            payload=None,
            timeout=30,
        )
        if not isinstance(payload, dict):
            raise RuntimeError("Jira issue 응답 형식이 올바르지 않습니다.")
        return payload

    def create_issue(
        self,
        *,
        project_key: str,
        summary: str,
        issue_type: str = "Task",
        description: str = "",
        assignee: str = "",
        priority: str = "",
        due_date: str = "",
        labels: list[str] | None = None,
    ) -> dict:
        fields: dict[str, object] = {
            "project": {"key": project_key},
            "summary": summary,
            "issuetype": {"name": issue_type},
        }
        if description:
            fields["description"] = _adf_text(description)
        if assignee:
            fields["assignee"] = {"accountId": self.account_id(assignee)}
        if priority:
            fields["priority"] = {"name": priority}
        if due_date:
            fields["duedate"] = due_date
        if labels:
            fields["labels"] = labels

        url = f"{self.config.base_url}/rest/api/3/issue"
        return json_request("POST", url, headers=self.headers, payload={"fields": fields}, timeout=30)

    def assign_issue(self, issue_key: str, account_id_or_email: str) -> None:
        account_id = self.account_id(account_id_or_email)
        url = f"{self.config.base_url}/rest/api/3/issue/{quote(issue_key)}/assignee"
        json_request("PUT", url, headers=self.headers, payload={"accountId": account_id})

    def account_id(self, account_id_or_email: str) -> str:
        value = account_id_or_email.strip()
        if not value:
            raise RuntimeError("Jira assignee is required.")
        if "@" not in value and len(value) > 20:
            return value
        matches = self.find_users(value)
        if not matches:
            raise RuntimeError(f"No Jira user found for {value}")
        return matches[0]["accountId"]

    def find_users(self, query: str) -> list[dict]:
        if not query.strip():
            return []
        url = f"{self.config.base_url}/rest/api/3/user/search?query={quote(query)}&maxResults=5"
        payload = json_request("GET", url, headers=self.headers)
        if not isinstance(payload, list):
            raise RuntimeError("Jira user search 응답 형식이 올바르지 않습니다.")
        return payload


def _adf_text(text: str) -> dict:
    paragraphs = []
    for line in text.splitlines() or [""]:
        paragraphs.append(
            {
                "type": "paragraph",
                "content": [{"type": "text", "text": line}] if line else [],
            }
        )
    return {"type": "doc", "version": 1, "content": paragraphs}
