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
    @Published private(set) var isHUDCollapsed: Bool = UserDefaults.standard.bool(forKey: hudCollapsedDefaultsKey)
    @Published private(set) var hudOpacity: Double = {
        if UserDefaults.standard.object(forKey: hudOpacityDefaultsKey) == nil {
            return defaultHUDOpacity
        }

        return normalizedHUDOpacity(UserDefaults.standard.double(forKey: hudOpacityDefaultsKey))
    }()
    @Published private(set) var hudDisplayMode: HUDDisplayMode = {
        guard
            let rawValue = UserDefaults.standard.string(forKey: HUDDisplayMode.defaultsKey),
            let displayMode = HUDDisplayMode(rawValue: rawValue)
        else {
            return .notchIsland
        }

        return displayMode
    }()

    private static let hudVisibilityDefaultsKey = "showsHUD"
    private static let hudCollapsedDefaultsKey = "hudCollapsed"
    private static let hudOpacityDefaultsKey = "hudOpacity"
    private static let hudOriginXDefaultsKey = "hudOriginX"
    private static let hudOriginYDefaultsKey = "hudOriginY"
    private static let defaultHUDOpacity = 1.0
    private static let minHUDOpacity = 0.35
    private static let maxHUDOpacity = 1.0
    private let authTokenStore = CodexAuthTokenStore()
    private let usageClient = WhamUsageClient()
    private let usageHistoryStore = UsageHistoryStore()

    private var hudPanel: NSPanel?
    private var hudHostingView: HUDHostingView?
    private var demoPanels: [NSPanel] = []
    private weak var menuBarState: MenuBarState?
    private var timer: Timer?
    private var isPaused = false
    private var isHUDExpanded = false
    private var isNotchPanelExpanded = false
    private var wantsHUDExpanded = false
    private var hudFrameAnimationTimer: Timer?
    private var notchCollapseTimer: Timer?
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        requestNotificationAuthorization()
        refreshUsage()
        startPolling()
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        hudFrameAnimationTimer?.invalidate()
        notchCollapseTimer?.invalidate()
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

    func setHUDDisplayMode(_ displayMode: HUDDisplayMode) {
        guard hudDisplayMode != displayMode else {
            return
        }

        if hudDisplayMode == .floating, let hudPanel {
            persistHUDOrigin(hudPanel.frame.origin)
        }

        hudDisplayMode = displayMode
        UserDefaults.standard.set(displayMode.rawValue, forKey: HUDDisplayMode.defaultsKey)
        isHUDExpanded = false
        isNotchPanelExpanded = false
        wantsHUDExpanded = false
        hudFrameAnimationTimer?.invalidate()
        hudFrameAnimationTimer = nil
        notchCollapseTimer?.invalidate()
        notchCollapseTimer = nil

        configureHUDPanelForCurrentMode()
        updateHUD()
        resizeHUDPanel(to: currentHUDSize, animated: displayMode == .floating, reposition: true)
        applyHUDVisibility()
    }

    func setHUDCollapsed(_ isCollapsed: Bool) {
        isHUDCollapsed = isCollapsed
        UserDefaults.standard.set(isCollapsed, forKey: Self.hudCollapsedDefaultsKey)

        guard hudDisplayMode == .floating else {
            return
        }

        updateHUD()
        resizeHUDPanel(to: currentHUDSize, animated: true)
    }

    func setHUDOpacity(_ opacity: Double) {
        let normalizedOpacity = Self.normalizedHUDOpacity(opacity)
        hudOpacity = normalizedOpacity
        UserDefaults.standard.set(normalizedOpacity, forKey: Self.hudOpacityDefaultsKey)
        applyHUDOpacity()
    }

    func setMenuBarState(_ menuBarState: MenuBarState) {
        self.menuBarState = menuBarState
        if menuBarState.snapshot != snapshot {
            menuBarState.snapshot = snapshot
        }
    }

    private func applyHUDVisibility() {
        if isHUDVisible {
            applyHUDOpacity()
            hudPanel?.orderFrontRegardless()
        } else {
            hudPanel?.orderOut(nil)
        }
    }

    private func applyHUDOpacity() {
        hudPanel?.alphaValue = hudDisplayMode == .floating ? CGFloat(hudOpacity) : 1
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
        let panel = makeHUDPanel(frame: currentHUDFrame(size: currentHUDSize, reposition: true), hostingView: hostingView)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hudPanelDidMove),
            name: NSWindow.didMoveNotification,
            object: panel
        )

        hudHostingView = hostingView
        hudPanel = panel
        configureHUDPanelForCurrentMode()
        applyHUDVisibility()
    }

    private func createDemoHUDs() {
        let snapshots = DemoUsageSnapshots.make()
        let layout = fallbackHUDLayout()
        let panelSize = demoHUDSize(layout: layout)
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 900, height: 800)
        let startX = visibleFrame.minX + 80
        var y = visibleFrame.maxY - panelSize.height - 60

        demoPanels = snapshots.map { snapshot in
            let hostingView = HUDHostingView(rootView: HUDView(
                snapshot: snapshot,
                displayMode: hudDisplayMode,
                isNotchExpanded: true,
                notchLayout: layout,
                isFloatingCollapsed: false
            ))
            hostingView.applyTransparentBackground()
            let panel = makeHUDPanel(
                frame: NSRect(x: startX, y: y, width: panelSize.width, height: panelSize.height),
                hostingView: hostingView
            )
            panel.orderFrontRegardless()
            y -= panelSize.height + 14
            return panel
        }
    }

    private func makeHUDPanel(frame: NSRect, hostingView: HUDHostingView) -> NSPanel {
        let panel = PaceHUDPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 1, height: 1)
        panel.contentMinSize = NSSize(width: 1, height: 1)
        hostingView.frame = NSRect(origin: .zero, size: frame.size)
        panel.contentView = hostingView
        panel.setFrame(frame, display: false)
        configureHUDPanel(panel, hostingView: hostingView)

        return panel
    }

    private func configureHUDPanelForCurrentMode() {
        guard let panel = hudPanel, let hudHostingView else {
            return
        }

        configureHUDPanel(panel, hostingView: hudHostingView)
    }

    private func configureHUDPanel(_ panel: NSPanel, hostingView: HUDHostingView) {
        switch hudDisplayMode {
        case .notchIsland:
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.hasShadow = false
            panel.isMovableByWindowBackground = false
            hostingView.canDragWindow = false
        case .floating:
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hasShadow = true
            panel.isMovableByWindowBackground = true
            hostingView.canDragWindow = true
        }

        panel.alphaValue = hudDisplayMode == .floating ? CGFloat(hudOpacity) : 1
    }

    private func demoHUDSize(layout: NotchHUDLayout) -> NSSize {
        switch hudDisplayMode {
        case .notchIsland:
            return layout.expandedSize
        case .floating:
            return FloatingHUDLayout.expandedSize
        }
    }

    private func currentHUDFrame(size: NSSize, reposition: Bool = false) -> NSRect {
        switch hudDisplayMode {
        case .notchIsland:
            return notchHUDFrame(size: size)
        case .floating:
            return floatingHUDFrame(size: size, reposition: reposition)
        }
    }

    private func notchHUDFrame(size: NSSize) -> NSRect {
        guard let screen = currentHUDScreen() else {
            return NSRect(x: 80, y: 640, width: size.width, height: size.height)
        }

        let size = pixelAligned(size, for: screen)
        let centerX = notchCenterX(for: screen) ?? screen.frame.midX
        let frame = NSRect(
            x: centerX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )

        return pixelAligned(frame, for: screen)
    }

    private func floatingHUDFrame(size: NSSize, reposition: Bool) -> NSRect {
        if !reposition, let hudPanel {
            return resizedFloatingHUDFrame(size: size, currentFrame: hudPanel.frame)
        }

        if
            UserDefaults.standard.object(forKey: Self.hudOriginXDefaultsKey) != nil,
            UserDefaults.standard.object(forKey: Self.hudOriginYDefaultsKey) != nil
        {
            let savedOrigin = NSPoint(
                x: UserDefaults.standard.double(forKey: Self.hudOriginXDefaultsKey),
                y: UserDefaults.standard.double(forKey: Self.hudOriginYDefaultsKey)
            )

            return constrainedHUDFrame(NSRect(
                x: savedOrigin.x,
                y: savedOrigin.y,
                width: size.width,
                height: size.height
            ), visibleFrame: bestVisibleFrame(for: savedOrigin))
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

    private func resizedFloatingHUDFrame(size: NSSize, currentFrame: NSRect) -> NSRect {
        var frame = currentFrame
        let maxY = frame.maxY
        frame.size = size
        frame.origin.y = maxY - size.height
        return constrainedHUDFrame(frame, visibleFrame: hudPanel?.screen?.visibleFrame)
    }

    @objc private func hudPanelDidMove(_ notification: Notification) {
        guard hudDisplayMode == .floating, let panel = notification.object as? NSPanel else {
            return
        }

        persistHUDOrigin(panel.frame.origin)
    }

    @objc private func screenParametersDidChange(_ notification: Notification) {
        guard hudDisplayMode == .notchIsland else {
            return
        }

        updateHUD()
        resizeHUDPanel(to: currentHUDSize, animated: false, reposition: true)
    }

    private func constrainedHUDFrame(_ frame: NSRect, visibleFrame: NSRect? = nil) -> NSRect {
        guard let visibleFrame = visibleFrame ?? bestVisibleFrame(for: frame.origin) else {
            return frame
        }

        var constrainedFrame = frame
        if constrainedFrame.maxX > visibleFrame.maxX {
            constrainedFrame.origin.x = visibleFrame.maxX - constrainedFrame.width
        }
        if constrainedFrame.minX < visibleFrame.minX {
            constrainedFrame.origin.x = visibleFrame.minX
        }
        if constrainedFrame.maxY > visibleFrame.maxY {
            constrainedFrame.origin.y = visibleFrame.maxY - constrainedFrame.height
        }
        if constrainedFrame.minY < visibleFrame.minY {
            constrainedFrame.origin.y = visibleFrame.minY
        }

        return constrainedFrame
    }

    private func bestVisibleFrame(for point: NSPoint) -> NSRect? {
        if let screen = NSScreen.screens.first(where: { $0.visibleFrame.contains(point) }) {
            return screen.visibleFrame
        }

        return NSScreen.main?.visibleFrame
    }

    private func persistHUDOrigin(_ origin: CGPoint) {
        UserDefaults.standard.set(origin.x, forKey: Self.hudOriginXDefaultsKey)
        UserDefaults.standard.set(origin.y, forKey: Self.hudOriginYDefaultsKey)
    }

    private func updateHUD(animated: Bool = false) {
        if animated {
            withAnimation(.easeOut(duration: NotchHUDAnimation.duration)) {
                hudHostingView?.rootView = makeHUDView()
            }
        } else {
            hudHostingView?.rootView = makeHUDView()
        }
        menuBarState?.snapshot = snapshot
    }

    private var currentHUDSize: NSSize {
        switch hudDisplayMode {
        case .notchIsland:
            let layout = currentHUDLayout()
            return isNotchPanelExpanded ? layout.expandedSize : layout.compactSize
        case .floating:
            return isHUDCollapsed ? FloatingHUDLayout.collapsedSize : FloatingHUDLayout.expandedSize
        }
    }

    private func resizeHUDPanel(to targetSize: NSSize, animated: Bool, reposition: Bool = false) {
        guard let panel = hudPanel else {
            return
        }

        let frame = currentHUDFrame(size: targetSize, reposition: reposition)

        guard panel.frame != frame else {
            return
        }

        if animated, hudDisplayMode == .floating {
            animateHUDPanel(to: frame)
        } else {
            hudFrameAnimationTimer?.invalidate()
            hudFrameAnimationTimer = nil
            panel.setFrame(frame, display: true)
            panel.contentView?.frame = NSRect(origin: .zero, size: frame.size)
        }

        if hudDisplayMode == .floating {
            persistHUDOrigin(frame.origin)
        }
    }

    private func animateHUDPanel(to targetFrame: NSRect) {
        guard let panel = hudPanel else {
            return
        }

        hudFrameAnimationTimer?.invalidate()

        let startFrame = panel.frame
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
                let frame = NSRect(
                    x: startFrame.origin.x + (targetFrame.origin.x - startFrame.origin.x) * easedProgress,
                    y: startFrame.origin.y + (targetFrame.origin.y - startFrame.origin.y) * easedProgress,
                    width: startFrame.width + (targetFrame.width - startFrame.width) * easedProgress,
                    height: startFrame.height + (targetFrame.height - startFrame.height) * easedProgress
                )

                panel.setFrame(frame, display: true)
                panel.contentView?.frame = NSRect(origin: .zero, size: frame.size)

                if progress >= 1 {
                    panel.setFrame(targetFrame, display: true)
                    panel.contentView?.frame = NSRect(origin: .zero, size: targetFrame.size)
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
        HUDView(
            snapshot: snapshot,
            displayMode: hudDisplayMode,
            isNotchExpanded: isHUDExpanded,
            notchLayout: currentHUDLayout(),
            isFloatingCollapsed: isHUDCollapsed
        )
    }

    private func currentHUDScreen() -> NSScreen? {
        switch hudDisplayMode {
        case .notchIsland:
            return notchedHUDScreen() ?? NSScreen.main ?? NSScreen.screens.first
        case .floating:
            return NSScreen.main ?? NSScreen.screens.first
        }
    }

    private func notchedHUDScreen() -> NSScreen? {
        NSScreen.screens.first { screen in
            notchWidth(for: screen) != nil
        }
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

    private func pixelAligned(_ frame: NSRect, for screen: NSScreen) -> NSRect {
        let scale = max(screen.backingScaleFactor, 1)
        return NSRect(
            x: (frame.origin.x * scale).rounded() / scale,
            y: (frame.origin.y * scale).rounded() / scale,
            width: (frame.width * scale).rounded() / scale,
            height: (frame.height * scale).rounded() / scale
        )
    }

    private func setHUDExpanded(_ isExpanded: Bool) {
        guard hudDisplayMode == .notchIsland else {
            return
        }

        guard wantsHUDExpanded != isExpanded else {
            return
        }

        wantsHUDExpanded = isExpanded
        let layout = currentHUDLayout()
        notchCollapseTimer?.invalidate()
        notchCollapseTimer = nil

        if isExpanded {
            isNotchPanelExpanded = true
            resizeHUDPanel(to: layout.expandedSize, animated: false, reposition: true)
            self.isHUDExpanded = true
            updateHUD(animated: true)
        } else {
            self.isHUDExpanded = false
            updateHUD(animated: true)

            let collapseTimer = Timer.scheduledTimer(withTimeInterval: NotchHUDAnimation.duration, repeats: false) { [weak self] timer in
                Task { @MainActor [weak self] in
                    guard let self else {
                        timer.invalidate()
                        return
                    }

                    guard !self.wantsHUDExpanded, self.hudDisplayMode == .notchIsland else {
                        return
                    }

                    self.isNotchPanelExpanded = false
                    self.resizeHUDPanel(to: layout.compactSize, animated: false, reposition: true)
                    if self.notchCollapseTimer === timer {
                        self.notchCollapseTimer = nil
                    }
                }
            }
            notchCollapseTimer = collapseTimer
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

    private static func normalizedHUDOpacity(_ opacity: Double) -> Double {
        min(max(opacity, minHUDOpacity), maxHUDOpacity)
    }
}

private final class PaceHUDPanel: NSPanel {}

private final class HUDHostingView: NSHostingView<HUDView> {
    var canDragWindow = false
    var onHoverChanged: ((Bool) -> Void)?
    private var hoverTrackingArea: NSTrackingArea?

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    func applyTransparentBackground() {
        translatesAutoresizingMaskIntoConstraints = true
        autoresizingMask = [.width, .height]
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

    override func mouseDown(with event: NSEvent) {
        if canDragWindow {
            window?.performDrag(with: event)
        } else {
            super.mouseDown(with: event)
        }
    }
}

private extension Double {
    var signedRoundedPercentPoints: String {
        let roundedValue = Int(rounded())
        return roundedValue >= 0 ? "+\(roundedValue) ahead" : "\(roundedValue) behind"
    }
}
