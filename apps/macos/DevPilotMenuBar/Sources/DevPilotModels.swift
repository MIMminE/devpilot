import SwiftUI

struct DevPilotCommandResult: Sendable {
    let succeeded: Bool
    let output: String
    let summary: String

    var displayText: String {
        let value = output.isEmpty ? summary : output
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "출력 없음" : value
    }
}

struct TokenStatusRecord: Identifiable, Decodable, Hashable, Sendable {
    let id: String
    let name: String
    let configured: Bool
    let status: String
    let detail: String
    let expiresAt: String
    let daysRemaining: Int?
    let source: String
    let tokenHint: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case configured
        case status
        case detail
        case expiresAt = "expires_at"
        case daysRemaining = "days_remaining"
        case source
        case tokenHint = "token_hint"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        configured = try container.decodeIfPresent(Bool.self, forKey: .configured) ?? false
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "unknown"
        detail = try container.decodeIfPresent(String.self, forKey: .detail) ?? ""
        expiresAt = try container.decodeIfPresent(String.self, forKey: .expiresAt) ?? ""
        daysRemaining = try container.decodeIfPresent(Int.self, forKey: .daysRemaining)
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? ""
        tokenHint = try container.decodeIfPresent(String.self, forKey: .tokenHint) ?? ""
    }
}

enum DevPilotProfileKind: String, Sendable {
    case work
    case personal
}

struct DevPilotProfile: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let kind: DevPilotProfileKind

    static let work = DevPilotProfile(
        id: "work",
        title: "업무",
        subtitle: "Git 중심, Jira/Slack 선택 연동",
        systemImage: "building.2",
        kind: .work
    )

    static let personal = DevPilotProfile(
        id: "personal",
        title: "개인",
        subtitle: "개인 GitHub 프로젝트 중심",
        systemImage: "person.crop.circle",
        kind: .personal
    )

    static let all: [DevPilotProfile] = [.work, .personal]

    static func profile(for id: String) -> DevPilotProfile? {
        all.first { $0.id == id }
    }
}

struct DevPilotSettings {
    var slackMode: String
    var slackBotToken: String
    var slackDefaultChannelID: String
    var slackTestChannelID: String
    var slackMorningChannelID: String
    var slackEveningChannelID: String
    var slackJiraChannelID: String
    var slackGitReportChannelID: String
    var slackGitStatusChannelID: String
    var slackAlertsChannelID: String
    var jiraBaseURL: String
    var jiraEmail: String
    var jiraApiToken: String
    var jiraDefaultProject: String
    var gitAuthor: String
    var workEndTime: String
    var cloneRoot: String
    var repoProjectPaths: Set<String>
    var repoProjectBaseBranches: [String: String]
    var openAIKey: String
    var jiraDailyEnabled: Bool
    var gitReportEnabled: Bool
    var gitStatusEnabled: Bool
    var jiraDailyScheduleEnabled: Bool
    var jiraDailyScheduleTime: String
    var jiraDailyCatchUp: Bool
    var gitReportScheduleEnabled: Bool
    var gitReportScheduleTime: String
    var gitReportCatchUp: Bool
    var gitStatusScheduleEnabled: Bool
    var gitStatusScheduleTime: String
    var gitStatusCatchUp: Bool
    var defaultIDEAppName: String
    var workCommitPreviewRows: Int

    var testChannelID: String {
        slackTestChannelID.isEmpty ? slackDefaultChannelID : slackTestChannelID
    }

    var jiraChannelID: String {
        slackJiraChannelID.isEmpty ? slackDefaultChannelID : slackJiraChannelID
    }

    var usesSlackOAuth: Bool {
        slackMode == "oauth"
    }

    var isReadyForBasicTests: Bool {
        jiraBaseURL.hasPrefix("https://")
            && jiraEmail.contains("@")
            && !jiraApiToken.isEmpty
            && !jiraDefaultProject.isEmpty
    }

    var isReadyForSlackTest: Bool {
        !slackBotToken.isEmpty && !testChannelID.isEmpty
    }

    private var slackJiraReady: Bool {
        !slackBotToken.isEmpty && !jiraChannelID.isEmpty
    }

    var jiraDailyScheduleTimeOrDefault: String {
        jiraDailyScheduleTime.isEmpty ? "09:00" : jiraDailyScheduleTime
    }

    var gitReportScheduleTimeOrDefault: String {
        gitReportScheduleTime.isEmpty ? "18:30" : gitReportScheduleTime
    }

    var gitStatusScheduleTimeOrDefault: String {
        gitStatusScheduleTime.isEmpty ? "09:10" : gitStatusScheduleTime
    }

    var workCommitPreviewRowsOrDefault: Int {
        min(max(workCommitPreviewRows, 1), 8)
    }
}

struct SlackChannel: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let isPrivate: Bool

    var label: String {
        "#\(name)\(isPrivate ? " (private)" : "")"
    }
}

struct LocalRepositoryOption: Identifiable, Hashable, Sendable {
    let path: String
    let name: String
    let branch: String
    let ahead: Int?
    let behind: Int?
    let dirtyCount: Int
    let baseBranch: String
    let baseRef: String
    let baseBehind: Int?
    let baseAhead: Int?
    let isWorkingBranch: Bool
    let baseRebaseAlert: String
    let todayCommitCount: Int
    let todayCommitLatest: String
    let baseCommitSummary: String
    let autoSyncMessage: String
    let pullRequestSummary: String
    let releaseSummary: String
    let branchForkDate: String
    let branchCommitCount: Int
    let branchCommitPreview: String

    var id: String {
        path
    }

    var syncLabel: String {
        if let ahead, let behind {
            if ahead > 0 && behind > 0 {
                return "rebase/merge 확인: ahead \(ahead), behind \(behind)"
            }
            if behind > 0 {
                return "rebase/pull 필요: behind \(behind)"
            }
            if ahead > 0 {
                return "push 필요: ahead \(ahead)"
            }
            return "동기화됨"
        }
        return "upstream 없음"
    }

    var baseLabel: String {
        let commitSuffix = baseCommitSummary.isEmpty ? "" : " · \(baseCommitSummary)"
        if !baseRebaseAlert.isEmpty {
            return "자동 rebase 확인 필요"
        }
        if isWorkingBranch {
            if let baseBehind, baseBehind > 0 {
                return "작업중 | 기준 \(baseBranch) 대비 rebase 필요: behind \(baseBehind)\(commitSuffix)"
            }
            return "작업중 | 기준 \(baseBranch)\(commitSuffix)"
        }
        return "기준 브랜치 \(baseBranch)\(commitSuffix)"
    }

    var autoSyncLabel: String {
        autoSyncMessage.isEmpty ? "" : "자동 처리됨"
    }

    var githubSummaryAvailable: Bool {
        !pullRequestSummary.isEmpty || !releaseSummary.isEmpty
    }

    var needsBaseRebase: Bool {
        isWorkingBranch && (baseBehind ?? 0) > 0
    }

    var todayCommitLabel: String {
        if todayCommitCount == 0 {
            return "오늘 작업 없음"
        }
        if todayCommitLines.isEmpty {
            return "오늘 작업 \(todayCommitCount)개"
        }
        return "오늘 작업 \(todayCommitCount)개"
    }

    var todayCommitLines: [String] {
        todayCommitLatest
            .components(separatedBy: " ¶ ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var needsUpdate: Bool {
        (behind ?? 0) > 0
    }

    var canFastForward: Bool {
        (behind ?? 0) > 0 && (ahead ?? 0) == 0
    }

    var needsRebase: Bool {
        (behind ?? 0) > 0 && (ahead ?? 0) > 0
    }

    var isProtectedWorkflowBranch: Bool {
        branch != baseBranch && ["main", "master", "dev", "develop", "development"].contains(branch.lowercased())
    }

    var isJiraWorkBranch: Bool {
        branch.range(of: #"[A-Z][A-Z0-9]+-\d+"#, options: [.regularExpression, .caseInsensitive]) != nil
            && branch != baseBranch
    }

    var branchCommitLines: [String] {
        branchCommitPreview
            .components(separatedBy: " ¶ ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

struct CodexProjectRecord: Identifiable, Codable, Hashable {
    let projectName: String
    let cwd: String
    let threadCount: Int
    let threads: [CodexThreadRecord]

    var id: String {
        cwd.isEmpty ? projectName : cwd
    }

    enum CodingKeys: String, CodingKey {
        case projectName = "project_name"
        case cwd
        case threadCount = "thread_count"
        case threads
    }
}

struct CodexThreadRecord: Identifiable, Codable, Hashable {
    let threadID: String
    let name: String
    let cwd: String
    let path: String
    let source: String
    let createdAt: String
    let updatedAt: String

    var id: String {
        threadID
    }

    enum CodingKeys: String, CodingKey {
        case threadID = "thread_id"
        case name
        case cwd
        case path
        case source
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct BranchOption: Identifiable, Hashable, Sendable {
    let name: String
    let current: Bool
    let remote: Bool

    var id: String {
        name
    }

    var label: String {
        remote ? "\(name) (remote)" : name
    }
}

struct GitHubRemoteRepositoryOption: Identifiable, Hashable, Sendable {
    let nameWithOwner: String
    let sshURL: String
    let webURL: String
    let visibility: String
    let defaultBranch: String

    var id: String {
        nameWithOwner
    }

    var shortName: String {
        nameWithOwner.split(separator: "/").last.map(String.init) ?? nameWithOwner
    }

    var cloneSource: String {
        sshURL.isEmpty ? nameWithOwner : sshURL
    }
}

struct IDEAppOption: Identifiable, Hashable, Sendable {
    let name: String
    let path: String

    var id: String {
        name
    }

    var label: String {
        path.isEmpty ? name : "\(name) - \(path)"
    }
}
