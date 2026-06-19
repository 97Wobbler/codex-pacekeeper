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
    private let usageHistoryStore = UsageHistoryStore()

    private var hudPanel: NSPanel?
    private var hudHostingView: NSHostingView<HUDView>?
    private var demoPanels: [NSPanel] = []
    private weak var menuBarState: MenuBarState?
    private var timer: Timer?
    private var isPaused = false
    private var isHUDExpanded = false
    private var wantsHUDExpanded = false
    private var hudTransitionGeneration = 0
    private var hudFrameAnimationTimer: Timer?
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
        hudFrameAnimationTimer?.invalidate()
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

    func setMenuBarState(_ menuBarState: MenuBarState) {
        self.menuBarState = menuBarState
        if menuBarState.snapshot != snapshot {
            menuBarState.snapshot = snapshot
        }
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
        let view = makeHUDView()
        let hostingView = HUDHostingView(rootView: view)
        hostingView.applyTransparentBackground()
        hostingView.onHoverChanged = { [weak self] isHovered in
            Task { @MainActor [weak self] in
                self?.setHUDExpanded(isHovered)
            }
        }
        let panel = makeHUDPanel(frame: notchHUDFrame(size: currentHUDSize), hostingView: hostingView)

        hudHostingView = hostingView
        hudPanel = panel
        applyHUDVisibility()
    }

    private func createDemoHUDs() {
        let snapshots = DemoUsageSnapshots.make()
        let layout = fallbackHUDLayout()
        let panelSize = layout.expandedSize
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 900, height: 800)
        let startX = visibleFrame.minX + 80
        var y = visibleFrame.maxY - panelSize.height - 60

        demoPanels = snapshots.map { snapshot in
            let panel = makeHUDPanel(
                frame: NSRect(x: startX, y: y, width: panelSize.width, height: panelSize.height),
                hostingView: HUDHostingView(rootView: HUDView(
                    snapshot: snapshot,
                    isExpanded: true,
                    layout: layout
                ))
            )
            panel.orderFrontRegardless()
            y -= panelSize.height + 14
            return panel
        }
    }

    private func makeHUDPanel(frame: NSRect, hostingView: HUDHostingView) -> NSPanel {
        let panel = NotchHUDPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.contentView = hostingView

        return panel
    }

    private func notchHUDFrame(size: NSSize) -> NSRect {
        guard let screen = currentHUDScreen() else {
            return NSRect(x: 80, y: 640, width: size.width, height: size.height)
        }

        let size = pixelAligned(size, for: screen)
        let centerX = notchCenterX(for: screen) ?? screen.frame.midX

        return NSRect(
            x: centerX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    private func updateHUD() {
        hudHostingView?.rootView = makeHUDView()
        menuBarState?.snapshot = snapshot
    }

    private var currentHUDSize: NSSize {
        let layout = currentHUDLayout()
        return isHUDExpanded ? layout.expandedSize : layout.compactSize
    }

    private func resizeHUDPanel(to targetSize: NSSize, animated: Bool) {
        guard let panel = hudPanel else {
            return
        }

        guard panel.frame.size != targetSize else {
            return
        }

        let frame = notchHUDFrame(size: targetSize)

        if animated {
            animateHUDPanel(to: targetSize)
        } else {
            hudFrameAnimationTimer?.invalidate()
            hudFrameAnimationTimer = nil
            panel.setFrame(frame, display: true)
        }
    }

    private func animateHUDPanel(to targetSize: NSSize) {
        guard let panel = hudPanel else {
            return
        }

        hudFrameAnimationTimer?.invalidate()

        let startSize = panel.frame.size
        let startDate = Date()
        let duration: TimeInterval = 0.16

        let animationTimer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self, weak panel] timer in
            Task { @MainActor [weak self, weak panel] in
                guard let self, let panel else {
                    timer.invalidate()
                    return
                }

                let elapsed = Date().timeIntervalSince(startDate)
                let progress = min(max(elapsed / duration, 0), 1)
                let easedProgress = 1 - pow(1 - progress, 3)
                let size = NSSize(
                    width: startSize.width + (targetSize.width - startSize.width) * easedProgress,
                    height: startSize.height + (targetSize.height - startSize.height) * easedProgress
                )

                panel.setFrame(self.notchHUDFrame(size: size), display: true)

                if progress >= 1 {
                    panel.setFrame(self.notchHUDFrame(size: targetSize), display: true)
                    timer.invalidate()
                    if self.hudFrameAnimationTimer === timer {
                        self.hudFrameAnimationTimer = nil
                    }
                }
            }
        }
        RunLoop.main.add(animationTimer, forMode: .common)
        hudFrameAnimationTimer = animationTimer
    }

    private func makeHUDView() -> HUDView {
        HUDView(snapshot: snapshot, isExpanded: isHUDExpanded, layout: currentHUDLayout())
    }

    private func currentHUDScreen() -> NSScreen? {
        NSScreen.main ?? NSScreen.screens.first
    }

    private func currentHUDLayout() -> NotchHUDLayout {
        guard let screen = currentHUDScreen() else {
            return fallbackHUDLayout()
        }

        return NotchHUDLayout(
            notchWidth: notchWidth(for: screen),
            topInset: screen.safeAreaInsets.top
        )
    }

    private func fallbackHUDLayout() -> NotchHUDLayout {
        NotchHUDLayout(notchWidth: nil, topInset: 32)
    }

    private func notchWidth(for screen: NSScreen) -> CGFloat? {
        guard
            let leftArea = screen.auxiliaryTopLeftArea,
            let rightArea = screen.auxiliaryTopRightArea
        else {
            return nil
        }

        let gapWidth = rightArea.minX - leftArea.maxX
        return gapWidth > 0 ? gapWidth : nil
    }

    private func notchCenterX(for screen: NSScreen) -> CGFloat? {
        guard
            let leftArea = screen.auxiliaryTopLeftArea,
            let rightArea = screen.auxiliaryTopRightArea
        else {
            return nil
        }

        let gapWidth = rightArea.minX - leftArea.maxX
        guard gapWidth > 0 else {
            return nil
        }

        return leftArea.maxX + gapWidth / 2
    }

    private func pixelAligned(_ size: NSSize, for screen: NSScreen) -> NSSize {
        let scale = max(screen.backingScaleFactor, 1)
        return NSSize(
            width: (size.width * scale).rounded() / scale,
            height: (size.height * scale).rounded() / scale
        )
    }

    private func setHUDExpanded(_ isExpanded: Bool) {
        guard wantsHUDExpanded != isExpanded else {
            return
        }

        wantsHUDExpanded = isExpanded
        hudTransitionGeneration += 1
        let transitionGeneration = hudTransitionGeneration
        let layout = currentHUDLayout()

        if isExpanded {
            self.isHUDExpanded = true
            updateHUD()
            resizeHUDPanel(to: layout.expandedSize, animated: true)
            return
        }

        resizeHUDPanel(to: layout.compactSize, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            Task { @MainActor [weak self] in
                guard
                    let self,
                    self.hudTransitionGeneration == transitionGeneration,
                    !self.wantsHUDExpanded
                else {
                    return
                }

                self.isHUDExpanded = false
                self.updateHUD()
            }
        }
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

private final class NotchHUDPanel: NSPanel {}

private final class HUDHostingView: NSHostingView<HUDView> {
    var onHoverChanged: ((Bool) -> Void)?
    private var hoverTrackingArea: NSTrackingArea?

    func applyTransparentBackground() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func updateTrackingAreas() {
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea

        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }
}

private extension Double {
    var signedRoundedPercentPoints: String {
        let roundedValue = Int(rounded())
        return roundedValue >= 0 ? "+\(roundedValue) ahead" : "\(roundedValue) behind"
    }
}
