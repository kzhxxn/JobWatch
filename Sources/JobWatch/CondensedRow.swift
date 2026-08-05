import SwiftUI

struct CondensedRow: View {
    let job: LaunchJob
    @Bindable var store: JobStore
    @State private var hovering = false

    private var title: String {
        let a = store.annotation(for: job)
        return a.displayName.isEmpty ? Inference.displayName(for: job) : a.displayName
    }
    private var statusColor: Color {
        if job.pid != nil { return .green }
        if !job.isLoaded { return .gray }
        let exit = store.history[job.label]?.last?.exitCode.map(Int.init) ?? job.lastExitCode
        if let e = exit, e != 0 { return .red }
        return .green
    }

    // 실제 실행 중(pid)이면 맥동으로 구분, 아니면 정적 점
    @ViewBuilder
    private var statusDot: some View {
        if job.pid != nil {
            Image(systemName: "circle.fill").font(.system(size: 7)).foregroundStyle(.green)
                .symbolEffect(.pulse, options: .repeating)
        } else {
            Circle().fill(statusColor).frame(width: 7, height: 7)
        }
    }
    // 예약 잡은 1초마다 갱신되는 카운트다운, 그 외엔 상태/마지막 실행
    @ViewBuilder
    private var timeView: some View {
        if job.pid != nil {
            Text(t("job.running")).font(.caption2).foregroundStyle(.secondary)
        } else if let n = job.nextRun {
            Text("T–\(countdown(n, now: store.tick))")
                .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
        } else if let last = store.history[job.label]?.last?.startedAt ?? job.lastRunApprox {
            Text(relTime(last)).font(.caption2).foregroundStyle(.secondary)
        }
    }
    private func relTime(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated
        return f.localizedString(for: d, relativeTo: store.tick)
    }
    private func countdown(_ date: Date, now: Date) -> String {
        let s = date.timeIntervalSince(now)
        if s < 0 { return "now" }
        if s < 86400 {                                    // 24h 이내 → 시:분:초
            let n = Int(s)
            return String(format: "%d:%02d:%02d", n / 3600, (n % 3600) / 60, n % 60)
        }
        return date.formatted(date: .numeric, time: .omitted)   // 넘어가면 연월일
    }

    var body: some View {
        HStack(spacing: 8) {
            statusDot
            Image(systemName: Inference.category(for: job).icon)
                .font(.caption).foregroundStyle(.secondary).frame(width: 15)
            Text(title).font(.callout).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 6)
            timeView
            Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30, alignment: .leading)
        .background(hovering ? Color.primary.opacity(0.06) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { store.selectedLabel = job.label }
        .onHover { hovering = $0 }
    }
}
