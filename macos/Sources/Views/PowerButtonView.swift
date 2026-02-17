import SwiftUI

// MARK: - Power Button View

struct PowerButtonView: View {
  let state: PowerButtonState
  var onTap: (() -> Void)? = nil

  @State private var pulsing = false
  @State private var isPressed = false
  @State private var haloPulsing = false

  var body: some View {
    ZStack {
      // Soft halo with gentle pulse
      Circle()
        .fill(stateColor.opacity(haloPulsing ? 0.10 : 0.05))
        .scaleEffect(haloPulsing ? 1.30 : 1.15)

      // Press ripple ring
      Circle()
        .stroke(stateColor.opacity(isPressed ? 0.3 : 0), lineWidth: 2)
        .scaleEffect(isPressed ? 1.3 : 1.0)

      Circle()
        .fill(stateColor)
        .scaleEffect(pulsing ? 0.88 : 1.0)

      iconView
        .scaleEffect(pulsing ? 0.88 : 1.0)
    }
    .scaleEffect(isPressed ? 0.85 : 1.0)
    .animation(.easeInOut(duration: 0.3), value: stateColor)
    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulsing)
    .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: haloPulsing)
    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: isPressed)
    .onTapGesture {
      isPressed = true
      onTap?()
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
        isPressed = false
      }
    }
    .onHover { inside in
      if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
    }
    .onChange(of: state) { _ in updatePulse() }
    .onAppear {
      updatePulse()
      haloPulsing = true
    }
  }

  private var stateColor: Color {
    switch state {
    case .noPermission: return DesignColor.mutedYellow
    case .unpaired: return DesignColor.mutedGray
    case .connecting: return DesignColor.mutedOrange
    case .connected: return DesignColor.mutedGreen
    case .disconnected: return DesignColor.mutedRed
    }
  }

  @ViewBuilder
  private var iconView: some View {
    let icon: ShieldIcon = {
      switch state {
      case .noPermission: return .warning
      case .unpaired: return .keyhole
      case .connecting: return .up
      case .connected: return .check
      case .disconnected: return .cross
      }
    }()

    GeometryReader { geo in
      let size = min(geo.size.width, geo.size.height)
      let iconSize = size * 0.45
      let scale = iconSize / 24.0
      let offset = (size - iconSize) / 2

      ZStack {
        // Shield outline — default lineCap/lineJoin per SVG source
        Path { p in
          let sub = parseSVGPath(Self.shieldPath)
          let transform = CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: offset, y: offset))
          p.addPath(sub.applying(transform))
        }
        .stroke(DesignColor.onButton, style: StrokeStyle(lineWidth: scale * 1.5))

        // Inner icon
        icon.view(scale: scale, offset: offset)
      }
    }
  }

  private func updatePulse() {
    pulsing = state == .connecting
  }

  // MARK: - Shield Icons

  enum ShieldIcon {
    case check, cross, keyhole, up, warning

    @ViewBuilder
    func view(scale: CGFloat, offset: CGFloat) -> some View {
      let transform = CGAffineTransform(scaleX: scale, y: scale)
        .concatenating(CGAffineTransform(translationX: offset, y: offset))

      switch self {
      case .check:
        // SVG: stroke-linecap="round" stroke-linejoin="round"
        Path { p in
          p.addPath(parseSVGPath("M9.5 12.4l1.429 1.6l3.571-4").applying(transform))
        }
        .stroke(
          DesignColor.onButton,
          style: StrokeStyle(lineWidth: scale * 1.5, lineCap: .round, lineJoin: .round))

      case .cross:
        // SVG: stroke-linecap="round"
        Path { p in
          p.addPath(parseSVGPath("M14.5 9.5l-5 5m0-5l5 5").applying(transform))
        }
        .stroke(DesignColor.onButton, style: StrokeStyle(lineWidth: scale * 1.5, lineCap: .round))

      case .keyhole:
        // SVG: stroke-linejoin="round"
        Path { p in
          p.addPath(
            parseSVGPath(
              "M11.5 16h1a1 1 0 0 0 1-1v-1.401A2.999 2.999 0 0 0 12 8a3 3 0 0 0-1.5 5.599V15a1 1 0 0 0 1 1Z"
            ).applying(transform))
        }
        .stroke(DesignColor.onButton, style: StrokeStyle(lineWidth: scale * 1.5, lineJoin: .round))

      case .up:
        // SVG: stroke-linecap="round" stroke-linejoin="round"
        Path { p in
          p.addPath(
            parseSVGPath("M16 11.55L12.6 9a1 1 0 0 0-1.2 0L8 11.55m6 2.5l-2-1.5l-2 1.5").applying(
              transform))
        }
        .stroke(
          DesignColor.onButton,
          style: StrokeStyle(lineWidth: scale * 1.5, lineCap: .round, lineJoin: .round))

      case .warning:
        // SVG: line stroke-linecap="round", dot is filled circle cx=12 cy=15 r=1
        ZStack {
          Path { p in
            p.addPath(parseSVGPath("M12 8v4").applying(transform))
          }
          .stroke(DesignColor.onButton, style: StrokeStyle(lineWidth: scale * 1.5, lineCap: .round))

          Circle()
            .fill(DesignColor.onButton)
            .frame(width: scale * 2, height: scale * 2)
            .position(x: offset + 12 * scale, y: offset + 15 * scale)
        }
      }
    }
  }

  // MARK: - Path Data

  static let shieldPath =
    "M3 10.417c0-3.198 0-4.797.378-5.335c.377-.537 1.88-1.052 4.887-2.081l.573-.196C10.405 2.268 11.188 2 12 2s1.595.268 3.162.805l.573.196c3.007 1.029 4.51 1.544 4.887 2.081C21 5.62 21 7.22 21 10.417v1.574c0 5.638-4.239 8.375-6.899 9.536C13.38 21.842 13.02 22 12 22s-1.38-.158-2.101-.473C7.239 20.365 3 17.63 3 11.991z"
}
