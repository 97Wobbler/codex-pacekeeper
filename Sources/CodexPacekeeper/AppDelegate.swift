import AppKit
import CodexPacekeeperCore
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published private(set) var snapshot = UsageSnapshot.placeholder
    @Published private(set) var isHUDVisible: Bool = {
        if UserDefaults.standard.object(forKey: hudVisibilityDefaultsKey) == nil {
            return true
        }

        return UserDefaults.standard.bool(forKey: hudVisibilityDefaultsKey)
    }()

    private static let hudVisibilityDefaultsKey = "showsHUD"
    private let authTokenStore = CodexAuthTokenStore()
    private let usageClient = WhamUsageClient()

    private var hudPanel: NSPanel?
    private var hudHostingView: NSHostingView<HUDView>?
    private var timer: Timer?
    private var isPaused = false
    private var lastSuccessfulSnapshot: UsageSnapshot?
    private var deliveredNotificationKeys = Set<String>()
    private lazy var notificationCenter: UNUserNotificationCenter? = {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            return nil
        }

        return UNUserNotificationCenter.current()
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        createHUD()
        requestNotificationAuthorization()
        refreshUsage()
        startPolling()
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
    }

    func refreshUsage() {
        if lastSuccessfulSnapshot == nil {
            snapshot = .placeholder.withPaused(isPaused)
            updateHUD()
        }

        Task {
            await loadUsage()
        }
    }

    func setPaused(_ isPaused: Bool) {
        self.isPaused = isPaused
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
        isHUDVisible = isVisible
        UserDefaults.standard.set(isVisible, forKey: Self.hudVisibilityDefaultsKey)
        applyHUDVisibility()
    }

    private func applyHUDVisibility() {
        if isHUDVisible {
            hudPanel?.orderFrontRegardless()
        } else {
            hudPanel?.orderOut(nil)
        }
    }

    private func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(
            timeInterval: 60,
            target: self,
            selector: #selector(refreshTimerFired),
            userInfo: nil,
            repeats: true
        )
    }

    @objc private func refreshTimerFired(_ timer: Timer) {
        refreshUsage()
    }

    private func loadUsage() async {
        do {
            let token = try authTokenStore.accessToken()
            let freshSnapshot = try await usageClient.fetchSnapshot(accessToken: token)
            lastSuccessfulSnapshot = freshSnapshot
            snapshot = freshSnapshot.withPaused(isPaused)
            updateHUD()
            deliverNotificationsIfNeeded(for: snapshot)
        } catch {
            let message = friendlyMessage(for: error)

            if let lastSuccessfulSnapshot {
                snapshot = lastSuccessfulSnapshot.markingStale(message: message).withPaused(isPaused)
            } else {
                snapshot = UsageSnapshot.unavailable(message: message).withPaused(isPaused)
            }

            updateHUD()
        }
    }

    private func createHUD() {
        let view = HUDView(snapshot: snapshot)
        let hostingView = NSHostingView(rootView: view)

        let panel = NSPanel(
            contentRect: NSRect(x: 80, y: 640, width: 280, height: 120),
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
        panel.isReleasedWhenClosed = false
        panel.contentView = hostingView

        hudHostingView = hostingView
        hudPanel = panel
        applyHUDVisibility()
    }

    private func updateHUD() {
        hudHostingView?.rootView = HUDView(snapshot: snapshot)
    }

    private func requestNotificationAuthorization() {
        notificationCenter?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func deliverNotificationsIfNeeded(for snapshot: UsageSnapshot) {
        guard snapshot.state == .fresh, !snapshot.primary.isPaused else {
            return
        }

        deliverNotificationIfNeeded(for: snapshot.primary)
        deliverNotificationIfNeeded(for: snapshot.weekly)
    }

    private func deliverNotificationIfNeeded(for reading: PaceReading) {
        guard reading.status == .threshold || reading.status == .redline else {
            return
        }

        let key = "\(reading.label)-\(reading.status.rawValue)-\(Int(reading.resetAt.timeIntervalSince1970))"
        guard !deliveredNotificationKeys.contains(key) else {
            return
        }

        deliveredNotificationKeys.insert(key)

        let content = UNMutableNotificationContent()
        content.title = reading.status == .redline ? "Redline pace" : "Ease up to stay on pace"
        content.body = "\(reading.label) \(reading.deltaPercentagePoints.signedRoundedPercentPoints) · \(reading.guidance)"
        content.sound = reading.status == .redline ? .default : nil

        let request = UNNotificationRequest(
            identifier: "codex-pacekeeper-\(key)",
            content: content,
            trigger: nil
        )

        notificationCenter?.add(request)
    }

    private func friendlyMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError, let description = localizedError.errorDescription {
            return description
        }

        return error.localizedDescription
    }
}

private extension Double {
    var signedRoundedPercentPoints: String {
        let roundedValue = Int(rounded())
        return roundedValue >= 0 ? "+\(roundedValue) ahead" : "\(roundedValue) behind"
    }
}
