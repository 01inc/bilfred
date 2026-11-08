import SwiftUI
import MapKit

struct OptionsView: View {
    @Bindable var store: AppStore
    @State private var camera: MapCameraPosition = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 59.923, longitude: 10.78), latitudinalMeters: 9_000, longitudinalMeters: 9_000))
    @State private var showArea = false
    @State private var resolver = AreaResolver()
    @FocusState private var areaFocused: Bool
    @State private var manualArea = "Oslo"
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack { Text("Verksteder").font(.system(.title, weight: .semibold)); Spacer(); Button { showArea = true } label: { Label(store.area.name, systemImage: "location").font(.system(size: 12, weight: .semibold)) } }
                Text("Valgt for omdømme, beliggenhet og pris.")
                    .font(.system(size: 14)).foregroundStyle(Palette.muted).padding(.top, -12)
                Map(position: $camera, selection: $store.selectedOptionId) {
                    ForEach(store.options) { option in
                        if let lat = option.latitude, let lon = option.longitude {
                            Marker(option.name, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
                                .tint(option.id == store.selectedOptionId ? Palette.accent : Color.gray)
                                .tag(option.id)
                        }
                    }
                }.mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                    .frame(height: 195).clipShape(RoundedRectangle(cornerRadius: 23))
                    .accessibilityLabel("Kart over verkstedalternativer i Oslo")
                if store.area.name.lowercased() != "oslo" {
                    Text("Demovisningen bruker verksteder i Oslo.").font(.caption).foregroundStyle(Palette.muted)
                }
                VStack(spacing: 10) {
                    ForEach(Array(store.options.enumerated()), id: \.element.id) { index, option in
                        optionCard(option, number: index + 1)
                    }
                }
                if let error = store.error { ErrorBanner(message: error) }
            }.padding(.horizontal, 20).padding(.top, 12)
        }.background(Palette.backdrop.ignoresSafeArea()).foregroundStyle(Palette.ink)
            .navigationTitle(store.currentService == "eu_kontroll" ? "EU-kontroll" : "Verksted")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(title: "Velg tidspunkt", busy: store.busy) { store.chooseAppointment() }
                    .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 9)
                    .background(Palette.background).accessibilityIdentifier("showSelectedOffer")
            }
            .toolbar(.hidden, for: .tabBar)
            .sensoryFeedback(.selection, trigger: store.selectedOptionId)
            .task(id: store.options.map(\.id).joined()) {
                let options = store.options
                for option in options {
                    if let point = await resolveWorkshop(option, area: store.area),
                       let index = store.options.firstIndex(where: { $0.id == option.id }) {
                        store.options[index].latitude = point.latitude; store.options[index].longitude = point.longitude
                    }
                }
                if store.options.contains(where: { $0.latitude != nil }) { withAnimation(.easeInOut(duration: 0.4)) { camera = .automatic } }
            }
            .sheet(isPresented: $showArea) { areaSheet }
            .onChange(of: resolver.resolved?.name) { _, _ in
                guard let area = resolver.resolved else { return }
                store.area = area; store.persist(); showArea = false
                Task { await store.findOptions(service: store.currentService) }
            }
    }

    private func optionCard(_ option: ServiceOption, number: Int) -> some View {
        let selected = store.selectedOptionId == option.id
        return Button {
            withAnimation(.snappy(duration: 0.22)) { store.selectedOptionId = option.id }
        } label: {
            HStack(alignment: .center, spacing: 13) {
                Text("\(number)").font(.system(size: 12, weight: .semibold)).foregroundStyle(selected ? .white : Palette.muted)
                    .frame(width: 27, height: 27).background(selected ? Palette.accent : Palette.soft, in: Circle())
                VStack(alignment: .leading, spacing: 7) {
                    Text(option.name).font(.system(size: 14, weight: .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(Color(red: 0.65, green: 0.53, blue: 0.25))
                        Text(option.rating.formatted(.number.precision(.fractionLength(1))))
                        Text("(\(option.reviewCount))").foregroundStyle(Palette.muted)
                        if let distance = distance(option) { Text("· \(distance)").foregroundStyle(Palette.muted) }
                    }.font(.system(size: 11))
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 8) {
                    Text(option.price).font(.system(size: 19, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    if number == 1 { Text("Anbefalt").font(.system(size: 9, weight: .semibold)).padding(.horizontal, 7).padding(.vertical, 4).background(Palette.soft, in: Capsule()) }
                    else { Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? Palette.accent : Palette.line) }
                }
            }.foregroundStyle(Palette.ink).padding(16).frame(minHeight: 96)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(selected ? Palette.accent : Color.clear, lineWidth: 1.7))
        }.buttonStyle(.plain).accessibilityIdentifier("option\(number)")
            .accessibilityLabel("\(option.name), \(option.price), vurdering \(option.rating) av 5, \(option.reviewCount) anmeldelser")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func distance(_ option: ServiceOption) -> String? {
        guard let lat = option.latitude, let lon = option.longitude else { return nil }
        let km = CLLocation(latitude: lat, longitude: lon).distance(from: CLLocation(latitude: store.area.latitude, longitude: store.area.longitude)) / 1000
        return "ca. " + km.formatted(.number.precision(.fractionLength(1))) + " km"
    }
    private var areaSheet: some View {
        NavigationStack {
        VStack(alignment: .leading, spacing: 22) {
            Text("Hvor passer det deg?").font(.system(size: 29, weight: .semibold))
            Text("Vi bruker området ditt for å finne verksteder i nærheten.").foregroundStyle(Palette.muted)
            PrimaryButton(title: "Bruk posisjonen min", busy: resolver.resolving) { resolver.request() }
            HStack {
                TextField("By eller postnummer", text: $manualArea).textContentType(.addressCity).focused($areaFocused).submitLabel(.search)
                    .onSubmit { areaFocused = false; Task { await resolver.manual(manualArea) } }.accessibilityIdentifier("manualArea")
                Button { areaFocused = false; Task { await resolver.manual(manualArea) } } label: { Image(systemName: "arrow.right.circle.fill").font(.title2) }
            }.padding(18).background(Palette.surface, in: RoundedRectangle(cornerRadius: 15))
            if let error = resolver.error { ErrorBanner(message: error) }
            Spacer(minLength: 0)
        }.padding(24).background(Palette.background)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Ferdig") { showArea = false } }
                KeyboardCloseToolbar { areaFocused = false }
            }
            .blockingLoading(resolver.resolving)
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
}
