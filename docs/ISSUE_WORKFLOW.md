# Issue Workflow

DevPilot의 Issue Workflow는 일감 하나가 들어온 뒤 분석, repository 확정, workspace 준비, AI 보조 구현, 테스트, 보고까지 이어지는 흐름을 로컬 상태로 관리한다. Git repository 관리는 핵심 전제이고, Jira와 Slack은 선택 연동이다.

## 목표

- Jira 또는 수동 등록 일감과 repository, 브랜치, 테스트 결과, 작업 보고를 하나의 세션으로 연결한다.
- Jira 상세 또는 수동 입력 내용을 기반으로 Codex 1차 분석 요청서를 만들고 신규 기능/As-Is/To-Be 판단을 먼저 정리한다.
- 아침 브리핑에서는 미완료 일감의 현재 진행도와 다음 행동을 보여준다.
- 저녁 브리핑에서는 완료/진행 중/막힘 상태를 정리해 오늘 한 일과 내일 이어갈 일을 만든다.
- 커밋 메시지는 기존 커밋 태그 규칙과 Jira 키를 함께 쓰도록 유도한다.

## 기본 흐름

```text
일감 확인(Jira 또는 수동 등록)
-> Issue Workflow 시작
-> Codex 1차 분석 요청
-> repository 확정
-> 일감 workspace와 작업 브랜치 생성
-> Codex 워크플로우 컨텍스트로 구현
-> 테스트 결과 기록
-> 작업 보고 기록
-> 아침/저녁 브리핑과 기록 화면에 반영
```

이 흐름의 핵심은 AI를 마지막 보고서 작성에만 쓰는 것이 아니라, 일감 사이사이에 두는 것이다. 초반에는 As-Is/To-Be와 작업 범위 판단을 돕고, workspace 준비 이후에는 일감 상태, 분석 결과, repository, 테스트/보고 기록을 포함한 컨텍스트 파일을 만들어 Codex 작업 루트를 연다.

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

## 앱 화면 흐름

macOS 앱의 `일감 처리 콘솔`은 위 CLI 흐름을 승인 단계로 보여준다.

![DevPilot 일감 처리 콘솔](assets/screenshots/devpilot-issue-flow.png)

```text
일감 수신 -> AI 분석 -> repo 확정 -> workspace 준비 -> 업무 처리 -> 테스트 -> 보고/완료
```

- `AI 분석` 단계에서는 Codex 1차 분석 요청서를 만들거나 Codex 스레드를 생성한다.
- `repo 확정` 단계에서는 일감과 관리 repository를 연결한다.
- `workspace 준비` 단계에서는 Jira 키가 포함된 worktree workspace를 생성한다.
- `업무 처리` 단계에서는 워크플로우 컨텍스트 파일을 만들고 Codex 작업 루트를 연다.
- `테스트`와 `보고/완료` 단계에서는 실행 결과와 보고 내용을 워크플로우 기록으로 남긴다.

`AI 작업 지휘관` 패널은 현재 워크플로우 상태를 바탕으로 분석, 작업 계획, repository 후보, 브랜치 전략, 테스트 추천, 컨벤션 점검, 보고 초안을 한 화면에 정리한다.

![DevPilot AI 작업 지휘관](assets/screenshots/devpilot-ai-director.png)

## Codex 컨텍스트 전달

실제 Codex 대화 화면은 개인 작업 기록이나 회사 업무 맥락이 함께 노출될 수 있으므로 공개 문서에는 직접 캡처를 넣지 않는다. 대신 DevPilot이 어떤 정보를 모아 Codex 작업 루트로 넘기는지 공개용 샘플 구조로 설명한다.

Codex 작업 루트를 열 때 포함하는 정보는 다음과 같다.

- Jira 또는 수동 일감 요약, 본문, 댓글, 완료 조건
- Codex 1차 분석 결과 또는 로컬 분석 기록
- 연결 repository, 기준 브랜치, 현재 브랜치, 변경 파일 상태
- `AGENTS.md` 같은 repository별 작업 규칙
- 테스트 추천, 보고 초안, 이전 단계의 승인 기록

실제 Codex 작업 화면을 문서에 추가할 때는 사이드바와 대화 기록에 민감 정보가 없는 샘플 프로필을 준비한 뒤, 해당 Codex 윈도우만 캡처해 보강한다.

## 브리핑 반영

출근 브리핑은 `issue morning` 내용을 포함한다.

퇴근 체크는 `issue evening` 내용을 포함한다.

이 단계에서는 워크플로우 상태 저장, CLI 흐름, 앱 승인 패널, Codex 작업 루트 연결까지 동작한다. 다음 개선은 실제 작업 결과를 바탕으로 테스트 명령 추천과 workspace 정리 자동화를 더 정교하게 만드는 것이다.
