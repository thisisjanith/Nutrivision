//
//  CardStyleModifier.swift
//  NutriVision
//

import SwiftUI

struct CardStyleModifier: ViewModifier {
    var padding: CGFloat = Theme.Spacing.md

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .stroke(.white.opacity(0.06), lineWidth: 1)
            }
    }
}

extension View {
    func cardStyle(padding: CGFloat = Theme.Spacing.md) -> some View {
        modifier(CardStyleModifier(padding: padding))
    }
}
