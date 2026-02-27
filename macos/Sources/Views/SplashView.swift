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

    func makeNSView(context _: Context) -> SplashNSView {
        SplashNSView(onFinished: onFinished)
    }

    func updateNSView(_: SplashNSView, context _: Context) {}
}

// MARK: - Core Animation Splash View

private class SplashNSView: NSView {
    private let onFinished: () -> Void
    private var meshImage: NSImage?
    private var displayLink: CVDisplayLink?
    private var startTime: CFTimeInterval = 0
    private var phase: Phase = .delayBefore
    private var logoColor: NSColor = .white

    private static let topBarPath = "M410.094 160.783H17.871l102.254-160.79h391.868z"
    private static let middleBarPath = "M305.464 336.398H108.914l101.529-160.79h191.956Z"
    private static let bottomBarPath = "M391.781 512.0H0.0l100.601-160.79h392.506z"

    private struct Bar {
        let cgPath: CGPath
        let bounds: CGRect
        let fromRight: Bool
        var drawProgress: CGFloat = 0
        var eraseProgress: CGFloat = 0
    }

    private var bars: [Bar] = []

    private static let delayBefore: CFTimeInterval = 0
    private static let delayAfter: CFTimeInterval = 0.50

    private static let topBarDuration: CFTimeInterval = 0.25
    private static let middleBarDuration: CFTimeInterval = 0.20
    private static let bottomBarDuration: CFTimeInterval = 0.25

    private static let middleBarBegin: CFTimeInterval = 0.20
    private static let bottomBarBegin: CFTimeInterval = 0.35
    private static let drawEnd: CFTimeInterval = bottomBarBegin + bottomBarDuration

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

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, bars.isEmpty else { return }
        setupBars()
        startDisplayLink()
    }

    private func setupBars() {
        let width = bounds.width > 0 ? bounds.width : 360
        let height = bounds.height > 0 ? bounds.height : 640
        let logoSize = min(width, height) * CGFloat(Brand.splashLogoScale)
        let scale = logoSize / Brand.logoViewbox
        let logoOffsetX = (width - logoSize) / 2
        let logoOffsetY = (height - logoSize) / 2

        let transform = CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: logoOffsetX, y: logoOffsetY))

        for (pathData, fromRight) in [
            (Self.topBarPath, false),
            (Self.middleBarPath, true),
            (Self.bottomBarPath, false),
        ] {
            let path = parseSVGPath(pathData).cgPath.copy(using: [transform])!
            let bounds = path.boundingBoxOfPath
            bars.append(Bar(cgPath: path, bounds: bounds, fromRight: fromRight))
        }
    }

    override var isFlipped: Bool {
        true
    }

    override func layout() {
        super.layout()
        if !bars.isEmpty { return }
        setupBars()
    }

    // MARK: - Display Link

    private func startDisplayLink() {
        startTime = CACurrentMediaTime()
        phase = .delayBefore

        var newDisplayLink: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&newDisplayLink)
        guard let newDisplayLink else { return }
        displayLink = newDisplayLink

        CVDisplayLinkSetOutputCallback(
            newDisplayLink,
            { _, _, _, _, _, context -> CVReturn in
                let view = Unmanaged<SplashNSView>.fromOpaque(context!).takeUnretainedValue()
                DispatchQueue.main.async { view.tick() }
                return kCVReturnSuccess
            }, Unmanaged.passUnretained(self).toOpaque()
        )

        CVDisplayLinkStart(newDisplayLink)
    }

    private func stopDisplayLink() {
        guard let activeLink = displayLink else { return }
        CVDisplayLinkStop(activeLink)
        displayLink = nil
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
            let elapsedTime = CACurrentMediaTime() - startTime
            bars[0].drawProgress = Self.ease(
                elapsedTime, duration: Self.topBarDuration, begin: 0,
                controlPoint1: (0.25, 0.1), controlPoint2: (0.25, 1)
            )
            bars[1].drawProgress = Self.ease(
                elapsedTime, duration: Self.middleBarDuration, begin: Self.middleBarBegin,
                controlPoint1: (0.42, 0), controlPoint2: (0.58, 1)
            )
            bars[2].drawProgress = Self.ease(
                elapsedTime, duration: Self.bottomBarDuration, begin: Self.bottomBarBegin,
                controlPoint1: (0.25, 0.1), controlPoint2: (0.6, 1)
            )
            if elapsedTime >= Self.drawEnd {
                for i in bars.indices {
                    bars[i].drawProgress = 1
                }
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
        _ time: CFTimeInterval, duration: CFTimeInterval, begin: CFTimeInterval,
        controlPoint1: (CGFloat, CGFloat), controlPoint2: (CGFloat, CGFloat)
    ) -> CGFloat {
        let localTime = time - begin
        if localTime <= 0 { return 0 }
        if localTime >= duration { return 1 }
        let fraction = CGFloat(localTime / duration)
        return cubicBezier(
            fraction, x1: controlPoint1.0, y1: controlPoint1.1,
            x2: controlPoint2.0, y2: controlPoint2.1)
    }

    private static func cubicBezier(
        _ parameter: CGFloat, x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat
    ) -> CGFloat {
        // Newton's method to solve for parameter at given x
        var guess = parameter
        for _ in 0..<8 {
            let bezierX = bezierComponent(guess, c1: x1, c2: x2)
            let derivativeX = bezierDerivative(guess, c1: x1, c2: x2)
            if abs(derivativeX) < 1e-6 { break }
            guess -= (bezierX - parameter) / derivativeX
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

    override func draw(_: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        if let meshSource = meshImage,
            let cgMeshImage = meshSource.cgImage(forProposedRect: nil, context: nil, hints: nil)
        {
            context.draw(cgMeshImage, in: bounds)
        }

        context.setFillColor(logoColor.cgColor)
        for bar in bars {
            if bar.drawProgress <= 0 { continue }
            let barBounds = bar.bounds
            let clipLeft: CGFloat
            let clipRight: CGFloat
            if bar.fromRight {
                clipRight = barBounds.maxX - barBounds.width * bar.eraseProgress
                clipLeft = barBounds.maxX - barBounds.width * bar.drawProgress
            } else {
                clipLeft = barBounds.minX + barBounds.width * bar.eraseProgress
                clipRight = barBounds.minX + barBounds.width * bar.drawProgress
            }
            if clipLeft >= clipRight { continue }
            context.saveGState()
            context.clip(
                to: CGRect(
                    x: clipLeft, y: barBounds.minY,
                    width: clipRight - clipLeft, height: barBounds.height
                ))
            context.addPath(bar.cgPath)
            context.fillPath()
            context.restoreGState()
        }
    }
}
