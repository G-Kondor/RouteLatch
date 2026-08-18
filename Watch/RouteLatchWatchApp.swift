import SwiftUI

@main
struct RouteLatchWatchApp: App {
    @StateObject private var model = WatchRouteLibraryModel()
    var body: some Scene { WindowGroup { WatchRouteLibraryView(model: model).tint(.orange) } }
}
