import SwiftUI

struct ContentView: View {
    @Bindable var store: JobStore

    var userJobs: [LaunchJob] { store.jobs.filter { $0.domain == .userAgent } }
    var globalJobs: [LaunchJob] { store.jobs.filter { $0.domain == .globalAgent } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LaunchPadView(store: store)
            header
            Divider()
            if let msg = store.lastMessage {
                messageBanner(msg)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if store.jobs.isEmpty {
                        Text(t("empty"))
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                    if !userJobs.isEmpty {
                        sectionHeader(t("section.user"))
                        ForEach(userJobs) { JobRow(job: $0, store: store) }
                    }
                    if !globalJobs.isEmpty {
                        sectionHeader(t("section.global"))
                        ForEach(globalJobs) { JobRow(job: $0, store: store) }
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 420)

            if let label = store.selectedLabel, let job = store.job(for: label) {
                Divider()
                selectionDetail(job)
            }
            Divider()
            footer
        }
        .frame(width: 380)
        .task {
            // 열려 있는 동안 5초마다 자동 갱신
            while !Task.isCancelled {
                await store.refresh()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    // 발사대에서 클릭한 잡의 상세 (하단 활성 패널)
    private func selectionDetail(_ job: LaunchJob) -> some View {
        let ann = store.annotation(for: job)
        let title = ann.displayName.isEmpty ? Inference.displayName(for: job) : ann.displayName
        let desc = ann.note.isEmpty ? Inference.description(for: job) : ann.note
        let h = store.history[job.label]
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: Inference.category(for: job).icon).foregroundStyle(.tint)
                Text(title).font(.callout).fontWeight(.semibold).lineLimit(1)
                Spacer()
                Button { store.selectedLabel = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 10))
                }.buttonStyle(.borderless).foregroundStyle(.secondary)
            }
            Text(desc).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(job.label).font(.caption2).foregroundStyle(.tertiary).textSelection(.enabled)
            HStack(spacing: 10) {
                Label(job.scheduleText, systemImage: "calendar")
                if let n = job.nextRun { Label(fmtTime(n), systemImage: "arrow.right.circle") }
            }.font(.caption2).foregroundStyle(.secondary)
            if let h, h.count > 0 {
                HStack(spacing: 3) {
                    Text(t("job.recorded")).font(.caption2).foregroundStyle(.secondary)
                    ForEach(Array(h.runs.prefix(12).reversed())) { run in
                        Circle().fill(run.success ? Color.green : Color.red).frame(width: 6, height: 6)
                    }
                    if let last = h.last { Text("· \(fmtDur(last.duration))").font(.caption2).foregroundStyle(.secondary) }
                }
            }
            HStack(spacing: 16) {
                if job.isManageable {
                    Button(t("action.run")) { Task { await store.runNow(job) } }
                    Button(job.isLoaded ? t("action.unload") : t("action.load")) { Task { await store.toggleLoaded(job) } }
                }
                Button(t("action.log")) { store.openLog(job) }
                Button(t("action.plist")) { store.revealPlist(job) }
            }
            .font(.caption).buttonStyle(.borderless)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.07))
    }

    private func fmtDur(_ d: Double?) -> String {
        guard let d else { return "—" }
        if d < 1 { return String(format: "%.0fms", d * 1000) }
        if d < 60 { return String(format: "%.1fs", d) }
        if d < 3600 { return String(format: "%.0fm", d / 60) }
        return String(format: "%.1fh", d / 3600)
    }
    private func fmtTime(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(date: .abbreviated, time: .shortened)
    }

    // 눈에 띄는 메시지 배너 (4초 뒤 자동 사라짐)
    private func messageBanner(_ msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.tint)
            Text(msg)
                .font(.callout).fontWeight(.medium)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button { store.lastMessage = nil } label: {
                Image(systemName: "xmark").font(.system(size: 10))
            }
            .buttonStyle(.borderless).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.15))
        .task(id: msg) {
            try? await Task.sleep(for: .seconds(4))
            if store.lastMessage == msg { store.lastMessage = nil }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "clock.badge.checkmark")
                Text(t("menu.title")).font(.headline)
                Spacer()
                Button {
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help(t("header.refresh"))
            }
            // 디스크 게이지
            HStack(spacing: 8) {
                Text(t("header.disk")).font(.caption).foregroundStyle(.secondary)
                ProgressView(value: store.disk.usedFraction)
                    .tint(store.disk.usedFraction > 0.85 ? .red : .accentColor)
                Text("\(store.disk.usedBytes.humanSize) / \(store.disk.totalBytes.humanSize)")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            Text(t("header.jobsSummary", store.jobs.count, store.healthyCount, store.problemCount))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption).bold()
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 2)
    }

    private var footer: some View {
        HStack {
            if let d = store.lastRefresh {
                Text(t("header.lastRefresh", d.formatted(date: .omitted, time: .standard)))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            Button(t("action.quit")) { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.caption)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}

struct JobRow: View {
    let job: LaunchJob
    @Bindable var store: JobStore
    @State private var hovering = false
    @State private var editing = false
    @State private var draftName = ""
    @State private var draftNote = ""
    @State private var draftTags = ""

    private var ann: JobAnnotation { store.annotation(for: job) }
    private var category: Inference.Category { Inference.category(for: job) }
    /// 표시 이름: 사용자 별명 > plist 추론 이름 > 라벨
    private var title: String {
        ann.displayName.isEmpty ? Inference.displayName(for: job) : ann.displayName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 9) {
                // 종류 아이콘 (색 = 건강 상태)
                Image(systemName: category.icon)
                    .font(.system(size: 15))
                    .foregroundStyle(statusColor)
                    .frame(width: 20)
                    .padding(.top, 2)
                    .help(category.name)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body).fontWeight(.medium)
                        .lineLimit(1).truncationMode(.middle)
                    // 설명: "무슨 일을 하는가" (사용자 메모 > 규칙 기반 추론) — 이름 바로 아래
                    Text(descriptionText)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(2)
                    // 원본 라벨은 설명 아래 회색 보조로
                    if title != job.label {
                        Text(job.label)
                            .font(.caption2).foregroundStyle(.tertiary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    if !ann.tags.isEmpty { tagChips }
                    whenLine       // ← 언제 실행됐나 (가독성 개선)
                    scheduleLine   // ← 스케줄 (보조)
                }
                Spacer()
            }
            if editing { editor }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(hovering ? Color.primary.opacity(0.06) : .clear)
        .overlay(alignment: .topTrailing) {
            if hovering && !editing { iconBar }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private var descriptionText: String {
        ann.note.isEmpty ? Inference.description(for: job) : ann.note
    }

    private var recorded: JobHistory? { store.history[job.label] }

    // "언제" — 마지막 실행(색으로 성공/실패) + 최근 실행 점 + 다음 실행. 가독성 최우선 줄.
    private var whenLine: some View {
        HStack(spacing: 10) {
            lastRunView
            if let h = recorded, h.count > 1 { recentDots(h) }
            if let next = job.nextRun {
                Label(t("job.nextRun", timeStr(next)), systemImage: "arrow.right.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .lineLimit(1).truncationMode(.tail)
    }

    @ViewBuilder
    private var lastRunView: some View {
        if job.pid != nil {
            Label(t("job.running"), systemImage: "play.circle.fill")
                .foregroundStyle(.green)
        } else if let last = recorded?.last {
            // Recorded — 정밀 시각 + duration (추정 아님)
            let ok = last.success
            Label {
                Text("\(rel(last.startedAt)) · \(fmtDuration(last.duration))")
            } icon: {
                Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
            }
            .foregroundStyle(ok ? .green : .red)
            .help(ok ? t("job.recorded")
                     : "\(t("status.exit", last.exitCode ?? -1)) · \(t("job.recorded"))")
        } else if let last = job.lastRunApprox {
            // Estimated — 로그 mtime 근사
            let ok = (job.lastExitCode ?? 0) == 0
            Label {
                Text(t("job.lastRun", "~" + rel(last)))
            } icon: {
                Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
            }
            .foregroundStyle(ok ? .green : .red)
            .help(ok ? t("job.estimated") : "\(t("status.exit", job.lastExitCode ?? -1)) · \(t("job.estimated"))")
        } else {
            Label(t("job.neverRun"), systemImage: "questionmark.circle")
                .foregroundStyle(.tertiary)
        }
    }

    // 최근 실행 결과 점 (오래된 것 왼쪽 → 최신 오른쪽)
    private func recentDots(_ h: JobHistory) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(h.runs.prefix(8).reversed())) { run in
                Circle()
                    .fill(run.success ? Color.green : Color.red)
                    .frame(width: 5, height: 5)
            }
        }
        .help(t("job.successRateHelp", Int((h.successRate * 100).rounded()), h.count))
    }

    private func fmtDuration(_ d: Double?) -> String {
        guard let d else { return "—" }
        if d < 1 { return String(format: "%.0fms", d * 1000) }
        if d < 60 { return String(format: "%.1fs", d) }
        if d < 3600 { return String(format: "%.0fm", d / 60) }
        return String(format: "%.1fh", d / 3600)
    }

    // 스케줄 (보조 정보)
    private var scheduleLine: some View {
        HStack(spacing: 6) {
            Label(job.scheduleText, systemImage: "calendar")
            if !job.isLoaded {
                Text("· \(t("status.unloaded"))")
            }
        }
        .font(.caption2).foregroundStyle(.secondary)
        .lineLimit(1).truncationMode(.tail)
    }

    private var statusColor: Color {
        if job.pid != nil { return .green }
        if !job.isLoaded { return .gray }
        if let code = job.lastExitCode, code != 0 { return .red }
        return .green
    }

    private var tagChips: some View {
        HStack(spacing: 4) {
            ForEach(ann.tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption2)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
            }
        }
    }

    // 우상단 아이콘 액션 바 (호버 시)
    private var iconBar: some View {
        HStack(spacing: 4) {
            iconButton("pencil", help: t("action.edit")) { beginEdit() }
            if job.isManageable {
                iconButton("play.fill", help: t("action.run")) {
                    Task { await store.runNow(job) }
                }
                iconButton("power", help: job.isLoaded ? t("action.unload") : t("action.load"),
                           tint: job.isLoaded ? .green : .secondary) {
                    Task { await store.toggleLoaded(job) }
                }
            }
            iconButton("doc.text", help: t("action.log")) { store.openLog(job) }
            iconButton("folder", help: t("action.plist")) { store.revealPlist(job) }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(.thinMaterial, in: Capsule())
        .padding(.trailing, 10).padding(.top, 4)
    }

    private func iconButton(_ system: String, help: String,
                            tint: Color = .secondary,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 12))
                .frame(width: 20, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(tint)
        .help(help)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(t("edit.name"), text: $draftName)
            TextField(t("edit.note"), text: $draftNote)
            TextField(t("edit.tags"), text: $draftTags)
            HStack {
                Spacer()
                Button(t("edit.cancel")) { editing = false }
                Button(t("edit.save")) { saveEdit() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .textFieldStyle(.roundedBorder)
        .font(.caption)
        .padding(.leading, 16).padding(.top, 2)
    }

    private func beginEdit() {
        // 아직 주석이 없으면 추론값을 기본으로 채워줌 (사용자가 확인/수정)
        draftName = ann.displayName.isEmpty ? Inference.displayName(for: job) : ann.displayName
        draftNote = ann.note
        draftTags = ann.tags.isEmpty
            ? Inference.suggestedTags(for: job).joined(separator: ", ")
            : ann.tags.joined(separator: ", ")
        editing = true
    }

    private func saveEdit() {
        let tags = draftTags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        store.setAnnotation(
            JobAnnotation(
                displayName: draftName.trimmingCharacters(in: .whitespaces),
                note: draftNote.trimmingCharacters(in: .whitespaces),
                tags: tags
            ),
            for: job.label
        )
        editing = false
    }

    private func rel(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }

    private func timeStr(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
