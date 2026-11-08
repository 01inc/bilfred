import SwiftUI

enum Palette {
    // Earned's native semantic color values, as requested for Bilfred.
    static let background = adaptive(0xFBFBFD, 0x323236)
    static let surface = adaptive(0xFFFFFF, 0x434349)
    static let field = adaptive(0xFFFFFF, 0x1C1C1E)
    static let ink = Color.primary
    static let accent = adaptive(0x0068D5, 0x64BFFF)
    static let muted = adaptive(0x545459, 0xC7C7CC)
    static let soft = adaptive(0xF2F2F7, 0x323236)
    static let line = adaptive(0xD1D1D6, 0x343436)
    static let onAccent = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? .black : .white })
    static let backdrop = LinearGradient(stops: [
        .init(color: adaptive(0xFFFFFF, 0x323236), location: 0),
        .init(color: adaptive(0xF2F2F7, 0x202023), location: 0.4)
    ], startPoint: .top, endPoint: .bottom)
    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
}

struct PrimaryButton: View {
    var title: String
    var busy = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Color.clear.frame(width: 20, height: 1).accessibilityHidden(true)
                Text(title).font(.headline).frame(maxWidth: .infinity)
                Image(systemName: "arrow.right").font(.system(size: 17, weight: .semibold))
                    .frame(width: 20).accessibilityHidden(true)
            }.padding(.horizontal, 20).padding(.vertical, 17)
                .frame(maxWidth: .infinity, minHeight: 56)
                .contentShape(RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(PrimaryActionStyle()).disabled(busy)
    }
}

private struct PrimaryActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(enabled ? Palette.onAccent : Palette.muted)
            .background(enabled ? Palette.accent : Palette.line.opacity(0.35), in: RoundedRectangle(cornerRadius: 18))
            .opacity(configuration.isPressed ? 0.86 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct Brand: View {
    var light = false
    var body: some View {
        Text("Bilfred").font(.system(.title3, weight: .semibold))
            .foregroundStyle(Palette.ink)
            .accessibilityLabel("Bilfred")
    }
}

struct Eyebrow: View {
    var text: String
    var body: some View { Text(text).font(.subheadline).foregroundStyle(Palette.muted) }
}

struct CarImage: View {
    var facts: VehicleFacts
    var size: CGFloat
    var body: some View {
        Group {
            if facts.make == "Škoda" && facts.model == "Superb", let path = Bundle.main.path(forResource: "superb", ofType: "png"), let image = UIImage(contentsOfFile: path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack { Palette.soft; Image(systemName: "car.side.fill").font(.system(size: 85)).foregroundStyle(Palette.accent) }
            }
        }.frame(width: size, height: size).clipped().clipShape(RoundedRectangle(cornerRadius: 26))
            .accessibilityLabel("Illustrasjon av \(facts.name)")
    }
}

struct ErrorBanner: View {
    let message: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) { Image(systemName: "info.circle"); Text(message).font(.subheadline) }
            .foregroundStyle(Palette.ink).padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.soft, in: RoundedRectangle(cornerRadius: 14)).accessibilityElement(children: .combine)
    }
}

struct KeyboardCloseToolbar: ToolbarContent {
    var close: () -> Void
    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Lukk tastatur", systemImage: "keyboard.chevron.compact.down", action: close)
                .labelStyle(.titleAndIcon).accessibilityIdentifier("closeKeyboard")
        }
    }
}

struct LoadingScreen: View {
    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ProgressView().controlSize(.large).tint(Palette.muted)
                .accessibilityLabel("Laster").accessibilityIdentifier("loadingSpinner")
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct BlockingLoading: ViewModifier {
    var loading: Bool
    func body(content: Content) -> some View {
        content
            .allowsHitTesting(!loading).accessibilityHidden(loading)
            .overlay { if loading { LoadingScreen() } }
    }
}

extension View {
    func blockingLoading(_ loading: Bool) -> some View { modifier(BlockingLoading(loading: loading)) }
}

struct SwipeAccept: View {
    var submitting: Bool
    var retrying: Bool
    var action: () -> Void
    @State private var offset: CGFloat = 0
    @State private var atThreshold = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geometry in
                let travel = max(1, geometry.size.width - 68)
                let progress = offset / travel
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.accent)
                    Capsule().fill(.white.opacity(0.12)).frame(width: min(geometry.size.width, offset + 68))
                    HStack {
                        Spacer()
                        if submitting { ProgressView().tint(Palette.onAccent) }
                        else { Text(retrying ? "Skyv for å kontrollere" : "Skyv for å godta").font(.system(size: 16, weight: .semibold)).opacity(max(0.15, 1 - progress * 1.5)) }
                        Spacer()
                    }.foregroundStyle(Palette.onAccent).padding(.leading, 35)
                    Circle().fill(Palette.surface)
                        .overlay(Image(systemName: "arrow.right").font(.system(size: 22, weight: .semibold)).foregroundStyle(Palette.accent))
                        .frame(width: 56, height: 56).padding(6).offset(x: offset)
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard !submitting else { return }
                                offset = min(travel, max(0, value.translation.width))
                                let reached = offset >= travel * 0.9
                                if reached && !atThreshold { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                                atThreshold = reached
                            }
                            .onEnded { _ in
                                guard !submitting else { return }
                                if offset >= travel * 0.9 {
                                    withAnimation(reduceMotion ? nil : .spring(duration: 0.25)) { offset = travel }
                                    action()
                                } else { reset() }
                            })
                }.frame(height: 68).accessibilityElement(children: .ignore)
                    .accessibilityLabel(retrying ? "Kontroller bestilling" : "Godta demotilbud")
                    .accessibilityHint("Godtar den viste prisen og det valgte demotilbudet.")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { if !submitting { action() } }
                    .accessibilityIdentifier("acceptSlider")
            }.frame(height: 68)
            if voiceOver {
                Button(retrying ? "Kontroller bestilling" : "Godta demotilbud", action: action).disabled(submitting)
            }
        }.onChange(of: submitting) { old, new in if old && !new { reset() } }
    }
    private func reset() {
        atThreshold = false
        withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.78)) { offset = 0 }
    }
}
