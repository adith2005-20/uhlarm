import SwiftUI

enum SkyStyle {
    /// Setup screens: deep night, stars, moonlit clouds.
    case night
    /// Ringing: a sunrise breaking through warm clouds (night or dawn by color scheme).
    case ringing
    /// Success and Wake Up Check: full morning.
    case dawn
    /// Emergency unlock: night with a low, dim sun.
    case fallback
}

/// The shared animated background. Clouds drift slowly behind Liquid Glass; stars twinkle at night.
/// Every layer stops moving under Reduce Motion.
struct SkyView: View {
    var style: SkyStyle
    /// Ringing only: how far the sunrise has come (0.55 at first ring → 1 after five minutes).
    var intensity: Double = 1
    /// Fades the scene into the calm morning blue after an NFC success.
    var calm: Double = 0

    @Environment(\.colorScheme) private var colorScheme

    private var isNight: Bool { colorScheme == .dark }

    var body: some View {
        GeometryReader { geo in
            let unit = CGSize(width: geo.size.width / 390, height: geo.size.height / 844)
            ZStack(alignment: .topLeading) {
                LinearGradient(stops: baseStops, startPoint: .top, endPoint: .bottom)

                LinearGradient(colors: [Theme.calmTop, Theme.calmMid, Theme.calmLow], startPoint: .top, endPoint: .bottom)
                    .opacity(calm)

                if isNight && style != .dawn {
                    StarField(unit: unit)
                        .opacity(starOpacity)
                }

                if let bloom {
                    SunBloom(
                        center: CGPoint(x: geo.size.width / 2, y: bloom.centerY * unit.height),
                        radii: CGSize(width: bloom.radiusX * unit.width, height: bloom.radiusY * unit.height),
                        breathes: bloom.breathes
                    )
                    .opacity(bloom.opacity * (1 - calm))
                }

                HorizonHaze()
                    .frame(width: geo.size.width * 1.6, height: geo.size.height * 0.5)
                    .position(x: geo.size.width / 2, y: geo.size.height)
                    .opacity((isNight ? 0.45 : 0.55) * (1 - calm))

                ForEach(clouds) { spec in
                    DriftingCloud(spec: spec, unit: unit, isNight: isNight)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var starOpacity: Double {
        let sunrise = style == .ringing ? 1 - 0.45 * intensity : 1
        return sunrise * (1 - calm)
    }

    private var baseStops: [Gradient.Stop] {
        switch style {
        case .night:
            return [stop(Theme.skyTop, 0), stop(Theme.skyMid, 0.5), stop(Theme.skyHorizon, 1)]
        case .ringing, .dawn:
            return [stop(Theme.skyTop, 0), stop(Theme.ringMid, 0.46), stop(Theme.ringHorizon, 0.78), stop(Theme.ringLow, 1)]
        case .fallback:
            return [stop(Theme.skyTop, 0), stop(Theme.ringMid, 0.5), stop(Theme.skyHorizon, 1)]
        }
    }

    private func stop(_ color: Color, _ location: CGFloat) -> Gradient.Stop {
        Gradient.Stop(color: color, location: location)
    }

    private struct Bloom {
        var centerY: CGFloat
        var radiusX: CGFloat
        var radiusY: CGFloat
        var opacity: Double
        var breathes: Bool
    }

    private var bloom: Bloom? {
        switch style {
        case .night:
            return nil
        case .ringing:
            return Bloom(centerY: 784, radiusX: 425, radiusY: 460, opacity: 0.35 + 0.65 * intensity, breathes: true)
        case .dawn:
            return Bloom(centerY: 930, radiusX: 400, radiusY: 430, opacity: 0.8, breathes: true)
        case .fallback:
            return Bloom(centerY: 954, radiusX: 425, radiusY: 450, opacity: 0.7, breathes: false)
        }
    }

    private var clouds: [CloudSpec] {
        switch style {
        case .night: CloudSpec.night
        case .ringing: CloudSpec.ringing
        case .dawn: CloudSpec.dawn
        case .fallback: CloudSpec.fallback
        }
    }
}

// MARK: - Sun

private struct SunBloom: View {
    let center: CGPoint
    let radii: CGSize
    let breathes: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        EllipticalGradient(
            stops: [
                Gradient.Stop(color: Theme.sunCore.opacity(0.98), location: 0),
                Gradient.Stop(color: Theme.sunMid.opacity(0.78), location: 0.24),
                Gradient.Stop(color: Theme.sunEdge.opacity(0.32), location: 0.54),
                Gradient.Stop(color: Theme.sunEdge.opacity(0.1), location: 0.78),
                Gradient.Stop(color: Theme.sunEdge.opacity(0), location: 1),
            ],
            center: .center,
            startRadiusFraction: 0,
            endRadiusFraction: 0.5
        )
        .frame(width: radii.width * 2, height: radii.height * 2)
        .phaseAnimator(breathes && !reduceMotion ? [0.0, 1.0] : [0.6]) { content, p in
            content
                .scaleEffect(0.94 + 0.1 * p, anchor: UnitPoint(x: 0.5, y: 0.7))
                .opacity(0.8 + 0.2 * p)
        } animation: { _ in
            .easeInOut(duration: 2.25)
        }
        .position(center)
    }
}

private struct HorizonHaze: View {
    var body: some View {
        EllipticalGradient(
            colors: [Theme.haze.opacity(0.9), Theme.haze.opacity(0.35), Theme.haze.opacity(0)],
            center: .center,
            startRadiusFraction: 0,
            endRadiusFraction: 0.5
        )
    }
}

// MARK: - Stars

private struct StarField: View {
    let unit: CGSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: reduceMotion)) { timeline in
            Canvas { context, _ in
                let t = timeline.date.timeIntervalSinceReferenceDate
                for (index, star) in Star.all.enumerated() {
                    let twinkle = reduceMotion ? 0.6 : 0.5 - 0.5 * cos(2 * .pi * t / star.period + Double(index) * 1.7)
                    let opacity = 0.35 + 0.55 * twinkle
                    let center = CGPoint(x: star.x * unit.width, y: star.y * unit.height)
                    if star.glow {
                        let halo = star.radius * 5
                        context.fill(
                            Path(ellipseIn: CGRect(x: center.x - halo, y: center.y - halo, width: halo * 2, height: halo * 2)),
                            with: .radialGradient(
                                Gradient(colors: [Theme.star.opacity(0.35 * opacity), Theme.star.opacity(0)]),
                                center: center, startRadius: 0, endRadius: halo
                            )
                        )
                    }
                    let r = star.radius
                    context.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                                 with: .color(Theme.star.opacity(opacity)))
                }
            }
        }
    }

    private struct Star {
        let x: CGFloat
        let y: CGFloat
        let radius: CGFloat
        let period: Double
        var glow = false

        static let all: [Star] = [
            Star(x: 42, y: 88, radius: 1.0, period: 5, glow: true),
            Star(x: 120, y: 40, radius: 0.75, period: 6),
            Star(x: 178, y: 132, radius: 0.85, period: 5.5),
            Star(x: 250, y: 64, radius: 0.6, period: 4.6),
            Star(x: 334, y: 112, radius: 1.0, period: 5.2, glow: true),
            Star(x: 366, y: 30, radius: 0.75, period: 6.4),
            Star(x: 82, y: 196, radius: 0.6, period: 4.8),
            Star(x: 300, y: 214, radius: 0.85, period: 5.8),
            Star(x: 214, y: 262, radius: 0.6, period: 6.2),
            Star(x: 24, y: 300, radius: 0.75, period: 5.4),
            Star(x: 150, y: 340, radius: 0.6, period: 4.4),
            Star(x: 356, y: 296, radius: 0.85, period: 5.9, glow: true),
            Star(x: 200, y: 18, radius: 0.5, period: 7),
            Star(x: 64, y: 140, radius: 0.45, period: 6.6),
            Star(x: 276, y: 160, radius: 0.5, period: 7.4),
            Star(x: 110, y: 250, radius: 0.45, period: 6.8),
            Star(x: 330, y: 380, radius: 0.5, period: 7.2),
            Star(x: 236, y: 410, radius: 0.4, period: 6.1),
            Star(x: 16, y: 420, radius: 0.4, period: 7.8),
            Star(x: 160, y: 96, radius: 0.9, period: 5.1, glow: true),
        ]
    }
}
