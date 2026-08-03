import Foundation
import Observation

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

    func job(for label: String) -> LaunchJob? { jobs.first { $0.label == label } }

    init() {
        annotations = AnnotationStore.load()
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
