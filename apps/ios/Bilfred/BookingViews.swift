import SwiftUI

struct BookingTimeView: View {
    @Bindable var store: AppStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Ønsket tidspunkt").font(.system(.largeTitle, weight: .semibold))
                if let option = store.options.first(where: { $0.id == store.selectedOptionId }) {
                    Text(option.name).font(.headline)
                    Text(option.address).font(.subheadline).foregroundStyle(Palette.muted)
                }
                DatePicker("Dato", selection: $store.selectedAppointment, in: Date.now...Date.now.addingTimeInterval(1095 * 86400), displayedComponents: .date)
                    .datePickerStyle(.graphical).padding(12).background(Palette.surface, in: RoundedRectangle(cornerRadius: 24))
                DatePicker("Klokkeslett", selection: $store.selectedAppointment, displayedComponents: .hourAndMinute)
                    .padding(20).background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))
                if let error = store.error { ErrorBanner(message: error) }
            }.padding(20)
        }.background(Palette.backdrop.ignoresSafeArea()).navigationTitle("Tidspunkt").navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(title: "Se tilbudet", busy: store.busy) { Task { await store.selectOffer() } }
                    .padding(20).background(Palette.background).accessibilityIdentifier("createTimedOffer")
            }
    }
}

struct PaymentStrip: View {
    @Binding var selection: String
    var disabled = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Betalingsmåte").font(.headline)
            HStack(spacing: 12) {
                method("apple_pay", title: "Apple Pay", symbol: "apple.logo")
                method("vipps", title: "Vipps", symbol: nil)
            }
        }.disabled(disabled)
    }
    private func method(_ id: String, title: String, symbol: String?) -> some View {
        Button { selection = id } label: {
            HStack(spacing: 8) {
                if let symbol { Image(systemName: symbol).font(.title3) }
                Text(title).font(.system(.body, weight: .semibold))
                Spacer(minLength: 0)
                Image(systemName: selection == id ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selection == id ? Palette.accent : Palette.muted)
            }.foregroundStyle(Palette.ink).padding(16).frame(maxWidth: .infinity)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(selection == id ? Palette.accent : Palette.line, lineWidth: selection == id ? 1.5 : 0.5))
        }.buttonStyle(.plain).accessibilityIdentifier("payment-\(id)")
            .accessibilityAddTraits(selection == id ? .isSelected : [])
    }
}

struct HistoryView: View {
    @Bindable var store: AppStore
    @State private var filter = "active"
    @State private var selected: Booking?
    private var rows: [Booking] { store.bookings.filter { $0.state == filter } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Vis", selection: $filter) {
                    Text("Aktive").tag("active")
                    Text("Fullførte").tag("completed")
                }.pickerStyle(.segmented).accessibilityIdentifier("historyFilter")
                if rows.isEmpty {
                    ContentUnavailableView(filter == "active" ? "Ingen aktive bestillinger" : "Ingen fullførte bestillinger", systemImage: "calendar", description: Text("Tilbud du godtar, lagres her."))
                }
                ForEach(rows) { booking in
                    Button { selected = booking; store.error = nil } label: { BookingCard(booking: booking) }
                        .buttonStyle(.plain).accessibilityIdentifier("history-\(booking.receipt.offer.service)")
                }
            }.padding(20)
        }.background(Palette.backdrop.ignoresSafeArea()).navigationTitle("Historikk")
            .refreshable { await store.refreshBookings() }.task { await store.refreshBookings() }
            .sheet(item: $selected) { booking in NavigationStack { BookingDetailView(store: store, initial: booking) } }
    }
}

struct BookingCard: View {
    let booking: Booking
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(booking.receipt.offer.title).font(.title3.weight(.semibold))
                    Text(booking.receipt.offer.workshop.name).font(.subheadline).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 12)
                Text(booking.receipt.offer.price).font(.headline)
            }
            Divider()
            Label(booking.appointmentLabel, systemImage: "calendar").font(.subheadline)
            HStack {
                Text(booking.state == "active" ? "Planlagt" : "Fullført").font(.caption).foregroundStyle(Palette.muted)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.muted)
            }
        }.padding(24).foregroundStyle(Palette.ink).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Palette.line, lineWidth: 0.5))
    }
}

struct BookingDetailView: View {
    @Bindable var store: AppStore
    let initial: Booking
    @Environment(\.dismiss) private var dismiss
    @State private var changingTime = false
    @State private var date = Date.now.addingTimeInterval(86400)
    private var booking: Booking { store.bookings.first { $0.id == initial.id } ?? initial }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                BookingCard(booking: booking)
                Label(booking.receipt.offer.workshop.address, systemImage: "mappin.and.ellipse").font(.subheadline)
                if let method = booking.paymentMethod {
                    Label(method == "vipps" ? "Vipps" : "Apple Pay", systemImage: "creditcard").font(.subheadline)
                }
                VStack(alignment: .leading, spacing: 14) {
                    Text("Inkludert").font(.headline)
                    ForEach(booking.receipt.offer.includes, id: \.self) { Text($0).font(.subheadline) }
                }
                if booking.state == "active" {
                    PrimaryButton(title: "Endre tidspunkt", busy: store.busy) {
                        date = max(Date.now.addingTimeInterval(86400), booking.appointmentAt.flatMap(Dates.instant) ?? Date.now.addingTimeInterval(86400))
                        changingTime = true
                    }.accessibilityIdentifier("rescheduleBooking")
                    Button("Marker som fullført") { Task { await store.changeBooking(booking, state: "completed") } }
                        .font(.subheadline).disabled(store.busy).accessibilityIdentifier("completeBooking")
                }
                if let error = store.error { ErrorBanner(message: error) }
            }.padding(20)
        }.background(Palette.backdrop.ignoresSafeArea()).navigationTitle("Bestilling").navigationBarTitleDisplayMode(.inline)
            .blockingLoading(store.busy)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Ferdig") { dismiss() } } }
            .sheet(isPresented: $changingTime) {
                NavigationStack {
                    Form {
                        DatePicker("Nytt tidspunkt", selection: $date, in: Date.now...Date.now.addingTimeInterval(1095 * 86400))
                    }.navigationTitle("Endre tidspunkt").navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Avbryt") { changingTime = false } }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Lagre") { Task { await store.changeBooking(booking, appointment: date); if store.error == nil { changingTime = false } } }.disabled(store.busy)
                            }
                        }
                }.blockingLoading(store.busy).presentationDetents([.medium])
            }
    }
}
