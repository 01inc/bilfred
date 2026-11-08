import SwiftUI
import Observation

enum Route: Hashable { case mileage, options, schedule, offer, confirmation }
enum AppTab: Hashable { case car, history }

struct SavedState: Codable {
    var home: VehicleHome?
    var offlineDemo: Bool
    var pendingOffer: Offer?
    var pendingKey: String?
    var area: Area
    var bookings: [Booking]? = nil
    var pendingPaymentMethod: String? = nil
}

enum DiskCache {
    static var url: URL {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Bilfred/ui-tests/state.json")
        }
        #endif
        let origin = Bundle.main.object(forInfoDictionaryKey: "BilfredAPIBaseURL") as? String ?? "default"
        let namespace = origin.filter { $0.isLetter || $0.isNumber }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Bilfred/\(namespace)/state.json")
    }
    static func load() -> SavedState? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-test-reset") { return nil }
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(SavedState.self, from: data)
        }
        #endif
        let legacy = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Bilfred/default/state.json")
        guard let data = (try? Data(contentsOf: url)) ?? (try? Data(contentsOf: legacy)) else { return nil }
        return try? JSONDecoder().decode(SavedState.self, from: data)
    }
    static func save(_ state: SavedState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

@MainActor @Observable final class AppStore {
    var path: [Route] = []
    var selectedTab: AppTab = .car
    var bookings: [Booking] = []
    var selectedAppointment = Date.now.addingTimeInterval(86400)
    var paymentMethod = "apple_pay"
    var registration = ""
    var mileageText = ""
    var lookup: VehicleLookup?
    var home: VehicleHome?
    var options: [ServiceOption] = []
    var selectedOptionId: String?
    var currentService = "eu_kontroll"
    var offer: Offer?
    var acceptance: Acceptance?
    var pendingKey: String?
    var area = Area()
    var busy = false
    var error: String?
    var offlineDemo = false
    var localOffers = false
    var maintenanceLoading = false
    var maintenanceMessage: String?
    @ObservationIgnored private var researchTask: Task<Void, Never>?
    private var generation = 0
    private let api = APIClient()

    init() {
        if let saved = DiskCache.load() {
            home = saved.home; offlineDemo = saved.offlineDemo; area = saved.area
            offer = saved.pendingOffer; pendingKey = saved.pendingKey
            bookings = saved.bookings ?? saved.home?.acceptance.map { [Booking.local($0)] } ?? []
            paymentMethod = saved.pendingPaymentMethod ?? "apple_pay"
            if pendingKey != nil && offer != nil { path = [.offer] }
        }
    }

    func persist() {
        DiskCache.save(SavedState(home: home, offlineDemo: offlineDemo,
                                 pendingOffer: pendingKey == nil ? nil : offer,
                                 pendingKey: pendingKey, area: area, bookings: bookings,
                                 pendingPaymentMethod: pendingKey == nil ? nil : paymentMethod))
    }

    func findCar(demo requestedDemo: Bool = false) async {
        #if DEBUG
        let demo = requestedDemo || (ProcessInfo.processInfo.arguments.contains("--ui-testing") && registration == "DEMO")
        #else
        let demo = requestedDemo
        #endif
        guard !busy else { return }
        generation += 1; let current = generation
        busy = true; error = nil
        defer { if current == generation { busy = false } }
        // Let keyboard dismissal and the blocking state settle before a cached
        // result changes NavigationStack in the same render transaction.
        try? await Task.sleep(for: .milliseconds(250))
        guard current == generation, !Task.isCancelled else { return }
        #if DEBUG
        if demo && ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            if ProcessInfo.processInfo.arguments.contains("--ui-test-loading") {
                try? await Task.sleep(for: .milliseconds(12000))
            }
            offlineDemo = true; lookup = Demo.lookup; mileageText = ""; path = [.mileage]; return
        }
        #endif
        do {
            let result: VehicleLookup = try await api.post("/v1/vehicles/lookup", body: LookupBody(registration: demo ? "DEMO" : registration, demo: demo))
            guard current == generation else { return }
            lookup = result; offlineDemo = false; mileageText = ""; path = [.mileage]
        } catch {
            guard current == generation else { return }
            if demo {
                offlineDemo = true; lookup = Demo.lookup; mileageText = ""; path = [.mileage]
            } else { self.error = error.localizedDescription }
        }
    }

    func addMileage() async {
        guard let lookup, let km = Int(mileageText.filter(\.isNumber)), km <= 3_000_000 else {
            error = "Skriv inn kilometerstanden."; return
        }
        guard !busy else { return }; busy = true; error = nil
        defer { busy = false }
        do {
            if offlineDemo {
                home = Demo.home(lookup: lookup, km: km)
            } else {
                let _: WriteReceipt = try await api.post("/v1/vehicles/\(lookup.vehicleId)/mileage", body: MileageBody(km: km, observedOn: Dates.today))
                home = try await api.request("/v1/vehicles/\(lookup.vehicleId)/home")
            }
            path = []; persist(); loadMaintenance()
        } catch { self.error = error.localizedDescription }
    }

    func refreshHome() async {
        guard let home, !offlineDemo else { return }
        let current = generation
        do {
            var value: VehicleHome = try await api.request("/v1/vehicles/\(home.vehicleId)/home")
            // A receipt already acknowledged and saved on this device remains
            // viewable after installation recovery; no new acceptance is inferred.
            if value.acceptance == nil { value.acceptance = home.acceptance }
            guard current == generation else { return }; self.home = value; persist()
        } catch {
            if (error as? APIError)?.status == 404, pendingKey == nil {
                // A restored device may retain its protected car cache without
                // its device-only Keychain item. Re-enrol only its cached car
                // through normal scoped endpoints; never transfer server ownership.
                do {
                    let restored: VehicleLookup = try await api.post("/v1/vehicles/lookup", body: LookupBody(registration: home.facts.registration, demo: home.facts.demo))
                    if let mileage = home.mileage {
                        let _: WriteReceipt = try await api.post("/v1/vehicles/\(restored.vehicleId)/mileage", body: MileageBody(km: mileage.km, observedOn: mileage.observedOn))
                    }
                    var recovered: VehicleHome = try await api.request("/v1/vehicles/\(restored.vehicleId)/home")
                    recovered.acceptance = home.acceptance
                    guard current == generation else { return }
                    self.home = recovered; persist()
                } catch { /* Retain cached facts, source time and saved receipt. */ }
            }
        }
    }

    func loadMaintenance() {
        guard let home, !offlineDemo, !home.facts.demo, researchTask == nil else { return }
        let current = generation
        maintenanceLoading = !home.timeline.contains { $0.kind == "proposal" }
        maintenanceMessage = nil
        researchTask = Task {
            defer { if current == generation { maintenanceLoading = false; researchTask = nil } }
            do {
                var status: ResearchStatus = try await api.post("/v1/vehicles/\(home.vehicleId)/research", body: EmptyBody())
                for _ in 0..<60 {
                    guard current == generation, !Task.isCancelled else { return }
                    if status.status == "ready" { await refreshHome(); return }
                    if status.status == "failed" || status.status == "demo" { break }
                    maintenanceLoading = true
                    try await Task.sleep(for: .seconds(4))
                    status = try await api.request("/v1/vehicles/\(home.vehicleId)/research")
                }
                maintenanceMessage = "Bilplanen er ikke klar ennå. Du kan prøve igjen."
            } catch is CancellationError { }
            catch { maintenanceMessage = "Vedlikeholdsplanen kunne ikke oppdateres. Lagrede opplysninger er beholdt." }
        }
    }

    func findOptions(service: String) async {
        guard let home, !busy else { return }
        currentService = service; error = nil; busy = true
        localOffers = false
        defer { busy = false }
        do {
            if offlineDemo { options = Demo.options }
            else {
                let result: SearchResult = try await api.post("/v1/service-searches", body: SearchBody(vehicleId: home.vehicleId, service: service, area: area))
                options = result.options
            }
            selectedOptionId = options.first?.id
            path = [.options]
        } catch {
            if error is URLError || ((error as? APIError)?.status ?? 0) >= 500 {
                localOffers = true; options = Demo.options
                selectedOptionId = options.first?.id; path = [.options]
                self.error = "Uten forbindelse. Du kan prøve lokale demotilbud."
            } else { self.error = error.localizedDescription }
        }
    }

    func selectOffer() async {
        guard let home, let selectedOptionId, !busy, pendingKey == nil else { return }
        busy = true; error = nil; defer { busy = false }
        do {
            if offlineDemo || localOffers {
                guard let option = options.first(where: { $0.id == selectedOptionId }) else { return }
                offer = Demo.offer(option: option, service: currentService)
                offer?.appointmentAt = selectedAppointment.ISO8601Format()
                offer?.appointmentLabel = Dates.appointment(selectedAppointment)
            } else {
                offer = try await api.post("/v1/offers", body: OfferBody(vehicleId: home.vehicleId, service: currentService, area: area, optionId: selectedOptionId, appointmentAt: selectedAppointment.ISO8601Format()))
            }
            path.append(.offer)
        } catch { self.error = error.localizedDescription }
    }

    func acceptOffer() async {
        guard var offer, !busy else { return }
        offer.paymentMethod = paymentMethod
        busy = true; error = nil
        pendingKey = pendingKey ?? UUID().uuidString
        persist()
        defer { busy = false }
        do {
            let receipt: Acceptance
            if offer.isLocal {
                receipt = Acceptance(id: UUID().uuidString, offerId: offer.id, status: "demo_accepted_local",
                    acceptedAt: Date.now.ISO8601Format(), offer: offer, message: "Demobestilling lagret",
                    detail: "Demobestillingen er lagret på denne enheten. Ingen faktisk verkstedtime er opprettet.")
            } else {
                receipt = try await api.post("/v1/offers/\(offer.id)/acceptances", body: AcceptBody(offerVersion: offer.version, idempotencyKey: pendingKey!, paymentMethod: paymentMethod))
            }
            if offer.isLocal { bookings.insert(.local(receipt), at: 0) }
            else {
                await refreshBookings()
                if !bookings.contains(where: { $0.receipt.id == receipt.id }) { bookings.insert(.local(receipt), at: 0) }
            }
            acceptance = receipt; home?.acceptance = receipt; pendingKey = nil; persist()
            withAnimation(.spring(duration: 0.45)) { path = [.confirmation] }
        } catch {
            if let apiError = error as? APIError, (400..<500).contains(apiError.status) {
                pendingKey = nil; self.error = apiError.message
            } else {
                self.error = "Svaret kom ikke frem. Prøv igjen for å kontrollere samme bestilling."
            }
            persist()
        }
    }

    func markDone(_ item: TimelineItem) async {
        guard let home, !busy else { return }
        busy = true; defer { busy = false }
        do {
            if offlineDemo {
                if let index = self.home?.timeline.firstIndex(where: { $0.id == item.id }) { self.home?.timeline[index].state = "recorded" }
            } else {
                let _: WriteReceipt = try await api.post("/v1/vehicles/\(home.vehicleId)/history", body: HistoryBody(service: item.id, completedOn: nil, km: nil))
                await refreshHome()
            }
            persist()
        } catch { self.error = error.localizedDescription }
    }

    func chooseAppointment() {
        guard !busy, pendingKey == nil else { return }
        var date = Date.now.addingTimeInterval(86400)
        if let value = home?.timeline.first(where: { $0.id == currentService })?.dueOn {
            let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
            if let planned = formatter.date(from: value) {
                date = max(date, currentService == "eu_kontroll" ? planned.addingTimeInterval(-14 * 86400) : planned)
            }
        }
        selectedAppointment = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: date) ?? date
        paymentMethod = "apple_pay"; path.append(.schedule)
    }

    func refreshBookings() async {
        guard !offlineDemo else { return }
        do {
            let result: BookingList = try await api.request("/v1/bookings")
            let local = bookings.filter(\.isLocal)
            bookings = result.bookings + local.filter { cached in !result.bookings.contains { $0.receipt.id == cached.receipt.id } }
            persist()
        } catch { /* Keep the last fetched history available offline. */ }
    }

    func changeBooking(_ booking: Booking, appointment: Date? = nil, state: String? = nil) async {
        guard !busy else { return }; busy = true; error = nil; defer { busy = false }
        do {
            if booking.isLocal {
                if let index = bookings.firstIndex(where: { $0.id == booking.id }) {
                    if let appointment { bookings[index].appointmentAt = appointment.ISO8601Format() }
                    if let state { bookings[index].state = state }
                    bookings[index].revision += 1
                }
            } else {
                let _: WriteReceipt = try await api.patch("/v1/bookings/\(booking.id)", body: BookingUpdateBody(revision: booking.revision, appointmentAt: appointment?.ISO8601Format(), state: state))
                await refreshBookings()
            }
            persist()
        } catch { self.error = error.localizedDescription }
    }

    func reset() {
        researchTask?.cancel(); researchTask = nil; maintenanceLoading = false; maintenanceMessage = nil
        generation += 1; home = nil; lookup = nil; options = []; offer = nil
        acceptance = nil; pendingKey = nil; registration = ""; mileageText = ""
        path = []; selectedTab = .car; error = nil; busy = false; offlineDemo = false; localOffers = false; persist()
    }
}

enum Demo {
    static let lookup = VehicleLookup(vehicleId: "local-demo", facts: VehicleFacts(
        registration: "DEMO", make: "Škoda", model: "Superb", firstRegisteredOn: "2020-06-15",
        euDueOn: "2026-11-30", euLastApprovedOn: "2024-11-12", source: "Demodata",
        fetchedAt: nil, cacheState: "demo", demo: true, powertrain: "Ladbar hybrid"), imageUrl: nil)
    static func home(lookup: VehicleLookup, km: Int) -> VehicleHome {
        VehicleHome(vehicleId: lookup.vehicleId, facts: lookup.facts, mileage: MileageReading(km: km, observedOn: Dates.today), imageUrl: nil,
                    timeline: [
                        TimelineItem(id: "eu_kontroll", title: "EU-kontroll", subtitle: "Periodisk kontroll av bilen.", kind: "demo", dueOn: "2026-11-30", why: "En illustrativ kontrollfrist i demovisningen.", state: "upcoming"),
                        TimelineItem(id: "service", title: "Neste service", subtitle: "Servicehistorikk mangler.", kind: "suggestion", dueOn: nil, why: "Tidligere servicehistorikk mangler. Dette er et forslag om gjennomgang.", state: "suggested"),
                        TimelineItem(id: "tires", title: "Dekksjekk", subtitle: "Dekk, mønsterdybde og lufttrykk.", kind: "suggestion", dueOn: nil, why: "En sesongkontroll er et forslag, ikke en diagnose.", state: "suggested")], acceptance: nil)
    }
    static let options: [ServiceOption] = [
        ServiceOption(id: "demo-1", name: "Demoverksted Sagene", address: "Sagene, Oslo · illustrasjon", priceOre: 129000, currency: "NOK", rating: 4.8, reviewCount: 128, label: "Anbefalt", priceSource: "demo", reputationSource: "demo", latitude: 59.936, longitude: 10.754),
        ServiceOption(id: "demo-2", name: "Demoverksted Sentrum", address: "Sentrum, Oslo · illustrasjon", priceOre: 109000, currency: "NOK", rating: 4.5, reviewCount: 86, label: "Lavest pris", priceSource: "demo", reputationSource: "demo", latitude: 59.914, longitude: 10.752),
        ServiceOption(id: "demo-3", name: "Demoverksted Økern", address: "Økern, Oslo · illustrasjon", priceOre: 149000, currency: "NOK", rating: 4.9, reviewCount: 214, label: "Best vurdert", priceSource: "demo", reputationSource: "demo", latitude: 59.929, longitude: 10.797)
    ]
    static func offer(option: ServiceOption, service: String) -> Offer {
        let title = ["eu_kontroll": "EU-kontroll", "oil_service": "Oljeservice", "inspection": "Inspeksjonsservice", "tires": "Dekksjekk", "brakes": "Bremsekontroll", "brake_fluid": "Bremsevæske", "cabin_filter": "Kupéfilter"][service] ?? "Servicegjennomgang"
        return Offer(id: "local-" + UUID().uuidString, version: 1, mode: "demo", service: service,
              title: title, workshop: option,
              priceOre: option.priceOre, currency: "NOK", appointmentLabel: "Torsdag 12. november · kl. 10.00",
              appointmentSource: "demo", includes: [title, "Rapport fra verkstedet", "Tilleggsarbeid avtales separat"],
              terms: "Demonstrasjon. Ingen betaling eller faktisk verkstedtime opprettes.", expiresAt: Date.now.addingTimeInterval(86400).ISO8601Format())
    }
}
