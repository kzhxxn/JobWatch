import SwiftUI

/// 기하학 "궤도 보드" — 앱/메뉴바 아이콘과 통일된 선형 스타일.
/// 예약 잡은 카운트다운 동안 궤도 바깥에서 중심(발사점)으로 접근 → T–0(합/일식)에 발사.
/// 성공 = 중심 플래시 후 바깥 궤도로 리셋, 실패 = 붉은 흩어짐. 데몬 = 바깥 궤도 회전 위성.
struct OrbitBoardView: View {
    @Bindable var store: JobStore

    private let horizon: Double = 24 * 3600   // 이 시간 이상 남으면 최외곽에 고정

    private var jobs: [LaunchJob] { store.jobs }
    private var upcoming: [LaunchJob] {
        jobs.filter { $0.nextRun != nil }.sorted { $0.nextRun! < $1.nextRun! }
    }
    private var daemons: [LaunchJob] { jobs.filter { $0.pid != nil && $0.nextRun == nil } }
    private var mainJob: LaunchJob? {
        jobs.first { $0.pid != nil && $0.nextRun != nil } ?? upcoming.first
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
    /// 발사 진행도 0~1 (launchAt 감지 후 1.4초, 중심→바깥 복귀). nil이면 발사 애니 아님.
    private func launchP(_ j: LaunchJob, _ now: Date) -> Double? {
        if let la = store.launchAt[j.label] {
            let p = now.timeIntervalSince(la) / 1.4
            if p >= 0 && p <= 1 { return p }
        }
        return nil
    }
    private func isRunning(_ j: LaunchJob) -> Bool { j.pid != nil }
    /// 카운트다운 → 반지름 비율(0=중심, 1=최외곽). 남은시간 클수록 바깥.
    private func radiusFrac(_ j: LaunchJob, _ now: Date) -> Double {
        guard let n = j.nextRun else { return 1 }
        let s = max(0, n.timeIntervalSince(now))
        return min(1, s / horizon)
    }

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width, H = geo.size.height
            let cx = W / 2, cy = H * 0.46
            let maxA = W * 0.42, maxB = H * 0.40
            TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { tl in
                let now = Date()
                let t = tl.date.timeIntervalSinceReferenceDate
                ZStack {
                    orbitCanvas(cx: cx, cy: cy, maxA: maxA, maxB: maxB, now: now, t: t)
                    ForEach(upcoming.prefix(10), id: \.id) { j in
                        approachingDot(j, cx: cx, cy: cy, maxA: maxA, maxB: maxB, now: now, t: t)
                    }
                    ForEach(Array(daemons.prefix(8).enumerated()), id: \.element.id) { i, j in
                        daemonDot(j, i: i, cx: cx, cy: cy, maxA: maxA, maxB: maxB, t: t)
                    }
                    if let m = mainJob {
                        VStack { Spacer()
                            Text(caption(m)).font(.caption2)
                                .foregroundStyle(.white.opacity(0.8)).lineLimit(1).padding(.bottom, 4)
                        }
                    }
                }
            }
        }
        .frame(height: 120)
        .background(LinearGradient(colors: [Color(red: 0.03, green: 0.04, blue: 0.12),
                                            Color(red: 0.08, green: 0.10, blue: 0.20)],
                                   startPoint: .top, endPoint: .bottom))
    }

    // 궤도 링 + 중심 노드 + 발사(일식) 플래시
    private func orbitCanvas(cx: CGFloat, cy: CGFloat, maxA: CGFloat, maxB: CGFloat,
                             now: Date, t: Double) -> some View {
        Canvas { ctx, _ in
            for f in [1.0, 0.72, 0.44] {
                let a = maxA * f, b = maxB * f
                ctx.stroke(Path(ellipseIn: CGRect(x: cx - a, y: cy - b, width: 2*a, height: 2*b)),
                           with: .color(.cyan.opacity(0.10)), lineWidth: 1)
            }
            // 실제 발사 순간(launchAt)에만 짧게 터지는 링 파동 — 상시 안 뜨게
            var flash = 0.0, fail = false
            for j in jobs {
                if let la = store.launchAt[j.label] {
                    let p = now.timeIntervalSince(la) / 1.4
                    if p >= 0 && p <= 1 {
                        flash = max(flash, 1 - p)
                        if store.isFailing(j) { fail = true }
                    }
                }
            }
            if flash > 0.01 {
                let col: Color = fail ? .red : .cyan
                // 퍼지는 얇은 링(파동)
                let r = 8 + CGFloat(1 - flash) * 30
                ctx.stroke(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2*r, height: 2*r)),
                           with: .color(col.opacity(0.6 * flash)), lineWidth: 2)
                // 중심 코어 글로우
                let g = 5 + CGFloat(flash) * 6
                ctx.fill(Path(ellipseIn: CGRect(x: cx - g, y: cy - g, width: 2*g, height: 2*g)),
                         with: .color(col.opacity(0.5 * flash)))
            }
            // 중심 노드(홈) — 은은한 시안 코어
            ctx.fill(Path(ellipseIn: CGRect(x: cx - 5, y: cy - 5, width: 10, height: 10)),
                     with: .color(.cyan.opacity(0.25)))
            ctx.fill(Path(ellipseIn: CGRect(x: cx - 3, y: cy - 3, width: 6, height: 6)),
                     with: .color(.white.opacity(0.9)))
        }
        .allowsHitTesting(false)
    }

    // 예약 잡 — 카운트다운 반지름으로 중심 접근, 발사 시 성공/실패 연출
    @ViewBuilder
    private func approachingDot(_ j: LaunchJob, cx: CGFloat, cy: CGFloat,
                               maxA: CGFloat, maxB: CGFloat, now: Date, t: Double) -> some View {
        // 각 잡 고유 각도 (label 해시로 분산). 화면상 반시계(-)로 통일.
        let baseAng = -(Double(abs(j.label.hashValue) % 360) * .pi / 180 + t * 0.15)
        let failing = store.isFailing(j)
        let lp = launchP(j, now)

        // 반지름: 평소=카운트다운, 발사 중이면 중심(0)→바깥으로 튕겨 리셋
        let frac: Double = lp.map { pow($0, 0.7) } ?? radiusFrac(j, now)
        let a = maxA * CGFloat(frac), b = maxB * CGFloat(frac)
        let x = cx + a * CGFloat(cos(baseAng))
        let y = cy + b * CGFloat(sin(baseAng))

        let active = lp != nil || isRunning(j)
        let color: Color = failing ? .red
            : (active ? .cyan : (j.label == mainJob?.label ? .cyan.opacity(0.85) : .white.opacity(0.8)))
        let sz: CGFloat = j.label == mainJob?.label ? 9 : 7
        let pulse: CGFloat = active ? CGFloat(1 + 0.35 * sin(t * 6)) : 1

        Circle().fill(color)
            .frame(width: sz * pulse, height: sz * pulse)
            .position(x: x, y: y)
            .help(tip(j))
            .onTapGesture { select(j) }
    }

    // 데몬 — 최외곽 궤도를 도는 위성
    @ViewBuilder
    private func daemonDot(_ j: LaunchJob, i: Int, cx: CGFloat, cy: CGFloat,
                          maxA: CGFloat, maxB: CGFloat, t: Double) -> some View {
        let ang = -(t * 0.4 + Double(i) * (2 * .pi / Double(max(daemons.count, 1))))  // 화면 반시계
        let x = cx + maxA * CGFloat(cos(ang)), y = cy + maxB * CGFloat(sin(ang))
        Circle().fill(.white.opacity(0.5))
            .frame(width: 4, height: 4)
            .position(x: x, y: y)
            .help(tip(j))
            .onTapGesture { select(j) }
    }

    private func caption(_ m: LaunchJob) -> String {
        if m.pid != nil { return "\(name(m)) — \(t("job.running"))" }
        if let n = m.nextRun { return "\(t("pad.next")): \(name(m)) · T–\(countdown(n))" }
        return name(m)
    }
    private func countdown(_ date: Date) -> String {
        let s = date.timeIntervalSince(store.tick)
        if s < 0 { return "now" }
        if s < 86400 { let n = Int(s); return String(format: "%d:%02d:%02d", n/3600, (n%3600)/60, n%60) }
        return date.formatted(date: .numeric, time: .omitted)
    }
}
