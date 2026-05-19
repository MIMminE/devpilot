import SwiftUI

struct RecordTimelineItem: Identifiable {
    let id: String
    let sortKey: String
    let time: String
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color
}

struct RecordDaySummaryStrip: View {
    let reportCount: Int
    let memoCount: Int
    let jiraCount: Int
    let overtimeCount: Int

    var body: some View {
        HStack(spacing: 6) {
            recordSummaryPill(title: "보고서", value: "\(reportCount)", tint: .blue)
            recordSummaryPill(title: "메모", value: "\(memoCount)", tint: .purple)
            recordSummaryPill(title: "Jira", value: "\(jiraCount)", tint: .green)
            recordSummaryPill(title: "연장", value: "\(overtimeCount)", tint: .orange)
        }
    }

    private func recordSummaryPill(title: String, value: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption2)
            Text(value)
                .font(.caption2.weight(.bold))
                .monospacedDigit()
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(tint.opacity(0.10))
        .clipShape(Capsule())
    }
}

struct RecordsTimelineView: View {
    @Binding var selectedDate: Date
    let items: [RecordTimelineItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Label("작업 타임라인", systemImage: "list.bullet.rectangle")
                        .font(.headline)
                    Text("\(formatKoreanDate(selectedDate)) · \(items.count)개 기록")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    selectedDate = Date()
                } label: {
                    Label("오늘", systemImage: "calendar")
                }
                .buttonStyle(.bordered)
            }

            if items.isEmpty {
                EmptyDashboardState(
                    systemImage: "calendar.badge.clock",
                    title: "이 날짜의 기록 없음",
                    message: "보고서 제출, 작업 메모, Jira 흐름, 연장근무 기록이 생기면 이곳에 시간순으로 모입니다."
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(items) { item in
                            timelineRecordRow(item)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(minHeight: 240, maxHeight: 380)
            }
        }
    }

    private func timelineRecordRow(_ item: RecordTimelineItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 4) {
                Image(systemName: item.systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(item.tint)
                    .frame(width: 22, height: 22)
                    .background(item.tint.opacity(0.12))
                    .clipShape(Circle())
                Rectangle()
                    .fill(Color(nsColor: .separatorColor).opacity(0.35))
                    .frame(width: 1)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(item.time.isEmpty ? "시간 -" : item.time)
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(item.tint)
                        .frame(width: 56, alignment: .leading)
                    Text(item.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                }
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.58))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(item.tint.opacity(0.14))
            )
        }
    }

    private func formatKoreanDate(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 EEEE"
        return formatter.string(from: value)
    }
}
