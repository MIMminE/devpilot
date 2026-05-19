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
        .help(state.detail)
    }
}
