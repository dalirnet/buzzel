import SwiftUI

// MARK: - Circular QR Code View

struct CircularQRCodeView: View {
    let matrix: [[Bool]]
    let size: CGFloat

    private let centerRatio: CGFloat = 0.28
    private let qrCodeScale: CGFloat = 0.72

    @ViewBuilder
    var body: some View {
        let moduleCount = matrix.count

        if moduleCount == 0 {
            EmptyView()
        } else {
            let qrCodeSize = size * qrCodeScale
            let qrCodeOrigin = (size - qrCodeSize) / 2
            let dotSize = qrCodeSize / CGFloat(moduleCount)
            let centerRadius = size * centerRatio / 2
            let logoSize = size * centerRatio * 0.5

            let noiseDots = Self.generateNoiseRing(
                size: size,
                qrCodeOrigin: qrCodeOrigin,
                qrCodeSize: qrCodeSize,
                dotSize: dotSize,
                centerRadius: centerRadius
            )

            ZStack {
                Canvas { context, _ in
                    let center = size / 2

                    for row in 0..<moduleCount {
                        for column in 0..<moduleCount {
                            guard matrix[row][column] else { continue }

                            let dotX = qrCodeOrigin + CGFloat(column) * dotSize + dotSize / 2
                            let dotY = qrCodeOrigin + CGFloat(row) * dotSize + dotSize / 2
                            let distanceX = dotX - center
                            let distanceY = dotY - center
                            let distanceFromCenter = sqrt(
                                distanceX * distanceX + distanceY * distanceY)

                            // Skip center logo area
                            if distanceFromCenter < centerRadius { continue }

                            let dotRadius = dotSize * 0.42
                            let dotRect = CGRect(
                                x: dotX - dotRadius, y: dotY - dotRadius,
                                width: dotRadius * 2, height: dotRadius * 2
                            )
                            context.fill(
                                SwiftUI.Path(ellipseIn: dotRect), with: .color(DesignColor.text))
                        }
                    }

                    for noiseDot in noiseDots {
                        let dotRadius = dotSize * 0.42
                        let dotRect = CGRect(
                            x: noiseDot.x - dotRadius, y: noiseDot.y - dotRadius,
                            width: dotRadius * 2, height: dotRadius * 2
                        )
                        context.fill(
                            SwiftUI.Path(ellipseIn: dotRect),
                            with: .color(DesignColor.text.opacity(noiseDot.opacity))
                        )
                    }
                }
                .frame(width: size, height: size)
                .clipShape(Circle())

                BuzzelLogoView(size: logoSize)
            }
            .frame(width: size, height: size)
        }
    }

    // MARK: - Noise Ring

    private struct NoiseDot {
        let x: CGFloat
        let y: CGFloat
        let opacity: CGFloat
    }

    private static func generateNoiseRing(
        size: CGFloat,
        qrCodeOrigin: CGFloat,
        qrCodeSize: CGFloat,
        dotSize: CGFloat,
        centerRadius: CGFloat
    ) -> [NoiseDot] {
        let center = size / 2
        let radius = size / 2
        let step = dotSize
        var dots: [NoiseDot] = []

        var randomSeed: UInt64 = 0xDEAD_BEEF
        func nextRandomValue() -> CGFloat {
            randomSeed = randomSeed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return CGFloat(randomSeed >> 33) / CGFloat(0x7FFF_FFFF)
        }

        let columnCount = Int(ceil(size / step)) + 1
        let rowCount = Int(ceil(size / step)) + 1

        for row in 0..<rowCount {
            for column in 0..<columnCount {
                let jitter = step * 0.3
                let dotX = CGFloat(column) * step + nextRandomValue() * jitter - jitter / 2
                let dotY = CGFloat(row) * step + nextRandomValue() * jitter - jitter / 2

                let distanceX = dotX - center
                let distanceY = dotY - center
                let distanceFromCenter = sqrt(distanceX * distanceX + distanceY * distanceY)

                guard distanceFromCenter + step * 0.4 < radius else { continue }

                let isInsideQRCode =
                    dotX >= qrCodeOrigin && dotX <= qrCodeOrigin + qrCodeSize
                    && dotY >= qrCodeOrigin && dotY <= qrCodeOrigin + qrCodeSize
                guard !isInsideQRCode else { continue }

                guard distanceFromCenter >= centerRadius else { continue }

                guard nextRandomValue() > 0.55 else { continue }

                let distanceFromQRCodeEdge = min(
                    abs(dotX - qrCodeOrigin), abs(dotX - (qrCodeOrigin + qrCodeSize)),
                    abs(dotY - qrCodeOrigin), abs(dotY - (qrCodeOrigin + qrCodeSize))
                )
                let edgeFadeAmount = min(distanceFromQRCodeEdge / (step * 2), 1.0)

                let distancePastFadeStart = max(0, distanceFromCenter - radius * 0.8)
                let circleFadeZoneWidth = radius * 0.2
                let circleFadeAmount = 1.0 - distancePastFadeStart / circleFadeZoneWidth

                let dotOpacity = edgeFadeAmount * circleFadeAmount * 0.5

                dots.append(NoiseDot(x: dotX, y: dotY, opacity: dotOpacity))
            }
        }

        return dots
    }
}
