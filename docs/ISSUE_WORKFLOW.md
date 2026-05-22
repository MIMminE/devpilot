# Issue Workflow

DevPilot의 Issue Workflow는 Jira 일감 하나가 배정된 뒤 작업, 테스트, 보고까지 이어지는 흐름을 로컬 상태로 관리한다.

## 목표

- Jira 일감과 repository, 브랜치, 테스트 결과, 작업 보고를 하나의 세션으로 연결한다.
- 아침 브리핑에서는 미완료 일감의 현재 진행도와 다음 행동을 보여준다.
- 저녁 브리핑에서는 완료/진행 중/막힘 상태를 정리해 오늘 한 일과 내일 이어갈 일을 만든다.
- 커밋 메시지는 기존 커밋 태그 규칙과 Jira 키를 함께 쓰도록 유도한다.

## 기본 흐름

```text
Jira 일감 확인
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
devpilot issue start LMS-123 --summary "입고 수량 검증 오류 수정"
devpilot dev start-issue LMS-123 --repo ~/work/service --summary "입고 수량 검증 오류 수정" --prefix fix
devpilot dev commit-message --repo ~/work/service --issue-key LMS-123 --type fix
devpilot issue status LMS-123 --state implemented --note "검증 로직 수정 완료" --next-action "테스트 실행"
devpilot issue record-test LMS-123 --command "./gradlew test" --result pass --summary "회귀 테스트 통과"
devpilot issue report LMS-123 --summary "검증 로직 수정 및 테스트 기록" --next-action "PR 작성"
devpilot issue morning
devpilot issue evening
```

## 브리핑 반영

출근 브리핑은 `issue morning` 내용을 포함한다.

퇴근 체크는 `issue evening` 내용을 포함한다.

이 단계에서는 워크플로우 상태 저장과 CLI 흐름을 먼저 안정화한다. 포트폴리오 문서는 실제 사용성이 확인된 뒤 정리한다.
