import AppKit
import CodexPacekeeperCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published private(set) var snapshot = UsageSnapshot.placeholder

    private var hudPanel: NSPanel?
    private var hudHostingView: NSHostingView<HUDView>?
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        createHUD()
        startPolling()
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
    }

    func refreshUsage() {
        // API polling will replace this with real usage data in the next milestone.
        snapshot = .placeholder
        updateHUD()
    }

    func setPaused(_ isPaused: Bool) {
        snapshot = snapshot.withPaused(isPaused)

        if isPaused {
            timer?.invalidate()
            timer = nil
        } else {
            startPolling()
        }

        updateHUD()
    }

    func setHUDVisible(_ isVisible: Bool) {
        if isVisible {
            hudPanel?.orderFrontRegardless()
        } else {
            hudPanel?.orderOut(nil)
        }
    }

    private func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refreshUsage()
        }
    }

    private func createHUD() {
        let view = HUDView(snapshot: snapshot)
        let hostingView = NSHostingView(rootView: view)

        let panel = NSPanel(
            contentRect: NSRect(x: 80, y: 640, width: 280, height: 84),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = hostingView
        panel.orderFrontRegardless()

        hudHostingView = hostingView
        hudPanel = panel
    }

    private func updateHUD() {
        hudHostingView?.rootView = HUDView(snapshot: snapshot)
    }
}
