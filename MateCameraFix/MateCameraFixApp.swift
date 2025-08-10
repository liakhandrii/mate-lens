import SwiftUI

@main
struct MateCameraFixApp: App {
    init() {
        Analytics.configure(ConsoleAnalytics.self)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
