import SwiftUI
import AppKit

@main
struct JobWatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = JobStore()

    var body: some Scene {
        MenuBarExtra {
            ContentView(store: store)
        } label: {
            // 문제 있는 잡이 있으면 느낌표 배지 아이콘
            Image(systemName: store.problemCount > 0
                  ? "clock.badge.exclamationmark"
                  : "clock.badge.checkmark")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Dock 아이콘 없이 메뉴바 전용으로 동작하도록 activation policy 설정.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
