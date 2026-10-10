import SwiftUI

enum PivotAccent: String, CaseIterable, Identifiable {
    static let storageKey = "pivot:accent-color"
    case mint, blue, purple, pink, orange, gold
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    static func resolve(_ value: String) -> Self { Self(rawValue: value) ?? .mint }
    var hex: UInt32 {
        switch self {
        case .mint: 0x78e3bf
        case .blue: 0x87c7ff
        case .purple: 0xc1a5ff
        case .pink: 0xff9fce
        case .orange: 0xffb477
        case .gold: 0xf2d369
        }
    }
    var color: Color {
        Color(red: Double((hex >> 16) & 255) / 255,
              green: Double((hex >> 8) & 255) / 255,
              blue: Double(hex & 255) / 255)
    }
}

private struct PivotAccentKey: EnvironmentKey {
    static let defaultValue = PivotAccent.mint.color
}

extension EnvironmentValues {
    var pivotAccent: Color {
        get { self[PivotAccentKey.self] }
        set { self[PivotAccentKey.self] = newValue }
    }
}

struct PivotSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pivotAccent) private var accent
    @AppStorage(PivotAccent.storageKey) private var selectedAccent = PivotAccent.mint.rawValue

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Accent color").font(.headline)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 95), spacing: 12)], spacing: 12) {
                        ForEach(PivotAccent.allCases) { option in
                            let selected = PivotAccent.resolve(selectedAccent) == option
                            Button { selectedAccent = option.rawValue } label: {
                                VStack(spacing: 10) {
                                    Circle().fill(option.color).frame(width: 36, height: 36)
                                        .overlay {
                                            if selected { Image(systemName: "checkmark").font(.body.bold()).foregroundStyle(Color.pivotBackground) }
                                        }
                                    Text(option.label).font(.subheadline).foregroundStyle(.white)
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 16)
                                .background(selected ? option.color.opacity(0.1) : Color.pivotSurface, in: RoundedRectangle(cornerRadius: 16))
                                .overlay { RoundedRectangle(cornerRadius: 16).stroke(selected ? option.color : Color.pivotBorder, lineWidth: 1) }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(option.label)
                            .accessibilityValue(selected ? "Selected" : "Not selected")
                            .accessibilityAddTraits(selected ? .isSelected : [])
                            .accessibilityIdentifier("accent-\(option.rawValue)")
                        }
                    }
                    Text("Applies to the app and its Lock Screen and Apple Watch Live Activities. Ride-status colors in the app stay the same. Your website color is saved separately.")
                        .font(.subheadline).foregroundStyle(Color.pivotMuted)
                    Divider()
                    Text("PIVOT \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown")")
                        .font(.subheadline.weight(.semibold))
                    Text("App updates are available in SideStore through the PIVOT source.")
                        .font(.subheadline).foregroundStyle(Color.pivotMuted)
                }.padding(20)
            }
            .background(Color.pivotBackground)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.tint(accent)
    }
}

extension Color {
    static let pivotBackground = Color(red: 0.039, green: 0.063, blue: 0.071)
    static let pivotSurface = Color(red: 0.075, green: 0.102, blue: 0.110)
    static let pivotSurfaceRaised = Color(red: 0.110, green: 0.145, blue: 0.153)
    static let pivotBorder = Color.white.opacity(0.09)
    static let pivotMuted = Color(red: 0.64, green: 0.71, blue: 0.72)
    // Retain the existing token name for all current controls and widgets.
    static let pivotPurple = Color(red: 0.47, green: 0.89, blue: 0.75)
    static let pivotPink = Color(red: 1.0, green: 0.48, blue: 0.48)
    static let pivotBlue = Color(red: 0.06, green: 0.52, blue: 0.95)
    static let pivotMint = Color(red: 0.47, green: 0.89, blue: 0.75)
    static let pivotWeather = Color(red: 0.37, green: 0.75, blue: 1.0)
}
struct PivotCardModifier: ViewModifier {
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.pivotSurface)
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.pivotBorder, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

extension View {
    func pivotCard(padding: CGFloat = 18) -> some View {
        modifier(PivotCardModifier(padding: padding))
    }
}

struct PivotStatusDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .accessibilityHidden(true)
    }
}

struct PivotIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 44, height: 44)
            .background(Color.pivotSurfaceRaised.opacity(configuration.isPressed ? 0.65 : 1))
            .overlay(Circle().stroke(Color.pivotBorder, lineWidth: 1))
            .clipShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}

private struct PivotNativeGlassIconButtonModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
        } else {
            content.buttonStyle(PivotIconButtonStyle())
        }
    }
}

extension View {
    func pivotNativeGlassIconButton() -> some View {
        modifier(PivotNativeGlassIconButtonModifier())
    }
}
