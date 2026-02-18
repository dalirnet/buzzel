import SwiftUI

// MARK: - SVG Icon View

struct SVGIconView: View {
  let paths: [[String]]
  let size: CGFloat
  let color: Color
  var mode: IconMode = .stroke(width: 1.5)
  var opacity: Double = 1.0

  enum IconMode {
    case stroke(width: CGFloat)
    case fill
    case mixed
  }

  var body: some View {
    let scale = size / 24.0

    ZStack {
      switch mode {
      case .stroke(let width):
        Path { p in
          for group in paths {
            for segment in group {
              p.addPath(
                parseSVGPath(segment).applying(
                  CGAffineTransform(scaleX: scale, y: scale)))
            }
          }
        }
        .stroke(
          color, style: StrokeStyle(lineWidth: scale * width, lineCap: .round, lineJoin: .round))

      case .fill:
        Path { p in
          for group in paths {
            for segment in group {
              p.addPath(
                parseSVGPath(segment).applying(
                  CGAffineTransform(scaleX: scale, y: scale)))
            }
          }
        }
        .fill(color)

      case .mixed:
        Path { p in
          for group in paths.prefix(3) {
            for segment in group {
              p.addPath(
                parseSVGPath(segment).applying(
                  CGAffineTransform(scaleX: scale, y: scale)))
            }
          }
        }
        .stroke(
          color, style: StrokeStyle(lineWidth: scale * 1.5, lineCap: .round, lineJoin: .round))

        Path { p in
          for group in paths.dropFirst(3) {
            for segment in group {
              p.addPath(
                parseSVGPath(segment).applying(
                  CGAffineTransform(scaleX: scale, y: scale)))
            }
          }
        }
        .fill(color)
      }
    }
    .frame(width: size, height: size)
    .opacity(opacity)
  }
}

// MARK: - Wave-B Logo View

struct WaveBLogoView: View {
  let size: CGFloat

  var body: some View {
    let raw = parseSVGPath(Brand.logoPath)
    let bounds = raw.boundingRect
    let sw: CGFloat = 64
    let totalW = bounds.width + sw
    let totalH = bounds.height + sw
    let maxDim = max(totalW, totalH)
    let scale = size / maxDim
    let strokeWidth = sw * scale
    let ox = (size - bounds.width * scale) / 2 - bounds.minX * scale
    let oy = (size - bounds.height * scale) / 2 - bounds.minY * scale

    Path { p in
      p.addPath(
        raw.applying(
          CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: ox, y: oy))))
    }
    .stroke(
      DesignColor.text,
      style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round)
    )
    .frame(width: size, height: size)
  }
}

// MARK: - App Header Label

struct AppHeaderLabel: View {
  let title: String

  private static let charInterval: TimeInterval = 0.035
  private static let charAnimation: Animation = .easeOut(duration: 0.08)

  @State private var displayedText: String = ""
  @State private var isAnimating = false

  var body: some View {
    HStack(spacing: 8) {
      WaveBLogoView(size: 14)
        .offset(y: -1)

      Text(displayedText)
        .font(Brand.font(size: 13, weight: .semibold))
        .foregroundColor(DesignColor.text)
        .animation(Self.charAnimation, value: displayedText)
    }
    .onAppear { displayedText = title }
    .onChange(of: title) { newTitle in
      guard !isAnimating else { return }
      animateTitle(to: newTitle)
    }
  }

  private func animateTitle(to newTitle: String) {
    isAnimating = true
    let current = displayedText
    let deleteCount = current.count
    let typeCount = newTitle.count
    let total = deleteCount + typeCount

    for step in 0..<total {
      DispatchQueue.main.asyncAfter(deadline: .now() + Self.charInterval * Double(step)) {
        withAnimation(Self.charAnimation) {
          if step < deleteCount {
            displayedText = String(current.prefix(deleteCount - step - 1))
          } else {
            displayedText = String(newTitle.prefix(step - deleteCount + 1))
          }
        }
        if step == total - 1 { isAnimating = false }
      }
    }
  }
}
