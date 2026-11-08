import SwiftUI

@main struct BilfredApp: App {
    @State private var store = AppStore()
    var body: some Scene {
        WindowGroup {
            RootView(store: store)
                .environment(\.locale, Locale(identifier: "nb_NO"))
                .environment(\.timeZone, TimeZone(identifier: "Europe/Oslo")!)
        }
    }
}

struct RootView: View {
    @Bindable var store: AppStore
    var body: some View {
        TabView(selection: $store.selectedTab) {
            Tab("Bil", systemImage: "car", value: AppTab.car) { carNavigation }
            Tab("Historikk", systemImage: "clock.arrow.circlepath", value: AppTab.history) {
                NavigationStack { HistoryView(store: store) }
            }
        }
        .tint(Palette.accent)
        .blockingLoading(store.busy)
        .task { await store.refreshHome(); store.loadMaintenance(); await store.refreshBookings() }
    }
    private var carNavigation: some View {
        NavigationStack(path: $store.path) {
            Group {
                if store.home != nil { HomeView(store: store) }
                else { PlateView(store: store) }
            }.navigationDestination(for: Route.self) { route in
                switch route {
                case .mileage: MileageView(store: store)
                case .options: OptionsView(store: store)
                case .schedule: BookingTimeView(store: store)
                case .offer: OfferView(store: store)
                case .confirmation: ConfirmationView(store: store)
                }
            }
        }.toolbar(store.home == nil || !store.path.isEmpty ? .hidden : .visible, for: .tabBar)
    }
}
