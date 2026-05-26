from __future__ import annotations

import argparse
from datetime import datetime
import json
from pathlib import Path
import subprocess
import sys
from zoneinfo import ZoneInfo

from devpilot.app_state import default_config_path, default_env_path, init_app_data
from devpilot.config import load_config
from devpilot.features.ai_assistant import daily_commit_report, git_summary, incident_draft, jira_issue_summary, monthly_review, pr_description
from devpilot.features.assignees import list_assignees
from devpilot.features.automation import tick
from devpilot.features.codex_threads import format_codex_threads
from devpilot.features.daily_activity import collect_daily_activity, draft_daily_work_report, summarize_daily_activity
from devpilot.features.dev_assistant import audit_jira_keys, branch_name, calendar_summary, commit_message, create_branch, dashboard, evening_check, morning_briefing, pr_draft
from devpilot.features.dev_insights import (
    ci_failure_alerts,
    deployment_waiting_issues,
    evening_checklist,
    pr_status_dashboard,
    recommend_issue_repositories,
    review_request_alerts,
    start_issue_work,
    trace_issue_work,
)
from devpilot.features.doctor import run_doctor
from devpilot.features.health import run_health
from devpilot.features.issue_projects import add_issue_project, format_issue_projects, import_jira_project_issues
from devpilot.features.issue_repositories import (
    format_issue_repository_links,
    link_issue_repository,
    unlink_issue_repository,
)
from devpilot.features.issue_analysis import draft_issue_analysis
from devpilot.features.issue_workflow import (
    evening_workflow_briefing,
    format_workflow,
    format_workflow_list,
    issue_director_briefing,
    morning_workflow_briefing,
    record_branch_ready,
    record_test_result,
    record_work_report,
    start_workflow,
    update_workflow_status,
)
from devpilot.features.issue_workspace import cleanup_issue_workspace, format_issue_workspace, prepare_issue_workspace
from devpilot.features.jira_daily import assign_issue, format_today_items
from devpilot.features.jira_flow import team_flow
from devpilot.features.jira_issues import create_issue, issue_detail
from devpilot.features.jira_issue_watch import check_new_issues
from devpilot.features.overtime import (
    add_overtime_record,
    delete_overtime_record,
    overtime_records,
    overtime_settings,
    overtime_summary,
    save_overtime_settings,
    update_overtime_record,
)
from devpilot.features.repo_report import report, snapshot
from devpilot.features.repo_morning_sync import morning_sync
from devpilot.features.repo_status import summarize_repositories
from devpilot.features.report_history import report_history, submit_report_file
from devpilot.features.remote_repos import clone_remote_repository, format_remote_repositories, list_remote_repositories
from devpilot.features.scheduler import install_schedules, schedule_status, uninstall_schedules
from devpilot.features.token_status import token_status
from devpilot.features.settings_import import import_settings
from devpilot.features.slack_test import send_test_message
from devpilot.features.work_notes import add_work_note_file, work_notes
from devpilot.integrations.git_repos import ahead_behind, auto_rebase_to_base, branch_options, checkout_branch, commits_between, configured_repositories, configured_repository_projects, fetch, git, owner_repo, pull_ff_only, pull_rebase, push, ref_last_commit_summary, require_clean_worktree, snapshot_repo, status_porcelain
from devpilot.integrations.slack import SlackClient, list_channels, section_block
from devpilot.runtime_env import load_env_file


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="devpilot", description="DevPilot 개인 개발자 자동화 비서")
    parser.add_argument("--config", help="사용할 config.toml 경로")
    parser.add_argument("--env", help="호환용 .env 파일 경로")
    parser.add_argument("--template-dir", help="예제 설정 파일이 있는 템플릿 폴더. 기본값은 ./examples 또는 현재 폴더")

    subparsers = parser.add_subparsers(dest="area", required=True)

    issue = subparsers.add_parser("issue", help="일감 처리 워크플로우")
    issue_sub = issue.add_subparsers(dest="command", required=True)
    issue_start = issue_sub.add_parser("start", help="일감 워크플로우 시작/등록")
    issue_start.add_argument("issue_key", help="일감 키. 예: Jira 키 또는 LOCAL-001")
    issue_start.add_argument("--summary", default="", help="일감 요약")
    issue_start.add_argument("--project", default="", help="일감을 묶을 프로젝트 이름")
    issue_start.add_argument("--repo", default="", help="연결 repository 경로")
    issue_start.add_argument("--branch", default="", help="이미 준비된 작업 브랜치")
    issue_start.add_argument("--source", choices=["manual", "jira"], default="manual", help="일감 출처")
    issue_analyze = issue_sub.add_parser("analyze", help="Jira 일감을 Codex 1차 분석 요청서로 정리")
    issue_analyze.add_argument("issue_key", help="Jira 이슈 키")
    issue_analyze.add_argument("--format", choices=["text", "json"], default="text", help="출력 형식")
    issue_analyze.add_argument("--codex-thread", action="store_true", help="Codex 앱 스레드를 만들고 첫 분석 질문까지 전송")
    issue_director = issue_sub.add_parser("director", help="일감 AI 작업 지휘관 초안 생성")
    issue_director.add_argument("issue_key", help="일감 키")
    issue_director.add_argument("--format", choices=["text", "json"], default="text", help="출력 형식")
    issue_director.add_argument("--provider", choices=["auto", "local", "local-director", "codex", "codex-local", "openai", "openai-api", "custom", "custom-command"], default="auto", help="AI 지휘관 생성 방식")
    issue_director.add_argument("--refresh", action="store_true", help="저장된 AI 지휘관 결과를 재사용하지 않고 새로 생성")
    issue_status = issue_sub.add_parser("status", help="일감 워크플로우 상태 변경")
    issue_status.add_argument("issue_key", help="Jira 이슈 키")
    issue_status.add_argument("--state", required=True, choices=["assigned", "branch_ready", "in_progress", "implemented", "tested", "pr_ready", "reviewing", "merged", "reported", "done", "blocked"], help="변경할 상태")
    issue_status.add_argument("--summary", default="", help="일감 요약 보강")
    issue_status.add_argument("--note", default="", help="상태 변경 메모")
    issue_status.add_argument("--next-action", default="", help="다음 행동")
    issue_status.add_argument("--blocker", default="", help="막힘 사유")
    issue_test = issue_sub.add_parser("record-test", help="일감 테스트 결과 기록")
    issue_test.add_argument("issue_key", help="Jira 이슈 키")
    issue_test.add_argument("--command", dest="test_command", required=True, help="실행한 테스트 명령")
    issue_test.add_argument("--result", required=True, choices=["pass", "fail", "skip"], help="테스트 결과")
    issue_test.add_argument("--summary", default="", help="테스트 결과 요약")
    issue_test.add_argument("--repo", default="", help="관련 repository 경로")
    issue_report = issue_sub.add_parser("report", help="일감 작업 보고 기록")
    issue_report.add_argument("issue_key", help="Jira 이슈 키")
    issue_report.add_argument("--summary", required=True, help="보고 내용")
    issue_report.add_argument("--next-action", default="", help="다음 행동")
    issue_report.add_argument("--done", action="store_true", help="보고와 함께 완료 처리")
    issue_show = issue_sub.add_parser("show", help="일감 워크플로우 상세 조회")
    issue_show.add_argument("issue_key", help="Jira 이슈 키")
    issue_projects = issue_sub.add_parser("projects", help="일감 프로젝트 등록/조회")
    issue_projects_sub = issue_projects.add_subparsers(dest="projects_command", required=True)
    issue_projects_list = issue_projects_sub.add_parser("list", help="등록된 일감 프로젝트 조회")
    issue_projects_list.add_argument("--format", choices=["text", "json"], default="text", help="출력 형식")
    issue_projects_add = issue_projects_sub.add_parser("add", help="일감 프로젝트 등록")
    issue_projects_add.add_argument("name", help="프로젝트 이름")
    issue_projects_add.add_argument("--management-type", choices=["auto", "manual", "jira"], default="auto", help="프로젝트 관리 방식")
    issue_projects_add.add_argument("--jira-project-key", default="", help="연결할 Jira 프로젝트 키")
    issue_projects_import = issue_projects_sub.add_parser("import-jira", help="프로젝트의 Jira 일감을 워크플로우로 가져오기")
    issue_projects_import.add_argument("name", help="프로젝트 이름")
    issue_projects_import.add_argument("--max-results", type=int, default=20, help="가져올 최대 일감 수")
    issue_workspace = issue_sub.add_parser("workspace", help="일감 단위 worktree workspace 관리")
    issue_workspace_sub = issue_workspace.add_subparsers(dest="workspace_command", required=True)
    issue_workspace_prepare = issue_workspace_sub.add_parser("prepare", help="일감 workspace를 만들고 repository worktree를 배치")
    issue_workspace_prepare.add_argument("issue_key", help="Jira 이슈 키")
    issue_workspace_prepare.add_argument("--repo", action="append", default=[], help="workspace에 포함할 관리 repository 경로. 여러 번 지정 가능")
    issue_workspace_prepare.add_argument("--summary", default="", help="브랜치명과 context에 사용할 일감 요약")
    issue_workspace_prepare.add_argument("--prefix", default="feature", help="브랜치 prefix")
    issue_workspace_prepare.add_argument("--base-branch", default="", help="작업 브랜치를 시작할 기준 브랜치. 비우면 repository 설정값 사용")
    issue_workspace_prepare.add_argument("--force", action="store_true", help="기존 workspace/worktree를 재생성")
    issue_workspace_status = issue_workspace_sub.add_parser("status", help="일감 workspace 상태 조회")
    issue_workspace_status.add_argument("issue_key", help="Jira 이슈 키")
    issue_workspace_status.add_argument("--format", choices=["text", "json"], default="text", help="출력 형식")
    issue_workspace_cleanup = issue_workspace_sub.add_parser("cleanup", help="일감 workspace worktree 정리")
    issue_workspace_cleanup.add_argument("issue_key", help="Jira 이슈 키")
    issue_workspace_cleanup.add_argument("--force", action="store_true", help="변경 파일 확인 실패 시에도 강제 제거")
    issue_list = issue_sub.add_parser("list", help="일감 워크플로우 목록")
    issue_list.add_argument("--all", action="store_true", help="완료/보고된 일감까지 포함")
    issue_list.add_argument("--format", choices=["text", "json"], default="text", help="출력 형식")
    issue_sub.add_parser("morning", help="아침 브리핑용 일감 워크플로우 요약")
    issue_sub.add_parser("evening", help="저녁 브리핑용 일감 워크플로우 요약")

    jira = subparsers.add_parser("jira", help="Jira 일감 자동화")
    jira_sub = jira.add_subparsers(dest="command", required=True)
    jira_today = jira_sub.add_parser("today", help="오늘 내 Jira 일감 조회")
    jira_today.add_argument("--max-results", type=int, default=25, help="최대 조회 개수")
    jira_today.add_argument("--send-slack", action="store_true", help="Slack으로 실제 전송")
    jira_today.add_argument("--dry-run", action="store_true", help="외부 전송 없이 설정/출력만 확인")

    jira_assign = jira_sub.add_parser("assign", help="Jira 일감 담당자 할당")
    jira_assign.add_argument("issue_key", help="Jira 이슈 키")
    jira_assign.add_argument("account_id_or_email", help="담당자 accountId, 이메일 또는 alias")
    jira_assign.add_argument("--dry-run", action="store_true", help="실제 할당 없이 미리보기")

    jira_create = jira_sub.add_parser("create", help="Jira 일감 간편 생성")
    jira_create.add_argument("--summary", required=True, help="일감 제목")
    jira_create.add_argument("--description", default="", help="일감 설명")
    jira_create.add_argument("--type", default="Task", help="이슈 타입 이름. 예: Task, Bug, Story")
    jira_create.add_argument("--assignee", default="", help="담당자 accountId, 이메일 또는 검색어")
    jira_create.add_argument("--priority", default="", help="우선순위 이름. 예: Highest, High, Medium")
    jira_create.add_argument("--due-date", default="", help="마감일 YYYY-MM-DD")
    jira_create.add_argument("--labels", default="", help="쉼표로 구분한 label 목록")
    jira_create.add_argument("--project", default="", help="프로젝트 키. 비우면 기본 프로젝트")
    jira_create.add_argument("--dry-run", action="store_true", help="생성 없이 입력값만 확인")

    jira_detail = jira_sub.add_parser("detail", help="Jira 일감 상세/첨부/댓글 조회")
    jira_detail.add_argument("issue_key", help="Jira 이슈 키")
    jira_detail.add_argument("--format", choices=["json", "text"], default="json", help="출력 형식")

    jira_link_repo = jira_sub.add_parser("link-repo", help="Jira 일감과 관리 중인 repository 연결")
    jira_link_repo.add_argument("issue_key", help="Jira 이슈 키")
    jira_link_repo.add_argument("--repo", required=True, help="연결할 관리 repository 경로")
    jira_link_repo.add_argument("--summary", default="", help="일감 요약")

    jira_unlink_repo = jira_sub.add_parser("unlink-repo", help="Jira 일감과 repository 연결 해제")
    jira_unlink_repo.add_argument("issue_key", help="Jira 이슈 키")
    jira_unlink_repo.add_argument("--repo", default=None, help="특정 repository 연결만 해제할 경로")

    jira_repo_links = jira_sub.add_parser("repo-links", help="Jira 일감과 repository 연결 목록")
    jira_repo_links.add_argument("--format", choices=["text", "tsv"], default="text", help="출력 형식")
    jira_deploy = jira_sub.add_parser("deploy-waiting", help="배포 대기 상태의 내 Jira 일감 조회")
    jira_deploy.add_argument("--send-slack", action="store_true", help="Slack alerts 채널로 전송")
    jira_watch = jira_sub.add_parser("watch-new", help="새로 등록된 Jira 일감 주기 조회")
    jira_watch.add_argument("--jql", default="", help="감시 대상 JQL. 비우면 기본 프로젝트 전체")
    jira_watch.add_argument("--max-results", type=int, default=20, help="최대 조회 개수")
    jira_watch.add_argument("--include-existing", action="store_true", help="첫 실행에서도 최근 이슈를 출력")
    jira_watch.add_argument("--send-slack", action="store_true", help="새 이슈가 있으면 Slack alerts 채널로 전송")
    jira_watch.add_argument("--analyze", action="store_true", help="새 이슈별 Codex 1차 분석 요청서를 함께 생성")
    jira_watch.add_argument("--codex-thread", action="store_true", help="--analyze와 함께 새 이슈별 Codex 앱 스레드를 생성")
    jira_flow = jira_sub.add_parser("flow", help="팀 Jira 처리 흐름 조회")
    jira_flow.add_argument("--days", type=int, default=7, help="조회 기간")
    jira_flow.add_argument("--max-results", type=int, default=80, help="최대 조회 개수")
    jira_flow.add_argument("--format", choices=["text", "tsv"], default="text", help="출력 형식")

    codex = subparsers.add_parser("codex", help="Codex 프로젝트/스레드 조회")
    codex_sub = codex.add_subparsers(dest="command", required=True)
    codex_threads = codex_sub.add_parser("threads", help="Codex 프로젝트와 스레드 목록 조회")
    codex_threads.add_argument("--format", choices=["text", "json"], default="text", help="출력 형식")

    slack = subparsers.add_parser("slack", help="Slack 알림")
    slack_sub = slack.add_subparsers(dest="command", required=True)
    slack_test = slack_sub.add_parser("test", help="Slack 테스트 메시지 전송")
    slack_test.add_argument("--dry-run", action="store_true", help="실제 전송 없이 메시지만 확인")
    slack_test.add_argument(
        "--destination",
        default="test",
        help="전송할 Slack 채널 설정 키: test, jira_daily, git_report, git_status, alerts, default",
    )
    slack_channels = slack_sub.add_parser("channels", help="Slack OAuth 채널 목록 조회")
    slack_channels.add_argument("--format", choices=["text", "tsv"], default="text", help="출력 형식")

    repo = subparsers.add_parser("repo", help="Git repository 자동화")
    repo_sub = repo.add_subparsers(dest="command", required=True)
    repo_snapshot = repo_sub.add_parser("snapshot", help="현재 repository HEAD 스냅샷 저장")
    repo_snapshot.add_argument("--name", default="morning", help="스냅샷 이름")

    repo_report = repo_sub.add_parser("report", help="스냅샷 이후 Git 작업 보고서 생성")
    repo_report.add_argument("--snapshot", default="morning", help="비교할 스냅샷 이름")
    repo_report.add_argument("--send-slack", action="store_true", help="Slack으로 실제 전송")
    repo_report.add_argument("--dry-run", action="store_true", help="외부 전송 없이 미리보기")
    repo_report.add_argument("--notes", default="", help="AI 보고서에 함께 반영할 수동 메모")
    repo_report.add_argument("--notes-file", help="AI 보고서에 함께 반영할 수동 메모 파일")
    repo_report.add_argument("--report-agent-file", help="보고서 작성 규칙 Markdown 파일")

    repo_status = repo_sub.add_parser("status", help="관리 repository 변경/push/pull 상태 요약")
    repo_status.add_argument("--send-slack", action="store_true", help="Slack으로 실제 전송")
    repo_status.add_argument("--dry-run", action="store_true", help="외부 전송 없이 미리보기")

    repo_list = repo_sub.add_parser("list", help="gh CLI로 등록한 관리 Git repository 목록 조회")
    repo_list.add_argument("--format", choices=["text", "tsv"], default="text", help="출력 형식")
    repo_list.add_argument("--all", action="store_true", help="호환용 옵션입니다. 현재는 관리 대상으로 등록한 repository만 조회합니다.")

    repo_remote_list = repo_sub.add_parser("remote-list", help="gh CLI 인증으로 접근 가능한 GitHub repository 후보 조회")
    repo_remote_list.add_argument("--owner", default="", help="조회할 GitHub user/org. 비우면 현재 gh 계정 기준")
    repo_remote_list.add_argument("--limit", type=int, default=200, help="최대 조회 개수")
    repo_remote_list.add_argument("--format", choices=["text", "tsv"], default="text", help="출력 형식")

    repo_clone = repo_sub.add_parser("clone", help="gh CLI로 원격 repository를 clone 위치에 내려받기")
    repo_clone.add_argument("--repo", required=True, help="owner/name, SSH URL 또는 HTTPS URL")
    repo_clone.add_argument("--target-root", required=True, help="clone할 상위 폴더")

    repo_update = repo_sub.add_parser("update", help="관리 중인 repository fetch/pull/rebase/push 실행")
    repo_update.add_argument("--repo", required=True, help="작업할 repository 경로")
    repo_update.add_argument("--mode", choices=["fetch", "pull", "rebase", "push"], default="pull", help="실행할 Git 작업")
    repo_update.add_argument("--dry-run", action="store_true", help="실행할 명령만 확인")

    repo_branches = repo_sub.add_parser("branches", help="repository의 브랜치 목록 조회")
    repo_branches.add_argument("--repo", required=True, help="조회할 repository 경로")
    repo_branches.add_argument("--format", choices=["text", "tsv"], default="text", help="출력 형식")

    repo_checkout = repo_sub.add_parser("checkout", help="관리 repository 브랜치 체크아웃")
    repo_checkout.add_argument("--repo", required=True, help="작업할 repository 경로")
    repo_checkout.add_argument("--branch", required=True, help="체크아웃할 브랜치 이름")

    repo_commits = repo_sub.add_parser("commits", help="repository의 오늘 내 커밋 조회")
    repo_commits.add_argument("--repo", required=True, help="조회할 repository 경로")

    repo_sub.add_parser("activity", help="오늘 브랜치/커밋/머지/PR 활동 요약")

    repo_daily_draft = repo_sub.add_parser("daily-draft", help="오늘 한 일 보고서 초안 생성")
    repo_daily_draft.add_argument("--notes", default="", help="초안에 포함할 수동 메모")
    repo_daily_draft.add_argument("--notes-file", help="초안에 포함할 수동 메모 파일")

    repo_send_text = repo_sub.add_parser("send-report-text", help="수정한 보고서 텍스트를 Slack으로 전송")
    repo_send_text.add_argument("--text-file", required=True, help="전송할 보고서 텍스트 파일")

    repo_submit_report = repo_sub.add_parser("submit-report", help="보고서를 앱 기록에 제출하고 선택적으로 Slack 전송")
    repo_submit_report.add_argument("--text-file", required=True, help="제출할 보고서 텍스트 파일")
    repo_submit_report.add_argument("--notes-file", default="", help="보고서 작성 시 사용한 수동 메모 파일")
    repo_submit_report.add_argument("--send-slack", action="store_true", help="Slack git_report 채널로 함께 전송")

    repo_report_history = repo_sub.add_parser("report-history", help="제출된 보고서 기록 조회")
    repo_report_history.add_argument("--format", choices=["json", "text"], default="json", help="출력 형식")

    memo = subparsers.add_parser("memo", help="작업 메모 관리")
    memo_sub = memo.add_subparsers(dest="command", required=True)
    memo_add = memo_sub.add_parser("add", help="작업 메모 저장")
    memo_add.add_argument("--target-type", default="general", help="메모 대상 종류: jira, repo, report, general")
    memo_add.add_argument("--target-id", default="general", help="메모 대상 식별자")
    memo_add.add_argument("--target-title", default="일반 메모", help="메모 대상 이름")
    memo_add.add_argument("--text-file", required=True, help="저장할 메모 텍스트 파일")
    memo_list = memo_sub.add_parser("list", help="작업 메모 목록 조회")
    memo_list.add_argument("--format", choices=["json", "text"], default="json", help="출력 형식")

    overtime = subparsers.add_parser("overtime", help="연장 근무 기록과 예상 수당")
    overtime_sub = overtime.add_subparsers(dest="command", required=True)
    overtime_add = overtime_sub.add_parser("add", help="연장 근무 기록 추가")
    overtime_add.add_argument("--date", default="", help="근무 날짜 YYYY-MM-DD. 비우면 오늘")
    overtime_add.add_argument("--hours", default="", help="연장 근무 시간. 시작/종료 시간을 넣으면 자동 계산")
    overtime_add.add_argument("--start", default="", help="시작 시간 HH:MM")
    overtime_add.add_argument("--end", default="", help="종료 시간 HH:MM")
    overtime_add.add_argument("--kind", choices=["overtime", "night", "holiday"], default="overtime", help="근무 구분")
    overtime_add.add_argument("--memo", default="", help="사유/메모")
    overtime_update = overtime_sub.add_parser("update", help="연장 근무 기록 수정")
    overtime_update.add_argument("--id", required=True, help="수정할 기록 id")
    overtime_update.add_argument("--date", required=True, help="근무 날짜 YYYY-MM-DD")
    overtime_update.add_argument("--hours", default="", help="연장 근무 시간. 시작/종료 시간을 넣으면 자동 계산")
    overtime_update.add_argument("--start", default="", help="시작 시간 HH:MM")
    overtime_update.add_argument("--end", default="", help="종료 시간 HH:MM")
    overtime_update.add_argument("--kind", choices=["overtime", "night", "holiday"], default="overtime", help="근무 구분")
    overtime_update.add_argument("--memo", default="", help="사유/메모")
    overtime_delete = overtime_sub.add_parser("delete", help="연장 근무 기록 삭제")
    overtime_delete.add_argument("--id", required=True, help="삭제할 기록 id")
    overtime_list = overtime_sub.add_parser("list", help="연장 근무 기록 목록")
    overtime_list.add_argument("--month", default="", help="대상 월 YYYY-MM")
    overtime_list.add_argument("--format", choices=["json", "text"], default="json", help="출력 형식")
    overtime_summary_parser = overtime_sub.add_parser("summary", help="월별 연장 근무 예상 수당")
    overtime_summary_parser.add_argument("--month", default="", help="대상 월 YYYY-MM. 비우면 이번 달")
    overtime_summary_parser.add_argument("--format", choices=["json", "text"], default="json", help="출력 형식")
    overtime_settings_parser = overtime_sub.add_parser("settings", help="연장 수당 계산 설정 조회/저장")
    overtime_settings_parser.add_argument("--hourly-rate", default="", help="시급")
    overtime_settings_parser.add_argument("--overtime-multiplier", default="", help="연장 배율")
    overtime_settings_parser.add_argument("--night-multiplier", default="", help="야간 추가 배율")
    overtime_settings_parser.add_argument("--holiday-multiplier", default="", help="휴일 추가 배율")
    overtime_settings_parser.add_argument("--rounding-minutes", type=int, default=0, help="반올림 단위 분")
    overtime_settings_parser.add_argument("--currency", default="KRW", help="통화")
    overtime_settings_parser.add_argument("--inclusive-salary", choices=["true", "false"], default="", help="포괄임금제 여부")
    overtime_settings_parser.add_argument("--inclusive-weekly-hours", default="", help="주당 포괄 연장 시간")
    overtime_settings_parser.add_argument("--base-monthly-salary", default="", help="월 기본급")
    overtime_settings_parser.add_argument("--inclusive-overtime-pay", default="", help="월 포괄 연장근로 수당")
    overtime_settings_parser.add_argument("--statutory-base-pay", default="", help="법정/통상임금 산정 기준액 메모용 금액")
    overtime_settings_parser.add_argument("--format", choices=["json", "text"], default="json", help="출력 형식")

    repo_morning_sync = repo_sub.add_parser("morning-sync", help="출근 Git 정비: fetch, 안전한 최신화, 전체 상태 알림")
    repo_morning_sync.add_argument("--send-slack", action="store_true", help="Slack으로 결과 전송")
    repo_morning_sync.add_argument("--dry-run", action="store_true", help="fetch/pull 없이 현재 상태 기준으로 미리보기")

    automation = subparsers.add_parser("automation", help="스케줄러가 호출하는 자동 실행")
    automation_sub = automation.add_subparsers(dest="command", required=True)
    automation_tick = automation_sub.add_parser("tick", help="현재 시간 기준으로 실행할 자동화를 1회 판단")
    automation_tick.add_argument("--task", choices=["morning_briefing", "evening_check", "jira_daily", "git_morning_sync", "git_report", "git_status"], help="특정 자동화 작업만 확인")
    automation_tick.add_argument("--dry-run", action="store_true", help="실행하지 않고 판단 결과만 출력")

    routine = subparsers.add_parser("routine", help="개발자 하루 루틴")
    routine_sub = routine.add_subparsers(dest="command", required=True)
    routine_morning = routine_sub.add_parser("morning", help="출근 브리핑 생성")
    routine_morning.add_argument("--send-slack", action="store_true", help="Slack으로 실제 전송")
    routine_morning.add_argument("--dry-run", action="store_true", help="외부 전송 없이 미리보기")
    routine_evening = routine_sub.add_parser("evening", help="퇴근 체크 생성")
    routine_evening.add_argument("--send-slack", action="store_true", help="Slack으로 실제 전송")
    routine_evening.add_argument("--dry-run", action="store_true", help="외부 전송 없이 미리보기")

    dev = subparsers.add_parser("dev", help="개발자 보조 도구")
    dev_sub = dev.add_subparsers(dest="command", required=True)
    dev_branch = dev_sub.add_parser("branch-name", help="Jira 키 기반 브랜치명 추천")
    dev_branch.add_argument("issue_key", help="Jira 이슈 키")
    dev_branch.add_argument("summary", help="브랜치명에 넣을 작업 요약")
    dev_branch.add_argument("--prefix", default="feature", help="브랜치 prefix")
    dev_create_branch = dev_sub.add_parser("create-branch", help="Jira 이슈 키 기반 로컬 브랜치 생성")
    dev_create_branch.add_argument("--repo", required=True, help="브랜치를 만들 repository 경로")
    dev_create_branch.add_argument("--issue-key", required=True, help="Jira 이슈 키")
    dev_create_branch.add_argument("--summary", default="", help="브랜치명에 사용할 작업 요약")
    dev_create_branch.add_argument("--prefix", default="feature", help="브랜치 prefix")
    dev_create_branch.add_argument("--base-branch", default="", help="작업 브랜치를 시작할 기준 브랜치. 비우면 repository 설정값 사용")
    dev_commit = dev_sub.add_parser("commit-message", help="커밋 메시지 초안 생성")
    dev_commit.add_argument("--repo", help="대상 repository 경로")
    dev_commit.add_argument("--issue-key", help="커밋 메시지에 넣을 Jira 이슈 키")
    dev_commit.add_argument("--type", default="fix", choices=["feat", "fix", "refactor", "test", "docs", "chore", "ci", "style", "perf"], help="커밋 작업 태그")
    dev_pr = dev_sub.add_parser("pr-draft", help="PR 제목/본문 초안 생성")
    dev_pr.add_argument("--repo", help="대상 repository 경로")
    dev_pr.add_argument("--issue-key", help="PR에 연결할 Jira 이슈 키")
    dev_sub.add_parser("audit-jira-keys", help="Jira 키가 없는 브랜치/커밋 점검")
    dev_recommend = dev_sub.add_parser("recommend-repo", help="Jira 이슈에 어울리는 관리 repository 추천")
    dev_recommend.add_argument("issue_key", help="Jira 이슈 키")
    dev_recommend.add_argument("--summary", default="", help="Jira 요약. 비우면 Jira API에서 조회")
    dev_trace = dev_sub.add_parser("trace-issue", help="Jira 키와 연결된 브랜치/커밋/PR 추적")
    dev_trace.add_argument("issue_key", help="Jira 이슈 키")
    dev_start = dev_sub.add_parser("start-issue", help="Jira 일감 시작: repository 연결 후 브랜치 생성")
    dev_start.add_argument("issue_key", help="Jira 이슈 키")
    dev_start.add_argument("--repo", help="작업할 관리 repository 경로. 비우면 추천 근거로 자동 선택")
    dev_start.add_argument("--summary", default="", help="브랜치명에 사용할 작업 요약")
    dev_start.add_argument("--prefix", default="feature", help="브랜치 prefix")
    dev_start.add_argument("--base-branch", default="", help="작업 브랜치를 시작할 기준 브랜치. 비우면 repository 설정값 사용")
    dev_pr_status = dev_sub.add_parser("pr-status", help="관리 repository의 열린 PR 상태 대시보드")
    dev_pr_status.add_argument("--send-slack", action="store_true", help="Slack alerts 채널로 전송")
    dev_review = dev_sub.add_parser("review-alerts", help="나에게 요청된 PR 리뷰 조회")
    dev_review.add_argument("--send-slack", action="store_true", help="Slack alerts 채널로 전송")
    dev_ci = dev_sub.add_parser("ci-alerts", help="관리 repository의 최근 CI 실패 조회")
    dev_ci.add_argument("--send-slack", action="store_true", help="Slack alerts 채널로 전송")
    dev_sub.add_parser("evening-checklist", help="퇴근 전 미커밋/미푸시/최신화 필요 체크리스트")
    dev_sub.add_parser("dashboard", help="관리 repository 상태 대시보드")
    dev_sub.add_parser("calendar", help="캘린더 일정 요약")

    ai = subparsers.add_parser("ai", help="AI 보고서/초안 생성")
    ai_sub = ai.add_subparsers(dest="command", required=True)
    ai_git = ai_sub.add_parser("git-summary", help="최근 Git 커밋 기반 작업 요약")
    ai_git.add_argument("--tone", choices=["brief", "detailed", "manager"], default="brief", help="보고 톤")
    ai_git.add_argument("--days", type=int, default=1, help="조회할 최근 일수")
    ai_daily = ai_sub.add_parser("daily-report", help="오늘 커밋 기반 AI 작업 보고서 작성")
    ai_daily.add_argument("--notes", default="", help="AI 보고서에 함께 반영할 수동 메모")
    ai_daily.add_argument("--notes-file", help="AI 보고서에 함께 반영할 수동 메모 파일")
    ai_daily.add_argument("--tone", choices=["brief", "detailed", "manager"], default="manager", help="보고 톤")
    ai_daily.add_argument("--report-agent-file", help="보고서 작성 규칙 Markdown 파일")
    ai_pr = ai_sub.add_parser("pr-draft", help="AI 기반 PR 제목/본문 초안")
    ai_pr.add_argument("--repo", help="대상 repository 경로")
    ai_pr.add_argument("--issue-key", help="연결할 Jira 이슈 키")
    ai_pr.add_argument("--tone", choices=["brief", "detailed", "manager"], default="brief", help="보고 톤")
    ai_jira = ai_sub.add_parser("jira-summary", help="AI 기반 Jira 이슈 정리")
    ai_jira.add_argument("issue_key", help="Jira 이슈 키")
    ai_jira.add_argument("--tone", choices=["brief", "detailed", "manager"], default="brief", help="보고 톤")
    ai_month = ai_sub.add_parser("monthly-review", help="월간 회고 초안 생성")
    ai_month.add_argument("--month", required=True, help="대상 월: YYYY-MM")
    ai_month.add_argument("--tone", choices=["brief", "detailed", "manager"], default="manager", help="보고 톤")
    ai_incident = ai_sub.add_parser("incident-draft", help="장애/버그 원인 정리 초안")
    ai_incident.add_argument("--issue-key", help="관련 Jira 이슈 키")
    ai_incident.add_argument("--notes", default="", help="추가 메모")
    ai_incident.add_argument("--tone", choices=["brief", "detailed", "manager"], default="detailed", help="보고 톤")

    status = subparsers.add_parser("status", help="설정/연결 상태 진단")
    status_sub = status.add_subparsers(dest="command", required=True)
    status_sub.add_parser("doctor", help="설정값과 관리 repository 진단")
    health = status_sub.add_parser("health", help="API 키/토큰과 실제 연결 상태 확인")
    health.add_argument("--no-network", action="store_true", help="네트워크 호출 없이 필수 설정만 확인")
    health.add_argument("--send-alert", action="store_true", help="실패 항목을 Slack alerts 채널로 전송")
    tokens = status_sub.add_parser("tokens", help="토큰 설정/만료 상태 확인")
    tokens.add_argument("--format", choices=["text", "json"], default="text", help="출력 형식")

    schedule = subparsers.add_parser("schedule", help="OS 스케줄러 등록/제거")
    schedule_sub = schedule.add_subparsers(dest="command", required=True)
    schedule_sub.add_parser("install", help="현재 설정 기준으로 OS 스케줄러 등록/갱신")
    schedule_sub.add_parser("uninstall", help="DevPilot OS 스케줄러 항목 제거")
    schedule_sub.add_parser("status", help="스케줄 설정과 OS 등록 상태 표시")

    settings = subparsers.add_parser("settings", help="설정 가져오기와 조회")
    settings_sub = settings.add_subparsers(dest="command", required=True)
    settings_import = settings_sub.add_parser("import", help="config.toml 또는 assignees.json 가져오기")
    settings_import.add_argument("--config-file", help="가져올 config.toml 경로")
    settings_import.add_argument("--assignees-file", help="가져올 assignees.json 경로")
    settings_assignees = settings_sub.add_parser("assignees", help="Jira 담당자 alias 목록")
    settings_assignees.add_argument("action", choices=["list"])

    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    init_app_data(template_dir=args.template_dir)
    env_path = args.env or default_env_path()
    config_path = args.config or default_config_path()
    load_env_file(env_path)
    config = load_config(config_path)

    if args.area == "issue" and args.command == "start":
        start_workflow(config, args.issue_key, summary=args.summary, project=args.project, repo_path=args.repo or None, branch=args.branch, source=args.source)
        print(format_workflow(config, args.issue_key))
        return 0

    if args.area == "issue" and args.command == "analyze":
        print(draft_issue_analysis(config, args.issue_key, output_format=args.format, codex_thread=args.codex_thread))
        return 0

    if args.area == "issue" and args.command == "director":
        print(issue_director_briefing(config, args.issue_key, output_format=args.format, provider=args.provider, refresh=args.refresh))
        return 0

    if args.area == "issue" and args.command == "projects":
        if args.projects_command == "add":
            project = add_issue_project(args.name, jira_project_key=args.jira_project_key, management_type=args.management_type)
            print(f"프로젝트를 등록했습니다: {project.get('name')}")
            return 0
        if args.projects_command == "list":
            print(format_issue_projects(output_format=args.format))
            return 0
        if args.projects_command == "import-jira":
            print(import_jira_project_issues(config, args.name, max_results=args.max_results))
            return 0

    if args.area == "issue" and args.command == "status":
        update_workflow_status(
            config,
            args.issue_key,
            status=args.state,
            summary=args.summary,
            note=args.note,
            next_action=args.next_action,
            blocker=args.blocker,
        )
        print(format_workflow(config, args.issue_key))
        return 0

    if args.area == "issue" and args.command == "record-test":
        record_test_result(
            config,
            args.issue_key,
            command=args.test_command,
            result=args.result,
            summary=args.summary,
            repo_path=args.repo,
        )
        print(format_workflow(config, args.issue_key))
        return 0

    if args.area == "issue" and args.command == "report":
        record_work_report(config, args.issue_key, summary=args.summary, next_action=args.next_action, done=args.done)
        print(format_workflow(config, args.issue_key))
        return 0

    if args.area == "issue" and args.command == "show":
        print(format_workflow(config, args.issue_key))
        return 0

    if args.area == "issue" and args.command == "workspace":
        if args.workspace_command == "prepare":
            print(
                prepare_issue_workspace(
                    config,
                    args.issue_key,
                    repo_paths=args.repo,
                    summary=args.summary,
                    prefix=args.prefix,
                    base_branch=args.base_branch,
                    force=args.force,
                )
            )
            return 0
        if args.workspace_command == "status":
            print(format_issue_workspace(args.issue_key, output_format=args.format))
            return 0
        if args.workspace_command == "cleanup":
            print(cleanup_issue_workspace(args.issue_key, force=args.force))
            return 0

    if args.area == "issue" and args.command == "list":
        print(format_workflow_list(config, active_only=not args.all, output_format=args.format))
        return 0

    if args.area == "issue" and args.command == "morning":
        print(morning_workflow_briefing(config))
        return 0

    if args.area == "issue" and args.command == "evening":
        print(evening_workflow_briefing(config))
        return 0

    if args.area == "jira" and args.command == "today":
        print(
            format_today_items(
                config,
                max_results=args.max_results,
                dry_run=args.dry_run,
                send_slack=args.send_slack,
            )
        )
        return 0

    if args.area == "jira" and args.command == "assign":
        print(assign_issue(config, args.issue_key, args.account_id_or_email, dry_run=args.dry_run))
        return 0

    if args.area == "jira" and args.command == "create":
        print(
            create_issue(
                config,
                summary=args.summary,
                description=args.description,
                issue_type=args.type,
                assignee=args.assignee,
                priority=args.priority,
                due_date=args.due_date,
                labels=args.labels.split(",") if args.labels else [],
                project_key=args.project,
                dry_run=args.dry_run,
            )
        )
        return 0

    if args.area == "jira" and args.command == "detail":
        print(issue_detail(config, args.issue_key, output_format=args.format))
        return 0

    if args.area == "jira" and args.command == "link-repo":
        link = link_issue_repository(config, args.issue_key, args.repo, summary=args.summary)
        print(f"{link.issue_key}\t{link.repo_path}\t{link.repo_name}\tlinked")
        return 0

    if args.area == "jira" and args.command == "unlink-repo":
        removed = unlink_issue_repository(args.issue_key, repo_path=args.repo)
        print(f"{args.issue_key.upper()}: {'unlinked' if removed else 'not linked'}")
        return 0

    if args.area == "jira" and args.command == "repo-links":
        print(format_issue_repository_links(output_format=args.format))
        return 0

    if args.area == "jira" and args.command == "deploy-waiting":
        print(deployment_waiting_issues(config, send_slack=args.send_slack))
        return 0

    if args.area == "jira" and args.command == "watch-new":
        print(
            check_new_issues(
                config,
                jql=args.jql,
                max_results=args.max_results,
                include_existing=args.include_existing,
                send_slack=args.send_slack,
                analyze=args.analyze or args.codex_thread,
                codex_thread=args.codex_thread,
            )
        )
        return 0

    if args.area == "jira" and args.command == "flow":
        print(team_flow(config, days=args.days, max_results=args.max_results, output_format=args.format))
        return 0

    if args.area == "codex" and args.command == "threads":
        print(format_codex_threads(output_format=args.format))
        return 0

    if args.area == "slack" and args.command == "test":
        print(send_test_message(config, dry_run=args.dry_run, destination=args.destination))
        return 0

    if args.area == "slack" and args.command == "channels":
        channels = list_channels(config.slack)
        if args.format == "tsv":
            print("\n".join(f"{item['id']}\t{item['name']}\t{item['is_private']}" for item in channels))
        else:
            print("Slack 채널 목록")
            print("\n".join(f"- #{item['name']} ({item['id']})" for item in channels))
        return 0

    if args.area == "repo" and args.command == "snapshot":
        output = snapshot(config, name=args.name)
        print(f"Snapshot saved: {output}")
        return 0

    if args.area == "repo" and args.command == "report":
        print(
            report(
                config,
                snapshot_name=args.snapshot,
                send_slack=args.send_slack,
                dry_run=args.dry_run,
                manual_notes=args.notes,
                manual_notes_file=args.notes_file,
                report_agent_file=args.report_agent_file,
            )
        )
        return 0

    if args.area == "repo" and args.command == "status":
        print(summarize_repositories(config, send_slack=args.send_slack, dry_run=args.dry_run))
        return 0

    if args.area == "repo" and args.command == "list":
        repos = configured_repository_projects(config)
        if args.format == "tsv":
            rows = []
            for repo in repos:
                rebase_result = auto_rebase_to_base(repo.path, base_branch=repo.base_branch)
                rebase_alert = "" if rebase_result.succeeded or _is_dirty_rebase_skip(rebase_result.message) else rebase_result.message
                auto_sync_message = rebase_result.message if rebase_result.succeeded and rebase_result.attempted else ""
                snapshot_item = snapshot_repo(repo.path, base_branch=repo.base_branch)
                dirty = len(status_porcelain(repo.path))
                ahead, behind = ahead_behind(repo.path)
                is_working = snapshot_item.branch != snapshot_item.base_branch and snapshot_item.branch != "detached"
                today_commit_count, today_commit_preview = _today_commit_status(config, repo.path)
                base_commit_summary = ref_last_commit_summary(repo.path, snapshot_item.base_ref)
                pull_request_summary, release_summary = _github_repo_overview(repo.path)
                fork_date, branch_commit_count, branch_commit_preview = _branch_work_status(repo.path, snapshot_item.base_ref, snapshot_item.branch, snapshot_item.base_branch)
                rows.append(
                    "\t".join(
                        [
                            str(repo.path),
                            repo.path.name,
                            snapshot_item.branch,
                            "" if ahead is None else str(ahead),
                            "" if behind is None else str(behind),
                            str(dirty),
                            snapshot_item.base_branch,
                            snapshot_item.base_ref,
                            "" if snapshot_item.base_behind is None else str(snapshot_item.base_behind),
                            "" if snapshot_item.base_ahead is None else str(snapshot_item.base_ahead),
                            "1" if is_working else "0",
                            rebase_alert.replace("\t", " ").replace("\n", " "),
                            str(today_commit_count),
                            today_commit_preview.replace("\t", " ").replace("\n", " ¶ "),
                            base_commit_summary.replace("\t", " ").replace("\n", " "),
                            auto_sync_message.replace("\t", " ").replace("\n", " "),
                            pull_request_summary.replace("\t", " ").replace("\n", " "),
                            release_summary.replace("\t", " ").replace("\n", " "),
                            fork_date.replace("\t", " ").replace("\n", " "),
                            str(branch_commit_count),
                            branch_commit_preview.replace("\t", " ").replace("\n", " ¶ "),
                        ]
                    )
                )
            print("\n".join(rows))
        else:
            print("Git repository 목록")
            for repo in repos:
                rebase_result = auto_rebase_to_base(repo.path, base_branch=repo.base_branch)
                snapshot_item = snapshot_repo(repo.path, base_branch=repo.base_branch)
                ahead, behind = ahead_behind(repo.path)
                sync = "upstream 없음" if ahead is None or behind is None else f"ahead {ahead}, behind {behind}"
                base_sync = (
                    "기준 비교 불가"
                    if snapshot_item.base_behind is None
                    else f"기준 {snapshot_item.base_ref}: behind {snapshot_item.base_behind}, ahead {snapshot_item.base_ahead}"
                )
                working = "작업중" if snapshot_item.branch != snapshot_item.base_branch and snapshot_item.branch != "detached" else "기준 브랜치"
                rebase_alert = "" if rebase_result.succeeded or _is_dirty_rebase_skip(rebase_result.message) else f", 자동 rebase 알림: {rebase_result.message}"
                auto_sync = f", 자동 처리: {rebase_result.message}" if rebase_result.succeeded and rebase_result.attempted else ""
                print(f"- {repo.path.name} [{snapshot_item.branch} <- {snapshot_item.base_branch}] {working}, {sync}, {base_sync}{auto_sync}{rebase_alert} | {repo.path}")
        return 0

    if args.area == "repo" and args.command == "remote-list":
        repos = list_remote_repositories(owner=args.owner, limit=args.limit)
        print(format_remote_repositories(repos, output_format=args.format))
        return 0

    if args.area == "repo" and args.command == "clone":
        path = clone_remote_repository(repo=args.repo, target_root=args.target_root)
        print(f"{path}\tclone 완료")
        return 0

    if args.area == "repo" and args.command == "update":
        repo_path = _managed_repo_path(config, args.repo)
        command = {
            "fetch": "git fetch --prune",
            "pull": "git pull --ff-only",
            "rebase": "git pull --rebase --autostash",
            "push": "git push",
        }[args.mode]
        if args.dry_run:
            print(f"[dry-run] {repo_path}: {command}")
            return 0

        if args.mode == "fetch":
            output = fetch(repo_path)
        elif args.mode == "pull":
            require_clean_worktree(repo_path, action="업데이트")
            output = pull_ff_only(repo_path)
        elif args.mode == "rebase":
            require_clean_worktree(repo_path, action="Rebase")
            output = pull_rebase(repo_path)
        else:
            output = push(repo_path)
        print(output or f"{repo_path.name}: {command} 완료")
        return 0

    if args.area == "repo" and args.command == "branches":
        repo_path = _managed_repo_path(config, args.repo)
        options = branch_options(
            repo_path,
            base_branch=_configured_base_branch(config, repo_path),
            author_identities=_git_author_identities(config, repo_path),
        )
        if args.format == "tsv":
            print("\n".join("\t".join([item.name, "1" if item.current else "0", "1" if item.remote else "0"]) for item in options))
        else:
            print(f"{repo_path.name} 브랜치")
            for item in options:
                marker = "*" if item.current else "-"
                origin = "remote" if item.remote else "local"
                print(f"{marker} {item.name} ({origin})")
        return 0

    if args.area == "repo" and args.command == "checkout":
        repo_path = _managed_repo_path(config, args.repo)
        output = checkout_branch(repo_path, args.branch)
        print(output or f"{repo_path.name}: {args.branch} 체크아웃 완료")
        return 0

    if args.area == "repo" and args.command == "commits":
        repo_path = _managed_repo_path(config, args.repo)
        today = __import__("datetime").date.today().isoformat()
        output = commits_between(
            repo_path,
            author=config.general.git_author,
            since=f"{today} 00:00",
            until=f"{today} {config.general.work_end_time}",
        )
        print(output or "오늘 내 커밋이 없습니다.")
        return 0

    if args.area == "repo" and args.command == "activity":
        print(summarize_daily_activity(config))
        return 0

    if args.area == "repo" and args.command == "daily-draft":
        notes = Path(args.notes_file).expanduser().read_text(encoding="utf-8") if args.notes_file else args.notes
        print(draft_daily_work_report(config, manual_notes=notes))
        return 0

    if args.area == "repo" and args.command == "send-report-text":
        text = Path(args.text_file).expanduser().read_text(encoding="utf-8")
        if not config.features.notifications:
            print("Slack 연동이 꺼져 있어 앱 기록만 사용합니다.")
            return 0
        SlackClient(config.slack, destination="git_report").send(text, blocks=[section_block(text)])
        print("보고서를 Slack으로 전송했습니다.")
        return 0

    if args.area == "repo" and args.command == "submit-report":
        print(submit_report_file(config, text_file=args.text_file, notes_file=args.notes_file, send_slack=args.send_slack))
        return 0

    if args.area == "repo" and args.command == "report-history":
        print(report_history(output_format=args.format))
        return 0

    if args.area == "memo" and args.command == "add":
        print(
            add_work_note_file(
                config,
                target_type=args.target_type,
                target_id=args.target_id,
                target_title=args.target_title,
                text_file=args.text_file,
            )
        )
        return 0

    if args.area == "memo" and args.command == "list":
        print(work_notes(output_format=args.format))
        return 0

    if args.area == "overtime" and args.command == "add":
        print(
            add_overtime_record(
                config,
                work_date=args.date,
                hours=args.hours,
                kind=args.kind,
                start_time=args.start,
                end_time=args.end,
                memo=args.memo,
            )
        )
        return 0

    if args.area == "overtime" and args.command == "update":
        print(
            update_overtime_record(
                record_id=args.id,
                work_date=args.date,
                hours=args.hours,
                kind=args.kind,
                start_time=args.start,
                end_time=args.end,
                memo=args.memo,
            )
        )
        return 0

    if args.area == "overtime" and args.command == "delete":
        print(delete_overtime_record(record_id=args.id))
        return 0

    if args.area == "overtime" and args.command == "list":
        print(overtime_records(month=args.month, output_format=args.format))
        return 0

    if args.area == "overtime" and args.command == "summary":
        print(overtime_summary(month=args.month, output_format=args.format))
        return 0

    if args.area == "overtime" and args.command == "settings":
        if (
            args.hourly_rate
            or args.overtime_multiplier
            or args.night_multiplier
            or args.holiday_multiplier
            or args.rounding_minutes
            or args.inclusive_salary
            or args.inclusive_weekly_hours
            or args.base_monthly_salary
            or args.inclusive_overtime_pay
            or args.statutory_base_pay
        ):
            current = json.loads(overtime_settings(output_format="json"))
            print(
                save_overtime_settings(
                    hourly_rate=args.hourly_rate or current["hourly_rate"],
                    overtime_multiplier=args.overtime_multiplier or current["overtime_multiplier"],
                    night_multiplier=args.night_multiplier or current["night_multiplier"],
                    holiday_multiplier=args.holiday_multiplier or current["holiday_multiplier"],
                    rounding_minutes=args.rounding_minutes or int(current["rounding_minutes"]),
                    currency=args.currency or current["currency"],
                    inclusive_salary_enabled=(args.inclusive_salary == "true") if args.inclusive_salary else bool(current.get("inclusive_salary_enabled")),
                    inclusive_weekly_hours=args.inclusive_weekly_hours or current.get("inclusive_weekly_hours", "0"),
                    base_monthly_salary=args.base_monthly_salary or current.get("base_monthly_salary", "0"),
                    inclusive_overtime_pay=args.inclusive_overtime_pay or current.get("inclusive_overtime_pay", "0"),
                    statutory_base_pay=args.statutory_base_pay or current.get("statutory_base_pay", "0"),
                )
            )
        else:
            print(overtime_settings(output_format=args.format))
        return 0

    if args.area == "repo" and args.command == "morning-sync":
        print(morning_sync(config, send_slack=args.send_slack, dry_run=args.dry_run))
        return 0

    if args.area == "automation" and args.command == "tick":
        print(tick(config, task_name=args.task, dry_run=args.dry_run))
        return 0

    if args.area == "routine" and args.command == "morning":
        print(morning_briefing(config, send_slack=args.send_slack, dry_run=args.dry_run))
        return 0

    if args.area == "routine" and args.command == "evening":
        print(evening_check(config, send_slack=args.send_slack, dry_run=args.dry_run))
        return 0

    if args.area == "dev" and args.command == "branch-name":
        print(branch_name(args.issue_key, args.summary, prefix=args.prefix))
        return 0

    if args.area == "dev" and args.command == "create-branch":
        result = create_branch(config, args.repo, args.issue_key, args.summary, prefix=args.prefix, base_branch=args.base_branch)
        record_branch_ready(config, args.issue_key, repo_path=args.repo, branch=branch_name(args.issue_key, args.summary, prefix=args.prefix), summary=args.summary)
        print(result)
        return 0

    if args.area == "dev" and args.command == "commit-message":
        print(commit_message(config, args.repo, args.issue_key, change_type=args.type))
        return 0

    if args.area == "dev" and args.command == "pr-draft":
        print(pr_draft(config, args.repo, args.issue_key))
        return 0

    if args.area == "dev" and args.command == "audit-jira-keys":
        print(audit_jira_keys(config))
        return 0

    if args.area == "dev" and args.command == "recommend-repo":
        print(recommend_issue_repositories(config, args.issue_key, summary=args.summary))
        return 0

    if args.area == "dev" and args.command == "trace-issue":
        print(trace_issue_work(config, args.issue_key))
        return 0

    if args.area == "dev" and args.command == "start-issue":
        print(
            start_issue_work(
                config,
                args.issue_key,
                repo_path=args.repo,
                summary=args.summary,
                prefix=args.prefix,
                base_branch=args.base_branch,
            )
        )
        return 0

    if args.area == "dev" and args.command == "pr-status":
        print(pr_status_dashboard(config, send_slack=args.send_slack))
        return 0

    if args.area == "dev" and args.command == "review-alerts":
        print(review_request_alerts(config, send_slack=args.send_slack))
        return 0

    if args.area == "dev" and args.command == "ci-alerts":
        print(ci_failure_alerts(config, send_slack=args.send_slack))
        return 0

    if args.area == "dev" and args.command == "evening-checklist":
        print(evening_checklist(config))
        return 0

    if args.area == "dev" and args.command == "dashboard":
        print(dashboard(config))
        return 0

    if args.area == "dev" and args.command == "calendar":
        print(calendar_summary(config))
        return 0

    if args.area == "ai" and args.command == "git-summary":
        print(git_summary(config, tone=args.tone, days=args.days))
        return 0

    if args.area == "ai" and args.command == "daily-report":
        notes = Path(args.notes_file).expanduser().read_text(encoding="utf-8") if args.notes_file else args.notes
        print(daily_commit_report(config, notes=notes, tone=args.tone, report_rules_file=args.report_agent_file))
        return 0

    if args.area == "ai" and args.command == "pr-draft":
        print(pr_description(config, repo_path=args.repo, issue_key=args.issue_key, tone=args.tone))
        return 0

    if args.area == "ai" and args.command == "jira-summary":
        print(jira_issue_summary(config, issue_key=args.issue_key, tone=args.tone))
        return 0

    if args.area == "ai" and args.command == "monthly-review":
        print(monthly_review(config, month=args.month, tone=args.tone))
        return 0

    if args.area == "ai" and args.command == "incident-draft":
        print(incident_draft(config, issue_key=args.issue_key, notes=args.notes, tone=args.tone))
        return 0

    if args.area == "status" and args.command == "doctor":
        print(run_doctor(config))
        return 0

    if args.area == "status" and args.command == "health":
        print(run_health(config, check_connections=not args.no_network, send_alert=args.send_alert))
        return 0

    if args.area == "status" and args.command == "tokens":
        print(token_status(config, output_format=args.format))
        return 0

    if args.area == "schedule" and args.command == "install":
        print(install_schedules(config))
        return 0

    if args.area == "schedule" and args.command == "uninstall":
        print(uninstall_schedules())
        return 0

    if args.area == "schedule" and args.command == "status":
        print(schedule_status(config))
        return 0

    if args.area == "settings" and args.command == "import":
        print(import_settings(config, config_file=args.config_file, assignees_file=args.assignees_file))
        return 0

    if args.area == "settings" and args.command == "assignees" and args.action == "list":
        print(list_assignees(config))
        return 0

    raise RuntimeError("Unknown command")


def _managed_repo_path(config, raw_path: str) -> Path:
    repo_path = Path(raw_path).expanduser().resolve()
    managed = {path.resolve() for path in configured_repositories(config)}
    if repo_path not in managed:
        raise RuntimeError(f"관리 대상 repository가 아닙니다: {repo_path}")
    return repo_path


def _configured_base_branch(config, repo_path: Path) -> str:
    for item in config.repo_projects:
        if item.path.expanduser().resolve() == repo_path:
            return item.base_branch
    return ""


def _git_author_identities(config, repo_path: Path) -> set[str]:
    identities = {config.general.git_author}
    for key in ("user.name", "user.email"):
        try:
            value = git(repo_path, "config", "--get", key)
        except RuntimeError:
            value = ""
        if value:
            identities.add(value)
    return {item.strip().strip("<>").lower() for item in identities if item.strip()}


def _today_commit_status(config, repo_path: Path) -> tuple[int, str]:
    timezone = ZoneInfo(config.general.timezone)
    now = datetime.now(timezone)
    today = now.date().isoformat()
    activity = collect_daily_activity(repo_path, today=today, author=config.general.git_author)
    items = [("커밋", row) for row in activity.commits]
    items.extend(("머지", row) for row in activity.merges)
    items.sort(key=lambda item: _commit_datetime(item[1]) or datetime.min, reverse=True)
    rows = [_compact_commit_line(row, now=now, kind=kind) for kind, row in items[:20]]
    rows = [row for row in rows if row]
    total = len(activity.commits) + len(activity.merges)
    if not rows:
        return 0, ""
    return total, "\n".join(rows[:20])


def _commit_datetime(row: str) -> datetime | None:
    parts = row.split(" | ", 3)
    if len(parts) < 2:
        return None
    try:
        return datetime.fromisoformat(parts[1].strip())
    except ValueError:
        return None


def _compact_commit_line(row: str, *, now: datetime | None = None, kind: str = "") -> str:
    parts = row.split(" | ", 3)
    if len(parts) == 3:
        relative = _relative_commit_time(parts[1], now=now)
        prefix_parts = [item for item in [kind, relative, parts[0]] if item]
        prefix = " ".join(prefix_parts)
        return f"{prefix} {parts[2]}"
    if len(parts) >= 4:
        relative = _relative_commit_time(parts[1], now=now)
        prefix_parts = [item for item in [kind, relative, parts[0]] if item]
        prefix = " ".join(prefix_parts)
        return f"{prefix} {parts[3]}"
    return row


def _relative_commit_time(value: str, *, now: datetime | None = None) -> str:
    try:
        committed_at = datetime.fromisoformat(value.strip())
    except ValueError:
        return ""
    current = now or datetime.now(committed_at.tzinfo)
    if committed_at.tzinfo is None and current.tzinfo is not None:
        committed_at = committed_at.replace(tzinfo=current.tzinfo)
    seconds = max(0, int((current - committed_at).total_seconds()))
    if seconds < 60:
        return "방금"
    minutes = seconds // 60
    if minutes < 60:
        return f"{minutes}분 전"
    hours = minutes // 60
    if hours < 24:
        return f"{hours}시간 전"
    return f"{hours // 24}일 전"


def _github_repo_overview(repo_path: Path) -> tuple[str, str]:
    repo_name = owner_repo(repo_path)
    if not repo_name:
        return "", ""
    pull_requests = _gh_json(
        [
            "gh",
            "pr",
            "list",
            "--repo",
            repo_name,
            "--state",
            "open",
            "--json",
            "number,title,headRefName,baseRefName,reviewDecision,updatedAt",
            "--limit",
            "20",
        ]
    )
    release = _gh_json(
        [
            "gh",
            "release",
            "view",
            "--repo",
            repo_name,
            "--json",
            "tagName,name,publishedAt,url",
        ]
    )
    return _format_pull_request_summary(pull_requests), _format_release_summary(release)


def _gh_json(args: list[str]) -> object:
    try:
        result = subprocess.run(args, check=True, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=8)
    except (FileNotFoundError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
        return None
    try:
        return json.loads(result.stdout or "null")
    except json.JSONDecodeError:
        return None


def _format_pull_request_summary(value: object) -> str:
    if not isinstance(value, list):
        return "PR 확인 불가"
    if not value:
        return "열린 PR 없음"
    first = value[0] if isinstance(value[0], dict) else {}
    decision = first.get("reviewDecision") or "리뷰 상태 없음"
    title = str(first.get("title") or "")
    return f"열린 PR {len(value)}개 · #{first.get('number')} {title} · {decision}"


def _format_release_summary(value: object) -> str:
    if not isinstance(value, dict):
        return "릴리즈 확인 불가"
    tag = str(value.get("tagName") or "").strip()
    if not tag:
        return "릴리즈 없음"
    published_at = str(value.get("publishedAt") or "")[:10]
    name = str(value.get("name") or "").strip()
    label = tag if not name or name == tag else f"{tag} · {name}"
    return f"최신 릴리즈 {label}" + (f" · {published_at}" if published_at else "")


def _branch_work_status(repo_path: Path, base_ref: str, branch: str, base_branch: str) -> tuple[str, int, str]:
    if not base_ref or branch == "detached" or branch == base_branch:
        return "", 0, ""
    merge_base = git(repo_path, "merge-base", "HEAD", base_ref).strip()
    if not merge_base:
        return "", 0, ""
    fork_date = git(repo_path, "show", "-s", "--format=%ci", merge_base).strip()
    count_raw = git(repo_path, "rev-list", "--count", f"{base_ref}..HEAD").strip()
    try:
        count = int(count_raw)
    except ValueError:
        count = 0
    preview = git(repo_path, "log", "--oneline", "--decorate=no", "--max-count=5", f"{base_ref}..HEAD")
    return fork_date, count, preview


def _is_dirty_rebase_skip(message: str) -> bool:
    return message.startswith("변경 파일 ") and "자동 rebase 건너뜀" in message


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"오류: {exc}", file=sys.stderr)
        raise SystemExit(1)
