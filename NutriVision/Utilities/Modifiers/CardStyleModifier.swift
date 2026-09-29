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
            .background(Color.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}

extension View {
    func cardStyle(padding: CGFloat = Theme.Spacing.md) -> some View {
        modifier(CardStyleModifier(padding: padding))
    }
}
