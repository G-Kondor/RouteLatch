import SwiftUI

@main
struct RouteLatchApp: App {
    @StateObject private var model = PhoneRouteLibraryModel()

    var body: some Scene {
        WindowGroup {
            RouteLibraryView(model: model)
                .tint(.orange)
                .onOpenURL { model.importRoute(from: $0) }
        }
    }
}
