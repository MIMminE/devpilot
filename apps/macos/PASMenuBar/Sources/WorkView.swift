import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct WorkView: View {
    @ObservedObject var runner: PASRunner
    private static let jiraKeyRegex = try? NSRegularExpression(pattern: #"[A-Z][A-Z0-9]+-\d+"#)

    @AppStorage("pas.work.appearance") private var appearance = "system"
    @AppStorage("pas.work.commandCenterExpanded") private var isCommandCenterExpanded = true
    @AppStorage("pas.work.repositoryOrder") private var repositoryOrderRaw = ""
    @AppStorage("pas.work.sidebarCollapsed") private var isSidebarCollapsed = false
    @AppStorage("pas.work.selectedSection") private var selectedSection = "dashboard"
    @AppStorage("pas.briefing.yesterdayMemo") private var briefingYesterdayMemo = ""
    @AppStorage("pas.briefing.focusProject") private var briefingFocusProject = ""
    @AppStorage("pas.briefing.memoryLog") private var briefingMemoryLog = ""
    @AppStorage("pas.overtime.settingsPasscode") private var overtimeSettingsPasscode = ""

    @State private var repositories: [LocalRepositoryOption] = []
    @State private var isLoading = false
    @State private var isInitialDataLoading = false
    @State private var selectedPath = ""
    @State private var lastMessage = ""
    @State private var reportDraft = ""
    @State private var reportNotes = ""
    @State private var reportWasRefined = false
    @State private var lastSubmittedReportID = ""
    @State private var filter = "all"
    @State private var pendingAction: RepoAction?
    @State private var showDirtyWarning = false
    @State private var notice: WorkNotice?
    @State private var branchOptionsByPath: [String: [BranchOption]] = [:]
    @State private var draggingRepositoryPath: String?
    @State private var workCommitPreviewRows = 4
    @State private var jiraMorningItems: [JiraListItem] = []
    @State private var jiraNewItems: [JiraListItem] = []
    @State private var jiraLastUpdatedText = ""
    @State private var hasAutoLoadedJiraMorningItems = false
    @State private var hasPreloadedBriefingData = false
    @State private var jiraTeamFlowItems: [JiraFlowItem] = []
    @State private var teamFlowStatusFilter = "all"
    @State private var isJiraQuickCreatePresented = false
    @State private var quickJiraSummary = ""
    @State private var quickJiraDescription = ""
    @State private var quickJiraIssueType = "Task"
    @State private var quickJiraAssignee = ""
    @State private var quickJiraPriority = ""
    @State private var quickJiraDueDate = ""
    @State private var quickJiraLabels = ""
    @State private var submittedReports: [SubmittedReportRecord] = []
    @State private var selectedReportID = ""
    @State private var workMemos: [WorkMemoRecord] = []
    @State private var codexHealth = CodexHealthStatus.unknown
    @State private var selectedWorkIssueKey = ""
    @State private var selectedIssueDetail = JiraIssueDetailRecord.empty
    @State private var isLoadingIssueDetail = false
    @State private var recordsViewMode = "timeline"
    @State private var selectedRecordDate = Date()
    @State private var overtimeSummary = OvertimeSummaryRecord.empty
    @State private var overtimeSelectedDate = Date()
    @State private var overtimeCalendarMonth = Date()
    @State private var overtimeUsesTimeRange = true
    @State private var overtimeStartHour = 18
    @State private var overtimeStartMinute = 0
    @State private var overtimeEndHour = 20
    @State private var overtimeEndMinute = 0
    @State private var overtimeHours = ""
    @State private var overtimeKind = "overtime"
    @State private var overtimeMemo = ""
    @State private var editingOvertimeRecordID = ""
    @State private var overtimeHourlyRate = ""
    @State private var overtimeMultiplier = "1.5"
    @State private var overtimeNightMultiplier = "0.5"
    @State private var overtimeHolidayMultiplier = "0.5"
    @State private var overtimeRoundingMinutes = "10"
    @State private var isOvertimeExpanded = false
    @State private var isOvertimeSettingsUnlocked = false
    @State private var overtimePasscodeInput = ""
    @State private var overtimeNewPasscode = ""
    @State private var overtimeInclusiveSalaryEnabled = false
    @State private var overtimeInclusiveWeeklyHours = "0"
    @State private var overtimeBaseMonthlySalary = "0"
    @State private var overtimeInclusiveOvertimePay = "0"
    @State private var overtimeStatutoryBasePay = "0"

    private var filteredRepositories: [LocalRepositoryOption] {
        let ordered = orderedRepositories(repositories)
        switch filter {
        case "needsUpdate":
            return ordered.filter { $0.needsUpdate }
        default:
            return ordered
        }
    }

    private var repositoryOrder: [String] {
        repositoryOrderRaw
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private var preferredScheme: ColorScheme? {
        switch appearance {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            return nil
        }
    }

    private var todayTitle: String {
        Date().formatted(.dateTime.month(.abbreviated).day().weekday(.wide))
    }

    private var activeRepositoryCount: Int {
        repositories.filter { $0.isWorkingBranch || $0.dirtyCount > 0 || $0.todayCommitCount > 0 }.count
    }

    private var pendingRepositoryCount: Int {
        repositories.filter(\.needsUpdate).count
    }

    private var recentBriefingMemories: [String] {
        briefingMemoryLog
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .suffix(6)
    }

    private var filteredJiraTeamFlowItems: [JiraFlowItem] {
        guard teamFlowStatusFilter != "all" else {
            return jiraTeamFlowItems
        }
        if teamFlowStatusFilter == "done" {
            return jiraTeamFlowItems.filter(\.isDone)
        }
        if teamFlowStatusFilter == "open" {
            return jiraTeamFlowItems.filter { !$0.isDone }
        }
        return jiraTeamFlowItems.filter { $0.status == teamFlowStatusFilter }
    }

    private var selectedReport: SubmittedReportRecord? {
        submittedReports.first { $0.id == selectedReportID } ?? submittedReports.first
    }

    private var selectedRecordDateString: String {
        formatDate(selectedRecordDate)
    }

    private var selectedDayReports: [SubmittedReportRecord] {
        submittedReports
            .filter { $0.date == selectedRecordDateString }
            .sorted { $0.submittedAt > $1.submittedAt }
    }

    private var selectedDayMemos: [WorkMemoRecord] {
        workMemos
            .filter { isSameRecordDate($0.date) || isSameRecordDate($0.createdAt) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var selectedDayJiraFlowItems: [JiraFlowItem] {
        jiraTeamFlowItems.filter { item in
            isSameRecordDate(item.created) || isSameRecordDate(item.updated) || isSameRecordDate(item.due)
        }
    }

    private var selectedDayOvertimeRecords: [OvertimeRecord] {
        overtimeSummary.records
            .filter { $0.date == selectedRecordDateString }
            .sorted { ($0.startTime ?? $0.createdAt) > ($1.startTime ?? $1.createdAt) }
    }

    private var selectedDayRepositoryWorkItems: [RecordTimelineItem] {
        guard Calendar.current.isDateInToday(selectedRecordDate) else {
            return []
        }
        return repositories.flatMap { repo in
            repo.todayCommitLines.enumerated().map { index, line in
                RecordTimelineItem(
                    id: "repo-\(repo.path)-\(index)",
                    sortKey: "23:\(String(format: "%02d", index))",
                    time: "오늘",
                    title: "\(repo.name) 작업",
                    detail: line,
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    tint: .green
                )
            }
        }
    }

    private var recordTimelineItems: [RecordTimelineItem] {
        let reportItems = selectedDayReports.map { report in
            RecordTimelineItem(
                id: "report-\(report.id)",
                sortKey: report.submittedAt,
                time: compactTimelineTime(report.submittedAt),
                title: report.title,
                detail: report.slackSent ? "앱과 Slack에 제출됨" : "앱 기록으로 제출됨",
                systemImage: "doc.text.fill",
                tint: .blue
            )
        }
        let memoItems = selectedDayMemos.map { memo in
            RecordTimelineItem(
                id: "memo-\(memo.id)",
                sortKey: memo.createdAt,
                time: compactTimelineTime(memo.createdAt),
                title: memo.targetTitle.isEmpty ? memo.targetID : memo.targetTitle,
                detail: memo.text,
                systemImage: "note.text",
                tint: memo.targetType == "jira" ? .purple : .secondary
            )
        }
        let jiraItems = selectedDayJiraFlowItems.map { item in
            RecordTimelineItem(
                id: "jira-\(item.id)",
                sortKey: item.updated.isEmpty ? item.created : item.updated,
                time: compactTimelineTime(item.updated.isEmpty ? item.created : item.updated),
                title: "\(item.key) \(item.status)",
                detail: item.title,
                systemImage: item.isDone ? "checkmark.circle.fill" : "arrow.triangle.branch",
                tint: flowTint(for: item.status)
            )
        }
        let overtimeItems = selectedDayOvertimeRecords.map { record in
            let timeRange = overtimeTimeRange(record) ?? compactTimelineTime(record.createdAt)
            return RecordTimelineItem(
                id: "overtime-\(record.id)",
                sortKey: record.startTime ?? record.createdAt,
                time: timeRange,
                title: "\(overtimeKindLabel(record.effectiveKind ?? record.kind)) \(record.hours)h",
                detail: record.memo.isEmpty ? "연장 근무 기록" : record.memo,
                systemImage: "clock.badge.exclamationmark",
                tint: .orange
            )
        }
        return (reportItems + memoItems + jiraItems + overtimeItems + selectedDayRepositoryWorkItems)
            .sorted { $0.sortKey > $1.sortKey }
    }

    private var currentMonthCalendarDays: [Int] {
        let calendar = Calendar.current
        let now = Date()
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: now),
            let range = calendar.range(of: .day, in: .month, for: now)
        else {
            return []
        }
        let leading = calendar.component(.weekday, from: monthInterval.start) - 1
        return Array(repeating: 0, count: leading) + Array(range)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color.accentColor.opacity(0.08),
                    Color(nsColor: .windowBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            HStack(spacing: 0) {
                WorkSidebarView(
                    selectedSection: $selectedSection,
                    isCollapsed: $isSidebarCollapsed,
                    activeProfileID: runner.activeProfileID,
                    profiles: runner.availableProfiles,
                    repositoryCount: repositories.count,
                    reportReady: !reportDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    onProfileChange: { profileID in
                        runner.switchProfile(to: profileID)
                    }
                )

                Divider()

                VStack(spacing: 0) {
                    compactToolbar

                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            selectedSectionContent
                        }
                        .padding(20)
                    }
                }
            }
        }
        .preferredColorScheme(preferredScheme)
        .frame(minWidth: 980, minHeight: 760)
        .task {
            await initialDataLoad()
            await autoRefreshLoop()
        }
        .task {
            await jiraIssueWatchLoop()
        }
        .task(id: selectedSection) {
            await autoLoadJiraMorningItemsIfNeeded()
        }
        .onChange(of: runner.activeProfileID) { _ in
            reportDraft = ""
            reportNotes = ""
            branchOptionsByPath = [:]
            hasAutoLoadedJiraMorningItems = false
            jiraMorningItems = []
            jiraNewItems = []
            jiraLastUpdatedText = ""
            if selectedSection == "jira" || selectedSection == "briefing" {
                selectedSection = "dashboard"
            }
            hasPreloadedBriefingData = false
            jiraTeamFlowItems = []
            submittedReports = []
            workMemos = []
            isInitialDataLoading = false
            Task {
                await initialDataLoad(notify: true)
            }
        }
        .sheet(item: $notice) { notice in
            WorkNoticeView(notice: notice)
        }
        .sheet(isPresented: $isJiraQuickCreatePresented) {
            JiraQuickCreateSheet(
                summary: $quickJiraSummary,
                description: $quickJiraDescription,
                issueType: $quickJiraIssueType,
                assignee: $quickJiraAssignee,
                priority: $quickJiraPriority,
                dueDate: $quickJiraDueDate,
                labels: $quickJiraLabels,
                isRunning: runner.isRunning,
                onCancel: {
                    isJiraQuickCreatePresented = false
                },
                onCreate: {
                    Task { await createQuickJiraIssue() }
                }
            )
        }
        .alert("변경 파일이 있습니다", isPresented: $showDirtyWarning, presenting: pendingAction) { _ in
            Button("확인", role: .cancel) {}
        } message: { action in
            Text("\(action.repo.name)에 커밋하지 않은 변경 파일이 있습니다. 업데이트나 rebase 전에 commit 또는 stash를 먼저 처리해 주세요.")
        }
    }

    private var compactToolbar: some View {
        HStack(spacing: 8) {
            if isInitialDataLoading {
                HStack(spacing: 7) {
                    ProgressView()
                        .controlSize(.small)
                    Text("초기 데이터 로딩")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.62))
                .clipShape(Capsule())
            }

            Spacer()

            Picker("화면", selection: $appearance) {
                Image(systemName: "circle.lefthalf.filled").tag("system")
                Image(systemName: "sun.max").tag("light")
                Image(systemName: "moon").tag("dark")
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 112)
            .help("화면 모드")

            Button {
                runner.openSetupWindow()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 24)
            }
            .buttonStyle(.borderless)
            .help("설정 열기")
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var selectedSectionContent: some View {
        switch selectedSection {
        case "dashboard", "briefing":
            dashboardSection
        case "work", "jira", "tools":
            workSection
        case "repositories", "workspace":
            VStack(alignment: .leading, spacing: 16) {
                repositoryActions
                repositorySection
            }
        case "report":
            reportSection
        case "records":
            recordsSection
        default:
            dashboardSection
        }
    }

    private var commandCenter: some View {
        CollapsibleDashboardPanel(
            title: runner.isPersonalProfile ? "개인 프로젝트 도우미" : "작업 도우미",
            systemImage: "rectangle.grid.2x2",
            isExpanded: $isCommandCenterExpanded
        ) {
            if runner.isPersonalProfile {
                HStack(alignment: .top, spacing: 12) {
                    personalToolActions
                        .frame(maxWidth: .infinity)
                    aiSection
                        .frame(maxWidth: .infinity)
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    toolActions
                        .frame(maxWidth: .infinity)
                    aiSection
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var workSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            myJiraDashboardPanel
            commandCenter
        }
    }

    private var dashboardSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            DashboardPanel(title: "오늘 개발 상황판", systemImage: "rectangle.grid.2x2") {
                HStack(spacing: 6) {
                    panelActionChip(title: "브리핑", systemImage: "doc.text") {
                        Task {
                            await runDashboardCommand(
                                ["routine", "morning", "--dry-run"],
                                title: "출근 브리핑",
                                running: "출근 브리핑을 만드는 중...",
                                success: "출근 브리핑 완료",
                                failure: "출근 브리핑 실패"
                            )
                            rememberBriefing("출근 브리핑 미리보기 생성")
                        }
                    }
                    .disabled(runner.isRunning)

                    if !runner.isPersonalProfile {
                        panelActionChip(title: "Slack", systemImage: "paperplane.fill") {
                            Task {
                                await runDashboardCommand(
                                    ["routine", "morning", "--send-slack"],
                                    title: "출근 브리핑 공유",
                                    running: "출근 브리핑을 Slack으로 공유하는 중...",
                                    success: "출근 브리핑을 Slack으로 공유했습니다",
                                    failure: "출근 브리핑 공유 실패"
                                )
                                rememberBriefing("출근 브리핑 Slack 공유")
                            }
                        }
                        .disabled(runner.isRunning)
                    }

                    panelActionChip(title: "퇴근", systemImage: "checkmark.seal") {
                        Task {
                            await runDashboardCommand(
                                ["routine", "evening", "--dry-run"],
                                title: "퇴근 전 점검",
                                running: "퇴근 전 점검을 만드는 중...",
                                success: "퇴근 전 점검 완료",
                                failure: "퇴근 전 점검 실패"
                            )
                            rememberBriefing("퇴근 전 점검 미리보기 생성")
                        }
                    }
                    .disabled(runner.isRunning)

                    panelActionChip(title: "작업 시작", systemImage: "arrow.branch") {
                        selectedSection = "work"
                    }
                }
            } content: {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(todayTitle)
                                .font(.title2.weight(.semibold))
                            Text(runner.isPersonalProfile ? "개인 프로젝트 진행 상태" : "오늘 할 일과 저장소 위험 신호")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        HStack(spacing: 8) {
                            codexHealthChip
                            briefingChannelBadge(title: "Slack", systemImage: "paperplane.fill", state: runner.isPersonalProfile ? "숨김" : "전송", tint: .green)
                            briefingChannelBadge(title: "앱 알림", systemImage: "bell.badge", state: "예정", tint: .orange)
                            briefingChannelBadge(title: "앱 내부", systemImage: "rectangle.stack", state: "활성", tint: .blue)
                        }
                    }

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10),
                        ],
                        spacing: 10
                    ) {
                        briefingMetric(title: "해야 할 일", value: "\(jiraMorningItems.count)", systemImage: "checklist", tint: .blue, isAttention: false)
                        briefingMetric(title: "새 Jira", value: "\(jiraNewItems.count)", systemImage: "bell.badge", tint: .orange, isAttention: jiraNewItems.count > 0)
                        briefingMetric(title: "작업 저장소", value: "\(activeRepositoryCount)", systemImage: "folder.badge.gearshape", tint: .green, isAttention: false)
                        briefingMetric(title: "정비 필요", value: "\(pendingRepositoryCount)", systemImage: "arrow.triangle.2.circlepath", tint: .red, isAttention: pendingRepositoryCount > 0)
                    }

                }
            }

            compactTodayWorkPanel

            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 320), spacing: 12, alignment: .top),
                    GridItem(.flexible(minimum: 320), spacing: 12, alignment: .top),
                ],
                alignment: .leading,
                spacing: 12
            ) {
                focusProjectPanel
                briefingMemoryPanel
            }
        }
    }

    private var compactTodayWorkPanel: some View {
        DashboardPanel(title: "오늘 할 일", systemImage: "checklist") {
            HStack(spacing: 6) {
                panelActionChip(title: "작업 화면", systemImage: "arrow.right") {
                    selectedSection = "work"
                }
                if !runner.isPersonalProfile {
                    panelActionChip(title: "새로고침", systemImage: "arrow.clockwise") {
                        Task { await loadJiraMorningItems(notifyLocal: false) }
                    }
                    .disabled(runner.isRunning)
                }
            }
        } content: {
            if runner.isPersonalProfile {
                EmptyDashboardState(systemImage: "checklist", title: "개인 작업 소스 연결 전", message: "개인 프로젝트용 이슈 소스를 붙이면 오늘 할 일이 표시됩니다.")
            } else if jiraMorningItems.isEmpty {
                EmptyDashboardState(systemImage: "checklist", title: "오늘 할 일이 비어 있습니다", message: "앱 실행 시 Jira 일감을 자동으로 가져옵니다.")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(jiraMorningItems.prefix(4)) { item in
                        HStack(spacing: 8) {
                            flowTag(item.key, tint: .blue)
                            Text(item.title.isEmpty ? "제목 없음" : item.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Spacer()
                            jiraMetaChip(item.statusText, tint: flowTint(for: item.statusText))
                        }
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor).opacity(0.48))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    private func briefingMetric(title: String, value: String, systemImage: String, tint: Color, isAttention: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint.opacity(isAttention ? 0.95 : 0.72))
                Spacer()
            }
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(isAttention ? 0.12 : 0.07))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isAttention ? tint.opacity(0.34) : Color(nsColor: .separatorColor).opacity(0.35))
        )
    }

    private func briefingChannelBadge(title: String, systemImage: String, state: String, tint: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
            Text(title)
                .font(.caption.weight(.semibold))
            Text(state)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(tint.opacity(0.09))
        .foregroundStyle(tint.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.18))
        )
    }

    private var codexHealthChip: some View {
        Button {
            Task { await loadCodexHealth() }
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(codexHealth.isAvailable ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                Text("Codex")
                    .font(.caption.weight(.semibold))
                Text(codexHealth.authMethod)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background((codexHealth.isAvailable ? Color.green : Color.orange).opacity(0.09))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke((codexHealth.isAvailable ? Color.green : Color.orange).opacity(0.20))
            )
        }
        .buttonStyle(.plain)
        .help("Codex 상태: \(codexHealth.version) · \(codexHealth.authMethod)\n\(codexHealth.executablePath)")
    }

    private func compactBriefingButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func panelActionChip(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var myJiraDashboardPanel: some View {
        DashboardPanel(title: "내 Jira 업무", systemImage: "checklist") {
            HStack(spacing: 6) {
                panelActionChip(title: "새로고침", systemImage: "arrow.clockwise") {
                    Task { await loadJiraMorningItems(notifyLocal: false) }
                }
                .disabled(runner.isRunning || runner.isPersonalProfile)

                if !runner.isPersonalProfile {
                    panelActionChip(title: "일감", systemImage: "plus.app") {
                        isJiraQuickCreatePresented = true
                    }
                    .disabled(runner.isRunning)
                }
            }
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                if runner.isPersonalProfile {
                    EmptyDashboardState(systemImage: "checklist", title: "개인 할 일 연결 전", message: "개인 프로젝트용 이슈 소스를 붙이면 이곳에 표시합니다.")
                } else if jiraMorningItems.isEmpty {
                    EmptyDashboardState(systemImage: "checklist", title: "Jira 일감 없음", message: "앱 실행 시 내게 할당된 Jira 업무를 자동으로 가져옵니다.")
                } else {
                    HStack(spacing: 8) {
                        flowTag("전체 \(jiraMorningItems.count)", tint: .blue)
                        flowTag("높은 우선순위 \(jiraMorningItems.filter { $0.priorityText.contains("High") || $0.priorityText.contains("높") }.count)", tint: .orange)
                        flowTag("마감 있음 \(jiraMorningItems.filter { $0.dueText != "-" }.count)", tint: .red)
                        Spacer()
                    }

                    issueStartFlowPanel
                    jiraIssueDetailPanel

                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(jiraMorningItems.prefix(12)) { item in
                                myJiraWorkCard(item)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(minHeight: 260, maxHeight: 520)
                }

            }
        }
    }

    private var issueStartFlowPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label("작업 시작 플로우", systemImage: "arrow.branch")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let item = selectedWorkIssue {
                    Button {
                        Task { await startFullIssueFlow(item) }
                    } label: {
                        Label("이 일감 시작", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(runner.isRunning)
                }
            }

            HStack(spacing: 8) {
                ForEach(jiraMorningItems.prefix(8)) { item in
                    Button {
                        selectedWorkIssueKey = item.key
                    } label: {
                        Text(item.key)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(selectedWorkIssue?.key == item.key ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor).opacity(0.72))
                            .foregroundStyle(selectedWorkIssue?.key == item.key ? Color.accentColor : Color.primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }

            if let item = selectedWorkIssue {
                HStack(spacing: 7) {
                    startFlowStep("1", "일감 선택", isActive: true)
                    startFlowConnector
                    startFlowStep("2", "저장소 연결", isActive: true)
                    startFlowConnector
                    startFlowStep("3", "브랜치 생성", isActive: true)
                    startFlowConnector
                    startFlowStep("4", "Codex 요청", isActive: true)
                    Spacer(minLength: 0)
                    Text(item.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.46))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear {
            if selectedWorkIssueKey.isEmpty {
                selectedWorkIssueKey = jiraMorningItems.first?.key ?? ""
            }
            Task { await loadSelectedIssueDetailIfNeeded(force: false) }
        }
        .onChange(of: selectedWorkIssueKey) { _ in
            Task { await loadSelectedIssueDetailIfNeeded(force: true) }
        }
    }

    private var jiraIssueDetailPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("기획 자료", systemImage: "rectangle.and.text.magnifyingglass")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if isLoadingIssueDetail {
                    ProgressView()
                        .controlSize(.small)
                }
                Button {
                    Task { await loadSelectedIssueDetailIfNeeded(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(isLoadingIssueDetail || selectedWorkIssueKey.isEmpty)
                .help("Jira 상세 새로고침")
                if !selectedIssueDetail.url.isEmpty {
                    Button {
                        runner.openExternalURL(selectedIssueDetail.url)
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .buttonStyle(.borderless)
                    .help("Jira에서 열기")
                }
            }

            if selectedWorkIssueKey.isEmpty {
                EmptyDashboardState(systemImage: "checklist", title: "선택된 일감 없음", message: "일감을 선택하면 기획 본문, 댓글, 첨부를 보여줍니다.")
            } else if selectedIssueDetail.key.isEmpty && !isLoadingIssueDetail {
                EmptyDashboardState(systemImage: "doc.text.magnifyingglass", title: "상세 정보 대기", message: "새로고침을 누르면 Jira 상세와 첨부 목록을 불러옵니다.")
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 7) {
                        flowTag(selectedIssueDetail.status.isEmpty ? "상태 -" : selectedIssueDetail.status, tint: flowTint(for: selectedIssueDetail.status))
                        flowTag(selectedIssueDetail.priority.isEmpty ? "우선순위 -" : selectedIssueDetail.priority, tint: .orange)
                        flowTag(selectedIssueDetail.assignee.isEmpty ? "담당 -" : selectedIssueDetail.assignee, tint: .blue)
                        Spacer(minLength: 0)
                    }

                    Text(selectedIssueDetail.description.isEmpty ? "기획 본문이 비어 있습니다." : selectedIssueDetail.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(5)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !selectedIssueDetail.attachments.isEmpty {
                        jiraAttachmentList
                    }

                    if !selectedIssueDetail.comments.isEmpty {
                        jiraCommentList
                    }
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var jiraAttachmentList: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("첨부 \(selectedIssueDetail.attachments.count)개")
                .font(.caption.weight(.semibold))
            ForEach(selectedIssueDetail.attachments.prefix(6)) { item in
                HStack(spacing: 8) {
                    Image(systemName: item.mimeType.hasPrefix("image/") ? "photo" : "paperclip")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.filename.isEmpty ? "첨부 파일" : item.filename)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text([item.mimeType, formattedFileSize(item.size), item.author].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button("열기") {
                        runner.openExternalURL(item.contentURL)
                    }
                    .disabled(item.contentURL.isEmpty)
                    .controlSize(.small)
                }
                .padding(7)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.46))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var jiraCommentList: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("최근 댓글")
                .font(.caption.weight(.semibold))
            ForEach(selectedIssueDetail.comments.prefix(3)) { item in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(item.author.isEmpty ? "작성자 -" : item.author)
                            .font(.caption2.weight(.semibold))
                        Text(item.updated.isEmpty ? item.created : item.updated)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text(item.body)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
                .padding(7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.46))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var selectedWorkIssue: JiraListItem? {
        if let selected = jiraMorningItems.first(where: { $0.key == selectedWorkIssueKey }) {
            return selected
        }
        return jiraMorningItems.first
    }

    private var startFlowConnector: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.5))
            .frame(width: 18, height: 1)
    }

    private func startFlowStep(_ number: String, _ title: String, isActive: Bool) -> some View {
        HStack(spacing: 5) {
            Text(number)
                .font(.caption2.weight(.bold))
                .frame(width: 17, height: 17)
                .background(isActive ? Color.accentColor.opacity(0.16) : Color(nsColor: .controlBackgroundColor))
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .clipShape(Circle())
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
        }
    }

    private func myJiraWorkCard(_ item: JiraListItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                flowTag(item.key, tint: .blue)
                flowTag("태그 \(item.key)", tint: .purple)
                jiraMetaChip(item.statusText, tint: flowTint(for: item.statusText))
                if item.priorityText != "-" {
                    jiraMetaChip(item.priorityText, tint: item.priorityText.contains("High") || item.priorityText.contains("높") ? .orange : .secondary)
                }
                Spacer(minLength: 8)
                if item.dueText != "-" {
                    Label(item.dueText, systemImage: "calendar")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.red.opacity(0.82))
                        .lineLimit(1)
                }
            }

            Text(item.title.isEmpty ? "제목 없음" : item.title)
                .font(.headline)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !item.bodyText.isEmpty {
                Text(item.bodyText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                jiraInfoPill("담당", item.assigneeText)
                jiraInfoPill("등록", item.createdText)
                jiraInfoPill("갱신", item.updatedText)
                Spacer(minLength: 0)
            }

            Divider()
                .opacity(0.58)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    issueActionButton("연결/태그", systemImage: "link.badge.plus") {
                        runner.openIssueRepositoryLinkWindow(issue: item.key, summary: item.title)
                    }
                    issueActionButton("이 일감 시작", systemImage: "play.fill") {
                        Task { await startFullIssueFlow(item) }
                    }
                    issueActionButton("추적", systemImage: "point.3.connected.trianglepath.dotted") {
                        Task { await traceIssueWork(item) }
                    }
                    issueActionButton("추천", systemImage: "sparkles") {
                        Task { await recommendIssueRepository(item) }
                    }
                    issueActionButton("Codex", systemImage: "sparkles.rectangle.stack") {
                        Task { await openCodexWorkspace(item) }
                    }
                    if let link = item.link, !link.isEmpty {
                        issueActionButton("Jira", systemImage: "arrow.up.right.square") {
                            runner.openExternalURL(link)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.40))
        )
        .contentShape(Rectangle())
    }

    private func issueActionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.70))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color(nsColor: .separatorColor).opacity(0.30))
                )
        }
        .buttonStyle(.plain)
        .disabled(runner.isRunning)
    }

    private func jiraMetaChip(_ text: String, tint: Color) -> some View {
        Text(text.isEmpty ? "-" : text)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(tint.opacity(0.10))
            .foregroundStyle(tint.opacity(0.92))
            .clipShape(Capsule())
    }

    private func jiraInfoPill(_ title: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "-" : value)
                .foregroundStyle(.primary.opacity(0.78))
                .lineLimit(1)
        }
        .font(.caption2)
    }

    private var teamFlowPanel: some View {
        DashboardPanel(title: "팀 Jira 흐름", systemImage: "arrow.triangle.branch") {
            panelActionChip(title: "새로고침", systemImage: "arrow.clockwise") {
                Task { await loadJiraTeamFlow() }
            }
            .disabled(runner.isRunning)
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                if jiraTeamFlowItems.isEmpty {
                    EmptyDashboardState(systemImage: "arrow.triangle.branch", title: "팀 흐름을 불러오는 중입니다", message: "앱 실행 시 최근 7일 기준 Jira 담당/처리 흐름을 자동으로 조회합니다.")
                } else {
                    let grouped = Dictionary(grouping: jiraTeamFlowItems, by: \.status)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            flowFilterButton(title: "전체 \(jiraTeamFlowItems.count)", value: "all", tint: .primary.opacity(0.8))
                            flowFilterButton(title: "완료 \(jiraTeamFlowItems.filter(\.isDone).count)", value: "done", tint: .green)
                            flowFilterButton(title: "진행 \(jiraTeamFlowItems.filter { !$0.isDone }.count)", value: "open", tint: .orange)
                            ForEach(grouped.keys.sorted(), id: \.self) { status in
                                flowFilterButton(title: "\(status) \(grouped[status]?.count ?? 0)", value: status, tint: flowTint(for: status))
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(filteredJiraTeamFlowItems.prefix(6)) { item in
                            Button {
                                if !item.link.isEmpty {
                                    runner.openExternalURL(item.link)
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    flowTag(item.key, tint: .blue)
                                    Text(item.title.isEmpty ? "제목 없음" : item.title)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                    fixedFlowTag(item.status, tint: flowTint(for: item.status), width: 84)
                                    Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(item.isDone ? Color.green.opacity(0.72) : Color.secondary)
                                }
                                .padding(8)
                                .background(Color(nsColor: .textBackgroundColor).opacity(0.44))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

            }
        }
    }

    private func teamFlowRow(_ item: JiraFlowItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    flowTag(item.key, tint: .blue)
                    flowTag(item.issueType, tint: .secondary)
                    Text(item.project)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(item.title.isEmpty ? "제목 없음" : item.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.link.isEmpty ? "Jira 링크 없음" : item.link)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                fixedFlowTag(item.status, tint: flowTint(for: item.status), width: 104)
                Text(item.isDone ? "처리 완료" : "진행 확인")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(item.isDone ? Color.green.opacity(0.82) : Color.orange.opacity(0.82))
            }
            .frame(width: 116, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                personFlowLine(title: "등록", name: item.reporter, tint: .purple)
                personFlowLine(title: "담당", name: item.assignee, tint: .blue)
            }
            .frame(width: 188, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text("등록 \(item.created)")
                Text("갱신 \(item.updated)")
                if item.due != "-" {
                    Text("마감 \(item.due)")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(width: 120, alignment: .leading)

            Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.secondary)
                .frame(width: 34, alignment: .trailing)
        }
        .padding(10)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.56))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.42))
        )
    }

    private func personFlowLine(title: String, name: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .leading)
            fixedFlowTag(name, tint: tint, width: 136)
        }
    }

    private func flowTag(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(tint.opacity(0.10))
            .foregroundStyle(tint.opacity(0.9))
            .clipShape(Capsule())
    }

    private func fixedFlowTag(_ text: String, tint: Color, width: CGFloat) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: width)
            .padding(.vertical, 4)
            .background(tint.opacity(0.10))
            .foregroundStyle(tint.opacity(0.9))
            .clipShape(Capsule())
    }

    private func flowFilterButton(title: String, value: String, tint: Color) -> some View {
        Button {
            teamFlowStatusFilter = value
        } label: {
            Text(title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(teamFlowStatusFilter == value ? tint.opacity(0.18) : tint.opacity(0.08))
                .foregroundStyle(tint.opacity(0.92))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(teamFlowStatusFilter == value ? tint.opacity(0.44) : Color(nsColor: .separatorColor).opacity(0.26), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func flowTint(for status: String) -> Color {
        let value = status.lowercased()
        if value.contains("done") || value.contains("complete") || value.contains("완료") || value.contains("배포") {
            return .green
        }
        if value.contains("progress") || value.contains("진행") || value.contains("작업") || value.contains("리뷰") {
            return .blue
        }
        if value.contains("backlog") || value.contains("todo") || value.contains("할 일") {
            return .secondary
        }
        return .orange
    }

    private var focusProjectPanel: some View {
        DashboardPanel(title: "주 프로젝트", systemImage: "scope") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("오늘 집중할 프로젝트", text: $briefingFocusProject)
                    .textFieldStyle(.roundedBorder)

                if repositories.isEmpty {
                    EmptyDashboardState(systemImage: "folder", title: "저장소 정보 없음", message: "워크스페이스를 불러오면 주요 프로젝트 후보가 표시됩니다.")
                } else {
                    ForEach(repositories.prefix(4)) { repo in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(repo.needsUpdate ? Color.orange : Color.green)
                                .frame(width: 7, height: 7)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(repo.name)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Text(repo.branch)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private var yesterdayMemoPanel: some View {
        DashboardPanel(title: "어제 메모", systemImage: "note.text") {
            panelActionChip(title: "반영", systemImage: "arrow.down.doc") {
                reportNotes = briefingYesterdayMemo
                rememberBriefing("어제 메모를 보고서 메모로 반영")
                selectedSection = "report"
            }
            .disabled(briefingYesterdayMemo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $briefingYesterdayMemo)
                    .font(.system(.body, design: .default))
                    .frame(minHeight: 120)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.75))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.65))
                    )

            }
        }
    }

    private var briefingMemoryPanel: some View {
        DashboardPanel(title: "브리핑 기억", systemImage: "clock.arrow.circlepath") {
            VStack(alignment: .leading, spacing: 10) {
                if recentBriefingMemories.isEmpty {
                    EmptyDashboardState(systemImage: "clock.arrow.circlepath", title: "아직 저장된 기억이 없습니다", message: "브리핑 보기, 보고서 생성, 메모 반영 같은 흐름을 이곳에 쌓아갑니다.")
                } else {
                    ForEach(recentBriefingMemories, id: \.self) { item in
                        Text(item)
                            .font(.caption)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var calendarBriefingPanel: some View {
        DashboardPanel(title: "달력", systemImage: "calendar") {
            VStack(alignment: .leading, spacing: 10) {
                briefingLine(title: "오늘", value: todayTitle)
                briefingLine(title: "Jira 마감", value: jiraMorningItems.filter { $0.detail.contains("마감:") && !$0.detail.contains("마감: -") }.isEmpty ? "표시할 마감 없음" : "해야 할 일에 표시")
                briefingLine(title: "기억", value: recentBriefingMemories.isEmpty ? "기록 없음" : "\(recentBriefingMemories.count)개")
                Text("다음 단계에서 캘린더 소스와 브리핑 기록을 날짜별 타임라인으로 연결합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var weeklyBriefingPanel: some View {
        DashboardPanel(title: "이번 주", systemImage: "calendar") {
            panelActionChip(title: "흐름", systemImage: "point.topleft.down.curvedto.point.bottomright.up") {
                Task { await showTodayActivity() }
            }
            .disabled(runner.isRunning)
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                briefingLine(title: "작업 흐름", value: "\(activeRepositoryCount)개 저장소에서 움직임")
                briefingLine(title: "정비", value: pendingRepositoryCount == 0 ? "정비 필요 없음" : "\(pendingRepositoryCount)개 확인 필요")
                briefingLine(title: "보고", value: reportDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "초안 없음" : "초안 작성됨")
            }
        }
    }

    private var monthlyBriefingPanel: some View {
        DashboardPanel(title: "이번 달", systemImage: "calendar.badge.clock") {
            HStack(spacing: 6) {
                panelActionChip(title: "초안", systemImage: "doc.badge.gearshape") {
                    selectedSection = "report"
                    if reportDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Task {
                            reportDraft = await runner.previewDailyReport(notes: briefingYesterdayMemo)
                            lastMessage = reportDraft
                            showNotice(title: "오늘 한 일 초안", message: reportDraft, succeeded: !reportDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            rememberBriefing("오늘 한 일 초안 생성")
                        }
                    }
                }
                .disabled(runner.isRunning)

                if !runner.isPersonalProfile {
                    panelActionChip(title: "공유", systemImage: "paperplane.fill") {
                        Task {
                            lastMessage = await runner.sendEditedReport(reportDraft)
                            showNotice(title: "보고서 공유", message: lastMessage, succeeded: !runner.status.contains("실패"))
                            rememberBriefing("보고서 Slack 공유")
                        }
                    }
                    .disabled(runner.isRunning || reportDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                briefingLine(title: "월간 회고", value: "초안 생성 준비")
                briefingLine(title: "주요 기록", value: "오늘 한 일 보고서와 메모 기반")
                briefingLine(title: "알림 채널", value: runner.isPersonalProfile ? "앱 내부 중심" : "Slack + 앱 내부")
            }
        }
    }

    private func briefingLine(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
    }

    private var jiraSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            DashboardPanel(title: "Jira 일감", systemImage: "checklist") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        DashboardButton(title: "아침 일감 새로고침", systemImage: "arrow.clockwise") {
                            Task { await loadJiraMorningItems(notifyLocal: true) }
                        }
                        .disabled(runner.isRunning)

                        DashboardButton(title: "새 일감 확인", systemImage: "bell.badge") {
                            Task { await checkNewJiraIssues(showEmptyResult: true) }
                        }
                        .disabled(runner.isRunning)

                        Spacer()
                    }

                    HStack(spacing: 8) {
                        Label("Slack 전송 없이 앱 안에서 일감을 확인합니다.", systemImage: "rectangle.stack")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if !jiraLastUpdatedText.isEmpty {
                            Text(jiraLastUpdatedText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            jiraListPanel(
                title: "내 아침 일감",
                systemImage: "sun.max",
                items: jiraMorningItems,
                emptyTitle: "아직 불러온 Jira 일감이 없습니다",
                emptyMessage: runner.isRunning ? "Jira 일감을 자동으로 불러오는 중입니다." : "Jira 메뉴에 들어오면 내게 할당된 미처리 일감이 자동으로 표시됩니다."
            )

            jiraListPanel(
                title: "새로 등록된 일감",
                systemImage: "bell.badge",
                items: jiraNewItems,
                emptyTitle: "새로 감지된 Jira 일감이 없습니다",
                emptyMessage: "업무 프로필에서는 5분마다 새 일감을 확인하고, 발견되면 이 목록과 macOS 알림에 함께 표시합니다."
            )
        }
    }

    private func jiraListPanel(
        title: String,
        systemImage: String,
        items: [JiraListItem],
        emptyTitle: String,
        emptyMessage: String
    ) -> some View {
        DashboardPanel(title: title, systemImage: systemImage) {
            VStack(alignment: .leading, spacing: 10) {
                if items.isEmpty {
                    EmptyDashboardState(systemImage: systemImage, title: emptyTitle, message: emptyMessage)
                } else {
                    ForEach(items) { item in
                        JiraIssueRow(item: item) {
                            if let link = item.link, !link.isEmpty {
                                runner.openExternalURL(link)
                            }
                        }
                    }
                }
            }
        }
    }

    private var repositoryActions: some View {
        DashboardPanel(title: "저장소 상태 도구", systemImage: "arrow.triangle.2.circlepath") {
            HStack(spacing: 10) {
                DashboardButton(title: isLoading ? "확인 중" : "상태 동기화", systemImage: "arrow.clockwise") {
                    Task { await reload(notify: true, fetchRemote: true) }
                }
                .disabled(isLoading || runner.isRunning)

                Spacer()
            }
        }
    }

    private var personalToolActions: some View {
        CommandGroup(title: "개인 프로젝트", subtitle: "Git 중심 점검", systemImage: "person.crop.circle") {
            VStack(spacing: 8) {
                DashboardButton(title: "오늘 흐름", systemImage: "point.topleft.down.curvedto.point.bottomright.up") {
                    Task { await showTodayActivity() }
                }
                .disabled(runner.isRunning)

                DashboardButton(title: "PR 상태", systemImage: "arrow.triangle.pull") {
                    Task {
                        await runDashboardCommand(
                            ["dev", "pr-status"],
                            title: "PR 상태",
                            running: "열린 PR 상태를 확인하는 중...",
                            success: "PR 상태 확인 완료",
                            failure: "PR 상태 확인 실패"
                        )
                    }
                }
                .disabled(runner.isRunning)

                DashboardButton(title: "CI 실패", systemImage: "xmark.seal") {
                    Task {
                        await runDashboardCommand(
                            ["dev", "ci-alerts"],
                            title: "CI 실패",
                            running: "최근 CI 실패를 확인하는 중...",
                            success: "CI 실패 확인 완료",
                            failure: "CI 실패 확인 실패"
                        )
                    }
                }
                .disabled(runner.isRunning)
            }
        }
    }

    private var toolActions: some View {
        CommandGroup(title: "루틴", subtitle: "점검과 연결 확인", systemImage: "checklist.checked") {
            VStack(spacing: 8) {
                DashboardButton(title: "퇴근 전 점검", systemImage: "checkmark.seal") {
                    Task {
                        await runDashboardCommand(
                            ["routine", "evening", "--dry-run"],
                            title: "퇴근 전 점검",
                            running: "퇴근 전 점검을 만드는 중...",
                            success: "퇴근 전 점검 미리보기 완료",
                            failure: "퇴근 전 점검 실패"
                        )
                    }
                }
                .disabled(runner.isRunning)

                DashboardButton(title: "Jira 키 점검", systemImage: "number.square") {
                    Task {
                        await runDashboardCommand(
                            ["dev", "audit-jira-keys"],
                            title: "Jira 키 점검",
                            running: "Jira 키 누락을 검사하는 중...",
                            success: "Jira 키 점검 완료",
                            failure: "Jira 키 점검 실패"
                        )
                    }
                }
                .disabled(runner.isRunning)

                DashboardButton(title: "연결 목록", systemImage: "link") {
                    Task {
                        let output = await runner.loadIssueRepositoryLinks()
                        lastMessage = output
                        showNotice(title: "일감-저장소 연결", message: output, succeeded: !runner.status.contains("실패"))
                    }
                }
                .disabled(runner.isRunning)

                DashboardButton(title: "오늘 흐름", systemImage: "point.topleft.down.curvedto.point.bottomright.up") {
                    Task { await showTodayActivity() }
                }
                .disabled(runner.isRunning)

                DashboardButton(title: "PR 상태", systemImage: "arrow.triangle.pull") {
                    Task {
                        await runDashboardCommand(
                            ["dev", "pr-status"],
                            title: "PR 상태",
                            running: "열린 PR 상태를 확인하는 중...",
                            success: "PR 상태 확인 완료",
                            failure: "PR 상태 확인 실패"
                        )
                    }
                }
                .disabled(runner.isRunning)

                DashboardButton(title: "리뷰 요청", systemImage: "person.2.badge.gearshape") {
                    Task {
                        await runDashboardCommand(
                            ["dev", "review-alerts"],
                            title: "리뷰 요청",
                            running: "리뷰 요청 PR을 확인하는 중...",
                            success: "리뷰 요청 확인 완료",
                            failure: "리뷰 요청 확인 실패"
                        )
                    }
                }
                .disabled(runner.isRunning)

                DashboardButton(title: "CI 실패", systemImage: "xmark.seal") {
                    Task {
                        await runDashboardCommand(
                            ["dev", "ci-alerts"],
                            title: "CI 실패",
                            running: "최근 CI 실패를 확인하는 중...",
                            success: "CI 실패 확인 완료",
                            failure: "CI 실패 확인 실패"
                        )
                    }
                }
                .disabled(runner.isRunning)

                DashboardButton(title: "배포 대기", systemImage: "shippingbox") {
                    Task {
                        await runDashboardCommand(
                            ["jira", "deploy-waiting"],
                            title: "배포 대기 Jira",
                            running: "배포 대기 Jira 일감을 확인하는 중...",
                            success: "배포 대기 Jira 확인 완료",
                            failure: "배포 대기 Jira 확인 실패"
                        )
                    }
                }
                .disabled(runner.isRunning)
            }
        }
    }

    private var repositorySection: some View {
        DashboardPanel(title: "저장소", systemImage: "point.3.connected.trianglepath.dotted") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Picker("필터", selection: $filter) {
                        Text("전체").tag("all")
                        Text("정비 필요").tag("needsUpdate")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)

                    Spacer()

                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                        Text("상태를 확인하는 중")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(filteredRepositories.count)개 표시")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if repositories.isEmpty {
                    EmptyDashboardState(
                        systemImage: "folder.badge.questionmark",
                        title: "관리 대상 저장소가 없습니다",
                        message: "설정에서 GitHub 후보를 불러온 뒤 관리할 저장소를 가져와 주세요."
                    )
                } else if filteredRepositories.isEmpty {
                    EmptyDashboardState(
                        systemImage: "line.3.horizontal.decrease.circle",
                        title: "현재 필터에 해당하는 저장소가 없습니다",
                        message: "다른 필터를 선택하거나 상태를 새로고침해 주세요."
                    )
                } else {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 12, alignment: .top),
                            GridItem(.flexible(), spacing: 12, alignment: .top),
                        ],
                        alignment: .leading,
                        spacing: 12
                    ) {
                        ForEach(filteredRepositories) { repo in
                            RepositoryDashboardRow(
                                repo: repo,
                                branches: branchOptionsByPath[repo.path] ?? [],
                                isSelected: selectedPath == repo.path,
                                isRunning: runner.isRunning,
                                onSelect: {
                                    selectedPath = repo.path
                                },
                                onCheckout: { branch in
                                    Task { await checkout(repo, branch: branch) }
                                },
                                onOpenIDE: {
                                    openIDE(repo)
                                },
                                onOpenCodex: {
                                    runner.openRepoCodexTaskWindow(repo: repo)
                                },
                                visibleCommitRows: workCommitPreviewRows
                            )
                            .opacity(draggingRepositoryPath == repo.path ? 0.58 : 1)
                            .onDrag {
                                draggingRepositoryPath = repo.path
                                return NSItemProvider(object: repo.path as NSString)
                            }
                            .onDrop(
                                of: [UTType.text],
                                delegate: RepositoryDropDelegate(
                                    targetPath: repo.path,
                                    draggingPath: $draggingRepositoryPath,
                                    move: moveRepository
                                )
                            )
                        }
                    }
                }
            }
        }
    }

    private var reportSection: some View {
        DashboardPanel(title: "보고서", systemImage: "doc.text") {
            HStack(spacing: 6) {
                panelActionChip(title: "초안", systemImage: "doc.badge.gearshape") {
                    Task {
                        reportDraft = await runner.previewDailyReport(notes: reportNotes)
                        reportWasRefined = false
                        lastMessage = reportDraft
                        showNotice(title: "오늘 한 일 초안", message: reportDraft, succeeded: !reportDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .disabled(runner.isRunning)

                panelActionChip(title: "ChatGPT", systemImage: "bubble.left.and.text.bubble.right") {
                    reportDraft = runner.makeChatGPTReportPrompt(draft: reportDraft, notes: reportNotes)
                    lastMessage = reportDraft
                    showNotice(title: "ChatGPT 전달용 프롬프트", message: reportDraft, succeeded: true)
                }
                .disabled(runner.isRunning)

                panelActionChip(title: "Codex", systemImage: "sparkles") {
                    Task { await refineReportWithCodex() }
                }
                .disabled(runner.isRunning)

                panelActionChip(title: "AI규칙", systemImage: "doc.plaintext") {
                    runner.openReportAgentEditor()
                }
                .disabled(runner.isRunning)

                if !runner.isPersonalProfile {
                    panelActionChip(title: "공유", systemImage: "paperplane.fill") {
                        Task {
                            lastMessage = await runner.sendEditedReport(reportDraft)
                            showNotice(title: "보고서 공유", message: lastMessage, succeeded: !runner.status.contains("실패"))
                        }
                    }
                    .disabled(runner.isRunning || reportDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                panelActionChip(title: "제출", systemImage: "tray.and.arrow.up.fill") {
                    Task { await submitReport() }
                }
                .disabled(runner.isRunning || reportDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                reportFlowStrip
                reportEvidenceStrip

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("수동 메모")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if !briefingYesterdayMemo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Button("어제 메모 반영") {
                                    reportNotes = [reportNotes, briefingYesterdayMemo]
                                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                        .filter { !$0.isEmpty }
                                        .joined(separator: "\n\n")
                                    rememberBriefing("어제 메모를 보고서 메모로 반영")
                                }
                                .font(.caption2)
                                .buttonStyle(.plain)
                            }
                        }
                        TextEditor(text: $reportNotes)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 130)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(Color(nsColor: .textBackgroundColor).opacity(0.72))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(nsColor: .separatorColor).opacity(0.65))
                            )
                    }
                    .frame(maxWidth: 340)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("보고서 초안")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if !lastSubmittedReportID.isEmpty {
                                Text("최근 제출 \(lastSubmittedReportID)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        TextEditor(text: $reportDraft)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 130)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(Color(nsColor: .textBackgroundColor).opacity(0.86))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(nsColor: .separatorColor).opacity(0.8))
                            )
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var reportFlowStrip: some View {
        HStack(spacing: 8) {
            reportStepPill("1", "초안 생성", isReady: !reportDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            startFlowConnector
            reportStepPill("2", "Codex 다듬기", isReady: reportWasRefined)
            startFlowConnector
            reportStepPill("3", runner.isPersonalProfile ? "앱 기록" : "앱 + Slack 제출", isReady: !lastSubmittedReportID.isEmpty)
            Spacer()
            Text("제출하면 기록 화면의 보고서 탭에 자동으로 쌓입니다.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(9)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var reportEvidenceStrip: some View {
        HStack(spacing: 8) {
            reportEvidenceBox(title: "오늘 작업", value: "\(todayWorkCountForReport)", detail: "커밋/머지 근거", systemImage: "clock")
            reportEvidenceBox(title: "Jira", value: "\(jiraMorningItems.count)", detail: "오늘 할 일", systemImage: "checklist")
            reportEvidenceBox(title: "메모", value: "\(reportNoteLineCount)", detail: reportNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "수동 메모 없음" : "수동 메모 반영", systemImage: "note.text")
            reportEvidenceBox(title: "기록", value: "\(submittedReports.count)", detail: lastSubmittedReportID.isEmpty ? "최근 제출 대기" : "방금 제출됨", systemImage: "tray")
        }
    }

    private func reportEvidenceBox(title: String, value: String, detail: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack(spacing: 5) {
                    Text(value)
                        .font(.caption.weight(.semibold))
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.36))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var todayWorkCountForReport: Int {
        repositories.reduce(0) { $0 + $1.todayCommitCount }
    }

    private var reportNoteLineCount: Int {
        reportNotes
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count
    }

    private func reportStepPill(_ number: String, _ title: String, isReady: Bool) -> some View {
        HStack(spacing: 5) {
            Text(number)
                .font(.caption2.weight(.bold))
                .frame(width: 17, height: 17)
                .background((isReady ? Color.green : Color.accentColor).opacity(0.14))
                .foregroundStyle(isReady ? Color.green : Color.accentColor)
                .clipShape(Circle())
            Text(title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
    }

    private var recordsSection: some View {
        DashboardPanel(title: "기록", systemImage: "calendar") {
            panelActionChip(title: "새로고침", systemImage: "arrow.clockwise") {
                    Task { await loadRecords() }
            }
            .disabled(runner.isRunning)
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                Text("보고서, 메모, Jira 흐름, 연장근무를 날짜별 작업 기록으로 모아 확인합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(alignment: .top, spacing: 14) {
                    reportCalendarGrid
                        .frame(width: 300)

                    VStack(alignment: .leading, spacing: 12) {
                        Picker("기록", selection: $recordsViewMode) {
                            Text("타임라인").tag("timeline")
                            Text("보고서").tag("reports")
                            Text("메모").tag("memos")
                            Text("Jira 흐름").tag("jira")
                            Text("연장 근무").tag("overtime")
                        }
                        .pickerStyle(.segmented)

                        recordsDetailContent
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .task {
                if submittedReports.isEmpty && workMemos.isEmpty {
                    await loadRecords()
                }
            }
        }
    }

    @ViewBuilder
    private var recordsDetailContent: some View {
        switch recordsViewMode {
        case "timeline":
            recordsTimelineView
        case "memos":
            workMemoList
        case "jira":
            teamFlowPanel
        case "overtime":
            overtimePanel
        default:
            selectedReportDetail
        }
    }

    private var reportCalendarGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(Date().formatted(.dateTime.year().month(.wide)))
                    .font(.headline)
                Spacer()
                Text(formatKoreanDate(selectedRecordDate))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(["일", "월", "화", "수", "목", "금", "토"], id: \.self) { day in
                    Text(day)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                ForEach(currentMonthCalendarDays, id: \.self) { day in
                    let reports = reports(on: day)
                    Button {
                        if let date = currentMonthDate(day: day) {
                            selectedRecordDate = date
                        }
                        if let first = reports.first {
                            selectedReportID = first.id
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text(day == 0 ? "" : "\(day)")
                                .font(.caption.weight(.semibold))
                            if !reports.isEmpty {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 5, height: 5)
                            } else {
                                Circle()
                                    .fill(Color.clear)
                                    .frame(width: 5, height: 5)
                            }
                        }
                        .frame(height: 38)
                        .frame(maxWidth: .infinity)
                        .background(calendarDayBackground(day: day, reports: reports))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(day == 0)
                    .help(calendarDayHelp(day: day, reports: reports))
                }
            }

            RecordDaySummaryStrip(
                reportCount: selectedDayReports.count,
                memoCount: selectedDayMemos.count,
                jiraCount: selectedDayJiraFlowItems.count,
                overtimeCount: selectedDayOvertimeRecords.count
            )

            if !submittedReports.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("최근 제출")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(submittedReports.prefix(8)) { report in
                        Button {
                            selectedReportID = report.id
                            if let date = parseDate(report.date) {
                                selectedRecordDate = date
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Text(report.date)
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Text(report.title)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Spacer()
                                if report.slackSent {
                                    Image(systemName: "paperplane.fill")
                                        .font(.caption2)
                                        .foregroundStyle(Color.green)
                                }
                            }
                            .padding(8)
                            .background(selectedReportID == report.id ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor).opacity(0.62))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.42))
        )
    }

    private var recordsTimelineView: some View {
        RecordsTimelineView(selectedDate: $selectedRecordDate, items: recordTimelineItems)
    }

    private var selectedReportDetail: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let report = selectedReport {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(report.title)
                            .font(.headline)
                            .lineLimit(2)
                        Text("\(report.date) · \(report.slackSent ? "앱 + Slack 제출" : "앱 기록")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        reportDraft = report.text
                        reportNotes = report.notes
                        selectedSection = "report"
                    } label: {
                        Label("다시 열기", systemImage: "arrow.uturn.left")
                    }
                    .buttonStyle(.bordered)
                }

                ScrollView {
                    Text(report.text)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(minHeight: 180, maxHeight: 320)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.76))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                EmptyDashboardState(systemImage: "doc.text.magnifyingglass", title: "선택된 보고서 없음", message: "왼쪽 달력이나 목록에서 제출 기록을 선택하세요.")
            }
        }
    }

    private var workMemoList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("작업 메모", systemImage: "note.text")
                    .font(.headline)
                Spacer()
                Button {
                    runner.openQuickMemoWindow()
                } label: {
                    Label("메모", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }

            if workMemos.isEmpty {
                EmptyDashboardState(systemImage: "note.text", title: "저장된 작업 메모 없음", message: "메뉴바의 빠른 작업 메모에서 초안 메모를 남길 수 있습니다.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(workMemos.prefix(8)) { memo in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 8) {
                                    flowTag(memo.targetID, tint: memo.targetType == "jira" ? .blue : .secondary)
                                    Text(memo.targetTitle)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                    Spacer()
                                    Text(memo.date)
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                Text(memo.text)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                                    .textSelection(.enabled)
                            }
                            .padding(9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .textBackgroundColor).opacity(0.56))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
    }

    private var aiSection: some View {
        CommandGroup(title: "AI 작성", subtitle: "요약과 초안 생성", systemImage: "brain.head.profile") {
            VStack(spacing: 8) {
                DashboardButton(title: "업무 요약", systemImage: "text.badge.checkmark") {
                    Task {
                        await runDashboardCommand(
                            ["ai", "git-summary", "--tone", "brief"],
                            title: "업무 요약",
                            running: "업무 요약을 만드는 중...",
                            success: "업무 요약 완료",
                            failure: "업무 요약 실패"
                        )
                    }
                }
                .disabled(runner.isRunning)

                DashboardButton(title: "보고용 요약", systemImage: "person.text.rectangle") {
                    Task {
                        await runDashboardCommand(
                            ["ai", "git-summary", "--tone", "manager"],
                            title: "보고용 요약",
                            running: "보고용 요약을 만드는 중...",
                            success: "보고용 요약 완료",
                            failure: "보고용 요약 실패"
                        )
                    }
                }
                .disabled(runner.isRunning)

                DashboardButton(title: "PR 작성안", systemImage: "arrow.triangle.pull") {
                    var args = ["ai", "pr-draft", "--tone", "brief"]
                    if !selectedPath.isEmpty {
                        args.append(contentsOf: ["--repo", selectedPath])
                    }
                    Task {
                        await runDashboardCommand(
                            args,
                            title: "PR 작성안",
                            running: "PR 작성안을 만드는 중...",
                            success: "PR 작성안 생성 완료",
                            failure: "PR 작성안 생성 실패"
                        )
                    }
                }
                .disabled(runner.isRunning)

                DashboardButton(title: "장애 정리안", systemImage: "stethoscope") {
                    Task {
                        await runDashboardCommand(
                            ["ai", "incident-draft", "--tone", "detailed"],
                            title: "장애 정리안",
                            running: "장애 정리안을 만드는 중...",
                            success: "장애 정리안 생성 완료",
                            failure: "장애 정리안 생성 실패"
                        )
                    }
                }
                .disabled(runner.isRunning)
            }
        }
    }

    private func initialDataLoad(notify: Bool = false) async {
        guard !isInitialDataLoading else {
            return
        }
        isInitialDataLoading = true
        await reload(notify: notify)
        async let briefing: Void = preloadBriefingData()
        async let records: Void = loadRecords(skipJiraFlow: true)
        async let memoTargets: [MemoTargetOption] = runner.loadMemoTargets()
        async let codex: Void = loadCodexHealth()
        _ = await (briefing, records, memoTargets, codex)
        isInitialDataLoading = false
    }

    private func reload(notify: Bool = false, fetchRemote: Bool = false) async {
        isLoading = true
        workCommitPreviewRows = runner.loadSettings().workCommitPreviewRowsOrDefault
        if fetchRemote {
            repositories = orderedRepositories(await runner.refreshManagedRepositories(fetchRemote: true))
        } else {
            repositories = orderedRepositories(await runner.loadManagedRepositories())
        }
        syncRepositoryOrder()
        await loadBranchOptions()
        isLoading = false
        if notify {
            showNotice(title: "상태 새로고침", message: "관리 중인 저장소 \(repositories.count)개의 상태를 다시 불러왔습니다.", succeeded: true)
        }
    }

    private func autoRefreshLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 600 * 1_000_000_000)
            if Task.isCancelled {
                return
            }
            guard !runner.isSetupOpen, !runner.isRunning, !isLoading else {
                continue
            }
            await reload(fetchRemote: true)
        }
    }

    private func jiraIssueWatchLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 300 * 1_000_000_000)
            if Task.isCancelled {
                return
            }
            guard !runner.isSetupOpen, !runner.isPersonalProfile, !runner.isRunning else {
                continue
            }
            await checkNewJiraIssues(showEmptyResult: false)
        }
    }

    private func showTodayCommits(_ repo: LocalRepositoryOption) async {
        selectedPath = repo.path
        lastMessage = await runner.loadTodayCommits(path: repo.path)
        showNotice(title: "\(repo.name) 오늘 커밋", message: lastMessage, succeeded: !runner.status.contains("실패"))
    }

    private func loadBranchOptions() async {
        let paths = repositories.map(\.path)
        let loaded = await withTaskGroup(of: (String, [BranchOption]).self) { group in
            for path in paths {
                group.addTask {
                    (path, await runner.loadRepositoryBranches(path: path))
                }
            }

            var values: [String: [BranchOption]] = [:]
            for await (path, branches) in group {
                values[path] = branches
            }
            return values
        }
        branchOptionsByPath = loaded
    }

    private func orderedRepositories(_ values: [LocalRepositoryOption]) -> [LocalRepositoryOption] {
        let indexByPath = Dictionary(uniqueKeysWithValues: repositoryOrder.enumerated().map { ($0.element, $0.offset) })
        return values.sorted {
            let left = indexByPath[$0.path] ?? Int.max
            let right = indexByPath[$1.path] ?? Int.max
            if left != right {
                return left < right
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func syncRepositoryOrder() {
        var paths = repositoryOrder.filter { path in repositories.contains(where: { $0.path == path }) }
        for repo in repositories where !paths.contains(repo.path) {
            paths.append(repo.path)
        }
        repositoryOrderRaw = paths.joined(separator: "\n")
    }

    private func moveRepository(draggingPath: String, targetPath: String) {
        var paths = repositoryOrder
        if paths.isEmpty {
            paths = orderedRepositories(repositories).map(\.path)
        }
        guard
            let sourceIndex = paths.firstIndex(of: draggingPath),
            let targetIndex = paths.firstIndex(of: targetPath),
            sourceIndex != targetIndex
        else {
            return
        }

        let sourcePath = paths.remove(at: sourceIndex)
        paths.insert(sourcePath, at: targetIndex)
        repositoryOrderRaw = paths.joined(separator: "\n")
        repositories = orderedRepositories(repositories)
    }

    private func checkout(_ repo: LocalRepositoryOption, branch: String) async {
        selectedPath = repo.path
        let result = await runner.checkoutRepositoryBranch(path: repo.path, branch: branch)
        showNotice(title: "\(repo.name) 브랜치 변경", message: result.displayText, succeeded: result.succeeded)
        await reload()
    }

    private func openIDE(_ repo: LocalRepositoryOption) {
        selectedPath = repo.path
        let appName = runner.loadSettings().defaultIDEAppName
        runner.openRepositoryInIDE(path: repo.path, appName: appName)
    }

    private func showTodayActivity() async {
        lastMessage = await runner.loadTodayActivity()
        showNotice(title: "오늘 흐름", message: lastMessage, succeeded: !runner.status.contains("실패"))
    }

    private func startIssueWork(_ item: JiraListItem) async {
        let result = await runner.startIssueWork(issue: item.key, summary: item.title)
        lastMessage = result.displayText
        if result.succeeded {
            showNotice(title: "\(item.key) 작업 시작", message: result.displayText, succeeded: true)
            rememberBriefing("\(item.key) repository 연결 및 브랜치 시작")
            await reload()
        } else if needsRepositorySelection(result.displayText) {
            runner.openIssueRepositoryLinkWindow(issue: item.key, summary: item.title)
        } else {
            showNotice(title: "\(item.key) 작업 시작", message: result.displayText, succeeded: false)
        }
    }

    private func startFullIssueFlow(_ item: JiraListItem) async {
        selectedWorkIssueKey = item.key
        let result = await runner.startIssueWork(issue: item.key, summary: item.title)
        lastMessage = result.displayText
        if result.succeeded {
            showNotice(title: "\(item.key) 작업 시작", message: result.displayText, succeeded: true)
            rememberBriefing("\(item.key) 저장소 연결, 브랜치 생성, Codex 작업 요청")
            await reload()
            await openCodexWorkspace(item)
        } else if needsRepositorySelection(result.displayText) {
            runner.openIssueRepositoryLinkWindow(issue: item.key, summary: item.title)
        } else {
            showNotice(title: "\(item.key) 작업 시작", message: result.displayText, succeeded: false)
        }
    }

    private func needsRepositorySelection(_ message: String) -> Bool {
        PASRunner.needsRepositorySelection(message)
    }

    private func loadSelectedIssueDetailIfNeeded(force: Bool) async {
        guard !runner.isPersonalProfile else {
            selectedIssueDetail = .empty
            return
        }
        let key = selectedWorkIssue?.key ?? selectedWorkIssueKey
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            selectedIssueDetail = .empty
            return
        }
        if !force, selectedIssueDetail.key == key {
            return
        }
        isLoadingIssueDetail = true
        selectedIssueDetail = await runner.loadJiraIssueDetail(issue: key)
        isLoadingIssueDetail = false
    }

    private func formattedFileSize(_ value: Int) -> String {
        guard value > 0 else {
            return ""
        }
        if value >= 1_000_000 {
            return String(format: "%.1f MB", Double(value) / 1_000_000.0)
        }
        if value >= 1_000 {
            return String(format: "%.0f KB", Double(value) / 1_000.0)
        }
        return "\(value) B"
    }

    private func recommendIssueRepository(_ item: JiraListItem) async {
        let result = await runner.recommendIssueRepository(issue: item.key, summary: item.title)
        lastMessage = result.displayText
        showNotice(title: "\(item.key) repository 추천", message: result.displayText, succeeded: result.succeeded)
    }

    private func traceIssueWork(_ item: JiraListItem) async {
        let result = await runner.traceIssueWork(issue: item.key)
        lastMessage = result.displayText
        showNotice(title: "\(item.key) 작업 추적", message: result.displayText, succeeded: result.succeeded)
    }

    private func openCodexWorkspace(_ item: JiraListItem) async {
        let result = await runner.openCodexWorkspaceForIssue(
            issue: item.key,
            summary: item.title,
            detail: item.detail,
            repositories: repositories
        )
        lastMessage = result.displayText
        showNotice(title: "\(item.key) Codex", message: result.displayText, succeeded: result.succeeded)
    }

    private func submitReport() async {
        let result = await runner.submitReport(reportDraft, notes: reportNotes, sendSlack: !runner.isPersonalProfile)
        lastMessage = result.displayText
        showNotice(title: "보고서 제출", message: result.displayText, succeeded: result.succeeded)
        if result.succeeded {
            rememberBriefing("보고서 제출")
            lastSubmittedReportID = submittedReportID(from: result.displayText)
            await loadRecords()
            if !lastSubmittedReportID.isEmpty {
                selectedReportID = lastSubmittedReportID
            }
            recordsViewMode = "reports"
            selectedSection = "records"
        }
    }

    private func submittedReportID(from text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .first { $0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("- id:") }?
            .replacingOccurrences(of: "- id:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func loadRecords(skipJiraFlow: Bool = false) async {
        async let reportsTask = runner.loadSubmittedReports()
        async let memosTask = runner.loadWorkMemos()
        async let overtimeTask = runner.loadOvertimeSummary()
        let (loadedReports, loadedMemos, loadedOvertime) = await (reportsTask, memosTask, overtimeTask)

        submittedReports = loadedReports
        workMemos = loadedMemos
        overtimeSummary = loadedOvertime
        syncOvertimeSettings()
        if selectedReportID.isEmpty || !submittedReports.contains(where: { $0.id == selectedReportID }) {
            selectedReportID = submittedReports.first?.id ?? ""
        }
        if !runner.isPersonalProfile && !skipJiraFlow {
            await loadJiraTeamFlow(showFailureNotice: false)
        }
    }

    private func loadCodexHealth() async {
        codexHealth = await runner.loadCodexHealth()
    }

    private var overtimePanel: some View {
        DisclosureGroup(isExpanded: $isOvertimeExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    overtimeMetric(title: "총 기록", value: "\(overtimeSummary.totalHours)h")
                    overtimeMetric(title: "포괄 포함", value: "\(overtimeSummary.includedHours)h")
                    overtimeMetric(title: "추가 산정", value: "\(overtimeSummary.payableHours)h")
                    overtimeMetric(title: "예상 추가 수당", value: "\(formattedAllowance) \(overtimeSummary.currency)")
                }
                if shouldShowOvertimeRateFallbackNotice {
                    Label("월 기본급 기준 추정 시급 \(formattedEffectiveHourlyRate) \(overtimeSummary.currency)을 사용합니다.", systemImage: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if overtimeSummary.settings.inclusiveSalaryEnabled {
                    Label("월 포괄수당은 주 포괄 시간 × 4.345주 × 추정 시급 × 연장 배율로 자동 산정합니다. 현재 \(formattedIncludedAllowance) \(overtimeSummary.currency)", systemImage: "sum")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                overtimeInputCard
                Text(overtimeInputGuide)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                overtimeSettingsPanel

                if overtimeSummary.records.isEmpty {
                    Text("이번 달 연장 근무 기록이 없습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    overtimeRecentRecords
                }
            }
            .padding(.top, 8)
        } label: {
            HStack {
                Label("연장 근무", systemImage: "clock.badge.exclamationmark")
                    .font(.headline)
                Spacer()
                Text("\(overtimeSummary.totalHours)h · \(formattedAllowance) \(overtimeSummary.currency)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.42))
        )
    }

    private var overtimeSettingsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            DisclosureGroup("계산 설정") {
                if isOvertimeSettingsUnlocked {
                    overtimeUnlockedSettings
                } else {
                    overtimeLockView
                }
                Text("실제 지급액은 회사 정책, 근로계약, 세전/세후 기준에 따라 달라질 수 있습니다.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var overtimeInputCard: some View {
        HStack(alignment: .top, spacing: 14) {
            overtimeCalendarCard

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Picker("", selection: $overtimeUsesTimeRange) {
                        Text("시간 범위").tag(true)
                        Text("총시간").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 190)
                    Spacer()
                    if !editingOvertimeRecordID.isEmpty {
                        Button("취소") {
                            resetOvertimeForm()
                        }
                    }
                    Button {
                        Task { await saveOvertimeRecord() }
                    } label: {
                        Label(editingOvertimeRecordID.isEmpty ? "기록" : "수정", systemImage: editingOvertimeRecordID.isEmpty ? "plus" : "checkmark")
                    }
                    .disabled(runner.isRunning || !canSaveOvertimeRecord)
                }

                if overtimeUsesTimeRange {
                    HStack(spacing: 10) {
                        overtimeClockPicker("시작", hour: $overtimeStartHour, minute: $overtimeStartMinute)
                        overtimeClockPicker("종료", hour: $overtimeEndHour, minute: $overtimeEndMinute)
                    }
                    Text("저장 시 야간(22:00-06:00)과 토/일 휴일 구간을 자동으로 나눕니다.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 8) {
                        TextField("총시간", text: $overtimeHours)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                        Picker("구분", selection: $overtimeKind) {
                            Text("연장").tag("overtime")
                            Text("야간").tag("night")
                            Text("휴일").tag("holiday")
                        }
                        .labelsHidden()
                        .frame(width: 100)
                    }
                    Text("총시간만 기록할 때는 구분을 직접 선택합니다. 토/일은 휴일로 보정됩니다.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                TextField("사유 또는 메모", text: $overtimeMemo)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.38))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var overtimeCalendarCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("근무일")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(formatKoreanDate(overtimeSelectedDate))
                        .font(.caption.weight(.semibold))
                }
                Spacer()
                Button {
                    moveOvertimeMonth(-1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                Button {
                    overtimeSelectedDate = Date()
                    overtimeCalendarMonth = Date()
                } label: {
                    Text("오늘")
                        .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.plain)
                Button {
                    moveOvertimeMonth(1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
            }

            Text(formatMonth(overtimeCalendarMonth))
                .font(.headline.weight(.semibold))

            HStack(spacing: 4) {
                ForEach(["일", "월", "화", "수", "목", "금", "토"], id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(symbol == "일" || symbol == "토" ? .secondary : .tertiary)
                        .frame(width: 30)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 4), count: 7), spacing: 5) {
                ForEach(Array(overtimeCalendarDays().enumerated()), id: \.offset) { _, day in
                    overtimeCalendarDay(day)
                }
            }
        }
        .padding(12)
        .frame(width: 270)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .controlBackgroundColor).opacity(0.76),
                    Color(nsColor: .textBackgroundColor).opacity(0.46),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.38))
        )
    }

    private func overtimeCalendarDay(_ day: Date?) -> some View {
        Group {
            if let day {
                let selected = Calendar.current.isDate(day, inSameDayAs: overtimeSelectedDate)
                let today = Calendar.current.isDateInToday(day)
                let weekend = Calendar.current.isDateInWeekend(day)
                Button {
                    overtimeSelectedDate = day
                } label: {
                    Text("\(Calendar.current.component(.day, from: day))")
                        .font(.caption.weight(selected ? .bold : .regular))
                        .foregroundStyle(selected ? Color.white : (weekend ? Color.accentColor : Color.primary))
                        .frame(width: 30, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(selected ? Color.accentColor : (today ? Color.accentColor.opacity(0.14) : Color.clear))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(today && !selected ? Color.accentColor.opacity(0.42) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .help(formatKoreanDate(day))
            } else {
                Color.clear
                    .frame(width: 30, height: 26)
            }
        }
    }

    private func overtimeClockPicker(_ title: String, hour: Binding<Int>, minute: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Picker("시", selection: hour) {
                    ForEach(0..<24, id: \.self) { value in
                        Text(String(format: "%02d", value)).tag(value)
                    }
                }
                .labelsHidden()
                .frame(width: 58)
                Text(":")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("분", selection: minute) {
                    ForEach([0, 10, 20, 30, 40, 50], id: \.self) { value in
                        Text(String(format: "%02d", value)).tag(value)
                    }
                }
                .labelsHidden()
                .frame(width: 58)
            }
        }
    }

    private var overtimeLockView: some View {
        HStack(spacing: 8) {
            if overtimeSettingsPasscode.isEmpty {
                SecureField("초기 설정 비밀번호", text: $overtimeNewPasscode)
                    .textFieldStyle(.roundedBorder)
                Button("설정") {
                    overtimeSettingsPasscode = overtimeNewPasscode
                    overtimeNewPasscode = ""
                    isOvertimeSettingsUnlocked = true
                }
                .disabled(overtimeNewPasscode.count < 4)
            } else {
                SecureField("비밀번호", text: $overtimePasscodeInput)
                    .textFieldStyle(.roundedBorder)
                Button("열기") {
                    isOvertimeSettingsUnlocked = overtimePasscodeInput == overtimeSettingsPasscode
                    overtimePasscodeInput = ""
                }
                .disabled(overtimePasscodeInput.isEmpty)
            }
            Text("급여/근로계약 정보가 포함될 수 있어 잠가둡니다.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var overtimeUnlockedSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("포괄임금제 적용", isOn: $overtimeInclusiveSalaryEnabled)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                overtimeField("시급", $overtimeHourlyRate, "0이면 월 기본급 또는 법정/통상 기준액을 209시간으로 나눠 추정합니다.")
                overtimeField("연장 배율", $overtimeMultiplier, "일반 연장 근무 시간에 곱할 배율입니다. 예: 1.5")
                overtimeField("야간 추가", $overtimeNightMultiplier, "야간 근무일 때 연장 배율에 더할 추가 배율입니다.")
                overtimeField("휴일 추가", $overtimeHolidayMultiplier, "휴일 근무일 때 연장 배율에 더할 추가 배율입니다.")
                overtimeField("반올림(분)", $overtimeRoundingMinutes, "기록 시간을 몇 분 단위로 반올림할지 정합니다.")
                overtimeField("주 포괄 시간", $overtimeInclusiveWeeklyHours, "포괄임금에 포함된 주당 연장 근무 시간입니다.")
                overtimeField("월 기본급", $overtimeBaseMonthlySalary, "근로계약상 월 기본급 또는 기준 급여를 기록합니다.")
                overtimeField("월 포괄수당", $overtimeInclusiveOvertimePay, "참고용 계약 금액입니다. 계산에는 월 기본급과 주 포괄 시간으로 자동 산정한 값을 우선 사용합니다.")
                overtimeField("법정/통상 기준액", $overtimeStatutoryBasePay, "법정 또는 통상임금 산정 기준으로 따로 관리할 금액입니다.")
            }
            HStack {
                Button("잠그기") {
                    isOvertimeSettingsUnlocked = false
                }
                Spacer()
                Button("저장") {
                    Task { await saveOvertimeSettings() }
                }
                .disabled(runner.isRunning || overtimeHourlyRate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var overtimeRecentRecords: some View {
        VStack(spacing: 6) {
            ForEach(overtimeSummary.records.prefix(5)) { item in
                HStack(spacing: 8) {
                    Text(item.date)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("\(item.hours)h")
                        .font(.caption.weight(.semibold))
                    if let range = overtimeTimeRange(item) {
                        Text(range)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text(overtimeKindLabel(item.effectiveKind ?? item.kind))
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    if item.autoClassified == true {
                        Text("자동")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    Text(item.memo.isEmpty ? "-" : item.memo)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        editOvertimeRecord(item)
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.plain)
                    .help("수정")
                    Button {
                        Task { await deleteOvertimeRecord(item) }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("삭제")
                }
            }
        }
    }

    private func overtimeMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func overtimeField(_ title: String, _ text: Binding<String>, _ help: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
            Text(help)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var formattedAllowance: String {
        guard let value = Int(overtimeSummary.estimatedAllowance) else {
            return overtimeSummary.estimatedAllowance
        }
        return value.formatted()
    }

    private var formattedEffectiveHourlyRate: String {
        guard let rawValue = overtimeSummary.effectiveHourlyRate,
              let value = Double(rawValue) else {
            return "0"
        }
        return Int(value.rounded()).formatted()
    }

    private var formattedIncludedAllowance: String {
        let rawValue = overtimeSummary.calculatedIncludedAllowance ?? overtimeSummary.includedAllowance
        guard let value = Int(rawValue) else {
            return rawValue
        }
        return value.formatted()
    }

    private var shouldShowOvertimeRateFallbackNotice: Bool {
        let explicitRate = Double(overtimeSummary.settings.hourlyRate) ?? 0
        let effectiveRate = Double(overtimeSummary.effectiveHourlyRate ?? "0") ?? 0
        return explicitRate <= 0 && effectiveRate > 0
    }

    private var canSaveOvertimeRecord: Bool {
        if overtimeUsesTimeRange {
            return true
        }
        let hasHours = !overtimeHours.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasHours
    }

    private var overtimeInputGuide: String {
        if overtimeUsesTimeRange {
            return "캘린더와 시간 선택값으로 연장/야간/휴일을 자동 계산합니다."
        }
        return Calendar(identifier: .gregorian).isDateInWeekend(overtimeSelectedDate) ? "총시간만 넣어도 토/일 기록은 휴일 근로 배율로 자동 계산됩니다." : "총시간만 넣으면 선택한 구분 기준으로 계산됩니다."
    }

    private func syncOvertimeSettings() {
        let settings = overtimeSummary.settings
        overtimeHourlyRate = settings.hourlyRate
        overtimeMultiplier = settings.overtimeMultiplier
        overtimeNightMultiplier = settings.nightMultiplier
        overtimeHolidayMultiplier = settings.holidayMultiplier
        overtimeRoundingMinutes = "\(settings.roundingMinutes)"
        overtimeInclusiveSalaryEnabled = settings.inclusiveSalaryEnabled
        overtimeInclusiveWeeklyHours = settings.inclusiveWeeklyHours
        overtimeBaseMonthlySalary = settings.baseMonthlySalary
        overtimeInclusiveOvertimePay = settings.inclusiveOvertimePay
        overtimeStatutoryBasePay = settings.statutoryBasePay
    }

    private func saveOvertimeRecord() async {
        let startTime = overtimeUsesTimeRange ? formatClock(hour: overtimeStartHour, minute: overtimeStartMinute) : ""
        let endTime = overtimeUsesTimeRange ? formatClock(hour: overtimeEndHour, minute: overtimeEndMinute) : ""
        let recordDate = formatDate(overtimeSelectedDate)
        let result: PASCommandResult
        if editingOvertimeRecordID.isEmpty {
            result = await runner.saveOvertimeRecord(
                date: recordDate,
                hours: overtimeUsesTimeRange ? "" : overtimeHours,
                kind: overtimeKind,
                startTime: startTime,
                endTime: endTime,
                memo: overtimeMemo
            )
        } else {
            result = await runner.updateOvertimeRecord(
                id: editingOvertimeRecordID,
                date: recordDate,
                hours: overtimeUsesTimeRange ? "" : overtimeHours,
                kind: overtimeKind,
                startTime: startTime,
                endTime: endTime,
                memo: overtimeMemo
            )
        }
        lastMessage = result.displayText
        showNotice(title: editingOvertimeRecordID.isEmpty ? "연장 근무 기록" : "연장 근무 수정", message: result.displayText, succeeded: result.succeeded)
        if result.succeeded {
            resetOvertimeForm()
            overtimeSummary = await runner.loadOvertimeSummary()
            syncOvertimeSettings()
        }
    }

    private func deleteOvertimeRecord(_ item: OvertimeRecord) async {
        let result = await runner.deleteOvertimeRecord(id: item.id)
        lastMessage = result.displayText
        showNotice(title: "연장 근무 삭제", message: result.displayText, succeeded: result.succeeded)
        if result.succeeded {
            if editingOvertimeRecordID == item.id {
                resetOvertimeForm()
            }
            overtimeSummary = await runner.loadOvertimeSummary()
            syncOvertimeSettings()
        }
    }

    private func editOvertimeRecord(_ item: OvertimeRecord) {
        editingOvertimeRecordID = item.id
        if let date = parseDate(item.date) {
            overtimeSelectedDate = date
            overtimeCalendarMonth = date
        }
        overtimeMemo = item.memo
        overtimeKind = item.kind
        if let start = item.startTime, let end = item.endTime, !start.isEmpty, !end.isEmpty {
            overtimeUsesTimeRange = true
            applyClock(start, isStart: true)
            applyClock(end, isStart: false)
            overtimeHours = ""
        } else {
            overtimeUsesTimeRange = false
            overtimeHours = item.hours
        }
    }

    private func resetOvertimeForm() {
        editingOvertimeRecordID = ""
        overtimeHours = ""
        overtimeMemo = ""
    }

    private func saveOvertimeSettings() async {
        let result = await runner.saveOvertimeSettings(
            hourlyRate: overtimeHourlyRate,
            overtimeMultiplier: overtimeMultiplier,
            nightMultiplier: overtimeNightMultiplier,
            holidayMultiplier: overtimeHolidayMultiplier,
            roundingMinutes: overtimeRoundingMinutes,
            inclusiveSalaryEnabled: overtimeInclusiveSalaryEnabled,
            inclusiveWeeklyHours: overtimeInclusiveWeeklyHours,
            baseMonthlySalary: overtimeBaseMonthlySalary,
            inclusiveOvertimePay: overtimeInclusiveOvertimePay,
            statutoryBasePay: overtimeStatutoryBasePay
        )
        lastMessage = result.displayText
        showNotice(title: "연장 수당 설정", message: result.displayText, succeeded: result.succeeded)
        if result.succeeded {
            overtimeSummary = await runner.loadOvertimeSummary()
            syncOvertimeSettings()
        }
    }

    private func overtimeKindLabel(_ value: String) -> String {
        switch value {
        case "holiday_night":
            return "휴일·야간"
        case "night":
            return "야간"
        case "holiday":
            return "휴일"
        default:
            return "연장"
        }
    }

    private func formatDate(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: value)
    }

    private func parseDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private func formatClock(hour: Int, minute: Int) -> String {
        "\(String(format: "%02d", hour)):\(String(format: "%02d", minute))"
    }

    private func applyClock(_ value: String, isStart: Bool) {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return }
        if isStart {
            overtimeStartHour = min(23, max(0, parts[0]))
            overtimeStartMinute = nearestTenMinute(parts[1])
        } else {
            overtimeEndHour = min(23, max(0, parts[0]))
            overtimeEndMinute = nearestTenMinute(parts[1])
        }
    }

    private func nearestTenMinute(_ value: Int) -> Int {
        min(50, max(0, Int((Double(value) / 10.0).rounded()) * 10))
    }

    private func formatMonth(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월"
        return formatter.string(from: value)
    }

    private func formatKoreanDate(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 EEEE"
        return formatter.string(from: value)
    }

    private func moveOvertimeMonth(_ offset: Int) {
        overtimeCalendarMonth = Calendar.current.date(byAdding: .month, value: offset, to: overtimeCalendarMonth) ?? overtimeCalendarMonth
    }

    private func overtimeCalendarDays() -> [Date?] {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: overtimeCalendarMonth)
        guard let firstDay = calendar.date(from: components),
              let dayRange = calendar.range(of: .day, in: .month, for: firstDay) else {
            return []
        }
        let leadingBlanks = calendar.component(.weekday, from: firstDay) - 1
        var days: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for day in dayRange {
            var dateComponents = components
            dateComponents.day = day
            days.append(calendar.date(from: dateComponents))
        }
        while days.count % 7 != 0 {
            days.append(nil)
        }
        return days
    }

    private func overtimeTimeRange(_ item: OvertimeRecord) -> String? {
        guard let start = item.startTime, let end = item.endTime, !start.isEmpty, !end.isEmpty else {
            return nil
        }
        return "\(start)-\(end)"
    }

    private func reports(on day: Int) -> [SubmittedReportRecord] {
        guard day > 0 else {
            return []
        }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: Date())
        let month = String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
        let date = "\(month)-\(String(format: "%02d", day))"
        return submittedReports.filter { $0.date == date }
    }

    private func currentMonthDate(day: Int) -> Date? {
        guard day > 0 else {
            return nil
        }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: Date())
        return calendar.date(from: DateComponents(year: components.year, month: components.month, day: day))
    }

    private func calendarDayHelp(day: Int, reports: [SubmittedReportRecord]) -> String {
        guard let date = currentMonthDate(day: day) else {
            return ""
        }
        let dateText = formatKoreanDate(date)
        if reports.isEmpty {
            return dateText
        }
        return "\(dateText) · 보고서 \(reports.count)개"
    }

    private func calendarDayBackground(day: Int, reports: [SubmittedReportRecord]) -> Color {
        guard day > 0 else {
            return Color.clear
        }
        if let date = currentMonthDate(day: day),
           Calendar.current.isDate(date, inSameDayAs: selectedRecordDate) {
            return Color.accentColor.opacity(0.18)
        }
        if reports.contains(where: { $0.id == selectedReportID }) {
            return Color.accentColor.opacity(0.18)
        }
        if !reports.isEmpty {
            return Color.accentColor.opacity(0.08)
        }
        return Color(nsColor: .controlBackgroundColor).opacity(0.55)
    }

    private func isSameRecordDate(_ value: String) -> Bool {
        value.hasPrefix(selectedRecordDateString)
    }

    private func compactTimelineTime(_ value: String) -> String {
        if value.count >= 16 {
            let separator = value[value.index(value.startIndex, offsetBy: 10)]
            if separator == "T" || separator == " " {
                let start = value.index(value.startIndex, offsetBy: 11)
                let end = value.index(value.startIndex, offsetBy: 16)
                return String(value[start..<end])
            }
        }
        if value.count >= 5, value.contains(":") {
            return String(value.prefix(5))
        }
        return ""
    }

    private func refineReportWithCodex() async {
        var draft = reportDraft
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft = await runner.previewDailyReport(notes: reportNotes)
            reportDraft = draft
        }
        let result = await runner.refineReportWithCodex(draft: draft, notes: reportNotes)
        lastMessage = result.displayText
        if result.succeeded {
            reportDraft = result.displayText
            reportWasRefined = true
            rememberBriefing("Codex 보고서 다듬기")
        }
        showNotice(title: "Codex 보고서", message: result.displayText, succeeded: result.succeeded)
    }

    private func createQuickJiraIssue() async {
        let result = await runner.createJiraIssue(
            summary: quickJiraSummary,
            description: quickJiraDescription,
            issueType: quickJiraIssueType,
            assignee: quickJiraAssignee,
            priority: quickJiraPriority,
            dueDate: quickJiraDueDate,
            labels: quickJiraLabels
        )
        lastMessage = result.displayText
        showNotice(title: "Jira 일감 생성", message: result.displayText, succeeded: result.succeeded)
        if result.succeeded {
            isJiraQuickCreatePresented = false
            quickJiraSummary = ""
            quickJiraDescription = ""
            quickJiraIssueType = "Task"
            quickJiraAssignee = ""
            quickJiraPriority = ""
            quickJiraDueDate = ""
            quickJiraLabels = ""
            await loadJiraMorningItems(notifyLocal: false)
        }
    }

    private func preloadBriefingData() async {
        guard !runner.isPersonalProfile, !hasPreloadedBriefingData else {
            return
        }
        hasPreloadedBriefingData = true
        await loadJiraMorningItems(notifyLocal: false, showFailureNotice: false)
        await loadJiraTeamFlow(showFailureNotice: false)
    }

    private func autoLoadJiraMorningItemsIfNeeded() async {
        guard selectedSection == "jira", !runner.isPersonalProfile, !hasAutoLoadedJiraMorningItems, !runner.isRunning else {
            return
        }
        hasAutoLoadedJiraMorningItems = true
        await loadJiraMorningItems(notifyLocal: false, showFailureNotice: false)
    }

    private func loadJiraMorningItems(notifyLocal: Bool) async {
        await loadJiraMorningItems(notifyLocal: notifyLocal, showFailureNotice: true)
    }

    private func loadJiraMorningItems(notifyLocal: Bool, showFailureNotice: Bool) async {
        let result = await runner.runDashboardCommand(
            ["jira", "today"],
            runningStatus: "Jira 아침 일감을 불러오는 중...",
            successStatus: "Jira 아침 일감 불러오기 완료",
            failureStatus: "Jira 아침 일감 불러오기 실패"
        )
        lastMessage = result.displayText
        if result.succeeded {
            jiraMorningItems = parseJiraItems(from: result.displayText)
            jiraLastUpdatedText = "마지막 갱신 \(Date().formatted(date: .omitted, time: .shortened))"
        } else if showFailureNotice {
            showNotice(title: "Jira 아침 일감", message: result.displayText, succeeded: false)
        }
        if notifyLocal && result.succeeded {
            runner.sendLocalNotification(title: "Jira 아침 일감", body: jiraNotificationBody(items: jiraMorningItems, fallback: result.displayText))
        }
    }

    private func checkNewJiraIssues(showEmptyResult: Bool) async {
        let result = await runner.checkNewJiraIssues()
        lastMessage = result.displayText
        let hasNewIssues = result.displayText.hasPrefix("새로 등록된 Jira 일감")
        if hasNewIssues && result.succeeded {
            let parsedItems = parseJiraItems(from: result.displayText)
            jiraNewItems = mergeJiraItems(parsedItems, into: jiraNewItems)
            jiraLastUpdatedText = "마지막 갱신 \(Date().formatted(date: .omitted, time: .shortened))"
            runner.sendLocalNotification(title: "새 Jira 일감", body: jiraNotificationBody(items: parsedItems, fallback: result.displayText))
        }
        if !result.succeeded || (showEmptyResult && !hasNewIssues) {
            showNotice(title: "새 Jira 일감", message: result.displayText, succeeded: result.succeeded)
        }
    }

    private func loadJiraTeamFlow() async {
        await loadJiraTeamFlow(showFailureNotice: true)
    }

    private func loadJiraTeamFlow(showFailureNotice: Bool) async {
        let result = await runner.runDashboardCommand(
            ["jira", "flow", "--format", "tsv", "--days", "7"],
            runningStatus: "팀 Jira 흐름을 불러오는 중...",
            successStatus: "팀 Jira 흐름 불러오기 완료",
            failureStatus: "팀 Jira 흐름 불러오기 실패"
        )
        lastMessage = result.displayText
        if result.succeeded {
            jiraTeamFlowItems = parseJiraFlowItems(from: result.displayText)
            rememberBriefing("팀 Jira 흐름 새로고침")
        } else if showFailureNotice {
            showNotice(title: "팀 Jira 흐름", message: result.displayText, succeeded: false)
        }
    }

    private func parseJiraItems(from text: String) -> [JiraListItem] {
        let lines = text.components(separatedBy: .newlines)
        var items: [JiraListItem] = []
        var index = 0

        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let key = jiraKey(in: line), isPrimaryJiraLine(line) else {
                index += 1
                continue
            }

            var link: String?
            var details: [String] = []
            var nextIndex = index + 1
            while nextIndex < lines.count {
                let next = lines[nextIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                if next.isEmpty {
                    if details.isEmpty {
                        nextIndex += 1
                        continue
                    }
                    break
                }
                if jiraKey(in: next) != nil && isPrimaryJiraLine(next) {
                    break
                }
                if next.hasPrefix("링크:") {
                    link = next.replacingOccurrences(of: "링크:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                } else if details.count < 3 {
                    details.append(next)
                }
                nextIndex += 1
            }

            items.append(
                JiraListItem(
                    key: key,
                    title: jiraTitle(from: line, key: key),
                    detail: details.joined(separator: "\n"),
                    link: link
                )
            )
            index = nextIndex
        }

        var seen: Set<String> = []
        return items.filter { item in
            let identity = "\(item.key)-\(item.title)"
            if seen.contains(identity) {
                return false
            }
            seen.insert(identity)
            return true
        }
    }

    private func isPrimaryJiraLine(_ line: String) -> Bool {
        if line.hasPrefix("[dry-run]") || line.hasPrefix("링크:") || line.contains("/browse/") {
            return false
        }
        if line.hasPrefix("관련 로컬 브랜치") || line.hasPrefix("연결 repository") || line.hasPrefix("하위 일감") {
            return false
        }
        if line.hasPrefix("- ") && !line.hasPrefix("- [") {
            return false
        }
        return true
    }

    private func jiraKey(in line: String) -> String? {
        guard let regex = Self.jiraKeyRegex else {
            return nil
        }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range), let swiftRange = Range(match.range, in: line) else {
            return nil
        }
        return String(line[swiftRange])
    }

    private func jiraTitle(from line: String, key: String) -> String {
        var value = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("- ") {
            value.removeFirst(2)
        }
        if value.hasPrefix("[\(key)]") {
            value.removeFirst(key.count + 2)
        } else if value.hasPrefix(key) {
            value.removeFirst(key.count)
        }
        return value.trimmingCharacters(in: CharacterSet(charactersIn: " -|[]").union(.whitespacesAndNewlines))
    }

    private func mergeJiraItems(_ newItems: [JiraListItem], into currentItems: [JiraListItem]) -> [JiraListItem] {
        var output = newItems
        let newKeys = Set(newItems.map(\.key))
        output.append(contentsOf: currentItems.filter { !newKeys.contains($0.key) })
        return Array(output.prefix(40))
    }

    private func jiraNotificationBody(items: [JiraListItem], fallback: String) -> String {
        guard !items.isEmpty else {
            return fallback
        }
        let preview = items.prefix(3).map { "\($0.key) \($0.title)" }.joined(separator: "\n")
        if items.count > 3 {
            return "\(preview)\n외 \(items.count - 3)개"
        }
        return preview
    }

    private func parseJiraFlowItems(from text: String) -> [JiraFlowItem] {
        text.components(separatedBy: .newlines).compactMap { line in
            let columns = line.components(separatedBy: "\t")
            guard columns.count >= 9 else {
                return nil
            }
            return JiraFlowItem(
                key: columns[0],
                title: columns[1],
                status: columns[2],
                reporter: columns[3],
                assignee: columns[4],
                created: columns[5],
                updated: columns[6],
                due: columns[7],
                issueType: columns.count > 9 ? columns[8] : "-",
                project: columns.count > 9 ? columns[9] : "-",
                link: columns.count > 10 ? columns[10] : columns[8]
            )
        }
    }

    private func rememberBriefing(_ text: String) {
        let stamp = Date().formatted(date: .abbreviated, time: .shortened)
        var lines = briefingMemoryLog
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        lines.append("\(stamp) · \(text)")
        briefingMemoryLog = lines.suffix(80).joined(separator: "\n")
    }

    private func run(_ repo: LocalRepositoryOption, mode: String, skipWarning: Bool = false) async {
        if !skipWarning && repo.dirtyCount > 0 && (mode == "pull" || mode == "rebase") {
            pendingAction = RepoAction(repo: repo, mode: mode)
            showDirtyWarning = true
            return
        }
        selectedPath = repo.path
        lastMessage = await runner.runRepositoryUpdate(path: repo.path, mode: mode)
        showNotice(title: "\(repo.name) \(mode)", message: lastMessage, succeeded: !runner.status.contains("실패"))
        await reload()
    }

    private func runDashboardCommand(
        _ arguments: [String],
        title: String,
        running: String,
        success: String,
        failure: String
    ) async {
        let result = await runner.runDashboardCommand(arguments, runningStatus: running, successStatus: success, failureStatus: failure)
        lastMessage = result.displayText
        showNotice(title: title, message: result.displayText, succeeded: result.succeeded)
    }

    private func showNotice(title: String, message: String, succeeded: Bool) {
        notice = WorkNotice(title: title, message: message, succeeded: succeeded)
    }
}

private struct RepositoryDropDelegate: DropDelegate {
    let targetPath: String
    @Binding var draggingPath: String?
    let move: (_ draggingPath: String, _ targetPath: String) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggingPath, draggingPath != targetPath else {
            return
        }
        move(draggingPath, targetPath)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingPath = nil
        return true
    }
}
