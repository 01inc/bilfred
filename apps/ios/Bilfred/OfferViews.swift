import SwiftUI
import ConfettiSwiftUI

struct OfferView: View {
    @Bindable var store: AppStore
    var body: some View {
        ScrollView {
            if let offer = store.offer {
                VStack(alignment: .leading, spacing: 25) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Image(systemName: "checkmark.shield").font(.system(size: 24)).frame(width: 54, height: 54).background(Palette.soft, in: RoundedRectangle(cornerRadius: 15))
                            VStack(alignment: .leading, spacing: 6) {
                                Text(offer.title).font(.system(size: 22, weight: .semibold))
                                Text(offer.workshop.name).font(.system(size: 13)).foregroundStyle(Palette.muted)
                            }
                            Spacer()
                        }
                        Divider().overlay(Palette.line)
                        Label(offer.appointmentLabel, systemImage: "calendar").font(.system(size: 14, weight: .semibold))
                        Label(offer.workshop.address, systemImage: "mappin.and.ellipse").font(.system(size: 13)).foregroundStyle(Palette.muted)
                        Divider().overlay(Palette.line)
                        ForEach(offer.includes, id: \.self) { line in
                            Label(line, systemImage: "checkmark").font(.system(size: 14))
                        }
                    }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(Palette.surface, in: RoundedRectangle(cornerRadius: 24))
                    HStack(alignment: .lastTextBaseline) {
                        VStack(alignment: .leading, spacing: 7) { Text("Totalt").font(.subheadline).foregroundStyle(Palette.muted); Text(offer.price).font(.system(size: 38, weight: .semibold)) }
                        Spacer(); Image(systemName: "lock.shield").font(.system(size: 24)).foregroundStyle(Palette.muted)
                    }.padding(.horizontal, 4)
                    PaymentStrip(selection: $store.paymentMethod, disabled: store.busy || store.pendingKey != nil)
                    if let error = store.error { ErrorBanner(message: error) }
                }.padding(.horizontal, 22).padding(.top, 24).padding(.bottom, 22)
            }
        }.background(Palette.backdrop.ignoresSafeArea()).foregroundStyle(Palette.ink).navigationTitle("Ditt tilbud")
            .navigationBarTitleDisplayMode(.inline).navigationBarBackButtonHidden(store.busy || store.pendingKey != nil)
            .toolbar(.hidden, for: .tabBar)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    SwipeAccept(submitting: store.busy, retrying: store.pendingKey != nil) { Task { await store.acceptOffer() } }
                }.padding(.horizontal, 22).padding(.top, 15).padding(.bottom, 10).background(Palette.background)
            }
    }
}

struct ConfirmationView: View {
    @Bindable var store: AppStore
    @State private var appeared = false
    @State private var celebrated = false
    @State private var confettiTrigger = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        OnboardingPage { _ in
            VStack(spacing: 28) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64, weight: .light)).foregroundStyle(Palette.accent)
                    .scaleEffect(appeared ? 1 : 0.85).opacity(appeared ? 1 : 0)
                    .accessibilityHidden(true)
                Text("Demobestilling\nlagret").font(.largeTitle.weight(.semibold)).multilineTextAlignment(.center)
                if let receipt = store.acceptance ?? store.home?.acceptance {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(receipt.offer.title).font(.headline)
                            Spacer()
                            Text(receipt.offer.price).font(.title3.weight(.semibold))
                        }
                        Text(receipt.offer.workshop.name).font(.subheadline).foregroundStyle(Palette.muted)
                        Divider()
                        Label(receipt.offer.appointmentLabel, systemImage: "calendar").font(.subheadline)
                        if let method = receipt.offer.paymentMethod {
                            Label(method == "vipps" ? "Vipps" : "Apple Pay", systemImage: "creditcard")
                                .font(.subheadline).foregroundStyle(Palette.muted)
                        }
                    }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 24))
                        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Palette.line, lineWidth: 0.5))
                }
            }
        } actions: {
            PrimaryButton(title: "Se i Historikk") { store.path = []; store.selectedTab = .history }
                .accessibilityIdentifier("viewHistory")
            Button("Tilbake til bilen") { store.path = []; store.selectedTab = .car }
                .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("backToCar")
        }
        .overlay {
            if !reduceMotion {
                GeometryReader { geometry in
                    Color.clear.frame(width: 1, height: 1)
                        .confettiCannon(trigger: $confettiTrigger, num: 36,
                            confettis: [.shape(.circle), .shape(.slimRectangle)],
                            colors: [Palette.accent, .cyan, .indigo, .mint],
                            confettiSize: 8, rainHeight: geometry.size.height * 0.7,
                            radius: geometry.size.width * 0.6, hapticFeedback: false)
                        .position(x: geometry.size.width / 2, y: geometry.size.height * 0.3)
                }.allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .toolbar(.hidden, for: .navigationBar).toolbar(.hidden, for: .tabBar)
        .task(id: store.busy) {
            guard !store.busy, !celebrated else { return }
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            guard !Task.isCancelled else { return }
            celebrated = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.8)) { appeared = true }
            if !reduceMotion { confettiTrigger += 1 }
        }
    }
}
