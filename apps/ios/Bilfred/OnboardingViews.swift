import SwiftUI

/// Keeps the main content centered in the space above the bottom actions.
struct OnboardingPage<Content: View, Actions: View>: View {
    @ViewBuilder var content: (CGSize) -> Content
    @ViewBuilder var actions: () -> Actions
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                content(geometry.size)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24).padding(.vertical, 24)
                    .frame(minHeight: max(0, geometry.size.height), alignment: .center)
            }.scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10, content: actions)
                .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 12)
                .background(Palette.background)
        }
        .background(Palette.background.ignoresSafeArea()).foregroundStyle(Palette.ink)
    }
}

struct PlateView: View {
    @Bindable var store: AppStore
    @FocusState private var focused: Bool
    var body: some View {
        OnboardingPage { _ in
            VStack(spacing: 24) {
                Text("Hvilken bil har du?").font(.largeTitle.weight(.semibold))
                    .multilineTextAlignment(.center)
                plate
                if let error = store.error { ErrorBanner(message: error) }
            }
        } actions: {
            PrimaryButton(title: "Finn bilen min", busy: store.busy) {
                focused = false; Task { await store.findCar() }
            }.disabled(store.registration.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("findCar")
        }
        .safeAreaInset(edge: .top) { Brand().frame(maxWidth: .infinity).padding(.vertical, 16) }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar { KeyboardCloseToolbar { focused = false } }
        .task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, store.path.isEmpty, !store.busy else { return }
            focused = true
        }
    }

    private var plate: some View {
        HStack(spacing: 0) {
            VStack(spacing: 10) {
                ZStack {
                    Rectangle().fill(Color(red: 0.82, green: 0.08, blue: 0.13))
                    Rectangle().fill(.white).frame(width: 9)
                    Rectangle().fill(.white).frame(height: 9)
                    Rectangle().fill(Color(red: 0.03, green: 0.12, blue: 0.30)).frame(width: 5)
                    Rectangle().fill(Color(red: 0.03, green: 0.12, blue: 0.30)).frame(height: 5)
                }.frame(width: 27, height: 20)
                Text("N").font(.system(size: 27, weight: .bold)).foregroundStyle(.white)
            }.frame(width: 53, height: 100).background(Color(red: 0.04, green: 0.24, blue: 0.57))
            TextField("AB 12345", text: $store.registration)
                .font(.system(size: 37, weight: .semibold, design: .monospaced)).foregroundStyle(.black)
                .textInputAutocapitalization(.characters).autocorrectionDisabled().keyboardType(.asciiCapable)
                .submitLabel(.search).focused($focused).multilineTextAlignment(.center)
                .padding(.horizontal, 9).accessibilityLabel("Registreringsnummer")
                .accessibilityIdentifier("registrationInput")
                .onChange(of: store.registration) { _, value in
                    let normalized = String(value.uppercased().filter { $0.isLetter || $0.isNumber || $0 == " " }.prefix(14))
                    if normalized != value { store.registration = normalized }
                }
                .onSubmit { focused = false; Task { await store.findCar() } }
        }.frame(height: 100).background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Palette.ink, lineWidth: 2))
            .shadow(color: Palette.ink.opacity(0.07), radius: 12, y: 6)
    }
}

struct MileageView: View {
    @Bindable var store: AppStore
    @FocusState private var focused: Bool
    var body: some View {
        OnboardingPage { size in
            if let vehicle = store.lookup {
                VStack(spacing: 22) {
                    Text(vehicle.facts.name).font(.title.weight(.semibold)).multilineTextAlignment(.center)
                    CarImage(facts: vehicle.facts, size: min(230, max(96, size.height * 0.38)))
                    VStack(spacing: 16) {
                        Text("Hvor langt har bilen kjørt?").font(.title2.weight(.semibold)).multilineTextAlignment(.center)
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            TextField("124 239", text: $store.mileageText).keyboardType(.numberPad)
                                .font(.largeTitle.weight(.semibold)).focused($focused)
                                .accessibilityIdentifier("mileageInput").accessibilityLabel("Kilometerstand")
                            Text("km").font(.title3).foregroundStyle(Palette.muted)
                        }.padding(18).background(Palette.field, in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.line, lineWidth: 0.5))
                    }
                    if let error = store.error { ErrorBanner(message: error) }
                }
            }
        } actions: {
            PrimaryButton(title: "Legg til bilen", busy: store.busy) {
                focused = false; Task { await store.addMileage() }
            }.disabled(store.mileageText.filter(\.isNumber).isEmpty).accessibilityIdentifier("addCar")
        }
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .toolbar { KeyboardCloseToolbar { focused = false } }
    }
}
