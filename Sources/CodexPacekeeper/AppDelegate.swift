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
    private static let hudOriginXDefaultsKey = "hudOriginX"
    private static let hudOriginYDefaultsKey = "hudOriginY"
    private let authTokenStore = CodexAuthTokenStore()
    private let usageClient = WhamUsageClient()
    private let usageHistoryStore = UsageHistoryStore()

    private var hudPanel: NSPanel?
    private var hudHostingView: NSHostingView<HUDView>?
    private var demoPanels: [NSPanel] = []
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

        if CommandLine.arguments.contains("--demo-huds") {
            createDemoHUDs()
            return
        }

        createHUD()
        requestNotificationAuthorization()
        refreshUsage()
        startPolling()
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        NotificationCenter.default.removeObserver(self)
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
            recordUsageSample(for: freshSnapshot)
            let trendedSnapshot = freshSnapshot.withTrend(usageTrend(now: freshSnapshot.lastRefreshedAt))
            lastSuccessfulSnapshot = trendedSnapshot
            snapshot = trendedSnapshot.withPaused(isPaused)
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

    private func usageTrend(now: Date) -> UsageTrend? {
        do {
            return try usageHistoryStore.recentTrend(now: now)
        } catch {
            NSLog("Codex Pacekeeper failed to load usage trend: \(error.localizedDescription)")
            return nil
        }
    }

    private func recordUsageSample(for snapshot: UsageSnapshot) {
        do {
            try usageHistoryStore.record(UsageSample(snapshot: snapshot))
        } catch {
            NSLog("Codex Pacekeeper failed to record usage sample: \(error.localizedDescription)")
        }
    }

    private func createHUD() {
        let view = HUDView(snapshot: snapshot)
        let hostingView = DraggableHUDHostingView(rootView: view)
        let panel = makeHUDPanel(frame: initialHUDFrame(), hostingView: hostingView)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hudPanelDidMove),
            name: NSWindow.didMoveNotification,
            object: panel
        )

        hudHostingView = hostingView
        hudPanel = panel
        applyHUDVisibility()
    }

    private func createDemoHUDs() {
        let snapshots = DemoUsageSnapshots.make()
        let panelSize = NSSize(width: 280, height: 120)
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 900, height: 800)
        let startX = visibleFrame.minX + 80
        var y = visibleFrame.maxY - panelSize.height - 60

        demoPanels = snapshots.map { snapshot in
            let panel = makeHUDPanel(
                frame: NSRect(x: startX, y: y, width: panelSize.width, height: panelSize.height),
                hostingView: DraggableHUDHostingView(rootView: HUDView(snapshot: snapshot))
            )
            panel.orderFrontRegardless()
            y -= panelSize.height + 14
            return panel
        }
    }

    private func makeHUDPanel(frame: NSRect, hostingView: DraggableHUDHostingView) -> NSPanel {
        let panel = DraggableHUDPanel(
            contentRect: frame,
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
        panel.isMovableByWindowBackground = true
        panel.contentView = hostingView

        return panel
    }

    private func initialHUDFrame() -> NSRect {
        let size = NSSize(width: 280, height: 120)

        if
            UserDefaults.standard.object(forKey: Self.hudOriginXDefaultsKey) != nil,
            UserDefaults.standard.object(forKey: Self.hudOriginYDefaultsKey) != nil
        {
            return NSRect(
                x: UserDefaults.standard.double(forKey: Self.hudOriginXDefaultsKey),
                y: UserDefaults.standard.double(forKey: Self.hudOriginYDefaultsKey),
                width: size.width,
                height: size.height
            )
        }

        if let visibleFrame = NSScreen.main?.visibleFrame {
            return NSRect(
                x: visibleFrame.minX + 80,
                y: visibleFrame.maxY - size.height - 80,
                width: size.width,
                height: size.height
            )
        }

        return NSRect(x: 80, y: 640, width: size.width, height: size.height)
    }

    @objc private func hudPanelDidMove(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel else {
            return
        }

        UserDefaults.standard.set(panel.frame.origin.x, forKey: Self.hudOriginXDefaultsKey)
        UserDefaults.standard.set(panel.frame.origin.y, forKey: Self.hudOriginYDefaultsKey)
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

private final class DraggableHUDPanel: NSPanel {}

private final class DraggableHUDHostingView: NSHostingView<HUDView> {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

private extension Double {
    var signedRoundedPercentPoints: String {
        let roundedValue = Int(rounded())
        return roundedValue >= 0 ? "+\(roundedValue) ahead" : "\(roundedValue) behind"
    }
}
