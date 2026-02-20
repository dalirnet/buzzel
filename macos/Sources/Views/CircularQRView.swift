import SwiftUI

// MARK: - Circular QR View

struct CircularQRView: View {
  let matrix: [[Bool]]
  let size: CGFloat

  private let centerRatio: CGFloat = 0.28
  private let qrScale: CGFloat = 0.72

  var body: some View {
    let modules = matrix.count
    guard modules > 0 else { return AnyView(EmptyView()) }

    let qrSize = size * qrScale
    let qrOrigin = (size - qrSize) / 2
    let dotSize = qrSize / CGFloat(modules)
    let centerRadius = size * centerRatio / 2
    let logoSize = size * centerRatio * 0.5

    let noiseDots = Self.noiseRing(
      size: size,
      qrOrigin: qrOrigin,
      qrSize: qrSize,
      dotSize: dotSize,
      centerRadius: centerRadius
    )

    return AnyView(
      ZStack {
        Canvas { context, _ in
          let center = size / 2

          // Draw QR modules as circular dots
          for row in 0..<modules {
            for col in 0..<modules {
              guard matrix[row][col] else { continue }

              let x = qrOrigin + CGFloat(col) * dotSize + dotSize / 2
              let y = qrOrigin + CGFloat(row) * dotSize + dotSize / 2
              let dx = x - center
              let dy = y - center
              let dist = sqrt(dx * dx + dy * dy)

              // Skip center logo area
              if dist < centerRadius { continue }

              let dotRadius = dotSize * 0.42
              let rect = CGRect(
                x: x - dotRadius, y: y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
              context.fill(SwiftUI.Path(ellipseIn: rect), with: .color(DesignColor.text))
            }
          }

          // Noise dots in the ring outside the QR square but inside the circle
          for dot in noiseDots {
            let dotRadius = dotSize * 0.42
            let rect = CGRect(
              x: dot.x - dotRadius, y: dot.y - dotRadius, width: dotRadius * 2,
              height: dotRadius * 2)
            context.fill(
              SwiftUI.Path(ellipseIn: rect),
              with: .color(DesignColor.text.opacity(dot.opacity))
            )
          }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())

        WaveBLogoView(size: logoSize)
      }
      .frame(width: size, height: size)
    )
  }

  // MARK: - Noise Ring

  private struct NoiseDot {
    let x: CGFloat
    let y: CGFloat
    let opacity: CGFloat
  }

  private static func noiseRing(
    size: CGFloat,
    qrOrigin: CGFloat,
    qrSize: CGFloat,
    dotSize: CGFloat,
    centerRadius: CGFloat
  ) -> [NoiseDot] {
    let center = size / 2
    let radius = size / 2
    let step = dotSize
    var dots: [NoiseDot] = []

    var seed: UInt64 = 0xDEAD_BEEF
    func nextRand() -> CGFloat {
      seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      return CGFloat(seed >> 33) / CGFloat(0x7FFF_FFFF)
    }

    let cols = Int(ceil(size / step)) + 1
    let rows = Int(ceil(size / step)) + 1

    for row in 0..<rows {
      for col in 0..<cols {
        let jitter = step * 0.3
        let x = CGFloat(col) * step + nextRand() * jitter - jitter / 2
        let y = CGFloat(row) * step + nextRand() * jitter - jitter / 2

        let dx = x - center
        let dy = y - center
        let dist = sqrt(dx * dx + dy * dy)

        guard dist + step * 0.4 < radius else { continue }

        let inQR =
          x >= qrOrigin && x <= qrOrigin + qrSize
          && y >= qrOrigin && y <= qrOrigin + qrSize
        guard !inQR else { continue }

        guard dist >= centerRadius else { continue }

        guard nextRand() > 0.55 else { continue }

        let distFromQREdge = min(
          abs(x - qrOrigin), abs(x - (qrOrigin + qrSize)),
          abs(y - qrOrigin), abs(y - (qrOrigin + qrSize))
        )
        let edgeFade = min(distFromQREdge / (step * 2), 1.0)
        let circleFade = 1.0 - max(0, (dist - radius * 0.8) / (radius * 0.2))
        let opacity = edgeFade * circleFade * 0.5

        dots.append(NoiseDot(x: x, y: y, opacity: opacity))
      }
    }

    return dots
  }
}
