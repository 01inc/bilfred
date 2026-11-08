import SwiftUI

/// A full-width photograph that fades into the home surface, without a card edge.
struct VehicleCover: View {
    let home: VehicleHome
    let width: CGFloat
    private var photo: UIImage? {
        guard home.facts.make == "Škoda", home.facts.model == "Superb",
              let path = Bundle.main.path(forResource: "superb", ofType: "png") else { return nil }
        return UIImage(contentsOfFile: path)
    }
    var body: some View {
        let height = min(620, max(530, width * 1.35))
        ZStack(alignment: .bottom) {
            if let photo {
                Image(uiImage: photo).resizable().scaledToFill()
                    .frame(width: width, height: height).clipped().accessibilityHidden(true)
            } else {
                Palette.soft.overlay(Image(systemName: "car.side.fill").font(.system(size: 90)).foregroundStyle(Palette.muted))
            }
            LinearGradient(stops: [
                .init(color: .black.opacity(0.35), location: 0),
                .init(color: .clear, location: 0.28),
                .init(color: .black.opacity(0.12), location: 0.48),
                .init(color: .black.opacity(0.78), location: 0.78),
                .init(color: .black.opacity(0.78), location: 1)
            ], startPoint: .top, endPoint: .bottom)
            LinearGradient(stops: [
                .init(color: Palette.soft.opacity(0), location: 0.72),
                .init(color: Palette.soft.opacity(0.35), location: 0.86),
                .init(color: Palette.soft, location: 1)
            ], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 13) {
                Text(home.facts.name).font(.system(.largeTitle, weight: .semibold)).multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 2)
                HStack(spacing: 8) {
                    Text(home.facts.registration).font(.system(.caption, design: .monospaced, weight: .semibold))
                    Text("·")
                    Text(home.facts.powertrain ?? home.facts.registrationYear ?? "")
                }.font(.caption).foregroundStyle(.white.opacity(0.85))
                HStack(spacing: 12) {
                    value(home.mileage.map { $0.km.formatted(.number.locale(Locale(identifier: "nb_NO"))) + " km" } ?? "—", label: "Kilometerstand")
                    Rectangle().fill(.white.opacity(0.22)).frame(width: 0.5, height: 32)
                    value(Dates.display(home.facts.euDueOn, year: true), label: "EU-frist")
                }.padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
                    .environment(\.colorScheme, .dark)
            }.foregroundStyle(.white).padding(.horizontal, 24).padding(.bottom, 28)
        }.frame(width: width, height: height).clipped()
    }
    private func value(_ text: String, label: String) -> some View {
        VStack(spacing: 5) {
            Text(text).font(.system(.subheadline, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.75))
        }.frame(maxWidth: .infinity)
    }
}
