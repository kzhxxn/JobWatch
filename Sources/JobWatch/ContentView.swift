import SwiftUI

struct ContentView: View {
    @Bindable var store: JobStore

    var userJobs: [LaunchJob] { store.jobs.filter { $0.domain == .userAgent } }
    var globalJobs: [LaunchJob] { store.jobs.filter { $0.domain == .globalAgent } }

    // 종류별 섹션 (로드된 잡을 kind로 분류) + 비활성
    private struct JobSection: Identifiable { let id: String; let color: Color; let jobs: [LaunchJob] }

    private var sections: [JobSection] {
        // 실패(문제) 잡은 종류 무관하게 맨 위 별도 섹션으로
        let loaded = store.jobs.filter { $0.isLoaded && !store.isFailing($0) }
        let failing = store.jobs.filter { store.isFailing($0) }.sorted { $0.label < $1.label }
        func byNext(_ a: LaunchJob, _ b: LaunchJob) -> Bool {
            switch (a.nextRun, b.nextRun) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.label < b.label
            }
        }
        func group(_ k: JobKind, sortByNext: Bool = false) -> [LaunchJob] {
            let g = loaded.filter { $0.kind == k }
            return sortByNext ? g.sorted(by: byNext) : g.sorted { $0.label < $1.label }
        }
        var out: [JobSection] = []
        if !failing.isEmpty { out.append(.init(id: t("section.issues"), color: .red, jobs: failing)) }
        let scheduled = group(.scheduled, sortByNext: true)
        if !scheduled.isEmpty { out.append(.init(id: t("kind.scheduled"), color: .green, jobs: scheduled)) }
        let daemon = group(.daemon)
        if !daemon.isEmpty { out.append(.init(id: t("kind.daemon"), color: .green, jobs: daemon)) }
        let watch = group(.watch)
        if !watch.isEmpty { out.append(.init(id: t("kind.watch"), color: .blue, jobs: watch)) }
        let once = group(.onceAtLogin)
        if !once.isEmpty { out.append(.init(id: t("kind.once"), color: .blue, jobs: once)) }
        let manual = group(.manual)
        if !manual.isEmpty { out.append(.init(id: t("kind.manual"), color: .gray, jobs: manual)) }
        let inactive = store.jobs.filter { !$0.isLoaded }.sorted { $0.label < $1.label }
        if !inactive.isEmpty { out.append(.init(id: t("section.inactive"), color: .gray, jobs: inactive)) }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.showScene {
                LaunchPadView(store: store)
            }
            header
            Divider()
            if let label = store.selectedLabel, let job = store.job(for: label) {
                detailView(job)                     // 드릴인 상세
            } else {
                if let msg = store.lastMessage { messageBanner(msg) }
                jobList                             // 간소화 그룹 목록
            }
            Divider()
            consoleStrip                            // 하단 시스템 콘솔
            Divider()
            footer
        }
        .frame(width: 380)
        .task {
            while !Task.isCancelled {
                await store.refresh()
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .task {
            // 공유 1초 틱 — 카운트다운 동기화 + 발사 트리거
            while !Task.isCancelled {
                store.advanceTick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var jobList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                if store.jobs.isEmpty {
                    Text(t("empty")).foregroundStyle(.secondary).padding()
                }
                ForEach(sections) { sec in
                    groupHeader(sec.id, sec.jobs.count, sec.color)
                    ForEach(sec.jobs) { CondensedRow(job: $0, store: store) }
                }
            }
            .padding(.vertical, 6)
        }
        .frame(maxHeight: 420)
    }

    private func groupHeader(_ title: String, _ count: Int, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title).font(.caption).bold().foregroundStyle(.secondary)
            Text("\(count)").font(.caption2).foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 2)
    }

    // 드릴인 상세 (목록 자리 위로 슬라이드, ← 뒤로)
    private func detailView(_ job: LaunchJob) -> some View {
        let ann = store.annotation(for: job)
        let title = ann.displayName.isEmpty ? Inference.displayName(for: job) : ann.displayName
        let desc = ann.note.isEmpty ? Inference.description(for: job) : ann.note
        let h = store.history[job.label]
        return ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Button { store.selectedLabel = nil } label: {
                    Label(t("detail.back"), systemImage: "chevron.left").font(.caption)
                }
                .buttonStyle(.borderless)

                HStack(spacing: 6) {
                    Image(systemName: Inference.category(for: job).icon).foregroundStyle(.tint)
                    Text(title).font(.headline).lineLimit(2)
                }
                Text(desc).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text(job.label).font(.caption2).foregroundStyle(.tertiary).textSelection(.enabled)
                HStack(spacing: 10) {
                    Label(job.scheduleText, systemImage: "calendar")
                    if let n = job.nextRun { Label(fmtTime(n), systemImage: "arrow.right.circle") }
                }.font(.caption).foregroundStyle(.secondary)
                // 마지막 종료 상태 (실행 중이면 상태, 아니면 종료 코드)
                lastStatusLine(job, h)
                runHistorySection(h)
                Divider().padding(.vertical, 2)
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
        }
        .frame(maxHeight: 440)
    }

    // 마지막 종료 상태 — 실행 중 / 정상 종료 / 실패(exit N)
    @ViewBuilder
    private func lastStatusLine(_ job: LaunchJob, _ h: JobHistory?) -> some View {
        if job.pid != nil {
            Label(t("job.running"), systemImage: "play.circle.fill")
                .font(.caption).foregroundStyle(.green)
        } else if let e = h?.last?.exitCode.map(Int.init) ?? job.lastExitCode {
            Label(t("detail.lastExit", e),
                  systemImage: e == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(e == 0 ? .green : .red)
        }
    }

    // 실행 시간 히스토리 (SQLite 기록) — 없으면 안내
    @ViewBuilder
    private func runHistorySection(_ h: JobHistory?) -> some View {
        if let h, !h.runs.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    ForEach(Array(h.runs.prefix(14).reversed())) { run in
                        Circle().fill(run.success ? Color.green : Color.red).frame(width: 7, height: 7)
                    }
                    Text(t("job.successRateHelp", Int((h.successRate * 100).rounded()), h.count))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Text(t("detail.history")).font(.caption).bold().foregroundStyle(.secondary).padding(.top, 2)
                ForEach(h.runs.prefix(10)) { run in
                    HStack(spacing: 6) {
                        Image(systemName: run.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.caption2).foregroundStyle(run.success ? .green : .red)
                        Text(run.startedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2).monospacedDigit()
                        Spacer()
                        if let e = run.exitCode, e != 0 {
                            Text("exit \(e)").font(.caption2).foregroundStyle(.red)
                        }
                        Text(fmtDur(run.duration)).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
        } else {
            Text(t("detail.noHistory")).font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
                // 발사대 씬 접기/펼치기
                Button { store.showScene.toggle() } label: {
                    Image(systemName: store.showScene ? "eye" : "eye.slash")
                }
                .buttonStyle(.borderless).help("발사기지 표시/숨김")
                Button {
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help(t("header.refresh"))
            }
            // 잡 건강 바 (히어로) — 실패 비율 빨강 / 나머지 초록
            healthBar
            Text(t("header.jobsSummary", store.jobs.count, store.healthyCount, store.failureCount))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
    }

    private var healthBar: some View {
        let total = max(store.jobs.count, 1)
        let fail = store.failureCount
        return GeometryReader { geo in
            HStack(spacing: 2) {
                if fail > 0 {
                    Capsule().fill(.red)
                        .frame(width: max(6, geo.size.width * Double(fail) / Double(total)))
                }
                Capsule().fill(.green.opacity(0.65))
            }
        }
        .frame(height: 6)
    }

    // 하단 미션컨트롤 콘솔 — CPU·MEM·DISK·실행중 잡수
    private var consoleStrip: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(t("section.system")).font(.caption).bold().foregroundStyle(.secondary)
            HStack(spacing: 14) {
                segGauge("CPU", store.vitals.cpu).frame(maxWidth: .infinity)
                segGauge("MEM", store.vitals.mem).frame(maxWidth: .infinity)
                segGauge("DISK", store.vitals.diskFraction).frame(maxWidth: .infinity)
                segGauge("JOB", store.jobLoad, countLabel: "\(store.runningCount)", tint: .blue)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func segGauge(_ label: String, _ value: Double,
                          countLabel: String? = nil, tint: Color? = nil) -> some View {
        let segs = 8
        let filled = min(segs, max(0, Int((value * Double(segs)).rounded())))
        let color = tint ?? (value < 0.6 ? Color.green : (value < 0.85 ? Color.yellow : Color.red))
        return VStack(spacing: 3) {
            HStack(spacing: 2) {
                ForEach(0..<segs, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(i < filled ? color : Color.secondary.opacity(0.18))
                        .frame(height: 9)
                        .frame(maxWidth: .infinity)      // 셀 너비를 꽉 채움
                }
            }
            HStack(spacing: 3) {
                Text(label).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                Text(countLabel ?? "\(Int(value * 100))%")
                    .font(.system(size: 9)).monospacedDigit().foregroundStyle(.secondary)
            }
        }
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

/// 간소화된 한 줄 행 — 상태점 · 종류 아이콘 · 이름 · 시각 · 화살표. 탭하면 상세로.
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
