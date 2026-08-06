import SwiftUI
import AppKit
import UserNotifications

@main
struct JobWatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = JobStore()

    var body: some Scene {
        MenuBarExtra {
            ContentView(store: store)
        } label: {
            // store.iconPhase가 활동 중 140ms마다 바뀌며 라벨 재렌더 → 발사 애니메이션
            Image(nsImage: JobWatchApp.barIcon(phase: store.iconPhase,
                                               active: store.isActive,
                                               alert: store.failureCount > 0))
        }
        .menuBarExtraStyle(.window)
    }

    /// 메뉴바용 기하학 궤도 마크 (앱 아이콘과 통일) — 링 + 중심 노드 + 궤도 점.
    /// 활동 중이면 점이 궤도를 돈다. template라 다크/라이트 적응, 실패 있으면 빨강.
    static func barIcon(phase: Int, active: Bool, alert: Bool) -> NSImage {
        let size: CGFloat = 18
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()
        let color = alert ? NSColor.systemRed : NSColor.black
        color.setStroke(); color.setFill()
        let c = size / 2
        let R: CGFloat = 6.5
        // 궤도 링
        let ring = NSBezierPath(ovalIn: NSRect(x: c - R, y: c - R, width: 2 * R, height: 2 * R))
        ring.lineWidth = 1.6
        ring.stroke()
        // 중심 노드(홈)
        let cd: CGFloat = 1.8
        NSBezierPath(ovalIn: NSRect(x: c - cd, y: c - cd, width: 2 * cd, height: 2 * cd)).fill()
        // 궤도 점 — 활동 중이면 회전, 아니면 상단 고정
        let ang = active ? Double(phase) * 0.55 + .pi / 2 : .pi / 2
        let od: CGFloat = 2.4
        let ox = c + R * CGFloat(cos(ang)), oy = c + R * CGFloat(sin(ang))
        NSBezierPath(ovalIn: NSRect(x: ox - od, y: oy - od, width: 2 * od, height: 2 * od)).fill()
        img.unlockFocus()
        img.isTemplate = !alert
        return img
    }
}

/// Dock 아이콘 없이 메뉴바 전용으로 동작하도록 activation policy 설정.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        RunnerInstall.installIfNeeded()      // 러너를 안정 경로로 설치
        // 알림 권한 요청 — 완료 핸들러가 백그라운드 스레드로 오는데 MainActor 격리로 추론되면
        // Swift 6 동시성 런타임이 SIGTRAP(신규 유저 첫 실행 크래시). 비격리 async로 안전하게.
        Task.detached {
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        }
    }
}
