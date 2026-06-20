import CodexPacekeeperCore
import SwiftUI

@MainActor
final class MenuBarState: ObservableObject {
    @Published var dashboard = UsageDashboardSnapshot.placeholder
}

@main
struct CodexPacekeeperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var menuBarState = MenuBarState()
    @AppStorage("showsHUD") private var showsHUD = true
    @AppStorage(HUDDisplayMode.defaultsKey) private var hudDisplayModeRawValue = HUDDisplayMode.notchIsland.rawValue
    @AppStorage("hudCollapsed") private var hudCollapsed = false
    @AppStorage(UsageProvider.notchCompactDefaultsKey) private var notchCompactProviderRawValue = UsageProvider.codex.rawValue
    @AppStorage(ClaudeUsageSourceMode.defaultsKey) private var claudeUsageSourceModeRawValue = ClaudeUsageSourceMode.statuslineOnly.rawValue
    @AppStorage(ClaudeUsageSourceMode.directAccessAuthorizedDefaultsKey) private var claudeDirectAccessAuthorized = false

    var body: some Scene {
        appDelegate.setMenuBarState(menuBarState)

        return MenuBarExtra(menuBarTitle, systemImage: menuBarIcon) {
            Toggle("Show HUD", isOn: hudVisibilityBinding)

            Divider()

            Picker("HUD Style", selection: hudDisplayModeBinding) {
                ForEach(HUDDisplayMode.allCases) { displayMode in
                    Text(displayMode.title).tag(displayMode)
                }
            }

            Picker("Claude Usage", selection: claudeUsageSourceModeBinding) {
                ForEach(ClaudeUsageSourceMode.allCases) { sourceMode in
                    Text(sourceMode.title).tag(sourceMode)
                }
            }

            if claudeUsageSourceMode.usesDirectFallback {
                Button(claudeDirectAccessAuthorized ? "Reauthorize Claude Direct Access..." : "Authorize Claude Direct Access...") {
                    appDelegate.authorizeClaudeDirectAccess()
                }

                Button("Refresh Claude Direct") {
                    appDelegate.refreshClaudeDirectUsage()
                }
                .disabled(!claudeDirectAccessAuthorized)
            }

            Button("Refresh Now") {
                appDelegate.refreshUsage()
            }

            if hudDisplayMode == .floating {
                Toggle("Collapse HUD", isOn: hudCollapsedBinding)

                Divider()
            } else {
                Picker("Compact Provider", selection: notchCompactProviderBinding) {
                    ForEach(UsageProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }

                Divider()
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .menuBarExtraStyle(.menu)
    }

    private var menuBarTitle: String {
        menuBarState.dashboard.menuBarTitle
    }

    private var menuBarIcon: String {
        menuBarState.dashboard.stateSystemImageName
    }

    private var hudDisplayMode: HUDDisplayMode {
        HUDDisplayMode(rawValue: hudDisplayModeRawValue) ?? .notchIsland
    }

    private var notchCompactProvider: UsageProvider {
        UsageProvider(rawValue: notchCompactProviderRawValue) ?? .codex
    }

    private var claudeUsageSourceMode: ClaudeUsageSourceMode {
        ClaudeUsageSourceMode(rawValue: claudeUsageSourceModeRawValue) ?? .statuslineOnly
    }

    private var hudVisibilityBinding: Binding<Bool> {
        Binding(
            get: { showsHUD },
            set: { newValue in
                showsHUD = newValue
                appDelegate.setHUDVisible(newValue)
            }
        )
    }

    private var hudDisplayModeBinding: Binding<HUDDisplayMode> {
        Binding(
            get: { hudDisplayMode },
            set: { newValue in
                hudDisplayModeRawValue = newValue.rawValue
                appDelegate.setHUDDisplayMode(newValue)
            }
        )
    }

    private var hudCollapsedBinding: Binding<Bool> {
        Binding(
            get: { hudCollapsed },
            set: { newValue in
                hudCollapsed = newValue
                appDelegate.setHUDCollapsed(newValue)
            }
        )
    }

    private var notchCompactProviderBinding: Binding<UsageProvider> {
        Binding(
            get: { notchCompactProvider },
            set: { newValue in
                notchCompactProviderRawValue = newValue.rawValue
                appDelegate.setNotchCompactProvider(newValue)
            }
        )
    }

    private var claudeUsageSourceModeBinding: Binding<ClaudeUsageSourceMode> {
        Binding(
            get: { claudeUsageSourceMode },
            set: { newValue in
                claudeUsageSourceModeRawValue = newValue.rawValue
                appDelegate.setClaudeUsageSourceMode(newValue)
            }
        )
    }
}
