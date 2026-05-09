import SwiftUI

@main
struct CodexPacekeeperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var isPaused = false
    @State private var showsHUD = true

    var body: some Scene {
        MenuBarExtra(menuBarTitle, systemImage: menuBarIcon) {
            PaceSummaryView(snapshot: appDelegate.snapshot)
                .frame(width: 260)
                .padding(.vertical, 8)

            Divider()

            Button("Refresh Now") {
                appDelegate.refreshUsage()
            }

            Toggle("Pause", isOn: $isPaused)
                .onChange(of: isPaused) { newValue in
                    appDelegate.setPaused(newValue)
                }

            Toggle("Show HUD", isOn: $showsHUD)
                .onChange(of: showsHUD) { newValue in
                    appDelegate.setHUDVisible(newValue)
                }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .menuBarExtraStyle(.menu)
    }

    private var menuBarTitle: String {
        appDelegate.snapshot.menuBarTitle
    }

    private var menuBarIcon: String {
        appDelegate.snapshot.stateSystemImageName
    }
}
