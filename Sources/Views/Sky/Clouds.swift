import SwiftUI

enum CloudDepth {
    case far, mid, near

    var blur: CGFloat {
        switch self {
        case .far: 10
        case .mid: 7
        case .near: 5
        }
    }

    /// Gentle vertical float, so clouds feel suspended rather than sliding on rails.
    var bob: CGFloat {
        switch self {
        case .far: 2
        case .mid: 3
        case .near: 4
        }
    }
}

/// A cloud placed on the 390 × 844 design canvas, scaled to the real screen.
struct CloudSpec: Identifiable {
    let id: Int
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let shape: CloudShape
    let nightOpacity: Double
    let dawnOpacity: Double
    /// 0 = cool, shaded underside; 1 = underside lit warm by a sun below the horizon.
    let warmth: Double
    let depth: CloudDepth
    /// Seconds for one sweep across the ±40 pt drift.
    let period: Double
    let direction: CGFloat

    static let night: [CloudSpec] = [
        CloudSpec(id: 0, x: 210, y: 112, width: 190, shape: .wisp, nightOpacity: 0.18, dawnOpacity: 0.55, warmth: 0, depth: .far, period: 110, direction: -1),
        CloudSpec(id: 1, x: -70, y: 226, width: 320, shape: .cumulus, nightOpacity: 0.3, dawnOpacity: 0.8, warmth: 0, depth: .mid, period: 64, direction: 1),
        CloudSpec(id: 2, x: -30, y: 384, width: 170, shape: .wisp, nightOpacity: 0.16, dawnOpacity: 0.5, warmth: 0, depth: .far, period: 120, direction: 1),
        CloudSpec(id: 3, x: 150, y: 420, width: 340, shape: .towering, nightOpacity: 0.26, dawnOpacity: 0.75, warmth: 0, depth: .mid, period: 88, direction: -1),
        CloudSpec(id: 4, x: -30, y: 640, width: 300, shape: .cumulus, nightOpacity: 0.32, dawnOpacity: 0.8, warmth: 0.1, depth: .near, period: 76, direction: 1),
        CloudSpec(id: 5, x: 196, y: 742, width: 260, shape: .wisp, nightOpacity: 0.26, dawnOpacity: 0.7, warmth: 0.1, depth: .near, period: 70, direction: -1),
    ]

    static let ringing: [CloudSpec] = [
        CloudSpec(id: 0, x: -70, y: 112, width: 300, shape: .wisp, nightOpacity: 0.22, dawnOpacity: 0.75, warmth: 0, depth: .far, period: 80, direction: 1),
        CloudSpec(id: 1, x: 236, y: 250, width: 170, shape: .wisp, nightOpacity: 0.18, dawnOpacity: 0.6, warmth: 0.1, depth: .far, period: 110, direction: -1),
        CloudSpec(id: 2, x: 150, y: 412, width: 330, shape: .towering, nightOpacity: 0.36, dawnOpacity: 0.62, warmth: 0.4, depth: .mid, period: 66, direction: -1),
        CloudSpec(id: 3, x: -60, y: 600, width: 320, shape: .cumulus, nightOpacity: 0.6, dawnOpacity: 0.88, warmth: 0.9, depth: .near, period: 58, direction: 1),
        CloudSpec(id: 4, x: 180, y: 684, width: 300, shape: .cumulus, nightOpacity: 0.5, dawnOpacity: 0.74, warmth: 0.85, depth: .near, period: 72, direction: -1),
    ]

    static let dawn: [CloudSpec] = [
        CloudSpec(id: 0, x: -70, y: 88, width: 300, shape: .cumulus, nightOpacity: 0.3, dawnOpacity: 0.85, warmth: 0.05, depth: .mid, period: 76, direction: 1),
        CloudSpec(id: 1, x: 190, y: 258, width: 300, shape: .wisp, nightOpacity: 0.25, dawnOpacity: 0.7, warmth: 0.1, depth: .far, period: 60, direction: -1),
        CloudSpec(id: 2, x: -40, y: 580, width: 330, shape: .towering, nightOpacity: 0.3, dawnOpacity: 0.8, warmth: 0.45, depth: .mid, period: 84, direction: 1),
        CloudSpec(id: 3, x: 180, y: 694, width: 290, shape: .cumulus, nightOpacity: 0.3, dawnOpacity: 0.85, warmth: 0.65, depth: .near, period: 66, direction: -1),
    ]

    static let fallback: [CloudSpec] = [
        CloudSpec(id: 0, x: -60, y: 244, width: 320, shape: .cumulus, nightOpacity: 0.3, dawnOpacity: 0.8, warmth: 0, depth: .mid, period: 70, direction: 1),
        CloudSpec(id: 1, x: 160, y: 476, width: 320, shape: .wisp, nightOpacity: 0.28, dawnOpacity: 0.75, warmth: 0.2, depth: .mid, period: 86, direction: -1),
        CloudSpec(id: 2, x: -20, y: 704, width: 280, shape: .towering, nightOpacity: 0.3, dawnOpacity: 0.8, warmth: 0.6, depth: .near, period: 74, direction: 1),
    ]
}

/// Cloud silhouettes built from overlapping puffs on a 100 × 42 grid, with a flat-ish base.
enum CloudShape {
    case cumulus, towering, wisp

    struct Puff {
        let x: CGFloat
        let y: CGFloat
        let r: CGFloat
        var dome = false
    }

    var puffs: [Puff] {
        switch self {
        case .cumulus:
            return [
                Puff(x: 8, y: 32, r: 5), Puff(x: 17, y: 30, r: 9), Puff(x: 30, y: 26, r: 12),
                Puff(x: 46, y: 24, r: 14), Puff(x: 62, y: 25, r: 12), Puff(x: 76, y: 28, r: 10), Puff(x: 88, y: 31, r: 6),
                Puff(x: 25, y: 22, r: 7, dome: true), Puff(x: 35, y: 17, r: 10, dome: true),
                Puff(x: 51, y: 13, r: 11, dome: true), Puff(x: 65, y: 18, r: 8, dome: true),
            ]
        case .towering:
            return [
                Puff(x: 10, y: 32, r: 6), Puff(x: 23, y: 29, r: 10), Puff(x: 39, y: 27, r: 12),
                Puff(x: 56, y: 28, r: 11), Puff(x: 72, y: 29, r: 10), Puff(x: 87, y: 31, r: 7),
                Puff(x: 30, y: 20, r: 9, dome: true), Puff(x: 44, y: 15, r: 11, dome: true),
                Puff(x: 52, y: 8, r: 7, dome: true), Puff(x: 59, y: 17, r: 10, dome: true), Puff(x: 71, y: 22, r: 7, dome: true),
            ]
        case .wisp:
            return [
                Puff(x: 8, y: 31, r: 4), Puff(x: 18, y: 29, r: 6), Puff(x: 30, y: 28, r: 7),
                Puff(x: 43, y: 27, r: 8), Puff(x: 56, y: 28, r: 7), Puff(x: 68, y: 27, r: 8),
                Puff(x: 80, y: 29, r: 6), Puff(x: 91, y: 31, r: 4),
                Puff(x: 37, y: 23, r: 6, dome: true), Puff(x: 63, y: 22, r: 6, dome: true),
            ]
        }
    }

    var base: CGRect {
        switch self {
        case .cumulus: CGRect(x: 7, y: 28, width: 85, height: 8)
        case .towering: CGRect(x: 6, y: 29, width: 87, height: 7)
        case .wisp: CGRect(x: 5, y: 28, width: 90, height: 5)
        }
    }
}

struct DriftingCloud: View {
    let spec: CloudSpec
    let unit: CGSize
    let isNight: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let width = spec.width * unit.width
        let height = width * 0.42
        CloudPuffs(shape: spec.shape, warmth: spec.warmth, isNight: isNight)
            .frame(width: width, height: height)
            .blur(radius: spec.depth.blur)
            .opacity(isNight ? spec.nightOpacity : spec.dawnOpacity)
            .phaseAnimator(reduceMotion ? [0.0] : [-1.0, 1.0]) { content, p in
                content.offset(x: p * 40 * unit.width * spec.direction)
            } animation: { _ in
                .easeInOut(duration: spec.period)
            }
            .phaseAnimator(reduceMotion ? [0.0] : [-1.0, 1.0]) { content, p in
                content.offset(y: p * spec.depth.bob)
            } animation: { _ in
                .easeInOut(duration: spec.period / 7)
            }
            // The design places clouds by their box's top-left corner.
            .position(x: spec.x * unit.width + width / 2,
                      y: spec.y * unit.height + spec.width * unit.height * 0.32 / 2)
    }
}

/// One cloud, drawn once: an opaque silhouette, then sky lighting painted onto it (cool highlight on
/// top, shade or warm sunrise glow underneath) and soft glints on the domes.
private struct CloudPuffs: View {
    let shape: CloudShape
    let warmth: Double
    let isNight: Bool

    var body: some View {
        Canvas { context, size in
            let s = size.width / 100
            let warmUnderside = Theme.cloudShade.mix(with: Theme.cloudWarm, by: warmth)

            context.drawLayer { layer in
                for puff in shape.puffs {
                    layer.fill(circle(puff.x * s, puff.y * s, puff.r * s), with: .color(Theme.cloudBody))
                }
                let base = shape.base
                layer.fill(
                    Path(roundedRect: CGRect(x: base.minX * s, y: base.minY * s, width: base.width * s, height: base.height * s),
                         cornerRadius: base.height * s / 2),
                    with: .color(Theme.cloudBody)
                )

                layer.blendMode = .sourceAtop
                layer.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .linearGradient(
                        Gradient(stops: [
                            Gradient.Stop(color: Theme.cloudHighlight, location: 0),
                            Gradient.Stop(color: Theme.cloudBody, location: 0.5),
                            Gradient.Stop(color: warmUnderside, location: 0.92),
                        ]),
                        startPoint: CGPoint(x: size.width / 2, y: 4 * s),
                        endPoint: CGPoint(x: size.width / 2, y: 36 * s)
                    )
                )

                for puff in shape.puffs where puff.dome {
                    let center = CGPoint(x: (puff.x - puff.r * 0.25) * s, y: (puff.y - puff.r * 0.35) * s)
                    let radius = puff.r * 0.9 * s
                    layer.fill(
                        circle(center.x, center.y, radius),
                        with: .radialGradient(
                            Gradient(colors: [Theme.cloudHighlight.opacity(isNight ? 0.55 : 0.8), Theme.cloudHighlight.opacity(0)]),
                            center: center, startRadius: 0, endRadius: radius
                        )
                    )
                }

                if warmth > 0.3 {
                    // A thin rim of sunrise light along the underside.
                    layer.fill(
                        Path(CGRect(x: 0, y: 26 * s, width: size.width, height: 12 * s)),
                        with: .linearGradient(
                            Gradient(colors: [Theme.cloudWarm.opacity(0), Theme.cloudWarm.opacity(0.7 * warmth)]),
                            startPoint: CGPoint(x: 0, y: 26 * s),
                            endPoint: CGPoint(x: 0, y: 37 * s)
                        )
                    )
                }
            }
        }
    }

    private func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }
}
