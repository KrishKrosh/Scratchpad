//
//  NameGenerator.swift
//  Scratchpad
//
//  Two-word playful auto-titles.
//

import Foundation

enum NameGenerator {
    private static let adjectives = [
        "Curious", "Dancing", "Lucky", "Sleepy", "Quirky", "Sunny",
        "Witty", "Bouncy", "Brave", "Fluffy", "Shiny", "Wandering",
        "Gentle", "Dreamy", "Noisy", "Spicy", "Zippy", "Plucky",
        "Mellow", "Nimble", "Cozy", "Rowdy", "Snappy", "Tidy",
        "Velvet", "Electric", "Midnight", "Peppy", "Wild", "Rusty"
    ]

    private static let nouns = [
        "Otter", "Sparrow", "Cactus", "Comet", "Lantern", "Pancake",
        "Thunder", "Raccoon", "Pebble", "Marble", "Tangerine", "Muffin",
        "Koala", "Penguin", "Jellyfish", "Tiger", "Waffle", "Harbor",
        "Bluejay", "Hedgehog", "Daffodil", "Biscuit", "Magpie", "Walrus",
        "Lighthouse", "Blizzard", "Puffin", "Barnacle", "Firefly", "Kite"
    ]

    static func next() -> String {
        let a = adjectives.randomElement() ?? "Lively"
        let n = nouns.randomElement() ?? "Notebook"
        return "\(a) \(n)"
    }
}
