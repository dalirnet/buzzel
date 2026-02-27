import SwiftUI

// MARK: - SVG Arc to Bezier

private func addArc(
    to path: inout Path,
    from startPoint: CGPoint, to endPoint: CGPoint,
    radiusX: CGFloat, radiusY: CGFloat,
    rotation: CGFloat,
    largeArc: Bool, sweep: Bool
) {
    guard startPoint != endPoint else { return }
    guard radiusX > 0, radiusY > 0 else {
        path.addLine(to: endPoint)
        return
    }

    let rotationRadians = rotation * .pi / 180
    let cosRotation = cos(rotationRadians)
    let sinRotation = sin(rotationRadians)

    // Step 1: Transform to center parameterization
    let deltaX = (startPoint.x - endPoint.x) / 2
    let deltaY = (startPoint.y - endPoint.y) / 2
    let transformedX = cosRotation * deltaX + sinRotation * deltaY
    let transformedY = -sinRotation * deltaX + cosRotation * deltaY

    // Correct radii if too small
    var radiusXSquared = radiusX * radiusX
    var radiusYSquared = radiusY * radiusY
    let transformedXSquared = transformedX * transformedX
    let transformedYSquared = transformedY * transformedY
    let lambda = transformedXSquared / radiusXSquared + transformedYSquared / radiusYSquared
    var correctedRadiusX = radiusX
    var correctedRadiusY = radiusY
    if lambda > 1 {
        let sqrtLambda = sqrt(lambda)
        correctedRadiusX *= sqrtLambda
        correctedRadiusY *= sqrtLambda
        radiusXSquared = correctedRadiusX * correctedRadiusX
        radiusYSquared = correctedRadiusY * correctedRadiusY
    }

    // Step 2: Compute center
    let numerator = max(
        0,
        radiusXSquared * radiusYSquared - radiusXSquared * transformedYSquared
            - radiusYSquared * transformedXSquared
    )
    let denominator = radiusXSquared * transformedYSquared + radiusYSquared * transformedXSquared
    let squareRoot = denominator > 0 ? sqrt(numerator / denominator) : 0
    let sign: CGFloat = (largeArc == sweep) ? -1 : 1
    let centerTransformedX =
        sign * squareRoot * (correctedRadiusX * transformedY / correctedRadiusY)
    let centerTransformedY =
        sign * squareRoot * (-correctedRadiusY * transformedX / correctedRadiusX)

    let midpointX = (startPoint.x + endPoint.x) / 2
    let midpointY = (startPoint.y + endPoint.y) / 2
    let centerX = cosRotation * centerTransformedX - sinRotation * centerTransformedY + midpointX
    let centerY = sinRotation * centerTransformedX + cosRotation * centerTransformedY + midpointY

    /// Step 3: Compute angles
    func angleBetweenVectors(
        ux: CGFloat, uy: CGFloat, vx: CGFloat, vy: CGFloat
    ) -> CGFloat {
        let dotProduct = ux * vx + uy * vy
        let magnitudeProduct = sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy)
        let cosineRatio = magnitudeProduct > 0 ? dotProduct / magnitudeProduct : 0
        let clampedCosine = max(-1, min(1, cosineRatio))
        var angle = magnitudeProduct > 0 ? acos(clampedCosine) : 0
        if ux * vy - uy * vx < 0 { angle = -angle }
        return angle
    }

    let startAngle = angleBetweenVectors(
        ux: 1, uy: 0,
        vx: (transformedX - centerTransformedX) / correctedRadiusX,
        vy: (transformedY - centerTransformedY) / correctedRadiusY
    )
    var sweepAngle = angleBetweenVectors(
        ux: (transformedX - centerTransformedX) / correctedRadiusX,
        uy: (transformedY - centerTransformedY) / correctedRadiusY,
        vx: (-transformedX - centerTransformedX) / correctedRadiusX,
        vy: (-transformedY - centerTransformedY) / correctedRadiusY
    )

    if !sweep, sweepAngle > 0 {
        sweepAngle -= 2 * .pi
    } else if sweep, sweepAngle < 0 {
        sweepAngle += 2 * .pi
    }

    // Step 4: Emit cubic bezier segments (max 90 degrees each)
    let segmentCount = max(1, Int(ceil(abs(sweepAngle) / (.pi / 2))))
    let segmentAngle = sweepAngle / CGFloat(segmentCount)
    let alpha = sin(segmentAngle) * (sqrt(4 + 3 * pow(tan(segmentAngle / 2), 2)) - 1) / 3

    var currentAngle = startAngle
    var currentCos = cos(currentAngle)
    var currentSin = sin(currentAngle)

    for _ in 0..<segmentCount {
        let nextAngle = currentAngle + segmentAngle
        let nextCos = cos(nextAngle)
        let nextSin = sin(nextAngle)

        // Endpoint on unit circle
        let startUnitX = currentCos
        let startUnitY = currentSin
        let endUnitX = nextCos
        let endUnitY = nextSin

        // Control points on unit ellipse
        let controlPoint1X = startUnitX - alpha * startUnitY
        let controlPoint1Y = startUnitY + alpha * startUnitX
        let controlPoint2X = endUnitX + alpha * endUnitY
        let controlPoint2Y = endUnitY - alpha * endUnitX

        /// Transform back
        func transformToOriginal(_ pointX: CGFloat, _ pointY: CGFloat) -> CGPoint {
            let scaledX = correctedRadiusX * pointX
            let scaledY = correctedRadiusY * pointY
            return CGPoint(
                x: cosRotation * scaledX - sinRotation * scaledY + centerX,
                y: sinRotation * scaledX + cosRotation * scaledY + centerY
            )
        }

        let control1 = transformToOriginal(controlPoint1X, controlPoint1Y)
        let control2 = transformToOriginal(controlPoint2X, controlPoint2Y)
        let endpoint = transformToOriginal(endUnitX, endUnitY)

        path.addCurve(to: endpoint, control1: control1, control2: control2)

        currentAngle = nextAngle
        currentCos = nextCos
        currentSin = nextSin
    }
}

// MARK: - SVG Path Parsing

func parseSVGPath(_ pathData: String) -> Path {
    var path = Path()
    let characters = Array(pathData)
    var index = 0
    var currentX: CGFloat = 0
    var currentY: CGFloat = 0
    var subpathStartX: CGFloat = 0
    var subpathStartY: CGFloat = 0

    func skipWhitespace() {
        while index < characters.count
            && (characters[index] == " " || characters[index] == "," || characters[index] == "\n")
        {
            index += 1
        }
    }

    func parseNumber() -> CGFloat? {
        skipWhitespace()
        guard index < characters.count else { return nil }
        var numberString = ""
        if index < characters.count && (characters[index] == "-" || characters[index] == "+") {
            numberString.append(characters[index])
            index += 1
        }
        var hasDecimalPoint = false
        while index < characters.count {
            let character = characters[index]
            if character.isNumber {
                numberString.append(character)
                index += 1
            } else if character == "." && !hasDecimalPoint {
                hasDecimalPoint = true
                numberString.append(character)
                index += 1
            } else if character == "e" || character == "E" {
                numberString.append(character)
                index += 1
                if index < characters.count
                    && (characters[index] == "-" || characters[index] == "+")
                {
                    numberString.append(characters[index])
                    index += 1
                }
            } else if character == "-" && !numberString.isEmpty {
                break
            } else {
                break
            }
        }
        return numberString.isEmpty ? nil : CGFloat(Double(numberString) ?? 0)
    }

    func parsePoint() -> CGPoint? {
        guard let x = parseNumber(), let y = parseNumber() else { return nil }
        return CGPoint(x: x, y: y)
    }

    var lastCommand: Character = " "
    var lastControlPoint: CGPoint?

    while index < characters.count {
        skipWhitespace()
        guard index < characters.count else { break }

        var command = characters[index]
        if command.isLetter {
            index += 1
            lastCommand = command
        } else {
            command = lastCommand
        }

        switch command {
        case "M":
            guard let point = parsePoint() else { break }
            path.move(to: point)
            currentX = point.x
            currentY = point.y
            subpathStartX = currentX
            subpathStartY = currentY
        case "m":
            guard let point = parsePoint() else { break }
            currentX += point.x
            currentY += point.y
            path.move(to: CGPoint(x: currentX, y: currentY))
            subpathStartX = currentX
            subpathStartY = currentY
        case "L":
            guard let point = parsePoint() else { break }
            path.addLine(to: point)
            currentX = point.x
            currentY = point.y
        case "l":
            guard let point = parsePoint() else { break }
            currentX += point.x
            currentY += point.y
            path.addLine(to: CGPoint(x: currentX, y: currentY))
        case "H":
            guard let x = parseNumber() else { break }
            path.addLine(to: CGPoint(x: x, y: currentY))
            currentX = x
        case "h":
            guard let deltaX = parseNumber() else { break }
            currentX += deltaX
            path.addLine(to: CGPoint(x: currentX, y: currentY))
        case "V":
            guard let y = parseNumber() else { break }
            path.addLine(to: CGPoint(x: currentX, y: y))
            currentY = y
        case "v":
            guard let deltaY = parseNumber() else { break }
            currentY += deltaY
            path.addLine(to: CGPoint(x: currentX, y: currentY))
        case "C":
            guard let control1 = parsePoint(), let control2 = parsePoint(), let point = parsePoint()
            else { break }
            path.addCurve(to: point, control1: control1, control2: control2)
            lastControlPoint = control2
            currentX = point.x
            currentY = point.y
        case "c":
            guard let control1 = parsePoint(), let control2 = parsePoint(), let point = parsePoint()
            else { break }
            let absoluteControl1 = CGPoint(x: currentX + control1.x, y: currentY + control1.y)
            let absoluteControl2 = CGPoint(x: currentX + control2.x, y: currentY + control2.y)
            let absolutePoint = CGPoint(x: currentX + point.x, y: currentY + point.y)
            path.addCurve(to: absolutePoint, control1: absoluteControl1, control2: absoluteControl2)
            lastControlPoint = absoluteControl2
            currentX = absolutePoint.x
            currentY = absolutePoint.y
        case "S":
            guard let control2 = parsePoint(), let point = parsePoint() else { break }
            let control1 =
                lastControlPoint.map {
                    CGPoint(x: 2 * currentX - $0.x, y: 2 * currentY - $0.y)
                } ?? CGPoint(x: currentX, y: currentY)
            path.addCurve(to: point, control1: control1, control2: control2)
            lastControlPoint = control2
            currentX = point.x
            currentY = point.y
        case "s":
            guard let control2 = parsePoint(), let point = parsePoint() else { break }
            let control1 =
                lastControlPoint.map {
                    CGPoint(x: 2 * currentX - $0.x, y: 2 * currentY - $0.y)
                } ?? CGPoint(x: currentX, y: currentY)
            let absoluteControl2 = CGPoint(x: currentX + control2.x, y: currentY + control2.y)
            let absolutePoint = CGPoint(x: currentX + point.x, y: currentY + point.y)
            path.addCurve(to: absolutePoint, control1: control1, control2: absoluteControl2)
            lastControlPoint = absoluteControl2
            currentX = absolutePoint.x
            currentY = absolutePoint.y
        case "Q":
            guard let controlPoint = parsePoint(), let point = parsePoint() else { break }
            path.addQuadCurve(to: point, control: controlPoint)
            currentX = point.x
            currentY = point.y
        case "q":
            guard let controlPoint = parsePoint(), let point = parsePoint() else { break }
            let absoluteControl = CGPoint(
                x: currentX + controlPoint.x, y: currentY + controlPoint.y
            )
            let absolutePoint = CGPoint(x: currentX + point.x, y: currentY + point.y)
            path.addQuadCurve(to: absolutePoint, control: absoluteControl)
            currentX = absolutePoint.x
            currentY = absolutePoint.y
        case "A", "a":
            let isRelative = command == "a"
            guard let arcRadiusX = parseNumber(), let arcRadiusY = parseNumber(),
                let arcRotation = parseNumber(), let largeArcFlag = parseNumber(),
                let sweepFlag = parseNumber(),
                let endX = parseNumber(), let endY = parseNumber()
            else { break }
            let arcEndPoint =
                isRelative
                ? CGPoint(x: currentX + endX, y: currentY + endY) : CGPoint(x: endX, y: endY)
            addArc(
                to: &path,
                from: CGPoint(x: currentX, y: currentY), to: arcEndPoint,
                radiusX: abs(arcRadiusX), radiusY: abs(arcRadiusY),
                rotation: arcRotation,
                largeArc: largeArcFlag != 0, sweep: sweepFlag != 0
            )
            currentX = arcEndPoint.x
            currentY = arcEndPoint.y
        case "Z", "z":
            path.closeSubpath()
            currentX = subpathStartX
            currentY = subpathStartY
        default:
            index += 1
        }
    }
    return path
}
