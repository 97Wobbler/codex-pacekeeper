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
    @Published private(set) var isHUDCollapsed: Bool = UserDefaults.standard.bool(forKey: hudCollapsedDefaultsKey)
    @Published private(set) var hudDisplayMode: HUDDisplayMode = {
        guard
            let rawValue = UserDefaults.standard.string(forKey: HUDDisplayMode.defaultsKey),
            let displayMode = HUDDisplayMode(rawValue: rawValue)
        else {
            return .notchIsland
        }

        return displayMode
    }()
    @Published private(set) var notchCompactProvider: UsageProvider = {
        guard
            let rawValue = UserDefaults.standard.string(forKey: UsageProvider.notchCompactDefaultsKey),
            let provider = UsageProvider(rawValue: rawValue)
        else {
            return .codex
        }

        return provider
    }()
    @Published private(set) var claudeUsageSourceMode: ClaudeUsageSourceMode = {
        guard
            let rawValue = UserDefaults.standard.string(forKey: ClaudeUsageSourceMode.defaultsKey),
            let sourceMode = ClaudeUsageSourceMode(rawValue: rawValue)
        else {
            return .statuslineOnly
        }

        return sourceMode
    }()
    @Published private(set) var claudeDirectAccessAuthorized: Bool = UserDefaults.standard.bool(
        forKey: ClaudeUsageSourceMode.directAccessAuthorizedDefaultsKey
    )

    private static let hudVisibilityDefaultsKey = "showsHUD"
    private static let hudCollapsedDefaultsKey = "hudCollapsed"
    private static let hudOriginXDefaultsKey = "hudOriginX"
    private static let hudOriginYDefaultsKey = "hudOriginY"
    private static let claudeDirectFallbackMinimumInterval: TimeInterval = 5 * 60
    private let codexAuthTokenStore = CodexAuthTokenStore()
    private let codexUsageClient = WhamUsageClient()
    private let claudeRateLimitCacheStore = ClaudeRateLimitCacheStore()
    private let claudeAuthTokenStore = ClaudeAuthTokenStore()
    private let pacekeeperClaudeCredentialStore = PacekeeperClaudeCredentialStore()
    private let claudeOAuthRefreshClient = ClaudeOAuthRefreshClient()
    private let claudeDirectUsageClient = ClaudeDirectUsageClient()
    private let codexUsageHistoryStore = UsageHistoryStore()
    private let claudeUsageHistoryStore = UsageHistoryStore(
        fileURL: UsageHistoryStore.defaultFileURL()
            .deletingLastPathComponent()
            .appendingPathComponent("claude-usage-samples.json", isDirectory: false)
    )

    private var hudPanel: NSPanel?
    private var hudHostingView: HUDHostingView?
    private var demoPanels: [NSPanel] = []
    private weak var menuBarState: MenuBarState?
    private var timer: Timer?
    private var isPaused = false
    private var isHUDExpanded = false
    private var isNotchPanelExpanded = false
    private var wantsHUDExpanded = false
    private var isNotchDragActive = false
    private var shouldCollapseAfterNotchDrag = false
    private var notchDragOffset: CGFloat = 0
    private var isNotchDetachReady = false
    private var notchExpandedMeasuredHeight: CGFloat?
    private var hudFrameAnimationTimer: Timer?
    private var notchCollapseTimer: Timer?
    private var lastSuccessfulSnapshots: [UsageProvider: UsageSnapshot] = [:]
    private var lastClaudeDirectFallbackAttemptAt: Date?
    private var lastClaudeDirectFallbackSnapshot: UsageSnapshot?
    private var cachedClaudeOAuthCredential: ClaudeOAuthCredential?
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
        if lastSuccessfulSnapshots.isEmpty {
            dashboard = UsageDashboardSnapshot.placeholder.withPaused(isPaused)
            updateHUD()
        }

        Task {
            await loadUsage()
        }
    }

    func refreshClaudeDirectUsage() {
        guard claudeUsageSourceMode.usesDirectFallback else {
            NSLog("Codex Pacekeeper manual Claude direct refresh ignored: fallback mode disabled")
            return
        }

        guard claudeDirectAccessAuthorized else {
            NSLog("Codex Pacekeeper manual Claude direct refresh ignored: direct access not authorized")
            applyProviderLoadResults(
                [.failure(.claudeCode, ClaudeDirectFallbackError.notAuthorized)],
                preservingExistingProviders: true
            )
            return
        }

        NSLog("Codex Pacekeeper manual Claude direct refresh requested")
        Task {
            await loadForcedClaudeDirectUsage()
        }
    }

    func authorizeClaudeDirectAccess() {
        guard claudeUsageSourceMode.usesDirectFallback else {
            NSLog("Codex Pacekeeper Claude direct access authorization ignored: fallback mode disabled")
            return
        }

        do {
            let sourceCredential = try claudeAuthTokenStore.oauthCredential(promptPolicy: .allow)
            let credential = try pacekeeperClaudeCredentialStore.saveCredential(sourceCredential)
            cachedClaudeOAuthCredential = credential
            setClaudeDirectAccessAuthorized(true)
            NSLog("Codex Pacekeeper Claude direct access authorized and imported")
            refreshClaudeDirectUsage()
        } catch {
            cachedClaudeOAuthCredential = nil
            setClaudeDirectAccessAuthorized(false)
            NSLog("Codex Pacekeeper Claude direct access authorization failed: \(friendlyMessage(for: error))")
            applyProviderLoadResults(
                [.failure(.claudeCode, error)],
                preservingExistingProviders: true
            )
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
        notchExpandedMeasuredHeight = nil
        resetNotchDragState()
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

    func setNotchCompactProvider(_ provider: UsageProvider) {
        guard notchCompactProvider != provider else {
            return
        }

        notchCompactProvider = provider
        UserDefaults.standard.set(provider.rawValue, forKey: UsageProvider.notchCompactDefaultsKey)
        updateHUD(animated: hudDisplayMode == .notchIsland)
    }

    func setClaudeUsageSourceMode(_ sourceMode: ClaudeUsageSourceMode) {
        guard claudeUsageSourceMode != sourceMode else {
            return
        }

        claudeUsageSourceMode = sourceMode
        UserDefaults.standard.set(sourceMode.rawValue, forKey: ClaudeUsageSourceMode.defaultsKey)
        lastClaudeDirectFallbackAttemptAt = nil
        lastClaudeDirectFallbackSnapshot = nil
        refreshUsage()
    }

    func setMenuBarState(_ menuBarState: MenuBarState) {
        self.menuBarState = menuBarState
        if menuBarState.dashboard != dashboard {
            menuBarState.dashboard = dashboard
        }
    }

    private func applyHUDVisibility() {
        if isHUDVisible {
            hudPanel?.alphaValue = 1
            hudPanel?.orderFrontRegardless()
        } else {
            hudPanel?.orderOut(nil)
        }
    }

    private func setClaudeDirectAccessAuthorized(_ isAuthorized: Bool) {
        claudeDirectAccessAuthorized = isAuthorized
        UserDefaults.standard.set(isAuthorized, forKey: ClaudeUsageSourceMode.directAccessAuthorizedDefaultsKey)
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

        applyProviderLoadResults(results, preservingExistingProviders: false)
    }

    private func loadForcedClaudeDirectUsage() async {
        let fallbackSnapshot = try? claudeRateLimitCacheStore.snapshot()
        lastClaudeDirectFallbackAttemptAt = nil

        let result = await loadClaudeDirectFallback(
            fallbackSnapshot: fallbackSnapshot,
            forceAttempt: true,
            promptPolicy: .allow
        )
        switch result {
        case .success(_, let snapshot):
            NSLog(
                "Codex Pacekeeper manual Claude direct refresh completed: state=\(snapshot.state.rawValue) primary=\(formattedPercent(snapshot.primary.actualPercent)) weekly=\(formattedPercent(snapshot.weekly.actualPercent))"
            )
        case .failure(_, let error):
            NSLog("Codex Pacekeeper manual Claude direct refresh failed: \(friendlyMessage(for: error))")
        }
        applyProviderLoadResults([result], preservingExistingProviders: true)
    }

    private func formattedPercent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    private func applyProviderLoadResults(
        _ results: [ProviderLoadResult],
        preservingExistingProviders: Bool
    ) {
        var providerSnapshotsByProvider = preservingExistingProviders
            ? Dictionary(
                uniqueKeysWithValues: dashboard.providers.map {
                    ($0.provider, ProviderUsageSnapshot(provider: $0.provider, snapshot: $0.snapshot.withPaused(isPaused)))
                }
            )
            : [:]

        for result in results {
            switch result {
            case .success(let provider, let snapshot):
                if snapshot.hasUsageData {
                    lastSuccessfulSnapshots[provider] = snapshot
                }

                let pausedSnapshot = snapshot.withPaused(isPaused)
                providerSnapshotsByProvider[provider] = ProviderUsageSnapshot(provider: provider, snapshot: pausedSnapshot)
                deliverNotificationsIfNeeded(for: provider, snapshot: pausedSnapshot)
            case .failure(let provider, let error):
                let message = friendlyMessage(for: error)
                if let lastSuccessfulSnapshot = lastSuccessfulSnapshots[provider] {
                    providerSnapshotsByProvider[provider] = ProviderUsageSnapshot(
                        provider: provider,
                        snapshot: lastSuccessfulSnapshot.markingStale(message: message).withPaused(isPaused)
                    )
                } else {
                    providerSnapshotsByProvider[provider] = ProviderUsageSnapshot(
                        provider: provider,
                        snapshot: UsageSnapshot.unavailable(message: message).withPaused(isPaused)
                    )
                }
            }
        }

        let sortedProviderSnapshots = providerSnapshotsByProvider.values.sorted {
            $0.provider.sortIndex < $1.provider.sortIndex
        }

        if sortedProviderSnapshots.isEmpty {
            dashboard = UsageDashboardSnapshot(
                providers: [],
                fallback: UsageSnapshot.unavailable(message: "Usage data is unavailable").withPaused(isPaused)
            )
        } else {
            dashboard = UsageDashboardSnapshot(
                providers: sortedProviderSnapshots,
                fallback: sortedProviderSnapshots[0].snapshot
            )
        }

        prepareNotchForExpandedContentChange()
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
        do {
            let snapshot = try claudeRateLimitCacheStore.snapshot()

            if snapshot.state == .fresh {
                lastClaudeDirectFallbackSnapshot = nil
                return claudeSuccess(snapshot)
            }

            guard claudeUsageSourceMode.usesDirectFallback, claudeDirectAccessAuthorized else {
                return claudeSuccess(snapshot)
            }

            return await loadClaudeDirectFallback(fallbackSnapshot: snapshot)
        } catch {
            guard claudeUsageSourceMode.usesDirectFallback, claudeDirectAccessAuthorized else {
                return .failure(.claudeCode, error)
            }

            return await loadClaudeDirectFallback(fallbackSnapshot: nil)
        }
    }

    private func loadClaudeDirectFallback(
        fallbackSnapshot: UsageSnapshot?,
        forceAttempt: Bool = false,
        promptPolicy: ClaudeKeychainPromptPolicy = .disallow
    ) async -> ProviderLoadResult {
        let now = Date()

        if !forceAttempt, let directSnapshot = reusableClaudeDirectFallbackSnapshot(now: now) {
            return claudeSuccess(directSnapshot)
        }

        guard forceAttempt || shouldAttemptClaudeDirectFallback(now: now, fallbackSnapshot: fallbackSnapshot) else {
            if let fallbackSnapshot {
                return claudeSuccess(fallbackSnapshot)
            }

            return .failure(.claudeCode, ClaudeDirectFallbackError.waitingToRetry)
        }

        lastClaudeDirectFallbackAttemptAt = now

        do {
            let snapshot = try await loadClaudeDirectSnapshot(now: now, promptPolicy: promptPolicy)
            lastClaudeDirectFallbackSnapshot = snapshot
            return claudeSuccess(snapshot)
        } catch {
            NSLog("Codex Pacekeeper Claude direct fallback unavailable: \(friendlyMessage(for: error))")
            let message = claudeDirectFallbackFailureMessage(for: error)

            if !forceAttempt, let directSnapshot = reusableClaudeDirectFallbackSnapshot(now: now) {
                return claudeSuccess(directSnapshot)
            }

            if let fallbackSnapshot {
                return claudeSuccess(
                    fallbackSnapshot.markingStale(
                        message: message
                    )
                )
            }

            return .failure(.claudeCode, error)
        }
    }

    private func loadClaudeDirectSnapshot(
        now: Date,
        promptPolicy: ClaudeKeychainPromptPolicy
    ) async throws -> UsageSnapshot {
        var credential = try cachedOrStoredClaudeOAuthCredential(promptPolicy: promptPolicy)

        if credential.isExpired(at: now) {
            credential = try await refreshClaudeOAuthCredential(credential, now: now)
        }

        do {
            return try await claudeDirectUsageClient.fetchSnapshot(accessToken: credential.accessToken, now: now)
        } catch ClaudeDirectUsageClientError.httpStatus(let status) where status == 401 || status == 403 {
            credential = try await refreshClaudeOAuthCredential(credential, now: now)
            return try await claudeDirectUsageClient.fetchSnapshot(accessToken: credential.accessToken, now: now)
        }
    }

    private func cachedOrStoredClaudeOAuthCredential(
        promptPolicy: ClaudeKeychainPromptPolicy
    ) throws -> ClaudeOAuthCredential {
        if let credential = cachedClaudeOAuthCredential {
            return credential
        }

        let credential = try pacekeeperClaudeCredentialStore.oauthCredential(promptPolicy: promptPolicy)
        cachedClaudeOAuthCredential = credential
        return credential
    }

    private func refreshClaudeOAuthCredential(
        _ credential: ClaudeOAuthCredential,
        now: Date
    ) async throws -> ClaudeOAuthCredential {
        guard let refreshToken = credential.refreshToken, !refreshToken.isEmpty else {
            throw ClaudeAuthTokenStoreError.refreshTokenMissing
        }

        let refreshResult = try await claudeOAuthRefreshClient.refreshToken(refreshToken, now: now)
        let refreshedCredential = try pacekeeperClaudeCredentialStore.saveRefreshResult(refreshResult, for: credential)
        cachedClaudeOAuthCredential = refreshedCredential
        return refreshedCredential
    }

    private func shouldAttemptClaudeDirectFallback(now: Date, fallbackSnapshot: UsageSnapshot?) -> Bool {
        guard let lastClaudeDirectFallbackAttemptAt else {
            return true
        }

        return now.timeIntervalSince(lastClaudeDirectFallbackAttemptAt) >= Self.claudeDirectFallbackMinimumInterval
    }

    private func reusableClaudeDirectFallbackSnapshot(now: Date) -> UsageSnapshot? {
        guard let snapshot = lastClaudeDirectFallbackSnapshot else {
            return nil
        }

        guard now.timeIntervalSince(snapshot.lastRefreshedAt) < Self.claudeDirectFallbackMinimumInterval else {
            return nil
        }

        guard !isPastClaudeReset(now: now, snapshot: snapshot) else {
            return nil
        }

        return snapshot
    }

    private func isPastClaudeReset(now: Date, snapshot: UsageSnapshot) -> Bool {
        now.timeIntervalSince(snapshot.primary.resetAt) > ClaudeRateLimitCacheStore.resetTolerance
            || now.timeIntervalSince(snapshot.weekly.resetAt) > ClaudeRateLimitCacheStore.resetTolerance
    }

    private func claudeSuccess(_ snapshot: UsageSnapshot) -> ProviderLoadResult {
        if snapshot.state == .fresh {
            recordUsageSample(for: snapshot, provider: .claudeCode)
        }

        return .success(
            .claudeCode,
            snapshot.withTrend(usageTrend(now: snapshot.lastRefreshedAt, provider: .claudeCode))
        )
    }

    private func claudeDirectFallbackFailureMessage(for error: Error) -> String {
        if let error = error as? ClaudeAuthTokenStoreError {
            switch error {
            case .credentialsMissing:
                return "Claude Code cache is stale; direct fallback credentials not found"
            case .unreadableCredentials:
                return "Claude Code cache is stale; direct fallback credentials unreadable"
            case .accessTokenMissing:
                return "Claude Code cache is stale; direct fallback access token not found"
            case .refreshTokenMissing:
                return "Claude Code cache is stale; direct fallback refresh token not found"
            case .credentialsNotWritable:
                return "Claude Code cache is stale; direct fallback credentials not writable"
            }
        }

        if let error = error as? ClaudeDirectUsageClientError {
            switch error {
            case .httpStatus(401), .httpStatus(403):
                return "Claude Code cache is stale; direct fallback unauthorized"
            default:
                break
            }
        }

        if let error = error as? ClaudeOAuthRefreshClientError {
            switch error {
            case .httpStatus(429):
                return "Claude Code cache is stale; direct fallback refresh rate limited"
            case .httpStatus(401), .httpStatus(403):
                return "Claude Code cache is stale; direct fallback refresh unauthorized"
            default:
                break
            }
        }

        return "Claude Code cache is stale; direct fallback unavailable"
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

    private func createHUD() {
        let view = makeHUDView()
        let hostingView = HUDHostingView(rootView: view)
        hostingView.applyTransparentBackground()
        hostingView.onHoverChanged = { [weak self] isHovered in
            Task { @MainActor [weak self] in
                self?.setHUDExpanded(isHovered)
            }
        }
        hostingView.onNotchDragBegan = { [weak self] in
            self?.beginNotchDrag()
        }
        hostingView.onNotchDragChanged = { [weak self] deltaY in
            self?.updateNotchDrag(deltaY: deltaY)
        }
        hostingView.onNotchDetachRequested = { [weak self] screenPoint in
            self?.detachNotchHUDForContinuousDrag(at: screenPoint)
        }
        hostingView.onNotchDragEnded = { [weak self] screenPoint in
            self?.finishNotchDrag(at: screenPoint)
        }
        hostingView.onFloatingDragEnded = { [weak self] in
            self?.finishFloatingDrag()
        }
        let panel = makeHUDPanel(frame: currentHUDFrame(size: currentHUDSize, reposition: true), hostingView: hostingView)

        hudHostingView = hostingView
        hudPanel = panel
        configureHUDPanelForCurrentMode()
        applyHUDVisibility()
    }

    private func createDemoHUDs() {
        let dashboards = DemoUsageSnapshots.make()
        let layout = fallbackHUDLayout()
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 900, height: 800)
        let startX = visibleFrame.minX + 80
        var y = visibleFrame.maxY - 60

        demoPanels = dashboards.map { dashboard in
            let panelSize = demoHUDSize(layout: layout, dashboard: dashboard)
            y -= panelSize.height
            let hostingView = HUDHostingView(rootView: HUDView(
                dashboard: dashboard,
                displayMode: hudDisplayMode,
                isNotchExpanded: true,
                notchLayout: layout,
                notchCompactProvider: notchCompactProvider,
                notchExpandedHeight: nil,
                notchDragOffset: 0,
                isNotchDetachReady: false,
                isFloatingCollapsed: false,
                onNotchExpandedHeightChanged: nil
            ))
            hostingView.applyTransparentBackground()
            let panel = makeHUDPanel(
                frame: NSRect(x: startX, y: y, width: panelSize.width, height: panelSize.height),
                hostingView: hostingView
            )
            panel.orderFrontRegardless()
            y -= 14
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
            hostingView.canDetachFromNotch = true
        case .floating:
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hasShadow = true
            panel.isMovableByWindowBackground = false
            hostingView.canDragWindow = true
            hostingView.canDetachFromNotch = false
        }

        panel.alphaValue = 1
    }

    private func demoHUDSize(layout: NotchHUDLayout, dashboard: UsageDashboardSnapshot) -> NSSize {
        switch hudDisplayMode {
        case .notchIsland:
            return layout.expandedSize(
                providerCount: dashboard.providers.count,
                staleCount: dashboard.staleProviderCount
            )
        case .floating:
            return FloatingHUDLayout.expandedSize(
                providerCount: dashboard.providers.count,
                staleCount: dashboard.staleProviderCount
            )
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

        return notchHUDFrame(size: size, on: screen)
    }

    private func notchHUDFrame(size: NSSize, on screen: NSScreen) -> NSRect {
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

    @objc private func screenParametersDidChange(_ notification: Notification) {
        guard hudDisplayMode == .notchIsland else {
            return
        }

        notchExpandedMeasuredHeight = nil
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
        menuBarState?.dashboard = dashboard
    }

    private var currentHUDSize: NSSize {
        switch hudDisplayMode {
        case .notchIsland:
            let layout = currentHUDLayout()
            return isNotchPanelExpanded
                ? notchExpandedSize(layout: layout)
                : layout.compactSize
        case .floating:
            return isHUDCollapsed
                ? FloatingHUDLayout.collapsedSize
                : FloatingHUDLayout.expandedSize(providerCount: dashboard.providers.count, staleCount: dashboard.staleProviderCount)
        }
    }

    private func notchExpandedSize(layout: NotchHUDLayout) -> NSSize {
        let fallbackSize = layout.expandedSize(
            providerCount: dashboard.providers.count,
            staleCount: dashboard.staleProviderCount
        )
        guard let notchExpandedMeasuredHeight else {
            return fallbackSize
        }

        return NSSize(
            width: fallbackSize.width,
            height: max(layout.compactSize.height, notchExpandedMeasuredHeight)
        )
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
            dashboard: dashboard,
            displayMode: hudDisplayMode,
            isNotchExpanded: isHUDExpanded,
            notchLayout: currentHUDLayout(),
            notchCompactProvider: notchCompactProvider,
            notchExpandedHeight: notchExpandedMeasuredHeight,
            notchDragOffset: notchDragOffset,
            isNotchDetachReady: isNotchDetachReady,
            isFloatingCollapsed: isHUDCollapsed,
            onNotchExpandedHeightChanged: { [weak self] height in
                Task { @MainActor [weak self] in
                    self?.setNotchExpandedMeasuredHeight(height)
                }
            }
        )
    }

    private func prepareNotchForExpandedContentChange() {
        guard hudDisplayMode == .notchIsland, isNotchPanelExpanded else {
            return
        }

        notchExpandedMeasuredHeight = nil
        resizeHUDPanel(to: currentHUDSize, animated: false, reposition: true)
    }

    private func setNotchExpandedMeasuredHeight(_ measuredHeight: CGFloat) {
        guard hudDisplayMode == .notchIsland, isNotchPanelExpanded, isHUDExpanded else {
            return
        }

        let normalizedHeight = measuredHeight.rounded(.up)
        guard notchExpandedMeasuredHeight.map({ abs($0 - normalizedHeight) > 0.5 }) ?? true else {
            return
        }

        notchExpandedMeasuredHeight = normalizedHeight
        updateHUD()
        resizeHUDPanel(to: currentHUDSize, animated: false, reposition: true)
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

    private func beginNotchDrag() {
        guard hudDisplayMode == .notchIsland, isHUDExpanded else {
            return
        }

        isNotchDragActive = true
        shouldCollapseAfterNotchDrag = false
        notchCollapseTimer?.invalidate()
        notchCollapseTimer = nil
    }

    private func updateNotchDrag(deltaY: CGFloat) {
        guard hudDisplayMode == .notchIsland, isHUDExpanded, isNotchDragActive else {
            return
        }

        let pullDistance = max(deltaY, 0)
        notchDragOffset = min(pullDistance * 0.62, HUDDockingInteraction.notchDetachMaxOffset)
        isNotchDetachReady = pullDistance >= HUDDockingInteraction.notchDetachThreshold
        updateHUD()
    }

    private func detachNotchHUDForContinuousDrag(at screenPoint: NSPoint) {
        guard hudDisplayMode == .notchIsland else {
            return
        }

        isHUDCollapsed = false
        UserDefaults.standard.set(false, forKey: Self.hudCollapsedDefaultsKey)

        resetNotchDragState()
        hudDisplayMode = .floating
        UserDefaults.standard.set(HUDDisplayMode.floating.rawValue, forKey: HUDDisplayMode.defaultsKey)
        isHUDExpanded = false
        isNotchPanelExpanded = false
        wantsHUDExpanded = false
        notchExpandedMeasuredHeight = nil
        notchCollapseTimer?.invalidate()
        notchCollapseTimer = nil
        hudFrameAnimationTimer?.invalidate()
        hudFrameAnimationTimer = nil

        configureHUDPanelForCurrentMode()
        updateHUD()
        placeFloatingHUDForDrag(at: screenPoint)
        applyHUDVisibility()
    }

    private func finishNotchDrag(at screenPoint: NSPoint) {
        guard hudDisplayMode == .notchIsland, isNotchDragActive else {
            resetNotchDragState()
            return
        }

        let shouldCollapse = shouldCollapseAfterNotchDrag
        resetNotchDragState()
        if shouldCollapse {
            setHUDExpanded(false)
        } else {
            updateHUD(animated: true)
        }
    }

    private func placeFloatingHUDForDrag(at screenPoint: NSPoint) {
        guard let hudPanel else {
            return
        }

        let size = FloatingHUDLayout.expandedSize(
            providerCount: dashboard.providers.count,
            staleCount: dashboard.staleProviderCount
        )
        let targetFrame = constrainedHUDFrame(
            NSRect(
                x: screenPoint.x - size.width / 2,
                y: screenPoint.y - size.height / 2,
                width: size.width,
                height: size.height
            ),
            visibleFrame: bestVisibleFrame(for: screenPoint)
        )
        hudPanel.setFrame(targetFrame, display: true)
        hudPanel.contentView?.frame = NSRect(origin: .zero, size: targetFrame.size)
        persistHUDOrigin(targetFrame.origin)
    }

    private func finishFloatingDrag() {
        guard hudDisplayMode == .floating, let hudPanel else {
            return
        }

        persistHUDOrigin(hudPanel.frame.origin)

        if shouldDockFloatingHUD(frame: hudPanel.frame) {
            setHUDDisplayMode(.notchIsland)
        }
    }

    private func shouldDockFloatingHUD(frame: NSRect) -> Bool {
        guard let screen = notchedHUDScreen() else {
            return false
        }

        let layout = NotchHUDLayout(
            notchWidth: notchWidth(for: screen),
            topInset: screen.safeAreaInsets.top
        )
        let topCenter = NSPoint(x: frame.midX, y: frame.maxY)
        let targetCenterX = notchCenterX(for: screen) ?? screen.frame.midX
        let expandedSize = layout.expandedSize(providerCount: dashboard.providers.count, staleCount: dashboard.staleProviderCount)
        let horizontalTolerance = max(expandedSize.width / 2 + 48, 240)
        let verticalDistanceFromTop = abs(screen.frame.maxY - topCenter.y)

        return abs(topCenter.x - targetCenterX) <= horizontalTolerance
            && verticalDistanceFromTop <= 92
    }

    private func resetNotchDragState() {
        isNotchDragActive = false
        shouldCollapseAfterNotchDrag = false
        notchDragOffset = 0
        isNotchDetachReady = false
    }

    private func setHUDExpanded(_ isExpanded: Bool) {
        guard hudDisplayMode == .notchIsland else {
            return
        }

        if isNotchDragActive && !isExpanded {
            shouldCollapseAfterNotchDrag = true
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
            notchExpandedMeasuredHeight = nil
            resizeHUDPanel(
                to: notchExpandedSize(layout: layout),
                animated: false,
                reposition: true
            )
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
                    self.notchExpandedMeasuredHeight = nil
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

private final class PaceHUDPanel: NSPanel {}

private enum ProviderLoadResult {
    case success(UsageProvider, UsageSnapshot)
    case failure(UsageProvider, Error)
}

private enum ClaudeDirectFallbackError: Error, LocalizedError {
    case waitingToRetry
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .waitingToRetry:
            return "Claude direct usage fallback is waiting before retrying"
        case .notAuthorized:
            return "Claude direct usage fallback is not authorized"
        }
    }
}

@MainActor
private final class HUDHostingView: NSHostingView<HUDView> {
    var canDragWindow = false
    var canDetachFromNotch = false
    var onHoverChanged: ((Bool) -> Void)?
    var onNotchDragBegan: (() -> Void)?
    var onNotchDragChanged: ((CGFloat) -> Void)?
    var onNotchDetachRequested: ((NSPoint) -> Void)?
    var onNotchDragEnded: ((NSPoint) -> Void)?
    var onFloatingDragEnded: (() -> Void)?
    private var hoverTrackingArea: NSTrackingArea?
    private var notchDragStartPoint: NSPoint?
    private var floatingDragOffset: NSSize?

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
        let screenPoint = screenPoint(for: event)

        if canDragWindow {
            beginFloatingDrag(at: screenPoint)
        } else if canDetachFromNotch {
            notchDragStartPoint = event.locationInWindow
            onNotchDragBegan?()
        } else {
            super.mouseDown(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let screenPoint = screenPoint(for: event)

        if floatingDragOffset != nil {
            moveFloatingWindow(to: screenPoint)
            return
        }

        guard canDetachFromNotch, let notchDragStartPoint else {
            super.mouseDragged(with: event)
            return
        }

        let deltaY = notchDragStartPoint.y - event.locationInWindow.y
        if deltaY >= HUDDockingInteraction.notchDetachThreshold {
            self.notchDragStartPoint = nil
            onNotchDetachRequested?(screenPoint)
            beginFloatingDrag(at: screenPoint)
            moveFloatingWindow(to: screenPoint)
            return
        }

        onNotchDragChanged?(deltaY)
    }

    override func mouseUp(with event: NSEvent) {
        if floatingDragOffset != nil {
            floatingDragOffset = nil
            onFloatingDragEnded?()
            return
        }

        guard canDetachFromNotch, notchDragStartPoint != nil else {
            super.mouseUp(with: event)
            return
        }

        notchDragStartPoint = nil

        if let window {
            onNotchDragEnded?(window.convertPoint(toScreen: event.locationInWindow))
        } else {
            onNotchDragEnded?(event.locationInWindow)
        }
    }

    private func beginFloatingDrag(at screenPoint: NSPoint) {
        guard let window else {
            return
        }

        floatingDragOffset = NSSize(
            width: screenPoint.x - window.frame.origin.x,
            height: screenPoint.y - window.frame.origin.y
        )
    }

    private func moveFloatingWindow(to screenPoint: NSPoint) {
        guard let window, let floatingDragOffset else {
            return
        }

        var frame = window.frame
        frame.origin = NSPoint(
            x: screenPoint.x - floatingDragOffset.width,
            y: screenPoint.y - floatingDragOffset.height
        )
        window.setFrame(frame, display: true)
    }

    private func screenPoint(for event: NSEvent) -> NSPoint {
        NSEvent.mouseLocation
    }
}

private extension Double {
    var signedRoundedPercentPoints: String {
        let roundedValue = Int(rounded())
        return roundedValue >= 0 ? "+\(roundedValue) ahead" : "\(roundedValue) behind"
    }
}
