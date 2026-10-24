import SwiftUI

struct FidgetLogo: View {
  var size: CGFloat
  @State private var angle: Double = 0
  @State private var lastTouch: Double?
  @State private var lastTime = Date()
  @State private var velocity: Double = 0

  var body: some View {
    Image("ArdiaMark")
      .resizable()
      .scaledToFit()
      .frame(width: size, height: size)
      .rotationEffect(.degrees(angle))
      .contentShape(Circle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            let touch = atan2(value.location.y - size / 2, value.location.x - size / 2) * 180 / .pi
            let now = Date()
            if let lastTouch {
              var delta = touch - lastTouch
              if delta > 180 { delta -= 360 }
              if delta < -180 { delta += 360 }
              angle += delta
              velocity = delta / max(0.008, now.timeIntervalSince(lastTime))
            } else {
              velocity = 0
              UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            }
            lastTouch = touch
            lastTime = now
          }
          .onEnded { value in
            lastTouch = nil
            let moved = hypot(value.translation.width, value.translation.height) > 4
            let spin = moved ? max(-2160, min(2160, velocity * 0.7)) : 360
            withAnimation(.timingCurve(0.15, 0.75, 0.25, 1, duration: max(0.7, min(3.2, abs(spin) / 520)))) { angle += spin }
            if abs(spin) > 900 { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
          }
      )
      .accessibilityLabel("Ardia")
  }
}
