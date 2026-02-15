import SwiftUI

struct ViewLayout<HeaderLeft: View, HeaderRight: View, Content: View, Footer: View>: View {
    let headerLeft: HeaderLeft
    let headerRight: HeaderRight
    let content: Content
    let footer: Footer

    init(
        @ViewBuilder headerLeft: () -> HeaderLeft,
        @ViewBuilder headerRight: () -> HeaderRight,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.headerLeft = headerLeft()
        self.headerRight = headerRight()
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                headerLeft
                Spacer()
                headerRight
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(height: 48)

            Divider()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
        }
    }
}

extension ViewLayout where Footer == EmptyView {
    init(
        @ViewBuilder headerLeft: () -> HeaderLeft,
        @ViewBuilder headerRight: () -> HeaderRight,
        @ViewBuilder content: () -> Content
    ) {
        self.headerLeft = headerLeft()
        self.headerRight = headerRight()
        self.content = content()
        self.footer = EmptyView()
    }
}

extension ViewLayout where HeaderRight == EmptyView, Footer == EmptyView {
    init(
        @ViewBuilder headerLeft: () -> HeaderLeft,
        @ViewBuilder content: () -> Content
    ) {
        self.headerLeft = headerLeft()
        self.headerRight = EmptyView()
        self.content = content()
        self.footer = EmptyView()
    }
}

struct HeaderTitle: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
        }
    }
}
