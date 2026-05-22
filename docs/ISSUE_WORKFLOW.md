# Issue Workflow

DevPilot의 Issue Workflow는 Jira 일감 하나가 배정된 뒤 작업, 테스트, 보고까지 이어지는 흐름을 로컬 상태로 관리한다.

## 목표

- Jira 일감과 repository, 브랜치, 테스트 결과, 작업 보고를 하나의 세션으로 연결한다.
- Jira 상세를 기반으로 Codex 1차 분석 요청서를 만들고 신규 기능/As-Is/To-Be 판단을 먼저 정리한다.
- 아침 브리핑에서는 미완료 일감의 현재 진행도와 다음 행동을 보여준다.
- 저녁 브리핑에서는 완료/진행 중/막힘 상태를 정리해 오늘 한 일과 내일 이어갈 일을 만든다.
- 커밋 메시지는 기존 커밋 태그 규칙과 Jira 키를 함께 쓰도록 유도한다.

## 기본 흐름

```text
Jira 일감 확인
-> Codex 1차 분석 요청
-> Issue Workflow 시작
-> repository 연결
-> Jira 키 포함 브랜치 생성
-> Codex와 작업
-> 커밋 메시지 초안 생성
-> 테스트 결과 기록
-> 작업 보고 기록
-> 아침/저녁 브리핑에 반영
```

## 상태

```text
assigned
branch_ready
in_progress
implemented
tested
pr_ready
reviewing
merged
reported
done
blocked
```

`reported`, `done`, `merged` 상태는 완료/보고 그룹으로 다루고, 나머지는 진행 중인 일감으로 브리핑에 반영한다.

## CLI

```bash
devpilot issue analyze LMS-123
devpilot issue analyze LMS-123 --codex-thread
devpilot jira watch-new --analyze
devpilot jira watch-new --analyze --codex-thread
devpilot issue start LMS-123 --summary "입고 수량 검증 오류 수정"
devpilot issue start LOCAL-20260522-001 --project WMS --summary "운영 요청 정리"
devpilot issue workspace prepare LMS-123 --repo ~/work/cms-back --repo ~/work/cms-front --summary "입고 수량 검증 오류 수정" --prefix fix
devpilot issue workspace status LMS-123
devpilot dev start-issue LMS-123 --repo ~/work/service --summary "입고 수량 검증 오류 수정" --prefix fix
devpilot dev commit-message --repo ~/work/service --issue-key LMS-123 --type fix
devpilot issue status LMS-123 --state implemented --note "검증 로직 수정 완료" --next-action "테스트 실행"
devpilot issue record-test LMS-123 --command "./gradlew test" --result pass --summary "회귀 테스트 통과"
devpilot issue report LMS-123 --summary "검증 로직 수정 및 테스트 기록" --next-action "PR 작성"
devpilot issue workspace cleanup LMS-123
devpilot issue morning
devpilot issue evening
```

`issue start`의 `--project`는 Jira 없이 직접 등록한 일감도 프로젝트 하위로 묶기 위한 값이다. 값이 없으면 Jira 키 접두어를 프로젝트처럼 보여주고, `LOCAL-*` 일감은 `Inbox`로 분류한다.

## 일감 Workspace

`issue workspace prepare`는 일감 전용 폴더를 만들고 필요한 repository를 Git worktree로 배치한다. 같은 원본 repository라도 일감마다 다른 작업 폴더와 작업 브랜치를 가질 수 있다.

```text
~/Library/Application Support/DevPilot/issue-workspaces/LMS-123/
  context.md
  repos/
    cms-back/
    cms-front/
```

기본 규칙은 다음과 같다.

- `--repo`를 여러 번 지정하면 해당 repository들을 workspace에 포함한다.
- `--repo`를 생략하면 `jira link-repo`로 연결된 repository를 사용한다.
- 작업 브랜치는 `fix/LMS-123-summary`처럼 Jira 키를 포함한다.
- 완료 후에는 `issue workspace cleanup`으로 worktree를 정리한다.
- 변경 파일이 남아 있으면 cleanup은 멈춘다. 정말 제거해야 할 때만 `--force`를 사용한다.

## 브리핑 반영

출근 브리핑은 `issue morning` 내용을 포함한다.

퇴근 체크는 `issue evening` 내용을 포함한다.

이 단계에서는 워크플로우 상태 저장과 CLI 흐름을 먼저 안정화한다. 포트폴리오 문서는 실제 사용성이 확인된 뒤 정리한다.
