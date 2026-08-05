import Foundation
import Observation
import ServiceManagement
import UserNotifications

/// 앱 전역 상태. 스캔은 백그라운드에서, 갱신은 메인 액터에서.
@MainActor
@Observable
final class JobStore {
    var jobs: [LaunchJob] = []
    var disk: DiskInfo = DiskInfo(totalBytes: 0, freeBytes: 0)
    var lastRefresh: Date?
    var isRefreshing = false
    var lastMessage: String?

    // 사용자 주석 (별명·설명·태그)
    var annotations: [String: JobAnnotation] = [:]

    // runner가 기록한 정밀 실행 이력 (label → history)
    var history: [String: JobHistory] = [:]

    // 발사대에서 클릭해 선택한 잡 (하단 상세 표시용)
    var selectedLabel: String?

    // 상단 발사대 씬 표시 여부(접기) — UserDefaults에 저장
    var showScene: Bool = (UserDefaults.standard.object(forKey: "showScene") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(showScene, forKey: "showScene") }
    }

    // 로그인 시 자동 시작 (SMAppService)
    var launchAtLogin: Bool = (SMAppService.mainApp.status == .enabled) {
        didSet {
            do {
                if launchAtLogin { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                lastMessage = "자동 시작 설정 실패: \(error.localizedDescription)"
            }
        }
    }

    // 모든 카운트다운이 공유하는 1초 틱 (목록 ↔ 발사대 동기화)
    var tick = Date()
    private var firedFor: [String: Date] = [:]   // 이미 발사 애니 재생한 nextRun 값

    // 하단 콘솔용 시스템 지표 (1초마다 샘플)
    var vitals = SystemVitals()
    private let sampler = SystemSampler()
    var runningCount: Int { jobs.filter { $0.pid != nil }.count }
    var jobLoad: Double { jobs.isEmpty ? 0 : Double(runningCount) / Double(jobs.count) }

    // 메뉴바 아이콘 애니메이션 조건: 실행 중이거나 최근 3초 내 발사 감지
    var isActive: Bool {
        if runningCount > 0 { return true }
        let now = Date()
        return launchAt.values.contains { now.timeIntervalSince($0) < 3 }
    }

    /// 1초마다 호출 — 틱 갱신 + 카운트다운 0 도달 시 발사 애니 트리거
    func advanceTick() {
        let now = Date()
        tick = now
        vitals = sampler.sample()
        for j in jobs {
            guard let nr = j.nextRun, nr <= now, firedFor[j.label] != nr else { continue }
            firedFor[j.label] = nr
            launchAt[j.label] = now
        }
        launchAt = launchAt.filter { now.timeIntervalSince($0.value) < 5 }
    }

    // 실제 실패한 잡 = 로드됐는데 마지막 종료코드 ≠ 0 (로드 안 됨은 실패 아님)
    func isFailing(_ j: LaunchJob) -> Bool {
        guard j.isLoaded, j.pid == nil else { return false }   // 실행 중이면 실패 아님
        let e = history[j.label]?.last?.exitCode.map(Int.init) ?? j.lastExitCode
        return (e ?? 0) != 0
    }
    var failureCount: Int { jobs.filter(isFailing).count }

    // 실패 알림 — 새 실패로 바뀔 때 1회만 (첫 스캔에선 알림 안 함)
    private var notifiedExit: [String: Int] = [:]
    private var failNotifReady = false

    private func checkFailureNotifications() {
        for j in jobs {
            let e = history[j.label]?.last?.exitCode.map(Int.init) ?? j.lastExitCode
            if isFailing(j), let code = e {
                if failNotifReady && notifiedExit[j.label] != code {
                    notifyFailure(job: j, code: code)
                }
                notifiedExit[j.label] = code
            } else {
                notifiedExit[j.label] = nil   // 정상/실행 중 → 다음 실패 때 다시 알림
            }
        }
        failNotifReady = true
    }

    private func notifyFailure(job: LaunchJob, code: Int) {
        let a = annotations[job.label]
        let name = (a?.displayName.isEmpty == false) ? a!.displayName : Inference.displayName(for: job)
        let content = UNMutableNotificationContent()
        content.title = "JobWatch"
        content.body = t("notif.failed", name, code)
        content.sound = .default
        let req = UNNotificationRequest(identifier: "fail-\(job.label)-\(code)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    // 최근 발사 감지 (label → 애니메이션 시작 시각). 짧은 잡도 놓치지 않게 이력/mtime 변화로 감지.
    var launchAt: [String: Date] = [:]
    private var lastSeenStart: [String: Date] = [:]
    private var launchDetectionInited = false

    func job(for label: String) -> LaunchJob? { jobs.first { $0.label == label } }

    private func detectLaunches() {
        let now = Date()
        var seen = lastSeenStart
        for j in jobs {
            guard let start = history[j.label]?.last?.startedAt ?? j.lastRunApprox else { continue }
            if launchDetectionInited, let prev = lastSeenStart[j.label], start > prev {
                launchAt[j.label] = now                     // 새 실행 감지 → 발사 애니메이션 시작
            }
            seen[j.label] = start
        }
        lastSeenStart = seen
        launchDetectionInited = true
        launchAt = launchAt.filter { now.timeIntervalSince($0.value) < 5 }   // 오래된 건 정리
    }

    // 정밀 추적(adopt)한 잡의 원본 인자 백업
    var adopted: [String: [String]] = AdoptStore.load()
    func isAdopted(_ job: LaunchJob) -> Bool { adopted[job.label] != nil }

    init() {
        annotations = AnnotationStore.load()
    }

    func createJob(name: String, command: String, schedule: JobSchedule) async {
        guard RunnerInstall.installIfNeeded() else { lastMessage = "runner 설치 실패"; return }
        let runner = RunnerInstall.installedPath
        let (label, msg) = await Task.detached {
            JobCreator.create(name: name, command: command, schedule: schedule, runner: runner)
        }.value
        if let label { setAnnotation(JobAnnotation(displayName: name), for: label) }
        lastMessage = msg
        await refresh()
    }

    func deleteJob(_ job: LaunchJob) async {
        guard job.isManageable else { lastMessage = "시스템 잡은 삭제 불가"; return }
        let plist = job.plistPath, label = job.label
        let (ok, msg) = await Task.detached { () -> (Bool, String) in
            let uid = getuid()
            Launchd.run("/bin/launchctl", ["bootout", "gui/\(uid)", plist])
            do { try FileManager.default.removeItem(atPath: plist); return (true, "삭제됨: \(label)") }
            catch { return (false, "삭제 실패: \(error.localizedDescription)") }
        }.value
        if ok {
            annotations[label] = nil; AnnotationStore.save(annotations)
            adopted[label] = nil; AdoptStore.save(adopted)
            if selectedLabel == label { selectedLabel = nil }
        }
        lastMessage = msg
        await refresh()
    }

    func adopt(_ job: LaunchJob) async {
        guard job.isManageable else { lastMessage = "시스템 잡은 정밀 추적 불가"; return }
        guard !job.isTracked else { return }
        guard RunnerInstall.installIfNeeded() else { lastMessage = "runner 설치 실패"; return }
        let plist = job.plistPath, label = job.label
        let original = job.programArguments
        let runner = RunnerInstall.installedPath
        let (ok, msg) = await Task.detached {
            LaunchdEdit.adopt(plistPath: plist, label: label, runner: runner, original: original)
        }.value
        if ok { adopted[label] = original; AdoptStore.save(adopted) }
        lastMessage = msg
        await refresh()
    }

    func unadopt(_ job: LaunchJob) async {
        // 백업이 있으면 그걸로, 없어도 job.programArguments는 이미 래퍼가 벗겨진 원본 명령
        let original = adopted[job.label] ?? job.programArguments
        guard !original.isEmpty else { return }
        let plist = job.plistPath
        let (ok, msg) = await Task.detached {
            LaunchdEdit.revert(plistPath: plist, original: original)
        }.value
        if ok { adopted[job.label] = nil; AdoptStore.save(adopted) }
        lastMessage = msg
        await refresh()
    }

    func annotation(for job: LaunchJob) -> JobAnnotation {
        annotations[job.label] ?? JobAnnotation()
    }

    func setAnnotation(_ ann: JobAnnotation, for label: String) {
        if ann.isEmpty {
            annotations[label] = nil
        } else {
            annotations[label] = ann
        }
        AnnotationStore.save(annotations)
    }

    func refresh() async {
        isRefreshing = true
        let scanned = await Task.detached(priority: .userInitiated) {
            Launchd.scanAll()
        }.value
        let disk = await Task.detached(priority: .utility) {
            DiskInfo.current()
        }.value
        let hist = await Task.detached(priority: .utility) {
            RunStore.loadAll()
        }.value
        self.jobs = scanned
        self.disk = disk
        self.history = hist
        detectLaunches()
        checkFailureNotifications()
        self.lastRefresh = Date()
        self.isRefreshing = false
    }

    // MARK: - 액션 (실행 후 상태 재조회)

    func runNow(_ job: LaunchJob) async {
        let (out, status) = await Task.detached { Launchd.kickstart(job.label) }.value
        report(status: status, ok: t("msg.ran", job.label), fail: out)
        await refresh()
    }

    func toggleLoaded(_ job: LaunchJob) async {
        let wasLoaded = job.isLoaded
        let plist = job.plistPath
        let (out, status) = await Task.detached {
            wasLoaded ? Launchd.unload(plist) : Launchd.load(plist)
        }.value
        report(status: status, ok: t(wasLoaded ? "msg.unloadedOk" : "msg.loadedOk", job.label), fail: out)
        await refresh()
    }

    func revealPlist(_ job: LaunchJob) {
        Launchd.revealInFinder(job.plistPath)
    }

    func openLog(_ job: LaunchJob) {
        if let log = job.stdoutPath ?? job.stderrPath {
            Launchd.openFile(log)
        } else {
            lastMessage = t("msg.noLog")
        }
    }

    private func report(status: Int32, ok: String, fail: String) {
        lastMessage = status == 0 ? ok : t("msg.failed", status, fail.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var healthyCount: Int { jobs.filter(\.healthy).count }
    var problemCount: Int { jobs.filter { !$0.healthy }.count }
}
