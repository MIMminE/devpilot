from __future__ import annotations

from pathlib import Path
import json

from devpilot.app_state import app_data_dir
from devpilot.config import AppConfig
from devpilot.features.issue_workflow import record_analysis_request
from devpilot.features.jira_issues import issue_detail


def draft_issue_analysis(config: AppConfig, issue_key: str, *, output_format: str = "text") -> str:
    key = issue_key.strip().upper()
    if not key:
        raise RuntimeError("Jira 이슈 키가 필요합니다.")

    detail = json.loads(issue_detail(config, key, output_format="json"))
    prompt = _build_codex_analysis_prompt(detail)
    prompt_path = _write_analysis_prompt(key, prompt)
    summary = str(detail.get("summary") or "")
    record_analysis_request(config, key, prompt_path=str(prompt_path), summary=summary)

    if output_format == "json":
        return json.dumps(
            {
                "issue_key": key,
                "summary": summary,
                "prompt_path": str(prompt_path),
                "prompt": prompt,
            },
            ensure_ascii=False,
            indent=2,
        )

    return "\n".join(
        [
            f"{key} 1차 분석 요청서를 준비했습니다.",
            f"- 요약: {summary or '-'}",
            f"- Codex 프롬프트: {prompt_path}",
            "",
            prompt,
        ]
    ).strip()


def _write_analysis_prompt(issue_key: str, prompt: str) -> Path:
    directory = app_data_dir() / "issue-analysis"
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / f"{issue_key.lower()}-analysis-prompt.md"
    path.write_text(prompt.rstrip() + "\n", encoding="utf-8")
    return path


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
            "# Jira 일감 1차 분석 요청",
            "",
            "너는 내 개발 매니저이자 구현 파트너다. 아래 Jira 일감을 먼저 파악하고, 바로 작업에 들어가기 전에 판단 가능한 범위와 확인이 필요한 범위를 분리해서 정리해줘.",
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
            "## Jira 일감",
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
