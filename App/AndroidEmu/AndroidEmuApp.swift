import SwiftUI

@main
struct AndroidEmuApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self)
    var appDelegate

    var body: some Scene {
        WindowGroup {
            AndroidViewControllerRepresentable()
                .ignoresSafeArea()
        }
    }
}
