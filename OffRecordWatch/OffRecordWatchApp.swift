import SwiftUI

@main
struct OffRecordWatchApp: App {
    @StateObject private var store = WatchCaptureStore.shared

    var body: some Scene {
        WindowGroup {
            QuickCaptureHomeView(store: store)
                .onAppear {
                    store.start()
                }
        }
    }
}
