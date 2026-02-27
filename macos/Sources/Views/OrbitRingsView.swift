import SwiftUI

// MARK: - Orbit Rings View

struct OrbitRingsView<Content: View>: View {
    var deviceName: String?
    var isConnected: Bool = true
    var isRemoteFocused: Bool = false
    @ViewBuilder let content: () -> Content

    @State private var startDate: Date?
    @State private var isWindowFocused = true
    @State private var pausedElapsed: TimeInterval = 0
    @State private var opacity: Double = 0

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed: TimeInterval =
                if let startDate, isWindowFocused {
                    max(0, timeline.date.timeIntervalSince(startDate))
                } else {
                    pausedElapsed
                }
            ZStack {
                ForEach(Array(Self.rings.enumerated()), id: \.offset) { _, ring in
                    ringView(ring: ring, elapsed: elapsed)
                }

                if let name = deviceName {
                    devicePlanet(name: name, elapsed: elapsed)
                }

                content()
            }
        }
        .frame(width: 294, height: 294)
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeIn(duration: 0.8)) {
                opacity = 1
            }
            startDate = Date.now.addingTimeInterval(1.0)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            guard !isWindowFocused else { return }
            startDate = Date.now.addingTimeInterval(-pausedElapsed)
            isWindowFocused = true
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
        ) { _ in
            if let startDate {
                pausedElapsed = max(0, Date.now.timeIntervalSince(startDate))
            }
            isWindowFocused = false
        }
    }

    // MARK: - Ring View

    private func ringView(ring: Ring, elapsed: TimeInterval) -> some View {
        let progress = elapsed / abs(ring.duration)
        let direction: Double = ring.duration > 0 ? 1 : -1
        let angle = progress * 360 * direction

        return ZStack {
            Circle()
                .stroke(DesignColor.secondary.opacity(0.08), lineWidth: 1)
                .frame(width: ring.radius * 2, height: ring.radius * 2)

            ForEach(Array(ring.dots.enumerated()), id: \.offset) { _, dot in
                ZStack {
                    Circle()
                        .fill(dot.color.opacity(0.4))
                        .frame(width: dot.size + dot.size * 0.8, height: dot.size + dot.size * 0.8)
                    Circle()
                        .fill(dot.color.opacity(0.6))
                        .frame(width: dot.size, height: dot.size)
                }
                .offset(x: ring.radius)
                .rotationEffect(.degrees(dot.offset * 360))
            }
        }
        .rotationEffect(.degrees(angle))
    }

    private var devicePlanetColor: Color {
        if !isConnected { return DesignColor.red }
        return isRemoteFocused ? DesignColor.green : DesignColor.yellow
    }

    // MARK: - Device Planet

    private func devicePlanet(name: String, elapsed: TimeInterval) -> some View {
        let ring = Self.rings[1]  // middle ring
        let progress = elapsed / abs(ring.duration)
        let direction: Double = ring.duration > 0 ? 1 : -1
        let angle = progress * 360 * direction
        let planetOffset = 0.45

        return Text(name)
            .font(Brand.font(size: 8))
            .foregroundColor(DesignColor.text)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(devicePlanetColor.opacity(0.15))
            .clipShape(Capsule())
            .rotationEffect(.degrees(-(angle + planetOffset * 360)))
            .offset(x: ring.radius)
            .rotationEffect(.degrees(planetOffset * 360))
            .rotationEffect(.degrees(angle))
    }

    // MARK: - Models

    private struct Ring {
        let radius: CGFloat
        let duration: Double
        let dots: [OrbitDot]
    }

    private struct OrbitDot {
        let offset: Double
        let size: CGFloat
        let color: Color
    }

    private static var rings: [Ring] {
        [
            Ring(
                radius: 84, duration: 12,
                dots: [
                    OrbitDot(offset: 0.0, size: 6, color: DesignColor.accent),
                    OrbitDot(offset: 0.55, size: 4, color: DesignColor.green),
                ]
            ),
            Ring(
                radius: 110, duration: -18,
                dots: [
                    OrbitDot(offset: 0.2, size: 5, color: DesignColor.orange),
                    OrbitDot(offset: 0.7, size: 3, color: DesignColor.accent),
                ]
            ),
            Ring(
                radius: 136, duration: 25,
                dots: [
                    OrbitDot(offset: 0.4, size: 4, color: DesignColor.red),
                    OrbitDot(offset: 0.85, size: 3, color: DesignColor.green),
                ]
            ),
        ]
    }
}
