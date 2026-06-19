import CodexPacekeeperCore
import SwiftUI

@MainActor
final class MenuBarState: ObservableObject {
    @Published var snapshot = UsageSnapshot.placeholder
}

@main
struct CodexPacekeeperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var menuBarState = MenuBarState()
    @AppStorage("showsHUD") private var showsHUD = true
    @AppStorage(HUDDisplayMode.defaultsKey) private var hudDisplayModeRawValue = HUDDisplayMode.notchIsland.rawValue
    @AppStorage("hudCollapsed") private var hudCollapsed = false
    @AppStorage("hudOpacity") private var hudOpacity = 1.0

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

            if hudDisplayMode == .floating {
                Toggle("Collapse HUD", isOn: hudCollapsedBinding)

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("HUD Opacity \(hudOpacityPercent)")
                    Slider(value: hudOpacityBinding, in: 0.35...1.0, step: 0.05)
                        .frame(width: 160)
                }

                Divider()
            } else {
                Divider()
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .menuBarExtraStyle(.menu)
    }

    private var menuBarTitle: String {
        menuBarState.snapshot.menuBarTitle
    }

    private var menuBarIcon: String {
        menuBarState.snapshot.stateSystemImageName
    }

    private var hudDisplayMode: HUDDisplayMode {
        HUDDisplayMode(rawValue: hudDisplayModeRawValue) ?? .notchIsland
    }

    private var hudOpacityPercent: String {
        "\(Int((hudOpacity * 100).rounded()))%"
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

    private var hudOpacityBinding: Binding<Double> {
        Binding(
            get: { hudOpacity },
            set: { newValue in
                let normalizedValue = min(max(newValue, 0.35), 1.0)
                hudOpacity = normalizedValue
                appDelegate.setHUDOpacity(normalizedValue)
            }
        )
    }
}
