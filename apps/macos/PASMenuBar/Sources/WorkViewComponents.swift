import AppKit
import SwiftUI

struct StatusPill: View {
    let text: String
    let isRunning: Bool

    var body: some View {
        HStack(spacing: 7) {
            if isRunning {
                ProgressView()
                    .controlSize(.small)
            } else {
                Circle()
                    .fill(Color.green)
                    .frame(width: 7, height: 7)
            }
            Text(text)
                .font(.caption)
                .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct WorkSidebarView: View {
    @Binding var selectedSection: String
    @Binding var isCollapsed: Bool
    let activeProfileID: String
    let profiles: [PASProfile]
    let repositoryCount: Int
    let reportReady: Bool
    let onProfileChange: (String) -> Void

    private var width: CGFloat {
        isCollapsed ? 68 : 218
    }

    var body: some View {
        VStack(alignment: isCollapsed ? .center : .leading, spacing: 14) {
            sidebarHeader
            profilePicker

            VStack(spacing: 6) {
                WorkSidebarButton(
                    title: "대시보드",
                    systemImage: "rectangle.grid.2x2",
                    detail: nil,
                    isSelected: selectedSection == "dashboard" || selectedSection == "briefing",
                    isCollapsed: isCollapsed
                ) {
                    selectedSection = "dashboard"
                }

                WorkSidebarButton(
                    title: "작업",
                    systemImage: "checklist",
                    detail: nil,
                    isSelected: selectedSection == "work" || selectedSection == "jira" || selectedSection == "tools",
                    isCollapsed: isCollapsed
                ) {
                    selectedSection = "work"
                }

                WorkSidebarButton(
                    title: "저장소",
                    systemImage: "folder.badge.gearshape",
                    detail: repositoryCount > 0 ? "\(repositoryCount)" : nil,
                    isSelected: selectedSection == "repositories" || selectedSection == "workspace",
                    isCollapsed: isCollapsed
                ) {
                    selectedSection = "repositories"
                }

                WorkSidebarButton(
                    title: "보고서",
                    systemImage: "doc.text",
                    detail: reportReady ? "작성됨" : nil,
                    isSelected: selectedSection == "report",
                    isCollapsed: isCollapsed
                ) {
                    selectedSection = "report"
                }

                WorkSidebarButton(
                    title: "기록",
                    systemImage: "calendar",
                    detail: nil,
                    isSelected: selectedSection == "records",
                    isCollapsed: isCollapsed
                ) {
                    selectedSection = "records"
                }
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isCollapsed.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isCollapsed ? "sidebar.left" : "sidebar.leading")
                    if !isCollapsed {
                        Text("메뉴 접기")
                        Spacer(minLength: 0)
                    }
                }
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: isCollapsed ? .center : .leading)
                .padding(.horizontal, isCollapsed ? 0 : 10)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.58))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .help(isCollapsed ? "메뉴 펼치기" : "메뉴 접기")
        }
        .padding(.horizontal, isCollapsed ? 10 : 14)
        .padding(.vertical, 16)
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
        .animation(.easeInOut(duration: 0.18), value: isCollapsed)
    }

    private var sidebarHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.16))
                Image(systemName: "bolt.horizontal.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 34, height: 34)

            if !isCollapsed {
                VStack(alignment: .leading, spacing: 1) {
                    Text("PAS")
                        .font(.headline)
                    Text("Work")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: isCollapsed ? .center : .leading)
    }

    private var profilePicker: some View {
        Group {
            if isCollapsed {
                Menu {
                    ForEach(profiles) { profile in
                        Button {
                            onProfileChange(profile.id)
                        } label: {
                            Label(profile.title, systemImage: profile.systemImage)
                        }
                    }
                } label: {
                    Image(systemName: activeProfile.systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 42, height: 34)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .menuStyle(.borderlessButton)
                .help("프로필 전환")
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("프로필")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Picker("프로필", selection: profileSelection) {
                        ForEach(profiles) { profile in
                            Label(profile.title, systemImage: profile.systemImage)
                                .tag(profile.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)

                    Text(activeProfile.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(9)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var activeProfile: PASProfile {
        PASProfile.profile(for: activeProfileID) ?? .work
    }

    private var profileSelection: Binding<String> {
        Binding(
            get: { activeProfileID },
            set: { onProfileChange($0) }
        )
    }
}

struct WorkSidebarButton: View {
    let title: String
    let systemImage: String
    let detail: String?
    let isSelected: Bool
    let isCollapsed: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 20)

                if !isCollapsed {
                    Text(title)
                        .font(.callout)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let detail {
                        Text(detail)
                            .font(.caption2)
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: isCollapsed ? .center : .leading)
            .padding(.horizontal, isCollapsed ? 0 : 10)
            .padding(.vertical, 9)
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .background(menuBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .shadow(
                color: Color.black.opacity(isHovered || isSelected ? 0.16 : 0),
                radius: isHovered || isSelected ? 10 : 0,
                x: 0,
                y: isHovered || isSelected ? 5 : 0
            )
            .scaleEffect(isHovered ? 1.015 : 1)
            .animation(.easeOut(duration: 0.14), value: isHovered)
            .animation(.easeOut(duration: 0.14), value: isSelected)
        }
        .buttonStyle(.plain)
        .help(title)
        .onHover { isHovered = $0 }
    }

    private var menuBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(isHovered ? 0.20 : 0.14)
        }
        if isHovered {
            return Color(nsColor: .controlBackgroundColor).opacity(0.82)
        }
        return Color.clear
    }
}

struct DashboardPanel<Content: View, Actions: View>: View {
    let title: String
    let systemImage: String
    let content: Content
    let actions: Actions

    init(
        title: String,
        systemImage: String,
        @ViewBuilder actions: () -> Actions,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.actions = actions()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(.headline)
                Spacer()
                actions
            }

            content
        }
        .padding(14)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.55))
        )
    }
}

extension DashboardPanel where Actions == EmptyView {
    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, systemImage: systemImage, actions: { EmptyView() }, content: content)
    }
}

struct CollapsibleDashboardPanel<Content: View>: View {
    let title: String
    let systemImage: String
    @Binding var isExpanded: Bool
    let content: Content

    init(title: String, systemImage: String, isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self._isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isExpanded ? 13 : 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                        .foregroundStyle(Color.accentColor)
                    Text(title)
                        .font(.headline)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                content
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.55))
        )
    }
}

struct DashboardButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }
}

struct CommandGroup<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let content: Content

    init(title: String, subtitle: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor.opacity(0.14))
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            content
        }
        .padding(12)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.50))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45))
        )
    }
}

struct RepositoryDashboardRow: View {
    let repo: LocalRepositoryOption
    let branches: [BranchOption]
    let isSelected: Bool
    let isRunning: Bool
    let isPrivacyMasked: Bool
    let onSelect: () -> Void
    let onCheckout: (String) -> Void
    let onOpenIDE: () -> Void
    let onOpenCodex: () -> Void
    let visibleCommitRows: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                RepoStatusIcon(statusImage: statusImage, statusColor: statusColor)

                VStack(alignment: .leading, spacing: 8) {
                    repoTitleRow
                    repoStatusSummary
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            repoSnapshotGrid

            if !repo.autoSyncMessage.isEmpty {
                AutoSyncNotice(message: displayRepoMessage(repo.autoSyncMessage), summary: displayRepoMessage(autoSyncSummary))
            } else if shouldShowGuidance {
                RepoGuidanceView(
                    title: guidanceTitle,
                    message: displayRepoMessage(guidanceMessage),
                    color: statusColor
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                TodayCommitInlineView(repo: repo, visibleRows: visibleCommitRows, isPrivacyMasked: isPrivacyMasked)
                GitHubRepoOverviewView(repo: repo, isPrivacyMasked: isPrivacyMasked)
            }
        }
        .padding(16)
        .background(isSelected ? Color.accentColor.opacity(0.16) : Color(nsColor: .textBackgroundColor).opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.85) : Color(nsColor: .separatorColor).opacity(0.72), lineWidth: isSelected ? 1.4 : 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }

    private var repoTitleRow: some View {
        HStack(spacing: 8) {
            Text(displayRepoName)
                .font(.system(size: 15, weight: .semibold))
                .help(isPrivacyMasked ? "마스킹됨: 실제 로컬 경로는 숨김 처리 중입니다." : repo.path)
            BranchPicker(
                currentBranch: repo.branch,
                displayCurrentBranch: displayBranch(repo.branch),
                branches: branches,
                isDisabled: isRunning || repo.dirtyCount > 0,
                onCheckout: onCheckout
            )
            SmallIDEButton(action: onOpenIDE)
                .disabled(isRunning)
            Button(action: onOpenCodex) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 27, height: 24)
            }
            .buttonStyle(.borderless)
            .disabled(isRunning)
            .help("Codex 작업 지시")
            Spacer(minLength: 0)
        }
    }

    private var repoBadges: some View {
        HStack(spacing: 8) {
            RepoStatusBadge(text: repo.syncLabel, color: statusColor)
            RepoStatusBadge(text: isPrivacyMasked ? "기준 브랜치 sample-base" : repo.baseLabel, color: repo.needsBaseRebase ? .red : .blue)
            if !repo.autoSyncLabel.isEmpty {
                RepoStatusBadge(text: repo.autoSyncLabel, color: .green, helpText: displayRepoMessage(repo.autoSyncMessage))
            }
            if repo.dirtyCount > 0 {
                RepoStatusBadge(text: "변경 \(repo.dirtyCount)", color: .orange)
            }
        }
    }

    private var repoStatusSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(guidanceTitle)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
                Text(riskLevel)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.12))
                    .foregroundStyle(statusColor)
                    .clipShape(Capsule())
                Spacer(minLength: 0)
            }

            Text(displayRepoMessage(statusSubtitle))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            repoBadges
        }
    }

    private var repoSnapshotGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
            ],
            spacing: 8
        ) {
            RepoSnapshotTile(title: "브랜치", value: displayBranch(repo.branch), detail: "기준 \(displayBranch(repo.baseBranch))", systemImage: "arrow.branch", tint: statusColor)
            RepoSnapshotTile(title: "동기화", value: compactSyncValue, detail: compactAheadBehind, systemImage: "arrow.triangle.2.circlepath", tint: syncTint)
            RepoSnapshotTile(title: "오늘 작업", value: repo.todayCommitCount > 0 ? "\(repo.todayCommitCount)개" : "없음", detail: displayCommitLine(repo.todayCommitLines.first ?? "오늘 커밋 없음"), systemImage: "clock", tint: repo.todayCommitCount > 0 ? .green : .secondary)
            RepoSnapshotTile(title: "PR/릴리즈", value: repo.githubSummaryAvailable ? "확인됨" : "정보 없음", detail: githubCompactDetail, systemImage: "arrow.triangle.pull", tint: repo.githubSummaryAvailable ? .blue : .secondary)
        }
    }

    private var displayRepoName: String {
        isPrivacyMasked ? "sample-repo" : repo.name
    }

    private func displayBranch(_ branch: String) -> String {
        guard isPrivacyMasked else { return branch }
        if branch == repo.baseBranch {
            return "sample-base"
        }
        return "feature/DEMO-123"
    }

    private func displayCommitLine(_ line: String) -> String {
        guard isPrivacyMasked else { return line }
        return line.replacingOccurrences(
            of: #"[A-Z][A-Z0-9]+-\d+"#,
            with: "DEMO-123",
            options: .regularExpression
        )
    }

    private func displayRepoMessage(_ message: String) -> String {
        guard isPrivacyMasked else { return message }
        var result = message
        result = result.replacingOccurrences(
            of: #"[A-Z][A-Z0-9]+-\d+"#,
            with: "DEMO-123",
            options: .regularExpression
        )
        result = result.replacingOccurrences(of: repo.name, with: displayRepoName)
        result = result.replacingOccurrences(of: repo.path, with: "/Users/dev/workspace/sample-repo")
        result = result.replacingOccurrences(of: repo.baseBranch, with: "sample-base")
        result = result.replacingOccurrences(
            of: #"(src|app|pages|components|features|lib|tests)/[A-Za-z0-9_./-]+"#,
            with: "src/sample/file.swift",
            options: .regularExpression
        )
        return result
    }

    private var riskLevel: String {
        if repo.isProtectedWorkflowBranch || !repo.baseRebaseAlert.isEmpty || repo.needsBaseRebase || repo.needsRebase {
            return "높음"
        }
        if repo.dirtyCount > 0 || repo.needsUpdate || (repo.ahead ?? 0) > 0 || repo.isWorkingBranch {
            return "확인"
        }
        return "정상"
    }

    private var statusSubtitle: String {
        if !repo.autoSyncMessage.isEmpty {
            return autoSyncSummary
        }
        if repo.dirtyCount > 0 {
            return "\(repo.dirtyCount)개 변경 파일이 있습니다. 최신화나 rebase 전 커밋 또는 stash가 필요합니다."
        }
        if repo.needsBaseRebase {
            return "현재 작업 브랜치가 기준 \(repo.baseBranch)보다 뒤처져 있습니다."
        }
        if repo.needsRebase {
            return "원격과 로컬이 모두 움직였습니다. rebase 또는 merge 판단이 필요합니다."
        }
        if repo.canFastForward {
            return "원격 변경을 fast-forward로 받을 수 있습니다."
        }
        if (repo.ahead ?? 0) > 0 {
            return "로컬 커밋이 원격보다 앞서 있습니다."
        }
        if repo.isWorkingBranch {
            return "작업 브랜치에서 진행 중입니다."
        }
        return "기준 브랜치 상태입니다."
    }

    private var compactSyncValue: String {
        let ahead = repo.ahead ?? 0
        let behind = repo.behind ?? 0
        if ahead == 0 && behind == 0 {
            return "동기화"
        }
        if ahead > 0 && behind > 0 {
            return "분기"
        }
        if behind > 0 {
            return "받기 필요"
        }
        if ahead > 0 {
            return "올리기 필요"
        }
        return "upstream 없음"
    }

    private var compactAheadBehind: String {
        guard repo.ahead != nil || repo.behind != nil else {
            return "원격 추적 없음"
        }
        return "ahead \(repo.ahead ?? 0) · behind \(repo.behind ?? 0)"
    }

    private var syncTint: Color {
        if repo.needsRebase || repo.needsUpdate {
            return .orange
        }
        if (repo.ahead ?? 0) > 0 {
            return .purple
        }
        return .green
    }

    private var githubCompactDetail: String {
        if isPrivacyMasked, repo.githubSummaryAvailable {
            return "PR #12 · 최신 릴리즈 v0.0.0"
        }
        if repo.pullRequestSummary.isEmpty && repo.releaseSummary.isEmpty {
            return "PR/릴리즈 없음"
        }
        if !repo.pullRequestSummary.isEmpty {
            return repo.pullRequestSummary
        }
        return repo.releaseSummary
    }

    private var autoSyncSummary: String {
        repo.autoSyncMessage
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "자동 처리 결과가 있습니다."
    }

    private var shouldShowGuidance: Bool {
        repo.dirtyCount > 0 ||
        repo.isProtectedWorkflowBranch ||
        !repo.baseRebaseAlert.isEmpty ||
        repo.needsBaseRebase ||
        repo.needsRebase ||
        repo.needsUpdate ||
        (repo.ahead ?? 0) > 0 ||
        (repo.behind ?? 0) > 0 ||
        repo.isWorkingBranch
    }

    private var statusColor: Color {
        if repo.dirtyCount > 0 {
            return .orange
        }
        if repo.isProtectedWorkflowBranch {
            return .red
        }
        if !repo.baseRebaseAlert.isEmpty {
            return .red
        }
        if repo.needsBaseRebase {
            return .red
        }
        if !repo.isJiraWorkBranch {
            return repo.isWorkingBranch ? .orange : .green
        }
        if repo.needsRebase {
            return .red
        }
        if repo.needsUpdate {
            return .orange
        }
        if (repo.ahead ?? 0) > 0 {
            return .purple
        }
        return .green
    }

    private var statusImage: String {
        if repo.dirtyCount > 0 {
            return "exclamationmark.triangle.fill"
        }
        if repo.isProtectedWorkflowBranch {
            return "lock.fill"
        }
        if !repo.baseRebaseAlert.isEmpty {
            return "exclamationmark.octagon.fill"
        }
        if repo.needsBaseRebase {
            return "arrow.triangle.merge"
        }
        if !repo.isJiraWorkBranch {
            return repo.isWorkingBranch ? "number" : "checkmark.seal.fill"
        }
        if repo.needsRebase {
            return "arrow.triangle.merge"
        }
        if repo.needsUpdate {
            return "arrow.down.circle.fill"
        }
        if (repo.ahead ?? 0) > 0 {
            return "arrow.up.circle.fill"
        }
        return "checkmark.circle.fill"
    }

    private var guidanceTitle: String {
        if repo.dirtyCount > 0 && repo.needsUpdate {
            return "판단 필요"
        }
        if repo.isProtectedWorkflowBranch {
            return "기준 브랜치 보호"
        }
        if !repo.autoSyncMessage.isEmpty {
            return "자동 처리 완료"
        }
        if !repo.baseRebaseAlert.isEmpty {
            return "자동 rebase 확인 필요"
        }
        if repo.needsBaseRebase {
            return "기준 브랜치 rebase 필요"
        }
        if !repo.isJiraWorkBranch {
            return repo.isWorkingBranch ? "Jira 키 브랜치 필요" : "기준 브랜치"
        }
        if repo.dirtyCount > 0 {
            return "로컬 변경 정리"
        }
        if repo.needsRebase {
            return "rebase 권장"
        }
        if repo.canFastForward {
            return "pull 가능"
        }
        if (repo.ahead ?? 0) > 0 {
            return "push 가능"
        }
        return "정상"
    }

    private var guidanceMessage: String {
        let ahead = repo.ahead ?? 0
        let behind = repo.behind ?? 0
        let baseBehind = repo.baseBehind ?? 0
        if repo.isProtectedWorkflowBranch {
            return "설정된 기준 브랜치가 아닌 보호 브랜치입니다. Jira 일감에서 작업 브랜치를 만든 뒤 PR로 반영하세요."
        }
        if !repo.autoSyncMessage.isEmpty {
            return repo.autoSyncMessage
        }
        if !repo.baseRebaseAlert.isEmpty {
            return repo.baseRebaseAlert
        }
        if repo.needsBaseRebase {
            return "현재 작업 브랜치가 기준 \(repo.baseBranch)보다 \(baseBehind)커밋 뒤처졌습니다. Fetch 후 Rebase로 정렬하세요."
        }
        if !repo.isJiraWorkBranch {
            return repo.isWorkingBranch
                ? "브랜치 이름에 LMS-123 같은 Jira 키가 필요합니다. Jira 일감 시작 흐름으로 브랜치를 생성하세요."
                : "이 repository의 기준 브랜치입니다. 새 작업은 Jira 일감 시작 흐름으로 작업 브랜치를 생성하세요."
        }
        if repo.dirtyCount > 0 && behind > 0 {
            return "1. 변경사항 commit/stash -> 2. Fetch -> 3. \(ahead > 0 ? "Rebase" : "Pull") -> 4. 테스트 후 Push"
        }
        if repo.dirtyCount > 0 {
            return ahead > 0
                ? "1. 변경사항 commit/stash -> 2. 테스트 -> 3. Push"
                : "1. 변경사항 commit/stash -> 2. 필요한 경우 Fetch로 원격 상태 확인"
        }
        if behind > 0 && ahead > 0 {
            return "1. Fetch -> 2. Rebase -> 3. 충돌 해결/테스트 -> 4. Push"
        }
        if behind > 0 {
            return "1. Fetch -> 2. Pull로 최신화 -> 3. 테스트"
        }
        if ahead > 0 {
            return "1. 원격 상태 확인 -> 2. 테스트 -> 3. Push"
        }
        return "추가 조치 없이 작업을 시작해도 됩니다."
    }
}

struct RepoSnapshotTile: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint.opacity(0.86))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value.isEmpty ? "-" : value)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(detail.isEmpty ? "-" : detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .help("\(title): \(value)\n\(detail)")
    }
}

struct AutoSyncNotice: View {
    let message: String
    let summary: String
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.arrow.trianglehead.counterclockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("자동 처리됨")
                            .font(.caption.weight(.semibold))
                        Text(summary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(message)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.56))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(9)
        .background(Color.green.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.green.opacity(0.18))
        )
        .help(message)
    }
}

struct RepoStatusIcon: View {
    let statusImage: String
    let statusColor: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(statusColor.opacity(0.18))
            Image(systemName: statusImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(statusColor)
        }
        .frame(width: 42, height: 42)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(statusColor.opacity(0.28))
        )
    }
}

struct GitHubRepoOverviewView: View {
    let repo: LocalRepositoryOption
    var isPrivacyMasked = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("GitHub")
                    .font(.caption)
                    .bold()
                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: 8) {
                GitHubSummaryBox(
                    label: "PR",
                    value: privacyValue(repo.pullRequestSummary, fallback: "PR #12 샘플 작업 리뷰 대기"),
                    systemImage: "arrow.triangle.pull",
                    tint: repo.pullRequestSummary.isEmpty ? .secondary : .blue
                )
                GitHubSummaryBox(
                    label: "릴리즈",
                    value: privacyValue(repo.releaseSummary, fallback: "v0.0.0 샘플 릴리즈"),
                    systemImage: "tag",
                    tint: repo.releaseSummary.isEmpty ? .secondary : .green
                )
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.55))
        )
    }

    private func privacyValue(_ value: String, fallback: String) -> String {
        if value.isEmpty {
            return "정보 없음"
        }
        return isPrivacyMasked ? fallback : value
    }
}

struct GitHubSummaryBox: View {
    let label: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .help(value)
    }
}

struct GitHubSummaryLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption2)
                .bold()
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)
            Text(value)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .help(value)
    }
}

struct BranchPicker: View {
    let currentBranch: String
    var displayCurrentBranch: String?
    let branches: [BranchOption]
    let isDisabled: Bool
    let onCheckout: (String) -> Void

    var body: some View {
        Menu {
            if branches.isEmpty {
                Text("브랜치 목록 없음")
            } else {
                ForEach(branches) { branch in
                    Button {
                        if branch.name != currentBranch {
                            onCheckout(branch.name)
                        }
                    } label: {
                        HStack {
                            Text(branch.label)
                            if branch.name == currentBranch {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(displayCurrentBranch ?? currentBranch)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .font(.caption)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .menuStyle(.borderlessButton)
        .disabled(isDisabled)
        .help(isDisabled && !branches.isEmpty ? "변경 파일이 있으면 브랜치 변경을 막습니다." : "브랜치 체크아웃")
    }
}

struct TodayCommitInlineView: View {
    let repo: LocalRepositoryOption
    let visibleRows: Int
    var isPrivacyMasked = false

    private var rowHeight: CGFloat {
        18
    }

    private var listHeight: CGFloat {
        rowHeight * CGFloat(max(1, visibleRows)) + 6
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: repo.todayCommitCount > 0 ? "checkmark.circle.fill" : "clock")
                    .font(.caption)
                    .foregroundStyle(repo.todayCommitCount > 0 ? .green : .secondary)
                Text(repo.todayCommitLabel)
                    .font(.caption)
                    .bold(repo.todayCommitCount > 0)
                    .foregroundStyle(repo.todayCommitCount > 0 ? .primary : .secondary)
                    .lineLimit(1)
            }

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 3) {
                    if repo.todayCommitLines.isEmpty {
                        Text("오늘 이 repository에서 확인된 작업이 없습니다.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } else {
                        ForEach(Array(repo.todayCommitLines.enumerated()), id: \.offset) { index, line in
                            CommitPreviewLine(line: line, maskedMessage: maskedCommitMessage(index: index, line: line))
                                .frame(height: rowHeight)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: listHeight)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.86))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.58))
        )
        .help(repo.todayCommitLabel)
    }

    private func maskedCommitMessage(index: Int, line: String) -> String? {
        guard isPrivacyMasked else { return nil }
        let sample = [
            "DEMO-123 작업 화면 흐름 정리",
            "DEMO-123 저장소 상태 카드 개선",
            "DEMO-123 보고서 초안 생성 기능 보강",
            "DEMO-123 기록 타임라인 정리",
        ]
        return sample[index % sample.count]
    }
}

struct CommitPreviewLine: View {
    let line: String
    var maskedMessage: String?

    private var parts: (kind: String, time: String, hash: String, message: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let pieces = trimmed.split(separator: " ", maxSplits: 4).map(String.init)
        if pieces.count >= 5, pieces[2] == "전" {
            return (pieces[0], "\(pieces[1]) 전", pieces[3], pieces[4])
        }
        if pieces.count >= 4, pieces[1] == "방금" {
            return (pieces[0], "방금", pieces[2], pieces[3])
        }
        if pieces.count >= 4, pieces[1] == "전" {
            return ("", "\(pieces[0]) 전", pieces[2], pieces[3])
        }
        if pieces.count >= 3, pieces[0] == "방금" {
            return ("", "방금", pieces[1], pieces[2])
        }
        guard let split = trimmed.firstIndex(where: { $0 == " " || $0 == "\t" }) else {
            return ("", "", "", trimmed)
        }
        let hash = String(trimmed[..<split])
        let message = String(trimmed[trimmed.index(after: split)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return ("", "", hash, message)
    }

    var body: some View {
        HStack(spacing: 6) {
            if !parts.kind.isEmpty {
                Text(parts.kind)
                    .font(.caption2)
                    .bold()
                    .foregroundStyle(parts.kind == "머지" ? .purple : .secondary)
                    .lineLimit(1)
                    .frame(width: 30, alignment: .leading)
            }
            if !parts.time.isEmpty {
                Text(parts.time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 48, alignment: .leading)
            }
            if !parts.hash.isEmpty {
                Text(parts.hash)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 50, alignment: .leading)
            }
            Text(maskedMessage ?? parts.message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct SmallIDEButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("IDE", systemImage: "macwindow")
                .font(.caption)
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("IDE에서 열기")
    }
}

struct RepoGuidanceView: View {
    let title: String
    let message: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "list.bullet.clipboard")
                .font(.caption)
                .foregroundStyle(color)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .bold()
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(8)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct RepoStatusBadge: View {
    let text: String
    let color: Color
    var helpText: String?

    var body: some View {
        Text(text)
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .help(helpText ?? text)
    }
}

struct EmptyDashboardState: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.66))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct WorkNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let succeeded: Bool
}

struct WorkNoticeView: View {
    @Environment(\.dismiss) private var dismiss
    let notice: WorkNotice
    @State private var didCopy = false
    @State private var isRawOutputExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(noticeColor.opacity(0.15))
                    Image(systemName: notice.succeeded ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(noticeColor)
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 4) {
                    Text(notice.title)
                        .font(.title3)
                        .bold()
                    Text(notice.succeeded ? "작업이 완료되었습니다." : "작업을 완료하지 못했습니다.")
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if notice.succeeded {
                ResultOutputView(output: notice.message, maxHeight: 320)
                    .frame(minHeight: 150)
            } else {
                WorkNoticeDiagnosticView(message: notice.message)

                DisclosureGroup("원문 오류 보기", isExpanded: $isRawOutputExpanded) {
                    ResultOutputView(output: notice.message, maxHeight: 260)
                        .frame(minHeight: 140)
                        .padding(.top, 8)
                }
            }

            HStack {
                Button {
                    copyNoticeMessage()
                } label: {
                    Label(didCopy ? "복사됨" : "전체 소스 복사", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                }
                .disabled(notice.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("오류 메시지 원문 전체를 클립보드에 복사")

                Spacer()
                Button("닫기") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 620)
    }

    private var noticeColor: Color {
        notice.succeeded ? .green : .red
    }

    private func copyNoticeMessage() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(notice.message, forType: .string)
        didCopy = true
    }
}

struct WorkNoticeDiagnosticView: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "stethoscope")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.orange)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(guide)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            if !cause.isEmpty {
                Text(cause)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.62))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.22))
        )
    }

    private var title: String {
        if message.contains("Jira API 토큰") || message.contains("Unauthorized") || message.contains("401") {
            return "Jira 인증을 확인해야 합니다"
        }
        if message.contains("gh auth") || message.contains("GitHub CLI") || message.localizedCaseInsensitiveContains("authentication required") {
            return "GitHub CLI 인증을 확인해야 합니다"
        }
        if PASRunner.needsRepositorySelection(message) {
            return "작업할 repository 선택이 필요합니다"
        }
        if message.localizedCaseInsensitiveContains("conflict") || message.contains("충돌") || message.contains("CONFLICT") {
            return "Git 충돌 확인이 필요합니다"
        }
        if message.localizedCaseInsensitiveContains("rebase") || message.contains("리베이스") {
            return "rebase 상태 확인이 필요합니다"
        }
        if message.contains("Codex CLI") || message.contains("codex") {
            return "Codex 실행 상태를 확인해야 합니다"
        }
        if message.contains("dirty") || message.contains("미커밋") || message.contains("commit 또는 stash") {
            return "로컬 변경 정리가 필요합니다"
        }
        if message.contains("Slack") || message.contains("chat.postMessage") {
            return "Slack 전송 설정을 확인해야 합니다"
        }
        if message.contains("Traceback") {
            return "명령 실행 중 예외가 발생했습니다"
        }
        return "작업을 완료하지 못했습니다"
    }

    private var guide: String {
        if message.contains("Jira API 토큰") || message.contains("Unauthorized") || message.contains("401") {
            return "설정의 Jira URL, 이메일, API Token이 유효한지 확인해 주세요. 토큰을 갱신했다면 설정 저장 후 다시 시도하면 됩니다."
        }
        if message.contains("gh auth") || message.contains("GitHub CLI") || message.localizedCaseInsensitiveContains("authentication required") {
            return "터미널에서 gh auth status를 확인하고, 필요하면 gh auth login을 다시 진행하세요. 조직 repository는 SSO 승인도 확인해야 합니다."
        }
        if PASRunner.needsRepositorySelection(message) {
            return "이 Jira 일감과 연결된 저장소가 없거나 여러 개입니다. repository 연결 창에서 작업할 저장소를 선택한 뒤 다시 시작하세요."
        }
        if message.localizedCaseInsensitiveContains("conflict") || message.contains("충돌") || message.contains("CONFLICT") {
            return "자동 처리 중 충돌이 난 상태입니다. 충돌 파일을 확인한 뒤 수동으로 정리하고 다시 실행하세요."
        }
        if message.localizedCaseInsensitiveContains("rebase") || message.contains("리베이스") {
            return "현재 브랜치와 기준 브랜치의 차이를 확인하세요. 자동 rebase가 실패했다면 충돌 또는 로컬 변경분이 있는지 먼저 보는 게 좋습니다."
        }
        if message.contains("Codex CLI") || message.contains("codex") {
            return "Codex CLI 설치/로그인 상태를 확인해 주세요. 대시보드 상단의 Codex 상태 칩으로 다시 점검할 수 있습니다."
        }
        if message.contains("dirty") || message.contains("미커밋") || message.contains("commit 또는 stash") {
            return "작업 전 변경분을 커밋하거나 stash 해야 합니다. 변경 파일이 의도한 것인지 먼저 확인하세요."
        }
        if message.contains("Slack") || message.contains("chat.postMessage") {
            return "Slack Bot Token과 전송 채널 권한을 확인해 주세요. 앱 기록은 남기고 Slack 전송만 다시 시도할 수 있습니다."
        }
        if message.contains("Traceback") {
            return "아래 요약 원인을 먼저 보고, 필요하면 원문 오류를 펼쳐 복사해 주세요."
        }
        return "아래 원문 오류를 확인해 원인을 파악하세요. 복사 버튼으로 전체 내용을 남길 수 있습니다."
    }

    private var cause: String {
        let lines = message
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if let runtime = lines.last(where: { $0.contains("RuntimeError:") }) {
            return runtime
        }
        if let last = lines.last {
            return last
        }
        return ""
    }
}

struct RepoAction: Identifiable {
    let id = UUID()
    let repo: LocalRepositoryOption
    let mode: String
}
