//
//  Theme.swift
//  NutriVision
//

import SwiftUI

extension Color {
    /// Creates a `Color` from a 6-digit RGB hex string (e.g. "1FA37A").
    init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }

    static let macroProtein = Color(hex: "E8556F")
    static let macroCarbs = Color(hex: "F2A93B")
    static let macroFat = Color(hex: "3B82D9")
    static let brandPrimary = Color(hex: "1FA37A")
    static let cardBackground = Color(.secondarySystemGroupedBackground)
}

enum Theme {
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum Radius {
        static let card: CGFloat = 20
        static let sheet: CGFloat = 28
        static let control: CGFloat = 14
    }
}
