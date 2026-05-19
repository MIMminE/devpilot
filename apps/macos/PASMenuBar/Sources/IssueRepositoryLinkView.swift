import SwiftUI

struct IssueRepositoryLinkView: View {
    @ObservedObject var runner: PASRunner
    let issue: String
    let summary: String

    @State private var repositories: [LocalRepositoryOption] = []
    @State private var selectedPaths: Set<String> = []
    @State private var isLoading = false
    @State private var isStartingWork = false
    @State private var resultMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor.opacity(0.16))
                    Image(systemName: "link.badge.plus")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 50, height: 50)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(issue) repository 연결")
                        .font(.title3)
                        .bold()
                    Text(summary.isEmpty ? "이 Jira 일감을 어느 관리 repository에서 처리할지 선택합니다." : summary)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()
            }

            HStack {
                Button(isLoading ? "불러오는 중..." : "관리 repository 불러오기") {
                    Task { await reload() }
                }
                .disabled(isBusy)

                Text("repository를 고르면 연결 저장, 브랜치 생성, Codex 작업 요청까지 한 번에 이어갈 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }

            startFlowSteps

            if isLoading {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("관리 중인 Git repository를 확인하는 중...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            } else if repositories.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("관리 repository가 없습니다")
                        .font(.headline)
                    Text("설정에서 GitHub 후보를 불러온 뒤 관리 repository를 먼저 등록해 주세요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(repositories) { repo in
                            Button {
                                toggleSelection(repo.path)
                            } label: {
                                let isSelected = selectedPaths.contains(repo.path)
                                HStack(spacing: 10) {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack {
                                            Text(repo.name)
                                                .font(.headline)
                                            Text(repo.branch)
                                                .font(.caption)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color(nsColor: .textBackgroundColor))
                                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                        }
                                        Text("\(repo.syncLabel) | \(repo.path)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                }
                                .padding(10)
                                .background(isSelected ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if !resultMessage.isEmpty {
                Text(resultMessage)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Text(selectedPaths.isEmpty ? "선택된 repository 없음" : "\(selectedPaths.count)개 repository 선택")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("닫기") {
                    runner.closeIssueRepositoryLinkWindow()
                }
                Button("연결 저장") {
                    Task { await saveLink() }
                }
                .disabled(selectedPaths.isEmpty || isBusy)

                Button("작업 시작") {
                    Task { await saveLinkStartBranchAndOpenCodex() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedPaths.isEmpty || isBusy)

                Button("IDE까지 열기") {
                    Task { await saveLinkStartBranchAndOpenIDE() }
                }
                .disabled(selectedPaths.isEmpty || isBusy)
            }
        }
        .padding(20)
        .frame(minWidth: 680, minHeight: 520)
        .task {
            await reload()
        }
    }

    private var isBusy: Bool {
        isLoading || isStartingWork || runner.isRunning
    }

    private var startFlowSteps: some View {
        HStack(spacing: 8) {
            flowStep("1", "저장소 선택", isReady: !selectedPaths.isEmpty)
            flowStep("2", "Jira 연결 저장", isReady: false)
            flowStep("3", "브랜치 생성", isReady: false)
            flowStep("4", "Codex 시작", isReady: false)
            Spacer()
            if isStartingWork {
                ProgressView()
                    .controlSize(.small)
                Text("작업 흐름을 준비하는 중")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func flowStep(_ number: String, _ title: String, isReady: Bool) -> some View {
        HStack(spacing: 5) {
            Text(number)
                .font(.caption2.weight(.bold))
                .frame(width: 17, height: 17)
                .background((isReady ? Color.green : Color.accentColor).opacity(0.14))
                .foregroundStyle(isReady ? Color.green : Color.accentColor)
                .clipShape(Circle())
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isReady ? .primary : .secondary)
        }
    }

    private func reload() async {
        isLoading = true
        repositories = await runner.loadManagedRepositories()
        let availablePaths = Set(repositories.map(\.path))
        selectedPaths = selectedPaths.intersection(availablePaths)
        if selectedPaths.isEmpty, repositories.count == 1, let onlyRepo = repositories.first {
            selectedPaths.insert(onlyRepo.path)
        }
        isLoading = false
    }

    private func saveLink() async {
        if await saveSelectedLinks() {
            runner.closeIssueRepositoryLinkWindow()
        }
    }

    private func saveLinkAndStartBranch() async {
        isStartingWork = true
        defer { isStartingWork = false }
        guard await saveSelectedLinks() else { return }
        let paths = selectedRepositories
        runner.closeIssueRepositoryLinkWindow()
        for repo in paths {
            _ = await runner.createBranch(issue: issue, repo: repo.path, summary: summary, showOutput: false)
        }
    }

    private func saveLinkStartBranchAndOpenIDE() async {
        isStartingWork = true
        defer { isStartingWork = false }
        guard await saveSelectedLinks() else { return }
        let repos = selectedRepositories
        runner.closeIssueRepositoryLinkWindow()
        for repo in repos {
            _ = await runner.createBranch(issue: issue, repo: repo.path, summary: summary, showOutput: false)
            runner.openRepositoryInIDE(path: repo.path, appName: runner.loadSettings().defaultIDEAppName)
        }
    }

    private func saveLinkStartBranchAndOpenCodex() async {
        isStartingWork = true
        defer { isStartingWork = false }
        guard await saveSelectedLinks() else { return }
        let repos = selectedRepositories
        var outputs: [String] = [resultMessage].filter { !$0.isEmpty }
        for repo in repos {
            let result = await runner.createBranch(issue: issue, repo: repo.path, summary: summary, showOutput: false)
            outputs.append(result.displayText)
            if !result.succeeded {
                resultMessage = outputs.joined(separator: "\n\n")
                return
            }
        }
        let codexResult = await runner.openCodexWorkspaceForIssue(
            issue: issue,
            summary: summary,
            detail: "",
            repositories: repos
        )
        outputs.append(codexResult.displayText)
        resultMessage = outputs.joined(separator: "\n\n")
        if codexResult.succeeded {
            runner.closeIssueRepositoryLinkWindow()
        }
    }

    private var selectedRepositoryPaths: [String] {
        repositories.map(\.path).filter { selectedPaths.contains($0) }
    }

    private var selectedRepositories: [LocalRepositoryOption] {
        repositories.filter { selectedPaths.contains($0.path) }
    }

    private func toggleSelection(_ path: String) {
        if selectedPaths.contains(path) {
            selectedPaths.remove(path)
        } else {
            selectedPaths.insert(path)
        }
    }

    private func saveSelectedLinks() async -> Bool {
        var outputs: [String] = []
        for path in selectedRepositoryPaths {
            let result = await runner.linkIssueRepository(issue: issue, repo: path, summary: summary, showWorkWindow: false)
            outputs.append(result.displayText)
            if !result.succeeded {
                resultMessage = outputs.joined(separator: "\n")
                return false
            }
        }
        resultMessage = outputs.joined(separator: "\n")
        return true
    }
}
