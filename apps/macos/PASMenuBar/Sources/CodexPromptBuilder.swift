import Foundation

enum CodexPromptKind {
    case report
    case memo
    case issueWorkspace
    case repositoryTask

    var title: String {
        switch self {
        case .report:
            return "보고서 작성"
        case .memo:
            return "작업 메모"
        case .issueWorkspace:
            return "Jira 작업 워크스페이스"
        case .repositoryTask:
            return "Repository 작업"
        }
    }

    var defaultOutputRule: String {
        switch self {
        case .report:
            return "보고서 본문만 출력하고, 별도의 메타 설명은 붙이지 않는다."
        case .memo:
            return "바로 메모에 붙여도 어색하지 않은 짧은 답변만 출력한다."
        case .issueWorkspace, .repositoryTask:
            return "먼저 현재 상태를 확인하고, 필요한 작업 단위와 위험 요소를 짧게 정리한다."
        }
    }
}

struct CodexPromptSection {
    let title: String
    let body: String

    init(_ title: String, _ body: String) {
        self.title = title
        self.body = body.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum CodexPromptBuilder {
    static let defaultGlobalRules = """
    # PAS Codex 공통 규칙

    ## 기본 태도

    - 사용자의 요청을 먼저 읽고, 앱이 제공한 컨텍스트와 함께 판단한다.
    - 답변은 친근하지만 과장하지 않고, 실무자가 바로 쓸 수 있게 간결하게 쓴다.
    - 확인된 사실과 추정은 구분한다.

    ## 작업 안전

    - 사용자가 만든 변경을 되돌리지 않는다.
    - 위험한 명령, 원격 push, PR 생성, destructive 작업은 사용자 승인 흐름을 따른다.
    - 민감한 토큰, 개인 정보, 내부 URL은 불필요하게 노출하지 않는다.

    ## 코드/저장소 작업

    - 먼저 현재 브랜치와 변경 상태를 확인한다.
    - repository의 AGENTS.md, 기존 git log, 로컬 컨벤션을 우선한다.
    - 커밋/PR은 논리 단위, 테스트 결과, 확인 필요 사항을 분리해서 정리한다.
    """

    static func build(
        kind: CodexPromptKind,
        userRequest: String,
        context: [CodexPromptSection] = [],
        globalRules: String = "",
        rules: [String] = [],
        outputRules: [String] = [],
        friendlyTone: Bool = true
    ) -> String {
        let request = userRequest.trimmingCharacters(in: .whitespacesAndNewlines)
        let globalRules = globalRules.trimmingCharacters(in: .whitespacesAndNewlines)
        let ruleLines = (baseRules(friendlyTone: friendlyTone) + rules)
            .map { "- \($0.trimmingCharacters(in: .whitespacesAndNewlines))" }
            .filter { $0 != "- " }
            .joined(separator: "\n")
        let outputLines = ([kind.defaultOutputRule] + outputRules)
            .map { "- \($0.trimmingCharacters(in: .whitespacesAndNewlines))" }
            .filter { $0 != "- " }
            .joined(separator: "\n")
        let contextText = context
            .filter { !$0.body.isEmpty }
            .map { "## \($0.title)\n\($0.body)" }
            .joined(separator: "\n\n")

        return """
        # PAS Codex Request: \(kind.title)

        너는 PAS 앱 안에서 개발자의 작업을 도와주는 Codex 동료다.
        아래 "사용자 요청"을 최우선으로 따르되, 공통 원칙과 앱이 수집한 컨텍스트를 함께 반영한다.

        ## 공통 원칙
        \(globalRules.isEmpty ? "" : "\(globalRules)\n")
        \(ruleLines)

        ## 사용자 요청
        \(request.isEmpty ? "- 사용자가 구체 요청을 비워두었습니다. 컨텍스트 기준으로 필요한 다음 행동을 제안합니다." : request)

        \(contextText.isEmpty ? "## 컨텍스트\n- 추가 컨텍스트 없음" : contextText)

        ## 출력 규칙
        \(outputLines)
        """
    }

    private static func baseRules(friendlyTone: Bool) -> [String] {
        var values = [
            "확인된 사실과 추정을 구분한다.",
            "없는 정보를 지어내지 않고, 모르는 부분은 확인 필요로 남긴다.",
            "사용자가 만든 변경을 되돌리지 않는다.",
            "민감한 토큰, 개인 정보, 내부 URL은 불필요하게 노출하지 않는다.",
            "위험한 명령, 원격 push, PR 생성, destructive 작업은 사용자 승인 흐름을 따른다.",
        ]
        if friendlyTone {
            values.append("말투는 친근하지만 과장하지 않고, 실무자가 바로 쓸 수 있게 간결하게 쓴다.")
        }
        return values
    }
}
