import Foundation

struct VehicleFacts: Codable, Sendable {
    var registration: String
    var make: String
    var model: String
    var firstRegisteredOn: String?
    var euDueOn: String?
    var euLastApprovedOn: String?
    var source: String
    var fetchedAt: String?
    var cacheState: String?
    var demo: Bool
    var powertrain: String?
    var name: String { "\(make) \(model)" }
    var registrationYear: String? { firstRegisteredOn.map { String($0.prefix(4)) } }
}

struct VehicleLookup: Codable, Sendable {
    var vehicleId: String
    var facts: VehicleFacts
    var imageUrl: String?
}

struct MileageReading: Codable, Sendable {
    var km: Int
    var observedOn: String
}

struct TimelineItem: Codable, Identifiable, Sendable {
    var id: String
    var title: String
    var subtitle: String
    var kind: String
    var dueOn: String?
    var why: String
    var state: String
    var guidance: [MaintenanceGuidance]? = nil
    var symbol: String {
        switch id {
        case "eu_kontroll", "inspection": "checkmark.shield"
        case "oil_service": "oilcan"
        case "brake_fluid": "drop"
        case "brakes": "brakesignal"
        case "tires": "tire"
        case "cabin_filter", "air_filter": "air.purifier"
        case "gearbox_service", "timing_belt": "gearshape.2"
        case "battery_check": "battery.100percent"
        case "spark_plugs": "bolt"
        default: "wrench.and.screwdriver"
        }
    }
}

struct MaintenanceGuidance: Codable, Sendable {
    var title: String
    var explanation: String
    var intervalKm: Int?
    var intervalMonths: Int?
    var sourceUrl: String?
}

struct VehicleHome: Codable, Sendable {
    var vehicleId: String
    var facts: VehicleFacts
    var mileage: MileageReading?
    var imageUrl: String?
    var timeline: [TimelineItem]
    var acceptance: Acceptance?
}

struct Area: Codable, Sendable {
    var name: String = "Oslo"
    var postcode: String? = nil
    var latitude: Double = 59.9139
    var longitude: Double = 10.7522
    var radiusKm: Double = 15
}

struct ServiceOption: Codable, Identifiable, Sendable {
    var id: String
    var name: String
    var address: String
    var priceOre: Int
    var currency: String
    var rating: Double
    var reviewCount: Int
    var label: String
    var priceSource: String?
    var reputationSource: String?
    var publishedPriceUrl: String?
    var ratingSourceUrl: String?
    var latitude: Double?
    var longitude: Double?
    var price: String { (priceOre / 100).formatted(.number.locale(Locale(identifier: "nb_NO"))) + " kr" }
}

struct SearchResult: Codable, Sendable {
    var mode: String
    var area: Area
    var coverageArea: String
    var notice: String
    var options: [ServiceOption]
}

struct Offer: Codable, Identifiable, Sendable {
    var id: String
    var version: Int
    var mode: String
    var service: String
    var title: String
    var workshop: ServiceOption
    var priceOre: Int
    var currency: String
    var appointmentLabel: String
    var appointmentSource: String
    var includes: [String]
    var terms: String
    var expiresAt: String
    var appointmentAt: String? = nil
    var paymentMethod: String? = nil
    var isLocal: Bool { id.hasPrefix("local-") }
    var price: String { (priceOre / 100).formatted(.number.locale(Locale(identifier: "nb_NO"))) + " kr" }
}

struct Acceptance: Codable, Identifiable, Sendable {
    var id: String
    var offerId: String
    var status: String
    var acceptedAt: String
    var offer: Offer
    var message: String
    var detail: String
}

struct Installation: Decodable, Sendable { var id: String; var token: String }
struct LookupBody: Encodable, Sendable { var registration: String; var demo: Bool }
struct MileageBody: Encodable, Sendable { var km: Int; var observedOn: String }
struct SearchBody: Encodable, Sendable {
    var vehicleId: String
    var service: String
    var area: Area
    var mode = "demo"
}
struct OfferBody: Encodable, Sendable {
    var vehicleId: String
    var service: String
    var area: Area
    var mode = "demo"
    var optionId: String
    var appointmentAt: String?
}
struct AcceptBody: Encodable, Sendable { var offerVersion: Int; var idempotencyKey: String; var paymentMethod: String }
struct HistoryBody: Encodable, Sendable { var service: String; var completedOn: String?; var km: Int? }
struct WriteReceipt: Decodable, Sendable { var id: String }
struct ResearchStatus: Decodable, Sendable { var status: String; var cacheHit: Bool }
struct EmptyBody: Encodable, Sendable {}

struct Booking: Codable, Identifiable, Sendable {
    var id: String
    var state: String
    var revision: Int
    var appointmentAt: String?
    var paymentMethod: String?
    var receipt: Acceptance
    var mode: String
    var isLocal: Bool { mode == "local_demo" }
    var appointmentLabel: String { appointmentAt.flatMap(Dates.instant).map(Dates.appointment) ?? receipt.offer.appointmentLabel }
    static func local(_ receipt: Acceptance) -> Booking {
        Booking(id: "saved-" + receipt.id, state: "active", revision: 1,
                appointmentAt: receipt.offer.appointmentAt, paymentMethod: receipt.offer.paymentMethod,
                receipt: receipt, mode: "local_demo")
    }
}
struct BookingList: Decodable, Sendable { var bookings: [Booking] }
struct BookingUpdateBody: Encodable, Sendable { var revision: Int; var appointmentAt: String?; var state: String? }

enum Dates {
    static func instant(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]; return formatter.date(from: value)
    }
    static func appointment(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "nb_NO")
        formatter.timeZone = TimeZone(identifier: "Europe/Oslo")
        formatter.dateFormat = "d. MMM yyyy 'kl.' HH:mm"; return formatter.string(from: date)
    }
    static var today: String { Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash)) }
    static func display(_ value: String?, year: Bool = false) -> String {
        guard let value else { return "Ikke oppgitt" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: String(value.prefix(10))) else { return value }
        formatter.locale = Locale(identifier: "nb_NO")
        formatter.dateFormat = year ? "d. MMM yyyy" : "d. MMM"
        return formatter.string(from: date)
    }
}
