import SwiftUI
import UIKit

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
        let light: UInt32
        switch self {
        case .mint: light = 0x08785C
        case .blue: light = 0x075BAA
        case .purple: light = 0x7037AF
        case .pink: light = 0xAA245C
        case .orange: light = 0x994400
        case .gold: light = 0x766000
        }
        return Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? hex : light
            return UIColor(red: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
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
            Form {
                Section {
                    ForEach(PivotAccent.allCases) { option in
                        let selected = PivotAccent.resolve(selectedAccent) == option
                        Button { selectedAccent = option.rawValue } label: {
                            HStack {
                                Circle().fill(option.color).frame(width: 22, height: 22).accessibilityHidden(true)
                                Text(option.label).foregroundStyle(.primary)
                                Spacer()
                                if selected { Image(systemName: "checkmark").foregroundStyle(accent) }
                            }.frame(minHeight: 32)
                        }
                        .accessibilityLabel(option.label)
                        .accessibilityValue(selected ? "Selected" : "Not selected")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityIdentifier("accent-\(option.rawValue)")
                    }
                } header: { Text("Accent color") } footer: {
                    Text("Applies to PIVOT and its Live Activities. Status colors retain their meanings. Appearance follows your iPhone’s Light or Dark setting.")
                }
                Section("About") {
                    Text("PIVOT \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown")")
                    Text("App updates are available in SideStore through the PIVOT source.").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .tint(accent)
#if DEBUG
        .modifier(PivotUITestTypeSize(probeIdentifier: "Settings body size"))
#endif
    }
}

extension Color {
    static let pivotBackground = Color(uiColor: .systemGroupedBackground)
    static let pivotSurface = Color(uiColor: .secondarySystemGroupedBackground)
    static let pivotSurfaceRaised = Color(uiColor: .tertiarySystemGroupedBackground)
    static let pivotBorder = Color(uiColor: .separator).opacity(0.45)
    static let pivotMuted = Color.secondary
    static let pivotPurple = PivotAccent.mint.color
    static let pivotPink = Color.red
    static let pivotBlue = Color.blue
    static let pivotMint = PivotAccent.mint.color
    static let pivotWeather = Color.blue
}
struct PivotCardModifier: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content.padding(padding)
            .background(Color.pivotSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
extension View {
    func pivotCard(padding: CGFloat = 16) -> some View { modifier(PivotCardModifier(padding: padding)) }
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
