import SwiftUI

// MARK: - Circular QR View

struct CircularQRView: View {
  let matrix: [[Bool]]
  let size: CGFloat

  private let centerRatio: CGFloat = 0.28

  var body: some View {
    let modules = matrix.count
    guard modules > 0 else { return AnyView(EmptyView()) }

    let dotSize = size / CGFloat(modules)
    let center = size / 2
    let radius = size / 2
    let centerRadius = size * centerRatio / 2
    let logoSize = size * centerRatio * 0.45

    return AnyView(
      ZStack {
        // QR dots
        Canvas { context, canvasSize in
          for row in 0..<modules {
            for col in 0..<modules {
              guard matrix[row][col] else { continue }

              let x = CGFloat(col) * dotSize + dotSize / 2
              let y = CGFloat(row) * dotSize + dotSize / 2
              let dx = x - center
              let dy = y - center
              let dist = sqrt(dx * dx + dy * dy)

              // Skip if outside circle or inside center logo area
              if dist + dotSize / 2 > radius { continue }
              if dist < centerRadius { continue }

              let dotRadius = dotSize * 0.4
              let rect = CGRect(
                x: x - dotRadius,
                y: y - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
              )
              context.fill(
                SwiftUI.Path(ellipseIn: rect),
                with: .color(DesignColor.text)
              )
            }
          }
        }

        // Center logo
        WaveBLogoView(size: logoSize)
      }
      .frame(width: size, height: size)
      .clipShape(Circle())
    )
  }
}
