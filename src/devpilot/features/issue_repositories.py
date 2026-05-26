from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

from devpilot.app_state import read_state, update_state
from devpilot.config import AppConfig
from devpilot.integrations.git_repos import configured_repositories


@dataclass(frozen=True)
class IssueRepositoryLink:
    issue_key: str
    repo_path: Path
    repo_name: str
    summary: str
    updated_at: str


def link_issue_repository(config: AppConfig, issue_key: str, repo_path: str, *, summary: str = "") -> IssueRepositoryLink:
    normalized_key = issue_key.strip().upper()
    if not normalized_key:
        raise RuntimeError("일감 키가 필요합니다.")

    repo = Path(repo_path).expanduser().resolve()
    managed = {path.expanduser().resolve() for path in configured_repositories(config)}
    if repo not in managed:
        raise RuntimeError(f"Managed repository is required: {repo}")
    if not (repo / ".git").is_dir():
        raise RuntimeError(f"Git repository not found: {repo}")

    updated_at = datetime.now(timezone.utc).isoformat()
    def mutate(state: dict) -> None:
        links = dict(state.get("issue_repositories") or {})
        current_links = _raw_repositories(links.get(normalized_key))
        current_links = [
            item
            for item in current_links
            if Path(str(item.get("repo_path") or "")).expanduser().resolve() != repo
        ]
        current_links.append({
            "repo_path": str(repo),
            "repo_name": repo.name,
            "summary": summary.strip(),
            "updated_at": updated_at,
        })
        links[normalized_key] = {
            "summary": summary.strip(),
            "updated_at": updated_at,
            "repositories": current_links,
        }
        state["issue_repositories"] = links

    update_state(mutate)
    return IssueRepositoryLink(normalized_key, repo, repo.name, summary.strip(), updated_at)


def unlink_issue_repository(issue_key: str, repo_path: str | None = None) -> bool:
    normalized_key = issue_key.strip().upper()
    existed = False

    def mutate(state: dict) -> bool:
        links = dict(state.get("issue_repositories") or {})
        found = normalized_key in links
        if repo_path is None:
            links.pop(normalized_key, None)
        else:
            target = Path(repo_path).expanduser().resolve()
            original = _raw_repositories(links.get(normalized_key))
            remaining = [
                item
                for item in original
                if Path(str(item.get("repo_path") or "")).expanduser().resolve() != target
            ]
            found = len(remaining) < len(original)
            if remaining:
                links[normalized_key] = {
                    "summary": str((links.get(normalized_key) or {}).get("summary") or ""),
                    "updated_at": datetime.now(timezone.utc).isoformat(),
                    "repositories": remaining,
                }
            else:
                links.pop(normalized_key, None)
        state["issue_repositories"] = links
        return found

    existed = bool(update_state(mutate))
    return existed


def get_issue_repository_link(issue_key: str) -> IssueRepositoryLink | None:
    links = issue_repository_link_groups()
    issue_links = links.get(issue_key.strip().upper()) or []
    return issue_links[0] if issue_links else None


def issue_repository_links() -> dict[str, IssueRepositoryLink]:
    return {issue_key: items[0] for issue_key, items in issue_repository_link_groups().items() if items}


def issue_repository_link_groups() -> dict[str, list[IssueRepositoryLink]]:
    return _read_link_groups()


def format_issue_repository_links(output_format: str = "text") -> str:
    link_groups = issue_repository_link_groups()
    if output_format == "tsv":
        return "\n".join(
            "\t".join([item.issue_key, str(item.repo_path), item.repo_name, item.summary, item.updated_at])
            for items in link_groups.values()
            for item in items
        )
    if not link_groups:
        return "연결된 일감 repository 없음"
    rows = ["연결된 일감 repository"]
    for issue_key, items in link_groups.items():
        rows.append(f"- {issue_key}: {len(items)} repositories")
        for item in items:
            summary = f" - {item.summary}" if item.summary else ""
            rows.append(f"  - {item.repo_name} | {item.repo_path}{summary}")
    return "\n".join(rows)


def _read_link_groups() -> dict[str, list[IssueRepositoryLink]]:
    state = read_state()
    raw_links = state.get("issue_repositories") or {}
    links: dict[str, list[IssueRepositoryLink]] = {}
    if not isinstance(raw_links, dict):
        return links
    for issue_key, raw in raw_links.items():
        key = str(issue_key).strip().upper()
        for item in _raw_repositories(raw):
            repo_path = item.get("repo_path")
            if not repo_path:
                continue
            links.setdefault(key, []).append(
                IssueRepositoryLink(
                    issue_key=key,
                    repo_path=Path(str(repo_path)).expanduser(),
                    repo_name=str(item.get("repo_name") or Path(str(repo_path)).name),
                    summary=str(item.get("summary") or ""),
                    updated_at=str(item.get("updated_at") or ""),
                )
            )
    return dict(sorted(links.items(), key=lambda item: item[0]))


def _raw_repositories(raw: object) -> list[dict[str, object]]:
    if not isinstance(raw, dict):
        return []
    repositories = raw.get("repositories")
    if isinstance(repositories, list):
        return [item for item in repositories if isinstance(item, dict)]
    if raw.get("repo_path"):
        return [raw]
    return []
