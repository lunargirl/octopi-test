import SwiftUI

@main
struct NavigationApp: App {
    @StateObject private var recorder = Recorder()

    var body: some Scene {
        WindowGroup {
            HomeView(recorder: recorder)
        }
    }
}
