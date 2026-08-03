import SwiftUI

enum PadState { case launching, onDeck, queued, failed }

// 수직(기립) 로켓 8x7
let ROCKET_PIXELS = [
    "...X...",
    "..XXX..",
    "..XwX..",
    "..XXX..",
    "..XXX..",
    "..XXX..",
    ".XXXXX.",
    "X.X.X.X",
]

// 수평(눕힘) 로켓 — 노즈가 왼쪽(발사대 방향), 5x11
let HROCKET_PIXELS = [
    "....XXXXX..",
    "..XXXXXXXX.",
    "XXXXXXXXXwX",
    "..XXXXXXXX.",
    "....XXXXX..",
]

func rocketColor(_ state: PadState, t: Double) -> (body: Color, beacon: Bool) {
    switch state {
    case .onDeck:    return (Color.cyan.opacity(0.6 + 0.4 * (0.5 + 0.5 * sin(t * 4))), true)
    case .launching: return (.white, true)
    case .queued:    return (.white.opacity(0.55), Int(t * 1.5) % 2 == 0)
    case .failed:    return (Color(red: 0.85, green: 0.4, blue: 0.4), false)
    }
}

/// 메인 발사대 — 발사탑(경광등·서비스암) + 기립 로켓 + 화염 트렌치 + 발사 이펙트.
struct MainPad: View {
    let state: PadState
    private let scale: CGFloat = 4

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { tl in
            Canvas { ctx, size in draw(&ctx, size: size, t: tl.date.timeIntervalSinceReferenceDate) }
        }
        .frame(width: 52, height: 60)
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let (body, beacon) = rocketColor(state, t: t)
        let groundY = size.height - 3
        let launching = state == .launching
        let yOffset: CGFloat = launching ? -CGFloat(abs(sin(t * 7)) * 7) : 0
        let ox: CGFloat = 16                                   // 로켓 x 시작
        let rH = CGFloat(ROCKET_PIXELS.count) * scale
        let topY = groundY - rH - 2 + yOffset

        // 지면 + 화염 트렌치(로켓 아래 어두운 홈)
        ctx.fill(Path(CGRect(x: 0, y: groundY, width: size.width, height: 3)), with: .color(.white.opacity(0.18)))
        ctx.fill(Path(CGRect(x: ox + 2 * scale, y: groundY, width: 3 * scale, height: 3)), with: .color(.black.opacity(0.6)))

        // 발사탑: 2개 기둥 + 가로 렁 + 상단 경광등
        let tower = Color.white.opacity(0.30)
        ctx.fill(Path(CGRect(x: 3, y: 4, width: 2, height: groundY - 4)), with: .color(tower))
        ctx.fill(Path(CGRect(x: 11, y: 4, width: 2, height: groundY - 4)), with: .color(tower))
        for y in stride(from: 8, to: groundY - 3, by: 7) {
            ctx.fill(Path(CGRect(x: 3, y: y, width: 10, height: 2)), with: .color(tower))
        }
        // 경광등(빨강 점멸)
        if Int(t * 2) % 2 == 0 {
            ctx.fill(Path(CGRect(x: 4, y: 1, width: 4, height: 3)), with: .color(.red.opacity(0.9)))
        }
        // 서비스 암 (발사 시 후퇴)
        let armY = topY + 3 * scale
        let armEnd: CGFloat = launching ? 13 + 4 : ox + 2
        ctx.fill(Path(CGRect(x: 13, y: armY, width: max(2, armEnd - 13), height: 2)), with: .color(tower))

        // 발사 플랫폼
        ctx.fill(Path(CGRect(x: ox - 3, y: groundY - 2, width: rH * 0 + CGFloat(ROCKET_PIXELS[0].count) * scale + 6, height: 2)),
                 with: .color(.white.opacity(0.35)))

        // 로켓
        for (row, line) in ROCKET_PIXELS.enumerated() {
            for (col, ch) in line.enumerated() where ch != "." {
                let c: Color = (ch == "w") ? (beacon ? .yellow : .cyan.opacity(0.5)) : body
                ctx.fill(Path(CGRect(x: ox + CGFloat(col) * scale, y: topY + CGFloat(row) * scale,
                                     width: scale, height: scale)), with: .color(c))
            }
        }

        // 불꽃 + 발사 연기
        if launching {
            let f = Int(t * 12) % 2 == 0
            let rows = f ? ["X.X", ".X.", "X.."] : [".X.", "X.X", ".X."]
            let fy = topY + rH
            for (row, line) in rows.enumerated() {
                for (col, ch) in line.enumerated() where ch != "." {
                    let c: Color = row == 0 ? .orange : .yellow
                    ctx.fill(Path(CGRect(x: ox + 2 * scale + CGFloat(col) * scale, y: fy + CGFloat(row) * scale,
                                         width: scale, height: scale)), with: .color(c.opacity(0.95)))
                }
            }
            for k in 0..<6 {
                let sx = ox - scale + CGFloat(k) * scale
                let jitter = CGFloat((Int(t * 6) + k) % 3)
                ctx.fill(Path(CGRect(x: sx, y: groundY - 4 - jitter, width: scale, height: scale)),
                         with: .color(.white.opacity(0.22)))
            }
        }
        // 실패 연기
        if state == .failed {
            let fy = topY + rH
            for k in 0..<3 {
                let sy = fy + CGFloat(k) * scale - CGFloat((Int(t * 3) + k) % 3)
                ctx.fill(Path(CGRect(x: ox + 3 * scale, y: sy, width: scale, height: scale)),
                         with: .color(.gray.opacity(0.45 - Double(k) * 0.12)))
            }
        }
    }
}

/// 대기 태스크 — 트랜스포터에 눕혀 발사대로 이송(누리호식). 바퀴가 돌며 살짝 전진.
struct TransporterSprite: View {
    let state: PadState
    var scale: CGFloat = 2

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 10.0)) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                let (body, beacon) = rocketColor(state, t: t)
                let creep = CGFloat(sin(t * 1.1) * 1.5)          // 이송 중 살짝 전후 크립
                let cols = HROCKET_PIXELS[0].count

                for (row, line) in HROCKET_PIXELS.enumerated() {
                    for (col, ch) in line.enumerated() where ch != "." {
                        let c: Color = (ch == "w") ? (beacon ? .yellow : .cyan.opacity(0.5)) : body
                        ctx.fill(Path(CGRect(x: creep + CGFloat(col) * scale, y: CGFloat(row) * scale,
                                             width: scale, height: scale)), with: .color(c))
                    }
                }
                // 플랫베드
                let bedY = CGFloat(HROCKET_PIXELS.count) * scale
                ctx.fill(Path(CGRect(x: creep, y: bedY, width: CGFloat(cols) * scale, height: scale)),
                         with: .color(.white.opacity(0.35)))
                // 바퀴(회전)
                let turn = Int(t * 6) % 2 == 0
                for w in stride(from: 1, to: cols - 1, by: 3) {
                    let on = ((w / 3) + (turn ? 0 : 1)) % 2 == 0
                    ctx.fill(Path(CGRect(x: creep + CGFloat(w) * scale, y: bedY + scale, width: scale, height: scale)),
                             with: .color(.white.opacity(on ? 0.55 : 0.2)))
                }
            }
        }
        .frame(width: 11 * scale + 4, height: 8 * scale)
    }
}

/// 상단 발사기지 — 메인 발사대(기립) + 이송 라인(눕혀서 이동) + 전체 보기.
struct LaunchPadView: View {
    @Bindable var store: JobStore
    @State private var expanded = false
    private let queueLimit = 5

    private var jobs: [LaunchJob] { store.jobs }
    private var upcoming: [LaunchJob] {
        jobs.filter { $0.nextRun != nil }.sorted { $0.nextRun! < $1.nextRun! }
    }
    private var running: [LaunchJob] { jobs.filter { $0.pid != nil } }
    private var mainJob: LaunchJob? { running.first ?? upcoming.first }
    private var queue: [LaunchJob] { upcoming.filter { $0.label != mainJob?.label } }

    private func state(_ j: LaunchJob) -> PadState {
        if j.pid != nil { return .launching }
        if let e = store.history[j.label]?.last?.exitCode.map(Int.init) ?? j.lastExitCode, e != 0 { return .failed }
        return j.label == mainJob?.label ? .onDeck : .queued
    }
    private func name(_ j: LaunchJob) -> String {
        let a = store.annotation(for: j)
        return a.displayName.isEmpty ? Inference.displayName(for: j) : a.displayName
    }
    private func tip(_ j: LaunchJob) -> String {
        let a = store.annotation(for: j)
        return "\(name(j)) — \(a.note.isEmpty ? Inference.description(for: j) : a.note)"
    }
    private func select(_ j: LaunchJob) {
        store.selectedLabel = (store.selectedLabel == j.label) ? nil : j.label
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            starrySky
            content
        }
        .frame(height: expanded ? 130 : 82)
        .clipped()
    }

    @ViewBuilder
    private var content: some View {
        if let main = mainJob {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .bottom, spacing: 8) {
                    MainPad(state: state(main))
                        .help(tip(main))
                        .onTapGesture { select(main) }
                    if !expanded {
                        HStack(alignment: .bottom, spacing: 4) {
                            ForEach(queue.prefix(queueLimit), id: \.id) { j in
                                TransporterSprite(state: state(j))
                                    .help(tip(j))
                                    .onTapGesture { select(j) }
                            }
                            if queue.count > queueLimit {
                                Text("+\(queue.count - queueLimit)")
                                    .font(.caption2).foregroundStyle(.white.opacity(0.7))
                            }
                        }
                    }
                    Spacer()
                    Button { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } } label: {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                    }
                    .buttonStyle(.borderless).help(t("pad.seeAll"))
                }
                Text(captionText(main))
                    .font(.caption2).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                if expanded { expandedQueue }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        } else {
            Text(t("pad.none")).font(.caption).foregroundStyle(.white.opacity(0.6)).padding(12)
        }
    }

    private var expandedQueue: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(queue, id: \.id) { j in
                    VStack(spacing: 1) {
                        TransporterSprite(state: state(j)).onTapGesture { select(j) }
                        Text(name(j)).font(.system(size: 8)).foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1).frame(width: 52)
                        if let n = j.nextRun {
                            Text(countdown(n)).font(.system(size: 8, weight: .medium))
                                .foregroundStyle(.cyan.opacity(0.85))
                        }
                    }
                    .help(tip(j))
                }
            }
            .padding(.top, 2)
        }
    }

    private func captionText(_ main: LaunchJob) -> String {
        if main.pid != nil { return "\(name(main)) — \(t("job.running"))" }
        if let n = main.nextRun { return "\(t("pad.next")): \(name(main)) · T–\(countdown(n))" }
        return name(main)
    }
    private func countdown(_ date: Date) -> String {
        let s = date.timeIntervalSinceNow
        if s < 0 { return "now" }
        if s < 60 { return "\(Int(s))s" }
        if s < 3600 { return "\(Int(s / 60))m" }
        if s < 86400 { return "\(Int(s / 3600))h" }
        return "\(Int(s / 86400))d"
    }

    private var starrySky: some View {
        TimelineView(.animation(minimumInterval: 0.2)) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                let stars: [(CGFloat, CGFloat)] = [(0.1,0.2),(0.28,0.42),(0.4,0.15),(0.55,0.33),
                    (0.66,0.12),(0.75,0.4),(0.88,0.22),(0.95,0.5),(0.18,0.6),(0.48,0.58),(0.82,0.66)]
                for (i, s) in stars.enumerated() {
                    let tw = 0.3 + 0.7 * (0.5 + 0.5 * sin(t * 2 + Double(i)))
                    ctx.fill(Path(CGRect(x: size.width * s.0, y: size.height * s.1, width: 2, height: 2)),
                             with: .color(.white.opacity(tw * 0.5)))
                }
            }
        }
        .background(
            LinearGradient(colors: [Color(red: 0.03, green: 0.04, blue: 0.12),
                                    Color(red: 0.10, green: 0.12, blue: 0.24)],
                           startPoint: .top, endPoint: .bottom)
        )
    }
}
