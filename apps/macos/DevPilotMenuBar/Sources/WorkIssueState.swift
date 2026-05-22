import SwiftUI

struct IssueRepositoryLinkRecord: Identifiable, Hashable {
    let issueKey: String
    let repoPath: String
    let repoName: String
    let summary: String
    let updatedAt: String

    var id: String {
        "\(issueKey)-\(repoPath)"
    }
}

struct IssueWorkState {
    let linkedRepositories: [IssueRepositoryLinkRecord]
    let activeRepositories: [LocalRepositoryOption]

    var isLinked: Bool {
        !linkedRepositories.isEmpty
    }

    var hasActiveBranch: Bool {
        !activeRepositories.isEmpty
    }

    var label: String {
        if hasActiveBranch {
            return "브랜치 준비"
        }
        if isLinked {
            return "저장소 연결"
        }
        return "작업 전"
    }

    var detail: String {
        if hasActiveBranch {
            return activeRepositories.map(\.name).joined(separator: ", ")
        }
        if isLinked {
            return linkedRepositories.map(\.repoName).joined(separator: ", ")
        }
        return "저장소를 연결하면 브랜치와 Codex 작업을 바로 시작할 수 있습니다."
    }

    var tint: Color {
        if hasActiveBranch {
            return .green
        }
        if isLinked {
            return .blue
        }
        return .orange
    }

    static let empty = IssueWorkState(linkedRepositories: [], activeRepositories: [])
}

struct IssueStartFlowStrip: View {
    let state: IssueWorkState
    let codexReady: Bool

    var body: some View {
        HStack(spacing: 7) {
            flowStep("1", "일감", isReady: true, tint: .blue)
            connector
            flowStep("2", "저장소", isReady: state.isLinked, tint: .blue)
            connector
            flowStep("3", "브랜치", isReady: state.hasActiveBranch, tint: .green)
            connector
            flowStep("4", "Codex", isReady: codexReady, tint: codexReady ? .green : .orange)
            Spacer(minLength: 0)
        }
    }

    private var connector: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.46))
            .frame(width: 16, height: 1)
    }

    private func flowStep(_ number: String, _ title: String, isReady: Bool, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: isReady ? "checkmark.circle.fill" : "\(number).circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isReady ? tint : Color.secondary)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isReady ? .primary : .secondary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background((isReady ? tint : Color.secondary).opacity(0.08))
        .clipShape(Capsule())
    }
}

struct IssueWorkStateBadge: View {
    let state: IssueWorkState
    var isPrivacyMasked = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(state.tint)
                .frame(width: 6, height: 6)
            Text(state.label)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(state.tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(state.tint.opacity(0.10))
        .clipShape(Capsule())
        .help(isPrivacyMasked ? "샘플 저장소 연결 상태입니다." : state.detail)
    }
}

struct IssueWorkflowRecord: Identifiable, Decodable, Hashable {
    let issueKey: String
    let summary: String
    let status: String
    let updatedAt: String
    let repositories: [IssueWorkflowRepositoryRecord]
    let analysis: IssueWorkflowAnalysisRecord?
    let tests: [IssueWorkflowTestRecord]
    let reports: [IssueWorkflowReportRecord]
    let nextActions: [String]
    let blockers: [String]

    var id: String { issueKey }

    enum CodingKeys: String, CodingKey {
        case issueKey = "issue_key"
        case summary
        case status
        case updatedAt = "updated_at"
        case repositories
        case analysis
        case tests
        case reports
        case nextActions = "next_actions"
        case blockers
    }

    init(
        issueKey: String,
        summary: String,
        status: String,
        updatedAt: String,
        repositories: [IssueWorkflowRepositoryRecord],
        analysis: IssueWorkflowAnalysisRecord?,
        tests: [IssueWorkflowTestRecord],
        reports: [IssueWorkflowReportRecord],
        nextActions: [String],
        blockers: [String]
    ) {
        self.issueKey = issueKey
        self.summary = summary
        self.status = status
        self.updatedAt = updatedAt
        self.repositories = repositories
        self.analysis = analysis
        self.tests = tests
        self.reports = reports
        self.nextActions = nextActions
        self.blockers = blockers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            issueKey: try container.decodeIfPresent(String.self, forKey: .issueKey) ?? "",
            summary: try container.decodeIfPresent(String.self, forKey: .summary) ?? "",
            status: try container.decodeIfPresent(String.self, forKey: .status) ?? "assigned",
            updatedAt: try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? "",
            repositories: try container.decodeIfPresent([IssueWorkflowRepositoryRecord].self, forKey: .repositories) ?? [],
            analysis: try container.decodeIfPresent(IssueWorkflowAnalysisRecord.self, forKey: .analysis),
            tests: try container.decodeIfPresent([IssueWorkflowTestRecord].self, forKey: .tests) ?? [],
            reports: try container.decodeIfPresent([IssueWorkflowReportRecord].self, forKey: .reports) ?? [],
            nextActions: try container.decodeIfPresent([String].self, forKey: .nextActions) ?? [],
            blockers: try container.decodeIfPresent([String].self, forKey: .blockers) ?? []
        )
    }
}

struct IssueWorkflowRepositoryRecord: Identifiable, Decodable, Hashable {
    let repoPath: String
    let repoName: String
    let summary: String
    let branch: String

    var id: String { repoPath }
    var isWorkspaceRepo: Bool { repoPath.contains("issue-workspaces") }

    enum CodingKeys: String, CodingKey {
        case repoPath = "repo_path"
        case repoName = "repo_name"
        case summary
        case branch
    }
}

struct IssueWorkflowAnalysisRecord: Decodable, Hashable {
    let promptPath: String
    let threadID: String
    let threadName: String
    let responsePath: String

    enum CodingKeys: String, CodingKey {
        case promptPath = "prompt_path"
        case threadID = "thread_id"
        case threadName = "thread_name"
        case responsePath = "response_path"
    }
}

struct IssueWorkflowTestRecord: Decodable, Hashable {
    let command: String
    let result: String
    let summary: String
}

struct IssueWorkflowReportRecord: Decodable, Hashable {
    let summary: String
    let recordedAt: String

    enum CodingKeys: String, CodingKey {
        case summary
        case recordedAt = "recorded_at"
    }
}
