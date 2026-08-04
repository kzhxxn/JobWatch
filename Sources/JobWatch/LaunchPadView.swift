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

/// 메인 발사대 — 넓은 기지(발사탑·서비스암·경광등·투광등·화염 트렌치) + 기립 로켓 + 리프트오프.
struct MainPad: View {
    let state: PadState
    var launchAtRef: Double?          // 발사 애니메이션 시작 시각 (timeIntervalSinceReferenceDate)
    private let scale: CGFloat = 4
    private let liftDuration = 2.6

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { tl in
            Canvas { ctx, size in draw(&ctx, size: size, t: tl.date.timeIntervalSinceReferenceDate) }
        }
        .frame(width: 88, height: 66)
        .contentShape(Rectangle())
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let (bodyBase, beacon) = rocketColor(state, t: t)
        let groundY = size.height - 3
        let ox: CGFloat = 22
        let rH = CGFloat(ROCKET_PIXELS.count) * scale
        let rw = CGFloat(ROCKET_PIXELS[0].count) * scale

        // 발사 페이즈 (0~1). launchAt이 최근이면 리프트오프.
        var phase: Double = -1
        if let la = launchAtRef {
            let p = (t - la) / liftDuration
            if p >= 0 && p <= 1 { phase = p }
        }
        let lifting = phase >= 0 || state == .launching
        let rise: CGFloat = phase >= 0
            ? CGFloat(pow(phase, 1.6)) * (groundY + rH)     // 가속 상승 → 화면 밖으로
            : (state == .launching ? CGFloat(abs(sin(t * 7)) * 6) : 0)
        let bodyAlpha = phase >= 0 ? max(0, 1 - phase * 1.1) : 1
        let body = bodyBase.opacity(bodyAlpha)
        let topY = groundY - rH - 2 - rise

        // 지면(넓게) + 화염 트렌치
        ctx.fill(Path(CGRect(x: 0, y: groundY, width: size.width, height: 3)), with: .color(.white.opacity(0.18)))
        ctx.fill(Path(CGRect(x: ox + 2 * scale, y: groundY, width: 3 * scale, height: 3)), with: .color(.black.opacity(0.6)))

        // 투광등 기둥 (좌/우 끝)
        let flood = Color.white.opacity(0.22)
        for fx in [CGFloat(1), size.width - 4] {
            ctx.fill(Path(CGRect(x: fx, y: groundY - 16, width: 2, height: 16)), with: .color(flood))
            ctx.fill(Path(CGRect(x: fx - 1, y: groundY - 18, width: 4, height: 2)), with: .color(.yellow.opacity(0.5)))
        }

        // 발사탑 (기둥2 + 렁 + 경광등)
        let tower = Color.white.opacity(0.32)
        ctx.fill(Path(CGRect(x: 9, y: 4, width: 2, height: groundY - 4)), with: .color(tower))
        ctx.fill(Path(CGRect(x: 17, y: 4, width: 2, height: groundY - 4)), with: .color(tower))
        for y in stride(from: 8, to: groundY - 3, by: 7) {
            ctx.fill(Path(CGRect(x: 9, y: y, width: 10, height: 2)), with: .color(tower))
        }
        if Int(t * 2) % 2 == 0 {
            ctx.fill(Path(CGRect(x: 10, y: 1, width: 4, height: 3)), with: .color(.red.opacity(0.9)))
        }

        // 서비스 암 (발사 시 후퇴)
        let armY = (groundY - rH - 2) + 3 * scale
        let armEnd: CGFloat = lifting ? 21 : ox + 2
        ctx.fill(Path(CGRect(x: 19, y: armY, width: max(2, armEnd - 19), height: 2)), with: .color(tower))

        // 넓은 발사 플랫폼
        ctx.fill(Path(CGRect(x: ox - 5, y: groundY - 2, width: CGFloat(ROCKET_PIXELS[0].count) * scale + 10, height: 2)),
                 with: .color(.white.opacity(0.35)))

        // 로켓 (상승 중 화면 위로 벗어나면 스킵)
        if topY + rH > -2 {
            for (row, line) in ROCKET_PIXELS.enumerated() {
                for (col, ch) in line.enumerated() where ch != "." {
                    let c: Color = (ch == "w") ? (beacon ? .yellow.opacity(bodyAlpha) : .cyan.opacity(0.5 * bodyAlpha)) : body
                    ctx.fill(Path(CGRect(x: ox + CGFloat(col) * scale, y: topY + CGFloat(row) * scale,
                                         width: scale, height: scale)), with: .color(c))
                }
            }
        }

        // 불꽃 (리프트오프/실행 중)
        if lifting {
            let f = Int(t * 14) % 2 == 0
            let len = phase >= 0 ? 4 + Int(phase * 4) : 3          // 발사 초반 화염 길어짐
            let fy = topY + rH
            for row in 0..<len {
                let w = (row % 2 == 0) ? "X.X" : ".X."
                for (col, ch) in w.enumerated() where ch != "." {
                    let c: Color = row < 2 ? .orange : .yellow
                    ctx.fill(Path(CGRect(x: ox + 2 * scale + CGFloat(col) * scale, y: fy + CGFloat(row) * scale,
                                         width: scale, height: scale)), with: .color(c.opacity(f ? 0.95 : 0.7)))
                }
            }
            // 발사 연기 구름 (지면에 넓게 퍼짐)
            let spread = phase >= 0 ? Int(4 + phase * 8) : 6
            for k in 0..<spread {
                let sx = ox + CGFloat(ROCKET_PIXELS[0].count) * scale / 2 - CGFloat(spread) * scale / 2 + CGFloat(k) * scale
                let jitter = CGFloat((Int(t * 6) + k) % 3)
                ctx.fill(Path(CGRect(x: sx, y: groundY - 4 - jitter, width: scale, height: scale)),
                         with: .color(.white.opacity(0.2)))
            }
        }
        // 실패 잡: 대기 중엔 연기, 발사하면 공중 폭발 💥
        if state == .failed {
            if phase < 0 {
                let fy = topY + rH
                for k in 0..<3 {
                    let sy = fy + CGFloat(k) * scale - CGFloat((Int(t * 3) + k) % 3)
                    ctx.fill(Path(CGRect(x: ox + 3 * scale, y: sy, width: scale, height: scale)),
                             with: .color(.gray.opacity(0.45 - Double(k) * 0.12)))
                }
            } else if phase >= 0.45 {
                let ep = (phase - 0.45) / 0.55            // 폭발 진행 0..1
                let cx = ox + rw / 2
                let cy = topY + rH / 2
                for k in 0..<12 {                          // 사방으로 파편
                    let ang = Double(k) / 12 * 2 * .pi
                    let dist = CGFloat(ep) * 24
                    let px = cx + CGFloat(cos(ang)) * dist
                    let py = cy + CGFloat(sin(ang)) * dist
                    let c: Color = k % 3 == 0 ? .orange : (k % 3 == 1 ? .red : .gray)
                    ctx.fill(Path(CGRect(x: px, y: py, width: scale, height: scale)),
                             with: .color(c.opacity(1 - ep)))
                }
                if ep < 0.35 {                             // 섬광
                    let r = 6 + ep * 20
                    ctx.fill(Path(CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                             with: .color(.orange.opacity(0.55 * (1 - ep / 0.35))))
                }
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
        .contentShape(Rectangle())
    }
}

/// 상단 발사기지 — 메인 발사대(기립) + 이송 라인(눕혀서 이동) + 전체 보기.
struct LaunchPadView: View {
    @Bindable var store: JobStore
    @State private var expanded = false

    private var jobs: [LaunchJob] { store.jobs }
    private var upcoming: [LaunchJob] {
        jobs.filter { $0.nextRun != nil }.sorted { $0.nextRun! < $1.nextRun! }
    }
    // 발사대는 예약 잡 전용 — 실행 중인 "예약" 잡(nextRun 있음) 우선, 없으면 다음 예약.
    // 데몬(nextRun 없음)은 여기 안 옴 → 궤도(orbit)로 감.
    private var mainJob: LaunchJob? {
        jobs.first { $0.pid != nil && $0.nextRun != nil } ?? upcoming.first
    }
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
            baseFloor
            content
            orbitLayer          // 위에 얹어 위성 클릭 가능 (빈 영역은 통과)
        }
        .frame(height: expanded ? 130 : 92)
        .clipped()
    }

    // 상시 데몬 = 실행 중(pid)인데 예약 시각 없음 → 이미 궤도에 올라 도는 위성
    private var orbiters: [LaunchJob] {
        jobs.filter { $0.pid != nil && $0.nextRun == nil }
    }

    // 위성 = 태스크(데몬). 제자리에서 작게 도는 궤도 + 호버 툴팁 + 클릭 상세.
    private var orbitLayer: some View {
        GeometryReader { geo in
            let sats = Array(orbiters.prefix(8).enumerated())
            let n = max(1, sats.count)
            TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                ForEach(sats, id: \.element.id) { i, j in
                    let anchorX = geo.size.width * (0.08 + 0.84 * (Double(i) + 0.5) / Double(n))
                    let ph = Double(i) * 1.3
                    SatelliteDot(daemon: name(j))
                        .help(tip(j))
                        .onTapGesture { select(j) }
                        .position(x: anchorX + cos(t * 0.8 + ph) * 6,
                                  y: 13 + sin(t * 0.8 + ph) * 4)
                }
            }
        }
        .frame(height: 30)
    }

    // 전체 폭 기지 바닥 + 원경 구조물 (정적, 애니메이션 불필요 → 저비용)
    private var baseFloor: some View {
        Canvas { ctx, size in
            let g = size.height - 9
            ctx.fill(Path(CGRect(x: 0, y: g, width: size.width, height: 9)), with: .color(.white.opacity(0.05)))
            ctx.fill(Path(CGRect(x: 0, y: g, width: size.width, height: 1)), with: .color(.white.opacity(0.15)))
            let structs: [(CGFloat, CGFloat, CGFloat)] = [(0.60,0.5,6),(0.70,0.8,4),(0.80,0.45,5),(0.90,0.65,4),(0.97,0.4,3)]
            for s in structs {
                let h = size.height * 0.22 * s.1
                ctx.fill(Path(CGRect(x: size.width * s.0, y: g - h, width: s.2, height: h)),
                         with: .color(.white.opacity(0.08)))
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let main = mainJob {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .bottom, spacing: 8) {
                    MainPad(state: state(main),
                            launchAtRef: store.launchAt[main.label]?.timeIntervalSinceReferenceDate)
                        .help(tip(main))
                        .onTapGesture { select(main) }
                    if !expanded {
                        // 공간에 맞게 최대한 채우기 (잘리지 않는 개수만큼) + 카운트다운으로 상단 여백 채움
                        GeometryReader { geo in
                            let slot: CGFloat = 46           // 트랜스포터(scale3) 37 + 간격
                            let n = max(1, Int(geo.size.width / slot))
                            HStack(alignment: .bottom, spacing: 9) {
                                ForEach(queue.prefix(n), id: \.id) { j in
                                    VStack(spacing: 2) {
                                        Spacer(minLength: 0)
                                        if let nn = j.nextRun {
                                            Text(countdown(nn))
                                                .font(.system(size: 9, weight: .semibold))
                                                .foregroundStyle(.cyan.opacity(0.9))
                                        }
                                        TransporterSprite(state: state(j), scale: 3)
                                    }
                                    .help(tip(j))
                                    .onTapGesture { select(j) }
                                }
                                if queue.count > n {
                                    Text("+\(queue.count - n)")
                                        .font(.caption2).foregroundStyle(.white.opacity(0.7))
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(maxHeight: .infinity, alignment: .bottom)
                        }
                        .frame(height: 56)
                    } else {
                        Spacer()
                    }
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
        let s = date.timeIntervalSince(store.tick)         // 공유 틱 기준 → 목록과 동기화
        if s < 0 { return "now" }
        if s < 86400 {                                    // 24h 이내 → 시:분:초 카운트다운
            let n = Int(s)
            return String(format: "%d:%02d:%02d", n / 3600, (n % 3600) / 60, n % 60)
        }
        return date.formatted(date: .numeric, time: .omitted)   // 넘어가면 연월일
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

/// 궤도 위성 = 상시 데몬 태스크. 작게 그린 도트(본체+태양전지판+안테나), 호버·클릭용 히트영역 확보.
struct SatelliteDot: View {
    let daemon: String
    var body: some View {
        Canvas { ctx, _ in
            ctx.fill(Path(CGRect(x: 0, y: 6, width: 4, height: 2)), with: .color(.cyan.opacity(0.8)))
            ctx.fill(Path(CGRect(x: 12, y: 6, width: 4, height: 2)), with: .color(.cyan.opacity(0.8)))
            ctx.fill(Path(CGRect(x: 6, y: 4, width: 4, height: 5)), with: .color(.white.opacity(0.9)))
            ctx.fill(Path(CGRect(x: 7, y: 1, width: 1, height: 3)), with: .color(.white.opacity(0.6)))
        }
        .frame(width: 16, height: 14)
        .contentShape(Rectangle())
    }
}
