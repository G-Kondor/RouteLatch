import SwiftUI

@main
struct RouteLatchApp: App {
    @StateObject private var model = PhoneRouteLibraryModel()

    var body: some Scene {
        WindowGroup {
            RouteLibraryView(model: model)
                .tint(LatchColor.accent)
                .onOpenURL { model.handleIncomingURL($0) }
        }
    }
}
