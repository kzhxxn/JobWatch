import SwiftUI

struct ContentView: View {
    @Bindable var store: JobStore
    // 잡 생성 폼 상태
    @State private var creating = false
    @State private var draftName = ""
    @State private var draftCommand = ""
    @State private var schedType = 0        // 0 주기 / 1 매일 / 2 매주
    @State private var intervalMin = 10
    @State private var timeOfDay = Date()
    @State private var weekday = 1
    @State private var expandedRun: Int64?   // 상세 이력에서 펼친 실행의 출력
    // AI 잡 생성
    @State private var aiPrompt = ""
    @State private var aiBusy = false
    @State private var aiProviderName: String?
    @State private var jobPendingDelete: LaunchJob?

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
            return sortByNext ? g.sorted { byNext($0, $1) } : g.sorted { $0.label < $1.label }
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
                switch store.sceneStyle {
                case .launchpad: LaunchPadView(store: store)
                case .orbit:     OrbitBoardView(store: store)
                }
            }
            header
            Divider()
            if creating {
                createForm                          // 새 잡 생성 폼
            } else if let label = store.selectedLabel, let job = store.job(for: label) {
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
        .frame(width: 440)
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
        .task {
            // AI provider(claude/codex) 조기 감지 — 생성 게이트용
            aiProviderName = await Task.detached { AIProvider.available() }.value
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
        .frame(minHeight: 480, maxHeight: 640)
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

    // 새 잡 생성 폼 (runner 경유로 생성 → 처음부터 정밀 추적)
    private var createForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Button { creating = false } label: {
                    Label(t("detail.back"), systemImage: "chevron.left").font(.caption)
                }.buttonStyle(.borderless)

                Text(t("create.title")).font(.headline)

                // AI로 만들기 — claude/codex 감지 시
                if let provider = aiProviderName {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(t("create.aiWith", provider), systemImage: "sparkles")
                            .font(.caption).foregroundStyle(.tint)
                        HStack(spacing: 6) {
                            TextField(t("create.aiPh"), text: $aiPrompt).textFieldStyle(.roundedBorder)
                            Button(action: generateWithAI) {
                                if aiBusy { ProgressView().controlSize(.small) }
                                else { Text(t("create.generate")) }
                            }
                            .disabled(aiPrompt.isEmpty || aiBusy)
                        }
                        Text(t("create.aiHint")).font(.caption2).foregroundStyle(.tertiary)
                    }
                    Divider()
                } else {
                    Text(t("create.noProvider")).font(.caption2).foregroundStyle(.tertiary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(t("create.name")).font(.caption).foregroundStyle(.secondary)
                    TextField(t("create.namePh"), text: $draftName).textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(t("create.command")).font(.caption).foregroundStyle(.secondary)
                    TextField(t("create.commandPh"), text: $draftCommand).textFieldStyle(.roundedBorder)
                }

                Picker("", selection: $schedType) {
                    Text(t("create.interval")).tag(0)
                    Text(t("create.daily")).tag(1)
                    Text(t("create.weekly")).tag(2)
                }.pickerStyle(.segmented).labelsHidden()

                if schedType == 0 {
                    HStack(spacing: 6) {
                        Text(t("create.every"))
                        TextField("", value: $intervalMin, format: .number)
                            .frame(width: 46).textFieldStyle(.roundedBorder)
                        Text(t("create.minutes"))
                    }.font(.caption)
                } else {
                    if schedType == 2 {
                        Picker(t("create.weekday"), selection: $weekday) {
                            ForEach(0..<7, id: \.self) { i in Text(t("weekday.\(i)")).tag(i) }
                        }.font(.caption)
                    }
                    DatePicker(t("create.at"), selection: $timeOfDay, displayedComponents: .hourAndMinute)
                        .font(.caption)
                }

                HStack {
                    Spacer()
                    Button(t("create.cancel")) { creating = false }
                    Button(t("create.create")) { submitCreate() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(draftName.isEmpty || draftCommand.isEmpty)
                }
            }
            .padding(12)
        }
        .frame(minHeight: 480, maxHeight: 640)
        .task { aiProviderName = await Task.detached { AIProvider.available() }.value }
    }

    private func generateWithAI() {
        let req = aiPrompt
        aiBusy = true
        Task {
            let result = await Task.detached { AIProvider.generate(request: req) }.value
            aiBusy = false
            switch result {
            case .ok(let d):
                draftName = d.name
                draftCommand = d.command
                switch d.schedule {
                case .interval(let m):
                    schedType = 0; intervalMin = m
                case .daily(let h, let mi):
                    schedType = 1; timeOfDay = timeFrom(h, mi)
                case .weekly(let wd, let h, let mi):
                    schedType = 2; weekday = wd; timeOfDay = timeFrom(h, mi)
                }
            case .fail(let msg):
                store.lastMessage = msg
            }
        }
    }

    private func timeFrom(_ h: Int, _ m: Int) -> Date {
        Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date()
    }

    private func submitCreate() {
        let cal = Calendar.current
        let h = cal.component(.hour, from: timeOfDay)
        let m = cal.component(.minute, from: timeOfDay)
        let sched: JobSchedule
        switch schedType {
        case 1: sched = .daily(hour: h, minute: m)
        case 2: sched = .weekly(weekday: weekday, hour: h, minute: m)
        default: sched = .interval(minutes: max(1, intervalMin))
        }
        let name = draftName, command = draftCommand
        Task {
            await store.createJob(name: name, command: command, schedule: sched)
            creating = false
            draftName = ""; draftCommand = ""
        }
    }

    // 드릴인 상세 (목록 자리 위로 슬라이드, ← 뒤로)
    private func detailView(_ job: LaunchJob) -> some View {
        let ann = store.annotation(for: job)
        let title = ann.displayName.isEmpty ? Inference.displayName(for: job) : ann.displayName
        let desc = ann.note.isEmpty ? Inference.description(for: job) : ann.note
        let h = store.history[job.label]
        return ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button { store.selectedLabel = nil } label: {
                        Label(t("detail.back"), systemImage: "chevron.left").font(.caption)
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                    if job.isManageable {
                        if jobPendingDelete?.id == job.id {
                            // 팝오버 안 인라인 확인 (alert는 메뉴바 팝오버를 닫아버림)
                            Text(t("detail.deleteConfirm")).font(.caption).foregroundStyle(.red)
                            Button(t("detail.delete"), role: .destructive) {
                                jobPendingDelete = nil
                                Task { await store.deleteJob(job) }
                            }.font(.caption)
                            Button(t("create.cancel")) { jobPendingDelete = nil }.font(.caption)
                        } else {
                            Button(role: .destructive) { jobPendingDelete = job } label: {
                                Image(systemName: "trash").font(.caption)
                            }
                            .buttonStyle(.borderless).help(t("detail.delete"))
                        }
                    }
                }

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
                // 정밀 추적(runner 경유) 토글 — 사용자 잡만
                if job.isManageable {
                    Toggle(isOn: Binding(
                        get: { job.isTracked },
                        set: { on in Task { on ? await store.adopt(job) : await store.unadopt(job) } }
                    )) {
                        Text(t("detail.preciseTracking")).font(.caption)
                    }
                    .toggleStyle(.switch).controlSize(.mini)
                    .help(t("detail.preciseTrackingHelp"))
                }
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
        .frame(minHeight: 480, maxHeight: 640)
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
                Text(t("detail.history")).font(.caption).bold().foregroundStyle(.secondary)
                ForEach(h.runs.prefix(10)) { run in
                    VStack(alignment: .leading, spacing: 2) {
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
                            Image(systemName: expandedRun == run.id ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8)).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { expandedRun = (expandedRun == run.id) ? nil : run.id }
                        if expandedRun == run.id { runOutput(run) }
                    }
                }
            }
        } else {
            Text(t("detail.noHistory")).font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // 한 실행의 상세 — 시작/종료/소요/exit + 캡처된 출력(stdout/stderr)
    private func runOutput(_ run: JobRun) -> some View {
        let out = (run.stdoutTail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let err = (run.stderrTail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let text = [out, err].filter { !$0.isEmpty }.joined(separator: "\n— stderr —\n")
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Label(run.startedAt.formatted(date: .omitted, time: .standard), systemImage: "play.fill")
                if let e = run.endedAt {
                    Label(e.formatted(date: .omitted, time: .standard), systemImage: "stop.fill")
                }
                Label(fmtDur(run.duration), systemImage: "timer")
                if let e = run.exitCode {
                    Text("exit \(e)").foregroundStyle(e == 0 ? .green : .red)
                }
            }
            .font(.system(size: 9)).foregroundStyle(.secondary)
            // 이중 스크롤 방지 — 바깥 상세 스크롤이 처리 (출력은 8KB 꼬리라 유한)
            Text(text.isEmpty ? t("detail.noOutput") : text)
                .font(.system(size: 9, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(6)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 4))
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
                // 새 잡 생성 — AI provider 없으면 설정 안내 팝업
                Button {
                    if aiProviderName != nil { creating = true }
                    else { store.lastMessage = t("setup.message") }
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless).help(t("create.title"))
                // 씬 스타일 전환 (발사대 픽셀 ↔ 궤도 기하학) — 비교용
                if store.showScene {
                    Button {
                        store.sceneStyle = store.sceneStyle == .launchpad ? .orbit : .launchpad
                    } label: {
                        Image(systemName: store.sceneStyle == .launchpad
                              ? "circle.hexagongrid" : "rectangle.grid.1x2")
                    }
                    .buttonStyle(.borderless).help(t("scene.toggle"))
                }
                // 씬 접기/펼치기
                Button { store.showScene.toggle() } label: {
                    Image(systemName: store.showScene ? "eye" : "eye.slash")
                }
                .buttonStyle(.borderless).help(t("scene.hide"))
                Button {
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help(t("header.refresh"))
                // 설정
                Menu {
                    Toggle(t("settings.launchAtLogin"), isOn: $store.launchAtLogin)
                    Toggle(t("settings.showScene"), isOn: $store.showScene)
                } label: {
                    Image(systemName: "gearshape")
                }
                .menuStyle(.borderlessButton).fixedSize()
                .help(t("settings.title"))
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

/// 간소화된 한 줄 행 — 상태점 · 종류 아이콘 · 이름 · 시각 · 화살표. 탭하면 상세로.
