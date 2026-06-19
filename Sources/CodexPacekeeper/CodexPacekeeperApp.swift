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

    var body: some Scene {
        appDelegate.setMenuBarState(menuBarState)

        return MenuBarExtra(menuBarTitle, systemImage: menuBarIcon) {
            Toggle("Show HUD", isOn: hudVisibilityBinding)

            Divider()

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

    private var hudVisibilityBinding: Binding<Bool> {
        Binding(
            get: { showsHUD },
            set: { newValue in
                showsHUD = newValue
                appDelegate.setHUDVisible(newValue)
            }
        )
    }
}
