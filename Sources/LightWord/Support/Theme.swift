import SwiftUI

enum Theme {
    static let accent = Color(red: 0.34, green: 0.38, blue: 0.94)
    static let accentSoft = Color(red: 0.34, green: 0.38, blue: 0.94).opacity(0.12)
    static let background = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let cellEmpty = Color(uiColor: .systemGray5)
    static let good = Color(red: 0.13, green: 0.66, blue: 0.45)
    static let bad = Color(red: 0.86, green: 0.28, blue: 0.32)
}

struct CardBackground: ViewModifier {
    var cornerRadius: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .background(Theme.card, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension View {
    func card(cornerRadius: CGFloat = 18) -> some View {
        modifier(CardBackground(cornerRadius: cornerRadius))
    }
}
