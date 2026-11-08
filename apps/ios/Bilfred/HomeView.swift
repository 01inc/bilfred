import SwiftUI

struct HomeView: View {
    @Bindable var store: AppStore
    @State private var detail: TimelineItem?
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                if let home = store.home {
                    VStack(spacing: 0) {
                        VehicleCover(home: home, width: geometry.size.width)
                            .overlay(alignment: .top) {
                                HStack {
                                    Text("Bilfred").font(.system(.title3, weight: .semibold))
                                    Spacer()
                                    Menu {
                                        Button("Oppdater bilinformasjon") { Task { await store.refreshHome() } }
                                        Button("Start på nytt", role: .destructive) { store.reset() }
                                    } label: {
                                        Image(systemName: "ellipsis").font(.title3)
                                            .frame(width: 40, height: 40)
                                            .background(.ultraThinMaterial, in: Circle())
                                    }.disabled(store.busy || store.pendingKey != nil).accessibilityLabel("Bilmeny")
                                }.foregroundStyle(.white).environment(\.colorScheme, .dark)
                                    .padding(.horizontal, 24).padding(.top, geometry.safeAreaInsets.top + 8)
                            }
                        VStack(alignment: .leading, spacing: 22) {
                            nextAction(home)
                            if let error = store.error { ErrorBanner(message: error) }
                            Text("Vedlikehold").font(.system(.title2, weight: .semibold)).padding(.top, 7)
                            if store.maintenanceLoading {
                                ProgressView().frame(maxWidth: .infinity, minHeight: 180)
                                    .accessibilityLabel("Laster vedlikeholdsplan")
                            }
                            if let message = store.maintenanceMessage {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(message).font(.subheadline).foregroundStyle(Palette.muted)
                                    Button("Prøv igjen") { store.loadMaintenance() }
                                }
                            }
                            VStack(spacing: 0) {
                                ForEach(Array(home.timeline.enumerated()), id: \.element.id) { index, item in
                                    maintenanceCard(item)
                                        .padding(.leading, 28)
                                        .padding(.bottom, index == home.timeline.count - 1 ? 0 : 14)
                                        .background(alignment: .leading) {
                                            MaintenanceTimelineRail(
                                                first: index == 0,
                                                last: index == home.timeline.count - 1,
                                                recorded: item.state == "recorded",
                                                official: item.kind == "official"
                                            ).frame(width: 14)
                                        }
                                }
                            }
                        }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
                    }
                }
            }.ignoresSafeArea(edges: .top)
        }.background(Palette.soft.ignoresSafeArea()).foregroundStyle(Palette.ink).toolbar(.hidden, for: .navigationBar)
            .sheet(item: $detail) { item in
                NavigationStack {
                    ScrollView { VStack(alignment: .leading, spacing: 22) {
                        Eyebrow(text: item.kind == "official" ? "Frist fra Statens vegvesen" : "Forslag til vedlikehold")
                        Text(item.title).font(.system(size: 32, weight: .semibold))
                        if let due = item.dueOn { Text(Dates.display(due, year: true)).font(.headline) }
                        Text(item.why).font(.body).foregroundStyle(Palette.muted)
                        if item.kind == "proposal" {
                            Text("Foreslått planpunkt. Vi tilpasser datoen når tidligere service er kjent.").font(.footnote).foregroundStyle(Palette.muted)
                        }
                        ForEach(Array((item.guidance ?? []).enumerated()), id: \.offset) { _, guidance in
                            VStack(alignment: .leading, spacing: 9) {
                                Text(guidance.title).font(.headline)
                                Text(guidance.explanation).font(.subheadline).foregroundStyle(Palette.muted)
                                if guidance.intervalKm != nil || guidance.intervalMonths != nil {
                                    Text(intervalLabel(guidance)).font(.subheadline.weight(.semibold))
                                }
                                if let source = guidance.sourceUrl, let url = URL(string: source) {
                                    Link("Les kilden", destination: url).font(.subheadline).foregroundStyle(Palette.accent)
                                }
                            }.padding(17).background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
                        }
                        PrimaryButton(title: "Se verksteder") { detail = nil; Task { await store.findOptions(service: item.id) } }
                        Button("Dette er allerede gjort") { detail = nil; Task { await store.markDone(item) } }
                            .font(.subheadline).frame(maxWidth: .infinity).foregroundStyle(Palette.accent)
                        Spacer(minLength: 0)
                    }.padding(26).padding(.top, 8) }.background(Palette.background)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Ferdig") { detail = nil }
                            }
                        }
                }.presentationDetents(item.guidance == nil ? [.medium, .large] : [.large])
                    .presentationDragIndicator(.visible)
            }
    }
    private func maintenanceCard(_ item: TimelineItem) -> some View {
        Button { detail = item } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: item.state == "recorded" ? "checkmark" : item.symbol)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(item.kind == "official" ? Palette.accent : Palette.ink)
                        .frame(width: 38, height: 38)
                        .background(Palette.soft, in: RoundedRectangle(cornerRadius: 11))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.state == "recorded" ? "Utført" : item.kind == "official" ? "Kontrollfrist" : "Foreslått")
                            .font(.caption).foregroundStyle(Palette.muted)
                        if let due = item.dueOn {
                            Text(Dates.display(due, year: true)).font(.subheadline.weight(.semibold))
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.muted)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title).font(.headline)
                    Text(item.state == "recorded" ? "Oppgitt utført av deg" : item.subtitle)
                        .font(.subheadline).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.padding(18).foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Palette.line.opacity(0.65), lineWidth: 0.5))
                .contentShape(RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(MaintenanceCardButtonStyle()).accessibilityIdentifier("maintenance-\(item.id)")
            .accessibilityHint("Viser detaljer og valg for vedlikeholdet.")
    }
    private func nextAction(_ home: VehicleHome) -> some View {
        let next = home.timeline.first { $0.state != "recorded" }
        return Button { Task { await store.findOptions(service: next?.id ?? "eu_kontroll") } } label: {
            VStack(alignment: .leading, spacing: 13) {
                Text("Anbefalt handling").font(.caption.weight(.semibold)).foregroundStyle(Palette.muted)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(next?.title ?? "EU-kontroll").font(.system(.title2, weight: .semibold))
                        Text(next?.subtitle ?? "Sammenlign verksteder i nærheten.").font(.subheadline).foregroundStyle(Palette.muted)
                    }; Spacer()
                }
                HStack { Text("Se verksteder").font(.system(size: 14, weight: .semibold)); Spacer(); if store.busy { ProgressView() } else { Image(systemName: "arrow.up.right").font(.system(size: 18)) } }.padding(.top, 4).foregroundStyle(Palette.accent)
            }.padding(24).foregroundStyle(Palette.ink).background(Palette.surface, in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Palette.line, lineWidth: 0.5))
        }.buttonStyle(.plain).disabled(store.busy).accessibilityIdentifier("arrangeNextService")
    }
    private func intervalLabel(_ guidance: MaintenanceGuidance) -> String {
        var parts: [String] = []
        if let km = guidance.intervalKm { parts.append(km.formatted(.number.locale(Locale(identifier: "nb_NO"))) + " km") }
        if let months = guidance.intervalMonths { parts.append("\(months) måneder") }
        return "Veiledende intervall: " + parts.joined(separator: " / ")
    }
}

private struct MaintenanceTimelineRail: View {
    let first: Bool
    let last: Bool
    let recorded: Bool
    let official: Bool
    @ScaledMetric(relativeTo: .caption) private var markerY: CGFloat = 37

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                path.move(to: CGPoint(x: 7, y: first ? markerY : 0))
                path.addLine(to: CGPoint(x: 7, y: last ? markerY : geometry.size.height))
            }.stroke(Palette.line, lineWidth: 1.5)
            Circle().fill(recorded ? Palette.accent : Palette.soft)
                .overlay(Circle().strokeBorder(official || recorded ? Palette.accent : Palette.muted.opacity(0.6), lineWidth: 1.5))
                .overlay {
                    if recorded { Image(systemName: "checkmark").font(.system(size: 7, weight: .bold)).foregroundStyle(Palette.onAccent) }
                }
                .frame(width: 12, height: 12).position(x: 7, y: markerY)
        }.accessibilityHidden(true)
    }
}

private struct MaintenanceCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.65 : 1)
    }
}
