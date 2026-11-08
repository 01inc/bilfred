import Foundation
import Observation
@preconcurrency import CoreLocation
@preconcurrency import MapKit

@MainActor @Observable final class AreaResolver: NSObject, @preconcurrency CLLocationManagerDelegate {
    var resolving = false
    var error: String?
    var resolved: Area?
    private let manager = CLLocationManager()
    override init() { super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyKilometer }
    func request() {
        error = nil; resolving = true
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        case .notDetermined: manager.requestWhenInUseAuthorization()
        default: resolving = false; error = "Velg område manuelt, eller gi tilgang i Innstillinger."
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard resolving else { return }
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways { manager.requestLocation() }
        else if manager.authorizationStatus != .notDetermined { resolving = false; error = "Du kan velge område manuelt." }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { resolving = false; return }
        Task {
            defer { resolving = false }
            do {
                guard let reverse = MKReverseGeocodingRequest(location: location) else { throw CLError(.geocodeFoundNoResult) }
                let marks = try await reverse.mapItems
                guard let name = marks.first?.addressRepresentations?.cityName else { throw CLError(.geocodeFoundNoResult) }
                // Geocode the locality anew: only its public centroid leaves the device.
                guard let request = MKGeocodingRequest(addressString: name + ", Norge") else { throw CLError(.geocodeFoundNoResult) }
                let locality = try await request.mapItems
                guard let centroid = locality.first?.location.coordinate else { throw CLError(.geocodeFoundNoResult) }
                resolved = Area(name: name, latitude: centroid.latitude, longitude: centroid.longitude)
            } catch { self.error = "Vi fant ikke området. Skriv inn et sted i stedet." }
        }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        resolving = false; self.error = "Posisjonen er ikke tilgjengelig. Velg område manuelt."
    }
    func manual(_ name: String) async {
        resolving = true; error = nil; defer { resolving = false }
        do {
            let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let request = MKGeocodingRequest(addressString: normalized + ", Norge") else { throw CLError(.geocodeFoundNoResult) }
            let results = try await request.mapItems
            guard let item = results.first else { throw CLError(.geocodeFoundNoResult) }
            let coordinate = item.location.coordinate
            let postcode = normalized.count == 4 && normalized.allSatisfy(\.isNumber) ? normalized : nil
            resolved = Area(name: item.addressRepresentations?.cityName ?? normalized, postcode: postcode, latitude: coordinate.latitude, longitude: coordinate.longitude)
        } catch { self.error = "Vi fant ikke stedet. Prøv et postnummer eller en by." }
    }
}

@MainActor func resolveWorkshop(_ option: ServiceOption, area: Area) async -> CLLocationCoordinate2D? {
    if let lat = option.latitude, let lon = option.longitude { return CLLocationCoordinate2D(latitude: lat, longitude: lon) }
    let request = MKLocalSearch.Request()
    request.naturalLanguageQuery = option.name + ", " + option.address
    request.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: area.latitude, longitude: area.longitude), latitudinalMeters: 30_000, longitudinalMeters: 30_000)
    do {
        let response = try await MKLocalSearch(request: request).start()
        let expectedStreet = option.address.split(separator: ",").first.map(String.init)?.lowercased() ?? ""
        let expectedName = expectedStreet.components(separatedBy: .decimalDigits).joined().trimmingCharacters(in: .whitespaces)
        let match = response.mapItems.first { item in
            guard !expectedName.isEmpty, let street = item.address?.fullAddress.lowercased() else { return false }
            return street.contains(expectedName)
        }
        if let match { return match.location.coordinate }
        // Resolve the official registry's address directly when Apple's place
        // directory uses a different trading name for the same workshop.
        guard let geocode = MKGeocodingRequest(addressString: option.address + ", Norge") else { return nil }
        return try await geocode.mapItems.first?.location.coordinate
    } catch { return nil }
}
