import SwiftUI

@main
struct PsstApp: App {
    @State private var exchange = LocalExchange()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(exchange)
        }
    }
}
