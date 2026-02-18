import AppKit
import SwiftUI

struct SplashView: View {
  var onFinished: () -> Void

  var body: some View {
    SplashNSViewRepresentable(onFinished: onFinished)
      .frame(width: 360, height: 640)
  }
}

// MARK: - NSView wrapper

private struct SplashNSViewRepresentable: NSViewRepresentable {
  let onFinished: () -> Void

  func makeNSView(context: Context) -> SplashNSView {
    SplashNSView(onFinished: onFinished)
  }

  func updateNSView(_ nsView: SplashNSView, context: Context) {}
}

// MARK: - Core Animation Splash View

private class SplashNSView: NSView {
  private let onFinished: () -> Void
  private var meshImage: NSImage?
  private var displayLink: CVDisplayLink?
  private var startTime: CFTimeInterval = 0
  private var phase: Phase = .delayBefore
  private var logoColor: NSColor = .white

  // Bar paths (from logo.svg)
  private static let bar1Path = "M410.094 160.783H17.871l102.254-160.79h391.868z"
  private static let bar2Path = "M305.464 336.398H108.914l101.529-160.79h191.956Z"
  private static let bar3Path = "M391.781 512.0H0.0l100.601-160.79h392.506z"

  private struct Bar {
    let cgPath: CGPath
    let bounds: CGRect
    let fromRight: Bool
    var drawProgress: CGFloat = 0
    var eraseProgress: CGFloat = 0
  }

  private var bars: [Bar] = []

  // Bar timings
  private static let delayBefore: CFTimeInterval = 0
  private static let bar1Dur: CFTimeInterval = 0.25
  private static let bar2Dur: CFTimeInterval = 0.20
  private static let bar3Dur: CFTimeInterval = 0.25
  private static let bar2Begin: CFTimeInterval = 0.20
  private static let bar3Begin: CFTimeInterval = 0.35
  private static let drawEnd: CFTimeInterval = bar3Begin + bar3Dur
  private static let delayAfter: CFTimeInterval = 0.50

  private enum Phase {
    case delayBefore, drawing, delayAfterPhase, done
  }

  init(onFinished: @escaping () -> Void) {
    self.onFinished = onFinished
    super.init(frame: .zero)

    if let url = Bundle.main.url(forResource: "Mesh", withExtension: "png") {
      meshImage = NSImage(contentsOf: url)
    }

    let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    logoColor =
      isDark
      ? NSColor(Brand.splashLogoColorDark)
      : NSColor(Brand.splashLogoColorLight)
  }

  required init?(coder: NSCoder) { fatalError() }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    guard window != nil, bars.isEmpty else { return }
    setupBars()
    startDisplayLink()
  }

  private func setupBars() {
    let w = bounds.width > 0 ? bounds.width : 360
    let h = bounds.height > 0 ? bounds.height : 640
    let logoSize = min(w, h) * CGFloat(Brand.splashLogoScale)
    let scale = logoSize / Brand.logoViewbox
    let ox = (w - logoSize) / 2
    let oy = (h - logoSize) / 2

    let transform = CGAffineTransform(scaleX: scale, y: scale)
      .concatenating(CGAffineTransform(translationX: ox, y: oy))

    for (pathData, fromRight) in [
      (Self.bar1Path, false),
      (Self.bar2Path, true),
      (Self.bar3Path, false),
    ] {
      let path = parseSVGPath(pathData).cgPath.copy(using: [transform])!
      let bounds = path.boundingBoxOfPath
      bars.append(Bar(cgPath: path, bounds: bounds, fromRight: fromRight))
    }
  }

  override var isFlipped: Bool { true }

  override func layout() {
    super.layout()
    if !bars.isEmpty { return }
    setupBars()
  }

  // MARK: - Display Link

  private func startDisplayLink() {
    startTime = CACurrentMediaTime()
    phase = .delayBefore

    var dl: CVDisplayLink?
    CVDisplayLinkCreateWithActiveCGDisplays(&dl)
    guard let dl = dl else { return }
    displayLink = dl

    CVDisplayLinkSetOutputCallback(
      dl,
      { (_, _, _, _, _, context) -> CVReturn in
        let view = Unmanaged<SplashNSView>.fromOpaque(context!).takeUnretainedValue()
        DispatchQueue.main.async { view.tick() }
        return kCVReturnSuccess
      }, Unmanaged.passUnretained(self).toOpaque())

    CVDisplayLinkStart(dl)
  }

  private func stopDisplayLink() {
    if let dl = displayLink {
      CVDisplayLinkStop(dl)
      displayLink = nil
    }
  }

  private func tick() {
    let elapsed = CACurrentMediaTime() - startTime

    switch phase {
    case .delayBefore:
      if elapsed >= Self.delayBefore {
        startTime = CACurrentMediaTime()
        phase = .drawing
      }

    case .drawing:
      let t = CACurrentMediaTime() - startTime
      bars[0].drawProgress = Self.ease(
        t, dur: Self.bar1Dur, begin: 0, cp1: (0.25, 0.1), cp2: (0.25, 1))
      bars[1].drawProgress = Self.ease(
        t, dur: Self.bar2Dur, begin: Self.bar2Begin, cp1: (0.42, 0), cp2: (0.58, 1))
      bars[2].drawProgress = Self.ease(
        t, dur: Self.bar3Dur, begin: Self.bar3Begin, cp1: (0.25, 0.1), cp2: (0.6, 1))
      if t >= Self.drawEnd {
        for i in bars.indices { bars[i].drawProgress = 1 }
        startTime = CACurrentMediaTime()
        phase = .delayAfterPhase
      }

    case .delayAfterPhase:
      if CACurrentMediaTime() - startTime >= Self.delayAfter {
        phase = .done
        stopDisplayLink()
        onFinished()
        return
      }

    case .done:
      return
    }

    setNeedsDisplay(bounds)
  }

  // MARK: - Cubic Bezier Easing

  private static func ease(
    _ t: CFTimeInterval, dur: CFTimeInterval, begin: CFTimeInterval,
    cp1: (CGFloat, CGFloat), cp2: (CGFloat, CGFloat)
  ) -> CGFloat {
    let local = t - begin
    if local <= 0 { return 0 }
    if local >= dur { return 1 }
    let frac = CGFloat(local / dur)
    return cubicBezier(frac, x1: cp1.0, y1: cp1.1, x2: cp2.0, y2: cp2.1)
  }

  private static func cubicBezier(_ t: CGFloat, x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat)
    -> CGFloat
  {
    // Newton's method to solve for parameter at given x
    var guess = t
    for _ in 0..<8 {
      let bx = bezierComponent(guess, c1: x1, c2: x2)
      let dx = bezierDerivative(guess, c1: x1, c2: x2)
      if abs(dx) < 1e-6 { break }
      guess -= (bx - t) / dx
    }
    return bezierComponent(guess, c1: y1, c2: y2)
  }

  private static func bezierComponent(_ t: CGFloat, c1: CGFloat, c2: CGFloat) -> CGFloat {
    let t2 = t * t
    let t3 = t2 * t
    return 3 * (1 - t) * (1 - t) * t * c1 + 3 * (1 - t) * t2 * c2 + t3
  }

  private static func bezierDerivative(_ t: CGFloat, c1: CGFloat, c2: CGFloat) -> CGFloat {
    let t2 = t * t
    return 3 * (1 - t) * (1 - t) * c1 + 6 * (1 - t) * t * (c2 - c1) + 3 * t2 * (1 - c2)
  }

  // MARK: - Drawing

  override func draw(_ dirtyRect: NSRect) {
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }

    // Draw mesh background
    if let img = meshImage, let cgImg = img.cgImage(forProposedRect: nil, context: nil, hints: nil)
    {
      ctx.draw(cgImg, in: bounds)
    }

    // Draw bars
    ctx.setFillColor(logoColor.cgColor)
    for bar in bars {
      if bar.drawProgress <= 0 { continue }
      let b = bar.bounds
      let clipLeft: CGFloat
      let clipRight: CGFloat
      if bar.fromRight {
        clipRight = b.maxX - b.width * bar.eraseProgress
        clipLeft = b.maxX - b.width * bar.drawProgress
      } else {
        clipLeft = b.minX + b.width * bar.eraseProgress
        clipRight = b.minX + b.width * bar.drawProgress
      }
      if clipLeft >= clipRight { continue }
      ctx.saveGState()
      ctx.clip(to: CGRect(x: clipLeft, y: b.minY, width: clipRight - clipLeft, height: b.height))
      ctx.addPath(bar.cgPath)
      ctx.fillPath()
      ctx.restoreGState()
    }
  }
}
