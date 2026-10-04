import SwiftUI

/// The big primary action: accent-filled Liquid Glass with an ink label (Done, I'm up, Test tag…).
struct AccentButton: View {
    let title: String
    var systemImage: String?
    var height: CGFloat = 56
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                if let systemImage { Image(systemName: systemImage) }
            }
            .font(height >= 70 ? .sora(.title2, .semibold) : .sora(.headline))
            .foregroundStyle(Theme.accentInk)
            .frame(maxWidth: .infinity, minHeight: height)
            .contentShape(.capsule)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
        .tint(Theme.accent)
        .contrastBorder(Capsule())
    }
}

/// A full-width glass capsule whose label sits on a tint we choose, so it stays legible at every
/// transparency setting (the ringing Stop button, Try again, Hold to turn off).
struct GlassCapsuleButton: View {
    let title: String
    var systemImage: String?
    var height: CGFloat = 76
    var font: Font = .sora(.title, .semibold)
    var tint: Color? = Theme.labelTint
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                if let systemImage { Image(systemName: systemImage) }
            }
            .font(font)
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, minHeight: height)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(tint).interactive(), in: .capsule)
        .contrastBorder(Capsule())
    }
}

/// Small round glass button for close / back.
struct GlassIconButton: View {
    let systemImage: String
    let label: String
    var size: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.sora(.body, .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: size, height: size)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .contrastBorder(Circle())
        .accessibilityLabel(label)
    }
}

/// Square icon tile used in rows (stop methods, codes).
struct IconTile: View {
    let systemImage: String
    var highlighted = false
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.5, weight: .medium))
            .foregroundStyle(highlighted ? Theme.accent : Theme.ink)
            .frame(width: size, height: size)
            .background(highlighted ? Theme.accent.opacity(0.18) : Theme.chipFill,
                        in: .rect(cornerRadius: size * 0.3))
            .accessibilityHidden(true)
    }
}

/// Four rounded corner brackets framing the scan target.
struct CornerBrackets: Shape {
    var length: CGFloat = 40
    var radius: CGFloat = 20

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: rect.minX, y: rect.minY), 1, 1),
            (CGPoint(x: rect.maxX, y: rect.minY), -1, 1),
            (CGPoint(x: rect.minX, y: rect.maxY), 1, -1),
            (CGPoint(x: rect.maxX, y: rect.maxY), -1, -1),
        ]
        for (corner, dx, dy) in corners {
            path.move(to: CGPoint(x: corner.x, y: corner.y + dy * length))
            path.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * radius))
            path.addArc(tangent1End: corner, tangent2End: CGPoint(x: corner.x + dx * radius, y: corner.y), radius: radius)
            path.addLine(to: CGPoint(x: corner.x + dx * length, y: corner.y))
        }
        return path
    }
}

/// Horizontal shake for wrong codes / tags (−10, 8, −4, 0 over 0.45 s). Still under Reduce Motion.
struct Shake: ViewModifier {
    let trigger: Int
    var amplitude: CGFloat = 10

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let isStill = reduceMotion
        let amplitude = amplitude
        return content.keyframeAnimator(initialValue: CGFloat(0), trigger: trigger) { view, x in
            view.offset(x: isStill ? 0 : x)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(-amplitude, duration: 0.09)
                LinearKeyframe(amplitude * 0.8, duration: 0.11)
                LinearKeyframe(-amplitude * 0.4, duration: 0.11)
                LinearKeyframe(0, duration: 0.14)
            }
        }
    }
}

extension View {
    /// Closes this view's sheets and covers the moment an alarm takes over the screen.
    func dismissOnRing(_ dismiss: @escaping () -> Void) -> some View {
        onChange(of: AppModel.shared.session?.id) { _, id in
            if id != nil { dismiss() }
        }
    }

    func shake(_ trigger: Int, amplitude: CGFloat = 10) -> some View {
        modifier(Shake(trigger: trigger, amplitude: amplitude))
    }

    /// Plain tinted fill for grouped rows on the sky (sections are not glass).
    func skyRowBackground() -> some View {
        listRowBackground(Theme.groupFill)
    }
}
