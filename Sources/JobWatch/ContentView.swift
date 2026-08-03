import SwiftUI

struct ContentView: View {
    @Bindable var store: JobStore

    var userJobs: [LaunchJob] { store.jobs.filter { $0.domain == .userAgent } }
    var globalJobs: [LaunchJob] { store.jobs.filter { $0.domain == .globalAgent } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
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

            if let msg = store.lastMessage {
                Divider()
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.horizontal, 12).padding(.vertical, 6)
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

    // "언제" — 마지막 실행(색으로 성공/실패) + 다음 실행. 가독성 최우선 줄.
    private var whenLine: some View {
        HStack(spacing: 12) {
            lastRunView
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
        } else if let last = job.lastRunApprox {
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
