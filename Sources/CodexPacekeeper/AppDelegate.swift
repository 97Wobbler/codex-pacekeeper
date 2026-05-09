import AppKit
import CodexPacekeeperCore
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published private(set) var dashboard = UsageDashboardSnapshot.placeholder
    @Published private(set) var isHUDVisible: Bool = {
        if UserDefaults.standard.object(forKey: hudVisibilityDefaultsKey) == nil {
            return true
        }

        return UserDefaults.standard.bool(forKey: hudVisibilityDefaultsKey)
    }()

    private static let hudVisibilityDefaultsKey = "showsHUD"
    private static let hudOriginXDefaultsKey = "hudOriginX"
    private static let hudOriginYDefaultsKey = "hudOriginY"
    private static let hudWidth: CGFloat = 280
    private static let hudSize = NSSize(width: hudWidth, height: 124)
    private static let claudeUsageFetchInterval: TimeInterval = 3 * 60
    private let codexAuthTokenStore = CodexAuthTokenStore()
    private let codexUsageClient = WhamUsageClient()
    private let codexUsageHistoryStore = UsageHistoryStore()
    private let claudeAuthTokenStore = ClaudeAuthTokenStore()
    private let claudeUsageClient = ClaudeUsageClient()
    private let claudeUsageCacheStore = ClaudeUsageCacheStore()
    private let claudeUsageHistoryStore = UsageHistoryStore(
        fileURL: UsageHistoryStore.defaultFileURL()
            .deletingLastPathComponent()
            .appendingPathComponent("claude-usage-samples.json")
    )

    private var hudPanel: NSPanel?
    private var hudHostingView: NSHostingView<HUDView>?
    private var demoPanels: [NSPanel] = []
    private weak var menuBarState: MenuBarState?
    private var timer: Timer?
    private var isPaused = false
    private var lastSuccessfulSnapshots: [UsageProvider: UsageSnapshot] = [:]
    private var lastClaudeUsageFetchAttemptAt: Date?
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
        if lastSuccessfulSnapshots.isEmpty {
            dashboard = UsageDashboardSnapshot.placeholder.withPaused(isPaused)
            updateHUD()
        }

        Task {
            await loadUsage()
        }
    }

    func setPaused(_ isPaused: Bool) {
        self.isPaused = isPaused
        dashboard = dashboard.withPaused(isPaused)

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
        if menuBarState.dashboard != dashboard {
            menuBarState.dashboard = dashboard
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
        async let codexResult = loadCodexUsage()
        async let claudeResult = loadClaudeUsage()

        let results = await [codexResult, claudeResult]
        var providerSnapshots: [ProviderUsageSnapshot] = []
        var messages: [String] = []

        for result in results {
            switch result {
            case .success(let provider, let snapshot):
                lastSuccessfulSnapshots[provider] = snapshot
                let pausedSnapshot = snapshot.withPaused(isPaused)
                providerSnapshots.append(ProviderUsageSnapshot(provider: provider, snapshot: pausedSnapshot))
                deliverNotificationsIfNeeded(for: provider, snapshot: pausedSnapshot)
            case .failure(let provider, let error):
                let message = friendlyMessage(for: error)
                if let lastSuccessfulSnapshot = lastSuccessfulSnapshots[provider] {
                    providerSnapshots.append(
                        ProviderUsageSnapshot(
                            provider: provider,
                            snapshot: lastSuccessfulSnapshot.markingStale(message: message).withPaused(isPaused)
                        )
                    )
                } else {
                    messages.append("\(provider.displayName): \(message)")
                }
            }
        }

        let sortedProviderSnapshots = providerSnapshots.sorted { lhs, rhs in
            providerSortIndex(lhs.provider) < providerSortIndex(rhs.provider)
        }

        if sortedProviderSnapshots.isEmpty {
            let message = messages.isEmpty ? "Usage data is unavailable" : messages.joined(separator: "\n")
            dashboard = UsageDashboardSnapshot(
                providers: [],
                fallback: UsageSnapshot.unavailable(message: message).withPaused(isPaused)
            )
        } else {
            dashboard = UsageDashboardSnapshot(
                providers: sortedProviderSnapshots,
                fallback: sortedProviderSnapshots[0].snapshot
            )
        }

        updateHUD()
    }

    private func loadCodexUsage() async -> ProviderLoadResult {
        do {
            let token = try codexAuthTokenStore.accessToken()
            let freshSnapshot = try await codexUsageClient.fetchSnapshot(accessToken: token)
            recordUsageSample(for: freshSnapshot, provider: .codex)
            return .success(
                .codex,
                freshSnapshot.withTrend(usageTrend(now: freshSnapshot.lastRefreshedAt, provider: .codex))
            )
        } catch {
            return .failure(.codex, error)
        }
    }

    private func loadClaudeUsage() async -> ProviderLoadResult {
        if let cachedSnapshot = freshCachedClaudeSnapshot() {
            return .success(
                .claudeCode,
                cachedSnapshot.withTrend(usageTrend(now: cachedSnapshot.lastRefreshedAt, provider: .claudeCode))
            )
        }

        let now = Date()
        if
            let lastClaudeUsageFetchAttemptAt,
            now.timeIntervalSince(lastClaudeUsageFetchAttemptAt) < Self.claudeUsageFetchInterval
        {
            if let cachedSnapshot = cachedClaudeSnapshot(message: "Using cached Claude Code usage") {
                return .success(
                    .claudeCode,
                    cachedSnapshot.withTrend(usageTrend(now: cachedSnapshot.lastRefreshedAt, provider: .claudeCode))
                )
            }

            return .failure(.claudeCode, UsageFetchThrottleError.claudeInterval)
        }

        lastClaudeUsageFetchAttemptAt = now

        do {
            let token = try claudeAuthTokenStore.accessToken()
            let freshSnapshot = try await claudeUsageClient.fetchSnapshot(accessToken: token)
            recordUsageSample(for: freshSnapshot, provider: .claudeCode)
            return .success(
                .claudeCode,
                freshSnapshot.withTrend(usageTrend(now: freshSnapshot.lastRefreshedAt, provider: .claudeCode))
            )
        } catch {
            if let cachedSnapshot = cachedClaudeSnapshot(message: friendlyMessage(for: error)) {
                return .success(
                    .claudeCode,
                    cachedSnapshot.withTrend(usageTrend(now: cachedSnapshot.lastRefreshedAt, provider: .claudeCode))
                )
            }

            return .failure(.claudeCode, error)
        }
    }

    private func freshCachedClaudeSnapshot() -> UsageSnapshot? {
        do {
            return try claudeUsageCacheStore.freshSnapshot(maxAge: Self.claudeUsageFetchInterval)
        } catch {
            return nil
        }
    }

    private func cachedClaudeSnapshot(message: String) -> UsageSnapshot? {
        do {
            return try claudeUsageCacheStore.snapshot(message: message)
        } catch {
            return nil
        }
    }

    private func usageTrend(now: Date, provider: UsageProvider) -> UsageTrend? {
        do {
            return try usageHistoryStore(for: provider).recentTrend(now: now)
        } catch {
            NSLog("Codex Pacekeeper failed to load \(provider.displayName) usage trend: \(error.localizedDescription)")
            return nil
        }
    }

    private func recordUsageSample(for snapshot: UsageSnapshot, provider: UsageProvider) {
        do {
            try usageHistoryStore(for: provider).record(UsageSample(snapshot: snapshot))
        } catch {
            NSLog("Codex Pacekeeper failed to record \(provider.displayName) usage sample: \(error.localizedDescription)")
        }
    }

    private func usageHistoryStore(for provider: UsageProvider) -> UsageHistoryStore {
        switch provider {
        case .codex:
            return codexUsageHistoryStore
        case .claudeCode:
            return claudeUsageHistoryStore
        }
    }

    private func providerSortIndex(_ provider: UsageProvider) -> Int {
        switch provider {
        case .codex:
            return 0
        case .claudeCode:
            return 1
        }
    }

    private func createHUD() {
        let view = HUDView(dashboard: dashboard)
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
        let dashboards = DemoUsageSnapshots.make()
        let panelSize = NSSize(width: Self.hudWidth, height: 250)
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 900, height: 800)
        let startX = visibleFrame.minX + 80
        var y = visibleFrame.maxY - panelSize.height - 60

        demoPanels = dashboards.map { dashboard in
            let size = hudSize(for: dashboard)
            let panel = makeHUDPanel(
                frame: NSRect(x: startX, y: y, width: size.width, height: size.height),
                hostingView: DraggableHUDHostingView(rootView: HUDView(dashboard: dashboard))
            )
            panel.orderFrontRegardless()
            y -= size.height + 14
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
        let size = Self.hudSize

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

    private func hudSize(for dashboard: UsageDashboardSnapshot) -> NSSize {
        guard dashboard.providers.count > 0 else {
            return Self.hudSize
        }

        let staleCount = dashboard.providers.filter { $0.snapshot.state != .fresh }.count
        let baseHeight: CGFloat = dashboard.providers.count == 1 ? 124 : 250
        return NSSize(width: Self.hudWidth, height: baseHeight + CGFloat(staleCount * 30))
    }

    private func resizeHUDIfNeeded() {
        guard let hudPanel else {
            return
        }

        let size = hudSize(for: dashboard)
        guard hudPanel.frame.size != size else {
            return
        }

        let frame = hudPanel.frame
        let resizedFrame = NSRect(
            x: frame.minX,
            y: frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        hudPanel.setFrame(resizedFrame, display: true)
    }

    @objc private func hudPanelDidMove(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel else {
            return
        }

        UserDefaults.standard.set(panel.frame.origin.x, forKey: Self.hudOriginXDefaultsKey)
        UserDefaults.standard.set(panel.frame.origin.y, forKey: Self.hudOriginYDefaultsKey)
    }

    private func updateHUD() {
        hudHostingView?.rootView = HUDView(dashboard: dashboard)
        resizeHUDIfNeeded()
        menuBarState?.dashboard = dashboard
    }

    private func requestNotificationAuthorization() {
        notificationCenter?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func deliverNotificationsIfNeeded(for provider: UsageProvider, snapshot: UsageSnapshot) {
        guard snapshot.state == .fresh, !snapshot.primary.isPaused else {
            return
        }

        deliverNotificationIfNeeded(for: snapshot.primary, provider: provider)
        deliverNotificationIfNeeded(for: snapshot.weekly, provider: provider)
    }

    private func deliverNotificationIfNeeded(for reading: PaceReading, provider: UsageProvider) {
        guard reading.status == .threshold || reading.status == .redline else {
            return
        }

        let key = "\(provider.rawValue)-\(reading.label)-\(reading.status.rawValue)-\(Int(reading.resetAt.timeIntervalSince1970))"
        guard !deliveredNotificationKeys.contains(key) else {
            return
        }

        deliveredNotificationKeys.insert(key)

        let content = UNMutableNotificationContent()
        content.title = reading.status == .redline ? "\(provider.displayName) redline pace" : "\(provider.displayName) pace warning"
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

private enum ProviderLoadResult {
    case success(UsageProvider, UsageSnapshot)
    case failure(UsageProvider, Error)
}

private enum UsageFetchThrottleError: LocalizedError {
    case claudeInterval

    var errorDescription: String? {
        switch self {
        case .claudeInterval:
            return "Waiting for the next Claude Code usage refresh"
        }
    }
}

private extension Double {
    var signedRoundedPercentPoints: String {
        let roundedValue = Int(rounded())
        return roundedValue >= 0 ? "+\(roundedValue) ahead" : "\(roundedValue) behind"
    }
}
