import SwiftUI

struct SplashView: View {
  var onFinished: () -> Void

  @Environment(\.colorScheme) private var colorScheme
  @State private var drawProgress: CGFloat = 0
  @State private var eraseProgress: CGFloat = 0
  @State private var started = false

  private static let delayBefore: TimeInterval = 0.25
  private static let duration: TimeInterval = 1.0
  private static let delayAfter: TimeInterval = 0.5

  private static let drawCurve = Animation.timingCurve(0.25, 0.7, 0.2, 1.0, duration: duration)
  private static let undrawCurve = Animation.timingCurve(0.8, 0.0, 0.75, 0.3, duration: duration)

  var body: some View {
    GeometryReader { geo in
      let w = geo.size.width
      let h = geo.size.height
      let logoSize = min(w, h) * Brand.splashLogoScale
      let scale = logoSize / Brand.logoViewbox
      let strokeWidth = Brand.logoStrokeWidth * scale
      let ox = (w - logoSize) / 2
      let oy = (h - logoSize) / 2
      let path = parseSVGPath(Brand.logoPathReversed)
      let logoColor = colorScheme == .dark ? Brand.splashLogoColorDark : Brand.splashLogoColorLight

      ZStack {
        Image(nsImage: loadMeshImage())
          .resizable()
          .aspectRatio(contentMode: .fill)
          .frame(width: w, height: h)
          .clipped()

        LogoShape(path: path, scale: scale, ox: ox, oy: oy)
          .trim(from: eraseProgress, to: drawProgress)
          .stroke(
            logoColor,
            style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round)
          )
          .animation(Self.drawCurve, value: drawProgress)
          .animation(Self.undrawCurve, value: eraseProgress)
      }
    }
    .frame(width: 360, height: 640)
    .onAppear { startAnimation() }
  }

  private func startAnimation() {
    guard !started else { return }
    started = true

    let t0 = Self.delayBefore
    let t1 = t0 + Self.duration
    let t2 = t1 + Self.duration
    let t3 = t2 + Self.delayAfter

    DispatchQueue.main.asyncAfter(deadline: .now() + t0) {
      drawProgress = 1
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + t1) {
      eraseProgress = 1
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + t3) {
      onFinished()
    }
  }

  private func loadMeshImage() -> NSImage {
    guard
      let url = Bundle.main.url(forResource: "MeshGradient", withExtension: "png"),
      let img = NSImage(contentsOf: url)
    else { return NSImage() }
    return img
  }
}

// MARK: - Logo Shape

private struct LogoShape: Shape {
  let path: Path
  let scale: CGFloat
  let ox: CGFloat
  let oy: CGFloat

  func path(in rect: CGRect) -> Path {
    Path { p in
      p.addPath(
        path.applying(
          CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: ox, y: oy))))
    }
  }
}
