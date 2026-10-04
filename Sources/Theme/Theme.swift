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

    /// SF Pro Rounded Light for the big clock times.
    static func clock(_ size: CGFloat) -> Font {
        .system(size: size, weight: .light, design: .rounded)
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
