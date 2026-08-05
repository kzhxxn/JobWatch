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
            Image(nsImage: JobWatchApp.barIcon(alert: store.failureCount > 0))
        }
        .menuBarExtraStyle(.window)
    }

    /// 메뉴바용 도트 로켓 — template NSImage라 다크/라이트 자동 적응. 실패 있으면 빨강.
    static func barIcon(alert: Bool) -> NSImage {
        let s: CGFloat = 2
        let cols = ROCKET_PIXELS[0].count, rows = ROCKET_PIXELS.count
        let img = NSImage(size: NSSize(width: CGFloat(cols) * s, height: CGFloat(rows) * s))
        img.lockFocus()
        (alert ? NSColor.systemRed : NSColor.black).setFill()
        for (r, line) in ROCKET_PIXELS.enumerated() {
            for (c, ch) in line.enumerated() where ch != "." {
                let y = CGFloat(rows - 1 - r) * s
                NSBezierPath(rect: NSRect(x: CGFloat(c) * s, y: y, width: s, height: s)).fill()
            }
        }
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
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}
