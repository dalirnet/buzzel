import SwiftUI

// MARK: - Orbit Rings View

struct OrbitRingsView<Content: View>: View {
  @ViewBuilder let content: () -> Content

  private struct Ring {
    let radius: CGFloat
    let duration: Double  // seconds per full rotation, negative = reverse
    let dots: [OrbitDot]
  }

  private struct OrbitDot {
    let offset: Double  // 0...1 position along the ring
    let size: CGFloat
    let color: Color
  }

  private static var rings: [Ring] {
    [
      Ring(
        radius: 80, duration: 12,
        dots: [
          OrbitDot(offset: 0.0, size: 6, color: DesignColor.accent),
          OrbitDot(offset: 0.55, size: 4, color: DesignColor.green),
        ]),
      Ring(
        radius: 105, duration: -18,
        dots: [
          OrbitDot(offset: 0.2, size: 5, color: DesignColor.orange),
          OrbitDot(offset: 0.7, size: 3, color: DesignColor.accent),
        ]),
      Ring(
        radius: 130, duration: 25,
        dots: [
          OrbitDot(offset: 0.4, size: 4, color: DesignColor.red),
          OrbitDot(offset: 0.85, size: 3, color: DesignColor.green),
        ]),
    ]
  }

  @State private var startDate = Date.now

  var body: some View {
    TimelineView(.animation) { timeline in
      let elapsed = timeline.date.timeIntervalSince(startDate)

      ZStack {
        ForEach(Array(Self.rings.enumerated()), id: \.offset) { _, ring in
          ringView(ring: ring, elapsed: elapsed)
        }

        content()
      }
    }
    .frame(width: 280, height: 280)
  }

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
}
