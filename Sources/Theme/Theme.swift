import SwiftUI

/// Every color in the app. Values live in the asset catalog with an Any (dawn) and a Dark (night)
/// appearance, so a screen picks its sky simply by setting its color scheme.
enum Theme {
    // Sky
    static let skyTop = Color("SkyTop")
    static let skyMid = Color("SkyMid")
    static let skyHorizon = Color("SkyHorizon")
    static let ringMid = Color("RingMid")
    static let ringHorizon = Color("RingHorizon")
    static let ringLow = Color("RingLow")
    static let haze = Color("Haze")
    static let calmTop = Color("CalmTop")
    static let calmMid = Color("CalmMid")
    static let calmLow = Color("CalmLow")

    // Sun bloom
    static let sunCore = Color("SunCore")
    static let sunMid = Color("SunMid")
    static let sunEdge = Color("SunEdge")

    // Clouds
    static let cloudHighlight = Color("CloudHighlight")
    static let cloudBody = Color("CloudBody")
    static let cloudShade = Color("CloudShade")
    static let cloudWarm = Color("CloudWarm")
    static let cloudDusk = Color("CloudDusk")

    // Content
    static let ink = Color("Ink")
    static let inkSecondary = Color("Ink").opacity(0.72)
    static let inkTertiary = Color("Ink").opacity(0.5)
    static let accent = Color("Accent")
    static let accentStrong = Color("AccentStrong")
    static let accentInk = Color("AccentInk")
    static let success = Color("Success")
    static let error = Color("Error")
    static let labelTint = Color("LabelTint")
    static let groupFill = Color("GroupFill")
    static let chipFill = Color("ChipFill")
    static let camera = Color("Camera")
    static let star = Color.white

    /// AlarmKit encodes its tint into the alarm, so it needs a concrete color rather than an asset reference.
    static let alarmTint = Color(red: 1.0, green: 0.769, blue: 0.420)

    /// Sora Light for the big clock times.
    static func clock(_ size: CGFloat) -> Font {
        .sora(fixed: size, .light)
    }
}

// MARK: - Sora

/// The app's typeface. Fonts ship in Resources/Fonts and are registered through UIAppFonts.
enum SoraWeight: String {
    case light = "Sora-Light"
    case regular = "Sora-Regular"
    case medium = "Sora-Medium"
    case semibold = "Sora-SemiBold"
    case bold = "Sora-Bold"
}

extension Font {
    /// Sora at the size of a system text style, scaling with Dynamic Type like the style it mirrors.
    static func sora(_ style: Font.TextStyle, _ weight: SoraWeight? = nil) -> Font {
        .custom((weight ?? style.soraDefaultWeight).rawValue, size: style.soraSize, relativeTo: style)
    }

    /// Sora at a fixed size, for the big clock faces that size themselves.
    static func sora(fixed size: CGFloat, _ weight: SoraWeight = .regular) -> Font {
        .custom(weight.rawValue, fixedSize: size)
    }
}

extension Font.TextStyle {
    var soraSize: CGFloat {
        switch self {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline: 17
        case .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        default: 17
        }
    }

    var soraDefaultWeight: SoraWeight {
        self == .headline ? .semibold : .regular
    }
}

/// UIKit-drawn chrome (navigation bar titles, tab bar labels) doesn't read SwiftUI's font,
/// so it gets Sora through appearance proxies, scaled for Dynamic Type.
@MainActor
enum SoraChrome {
    static func apply() {
        if let large = scaled(.bold, 34, .largeTitle), let inline = scaled(.semibold, 17, .headline) {
            UINavigationBar.appearance().largeTitleTextAttributes = [.font: large]
            UINavigationBar.appearance().titleTextAttributes = [.font: inline]
        }
        if let tab = scaled(.medium, 10, .caption2) {
            UITabBarItem.appearance().setTitleTextAttributes([.font: tab], for: .normal)
            UITabBarItem.appearance().setTitleTextAttributes([.font: tab], for: .selected)
        }
        if let bar = scaled(.medium, 17, .body) {
            UIBarButtonItem.appearance().setTitleTextAttributes([.font: bar], for: .normal)
        }
    }

    private static func scaled(_ weight: SoraWeight, _ size: CGFloat, _ style: UIFont.TextStyle) -> UIFont? {
        UIFont(name: weight.rawValue, size: size).map { UIFontMetrics(forTextStyle: style).scaledFont(for: $0) }
    }
}

/// A Form section header in Sora, sentence case.
struct SectionHeader: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.sora(.subheadline, .semibold))
            .foregroundStyle(Theme.inkSecondary)
            .textCase(nil)
    }
}

/// A Form section footer in Sora.
struct SectionFooter: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.sora(.footnote))
            .foregroundStyle(Theme.inkSecondary)
    }
}

extension View {
    /// Increase Contrast: a 2 pt primary-colored border around a capsule or circle control.
    func contrastBorder<S: InsettableShape>(_ shape: S) -> some View {
        modifier(ContrastBorder(shape: shape))
    }
}

private struct ContrastBorder<S: InsettableShape>: ViewModifier {
    let shape: S
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content.overlay {
            if contrast == .increased {
                shape.strokeBorder(Theme.ink, lineWidth: 2)
            }
        }
    }
}

extension String {
    /// "Kitchen QR" → "kitchen QR", for use mid-sentence.
    var lowercasingFirstLetter: String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }
}
