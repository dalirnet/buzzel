import SwiftUI

// MARK: - SVG Arc to Bezier

private func addArc(
    to path: inout Path,
    from p1: CGPoint, to p2: CGPoint,
    rx: CGFloat, ry: CGFloat,
    rotation: CGFloat,
    largeArc: Bool, sweep: Bool
) {
    guard p1 != p2 else { return }
    guard rx > 0 && ry > 0 else { path.addLine(to: p2); return }

    let phi = rotation * .pi / 180
    let cosPhi = cos(phi), sinPhi = sin(phi)

    // Step 1: Transform to center parameterization
    let dx = (p1.x - p2.x) / 2, dy = (p1.y - p2.y) / 2
    let x1p = cosPhi * dx + sinPhi * dy
    let y1p = -sinPhi * dx + cosPhi * dy

    // Correct radii if too small
    var rxSq = rx * rx, rySq = ry * ry
    let x1pSq = x1p * x1p, y1pSq = y1p * y1p
    let lambda = x1pSq / rxSq + y1pSq / rySq
    var rxC = rx, ryC = ry
    if lambda > 1 {
        let sq = sqrt(lambda)
        rxC *= sq; ryC *= sq
        rxSq = rxC * rxC; rySq = ryC * ryC
    }

    // Step 2: Compute center
    let num = max(0, rxSq * rySq - rxSq * y1pSq - rySq * x1pSq)
    let den = rxSq * y1pSq + rySq * x1pSq
    let sq = den > 0 ? sqrt(num / den) : 0
    let sign: CGFloat = (largeArc == sweep) ? -1 : 1
    let cxp = sign * sq * (rxC * y1p / ryC)
    let cyp = sign * sq * (-ryC * x1p / rxC)

    let midX = (p1.x + p2.x) / 2, midY = (p1.y + p2.y) / 2
    let centerX = cosPhi * cxp - sinPhi * cyp + midX
    let centerY = sinPhi * cxp + cosPhi * cyp + midY

    // Step 3: Compute angles
    func angle(ux: CGFloat, uy: CGFloat, vx: CGFloat, vy: CGFloat) -> CGFloat {
        let dot = ux * vx + uy * vy
        let len = sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy)
        var a = len > 0 ? acos(max(-1, min(1, dot / len))) : 0
        if ux * vy - uy * vx < 0 { a = -a }
        return a
    }

    let theta1 = angle(ux: 1, uy: 0, vx: (x1p - cxp) / rxC, vy: (y1p - cyp) / ryC)
    var dTheta = angle(
        ux: (x1p - cxp) / rxC, uy: (y1p - cyp) / ryC,
        vx: (-x1p - cxp) / rxC, vy: (-y1p - cyp) / ryC
    )

    if !sweep && dTheta > 0 { dTheta -= 2 * .pi }
    else if sweep && dTheta < 0 { dTheta += 2 * .pi }

    // Step 4: Emit cubic bezier segments (max 90° each)
    let segments = max(1, Int(ceil(abs(dTheta) / (.pi / 2))))
    let segAngle = dTheta / CGFloat(segments)
    let alpha = sin(segAngle) * (sqrt(4 + 3 * pow(tan(segAngle / 2), 2)) - 1) / 3

    var curAngle = theta1
    var curCos = cos(curAngle), curSin = sin(curAngle)

    for _ in 0..<segments {
        let nextAngle = curAngle + segAngle
        let nextCos = cos(nextAngle), nextSin = sin(nextAngle)

        // Endpoint on unit circle
        let ex1 = curCos, ey1 = curSin
        let ex2 = nextCos, ey2 = nextSin

        // Control points on unit ellipse
        let q1x = ex1 - alpha * ey1, q1y = ey1 + alpha * ex1
        let q2x = ex2 + alpha * ey2, q2y = ey2 - alpha * ex2

        // Transform back
        func transform(_ px: CGFloat, _ py: CGFloat) -> CGPoint {
            let x = rxC * px, y = ryC * py
            return CGPoint(
                x: cosPhi * x - sinPhi * y + centerX,
                y: sinPhi * x + cosPhi * y + centerY
            )
        }

        let cp1 = transform(q1x, q1y)
        let cp2 = transform(q2x, q2y)
        let end = transform(ex2, ey2)

        path.addCurve(to: end, control1: cp1, control2: cp2)

        curAngle = nextAngle
        curCos = nextCos; curSin = nextSin
    }
}

// MARK: - SVG Path Parsing

func parseSVGPath(_ d: String) -> Path {
    var path = Path()
    let chars = Array(d)
    var i = 0
    var cx: CGFloat = 0, cy: CGFloat = 0
    var startX: CGFloat = 0, startY: CGFloat = 0

    func skipWS() {
        while i < chars.count && (chars[i] == " " || chars[i] == "," || chars[i] == "\n") { i += 1 }
    }

    func parseNumber() -> CGFloat? {
        skipWS()
        guard i < chars.count else { return nil }
        var s = ""
        if i < chars.count && (chars[i] == "-" || chars[i] == "+") { s.append(chars[i]); i += 1 }
        var hasDot = false
        while i < chars.count {
            let c = chars[i]
            if c.isNumber { s.append(c); i += 1 }
            else if c == "." && !hasDot { hasDot = true; s.append(c); i += 1 }
            else if c == "e" || c == "E" {
                s.append(c); i += 1
                if i < chars.count && (chars[i] == "-" || chars[i] == "+") { s.append(chars[i]); i += 1 }
            }
            else if c == "-" && !s.isEmpty { break }
            else { break }
        }
        return s.isEmpty ? nil : CGFloat(Double(s) ?? 0)
    }

    func parsePoint() -> CGPoint? {
        guard let x = parseNumber(), let y = parseNumber() else { return nil }
        return CGPoint(x: x, y: y)
    }

    var lastCmd: Character = " "
    var lastControl: CGPoint?

    while i < chars.count {
        skipWS()
        guard i < chars.count else { break }

        var cmd = chars[i]
        if cmd.isLetter { i += 1; lastCmd = cmd }
        else { cmd = lastCmd }

        switch cmd {
        case "M":
            guard let p = parsePoint() else { break }
            path.move(to: p); cx = p.x; cy = p.y; startX = cx; startY = cy
        case "m":
            guard let p = parsePoint() else { break }
            cx += p.x; cy += p.y; path.move(to: CGPoint(x: cx, y: cy)); startX = cx; startY = cy
        case "L":
            guard let p = parsePoint() else { break }
            path.addLine(to: p); cx = p.x; cy = p.y
        case "l":
            guard let p = parsePoint() else { break }
            cx += p.x; cy += p.y; path.addLine(to: CGPoint(x: cx, y: cy))
        case "H":
            guard let x = parseNumber() else { break }
            path.addLine(to: CGPoint(x: x, y: cy)); cx = x
        case "h":
            guard let dx = parseNumber() else { break }
            cx += dx; path.addLine(to: CGPoint(x: cx, y: cy))
        case "V":
            guard let y = parseNumber() else { break }
            path.addLine(to: CGPoint(x: cx, y: y)); cy = y
        case "v":
            guard let dy = parseNumber() else { break }
            cy += dy; path.addLine(to: CGPoint(x: cx, y: cy))
        case "C":
            guard let c1 = parsePoint(), let c2 = parsePoint(), let p = parsePoint() else { break }
            path.addCurve(to: p, control1: c1, control2: c2)
            lastControl = c2; cx = p.x; cy = p.y
        case "c":
            guard let c1 = parsePoint(), let c2 = parsePoint(), let p = parsePoint() else { break }
            let ac1 = CGPoint(x: cx + c1.x, y: cy + c1.y)
            let ac2 = CGPoint(x: cx + c2.x, y: cy + c2.y)
            let ap = CGPoint(x: cx + p.x, y: cy + p.y)
            path.addCurve(to: ap, control1: ac1, control2: ac2)
            lastControl = ac2; cx = ap.x; cy = ap.y
        case "S":
            guard let c2 = parsePoint(), let p = parsePoint() else { break }
            let c1 = lastControl.map { CGPoint(x: 2 * cx - $0.x, y: 2 * cy - $0.y) } ?? CGPoint(x: cx, y: cy)
            path.addCurve(to: p, control1: c1, control2: c2)
            lastControl = c2; cx = p.x; cy = p.y
        case "s":
            guard let c2 = parsePoint(), let p = parsePoint() else { break }
            let c1 = lastControl.map { CGPoint(x: 2 * cx - $0.x, y: 2 * cy - $0.y) } ?? CGPoint(x: cx, y: cy)
            let ac2 = CGPoint(x: cx + c2.x, y: cy + c2.y)
            let ap = CGPoint(x: cx + p.x, y: cy + p.y)
            path.addCurve(to: ap, control1: c1, control2: ac2)
            lastControl = ac2; cx = ap.x; cy = ap.y
        case "Q":
            guard let ctrl = parsePoint(), let p = parsePoint() else { break }
            path.addQuadCurve(to: p, control: ctrl)
            cx = p.x; cy = p.y
        case "q":
            guard let ctrl = parsePoint(), let p = parsePoint() else { break }
            let ac = CGPoint(x: cx + ctrl.x, y: cy + ctrl.y)
            let ap = CGPoint(x: cx + p.x, y: cy + p.y)
            path.addQuadCurve(to: ap, control: ac)
            cx = ap.x; cy = ap.y
        case "A", "a":
            let isRelative = cmd == "a"
            guard let rx = parseNumber(), let ry = parseNumber(),
                  let rotation = parseNumber(), let largeArc = parseNumber(), let sweep = parseNumber(),
                  let ex = parseNumber(), let ey = parseNumber() else { break }
            let ep = isRelative ? CGPoint(x: cx + ex, y: cy + ey) : CGPoint(x: ex, y: ey)
            addArc(
                to: &path,
                from: CGPoint(x: cx, y: cy), to: ep,
                rx: abs(rx), ry: abs(ry),
                rotation: rotation,
                largeArc: largeArc != 0, sweep: sweep != 0
            )
            cx = ep.x; cy = ep.y
        case "Z", "z":
            path.closeSubpath(); cx = startX; cy = startY
        default:
            i += 1
        }
    }
    return path
}
