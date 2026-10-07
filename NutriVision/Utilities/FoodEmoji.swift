//
//  FoodEmoji.swift
//  NutriVision
//

import Foundation

enum FoodEmoji {
    private static let table: [(keys: [String], emoji: String)] = [
        (["pizza"], "🍕"), (["burger", "hamburger", "cheeseburger"], "🍔"), (["fries"], "🍟"),
        (["hot dog", "hotdog"], "🌭"), (["sandwich", "panini"], "🥪"), (["taco"], "🌮"), (["burrito"], "🌯"),
        (["sushi", "sashimi"], "🍣"), (["ramen", "noodle", "soup", "pho"], "🍜"), (["pasta", "spaghetti", "lasagna", "macaroni"], "🍝"),
        (["rice", "risotto"], "🍚"), (["curry"], "🍛"), (["salad"], "🥗"), (["egg", "omelet"], "🍳"),
        (["bread", "toast", "bagel"], "🍞"), (["croissant"], "🥐"), (["pancake", "waffle"], "🥞"),
        (["cake", "cupcake"], "🍰"), (["donut", "doughnut"], "🍩"), (["cookie", "biscuit"], "🍪"),
        (["ice cream", "gelato"], "🍨"), (["chocolate"], "🍫"), (["apple"], "🍎"), (["banana"], "🍌"),
        (["orange"], "🍊"), (["strawberr"], "🍓"), (["grape"], "🍇"), (["watermelon"], "🍉"),
        (["avocado", "guacamole"], "🥑"), (["steak", "meat", "beef", "pork", "lamb", "bacon"], "🥩"),
        (["chicken", "wings", "nugget"], "🍗"), (["fish", "salmon", "tuna"], "🐟"),
        (["shrimp", "seafood", "prawn", "crab", "lobster"], "🦐"), (["cheese"], "🧀"),
        (["coffee", "latte", "espresso"], "☕️"), (["tea"], "🍵"), (["beer"], "🍺"), (["wine"], "🍷"),
        (["juice", "smoothie", "milk", "drink", "soda"], "🥤"), (["potato"], "🥔"), (["carrot"], "🥕"),
        (["broccoli"], "🥦"), (["corn"], "🌽"), (["dumpling"], "🥟"),
    ]

    static func emoji(for name: String) -> String {
        let lower = name.lowercased()
        return table.first { $0.keys.contains { lower.contains($0) } }?.emoji ?? "🍽️"
    }
}
