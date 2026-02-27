import SwiftUI

// MARK: - Animated Switcher

struct AnimatedSwitcher<Key: Hashable, Content: View>: View {
    let key: Key
    @ViewBuilder let content: (Key) -> Content

    private static var scaleDownDuration: Double { 0.25 }
    private static var swapAt: Double { 0.12 }

    @State private var displayedKey: Key
    @State private var scale: CGFloat = 1.0
    @State private var isAnimating = false

    init(key: Key, @ViewBuilder content: @escaping (Key) -> Content) {
        self.key = key
        self.content = content
        _displayedKey = State(initialValue: key)
    }

    var body: some View {
        content(displayedKey)
            .scaleEffect(scale)
            .onChange(of: key) { newKey in
                guard !isAnimating else { return }
                isAnimating = true

                withAnimation(.easeIn(duration: Self.scaleDownDuration)) {
                    scale = 0.0
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + Self.swapAt) {
                    displayedKey = newKey
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        scale = 1.0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        isAnimating = false
                    }
                }
            }
    }
}
