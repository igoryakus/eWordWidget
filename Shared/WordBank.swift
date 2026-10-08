//
//  WordBank.swift
//  Базы слов по уровням A1–C2 лежат в Words/*.json (A1–C1 — по Oxford 5000).
//  Слово встречается только на одном уровне: каждый уровень дополняет предыдущие.
//  Уровень загружается из JSON при первом обращении и кэшируется.
//

import Foundation

nonisolated enum WordBank {
    static func words(for level: Level) -> [Word] {
        switch level {
        case .a1: a1
        case .a2: a2
        case .b1: b1
        case .b2: b2
        case .c1: c1
        case .c2: c2
        }
    }

    static var all: [Word] { Level.allCases.flatMap { words(for: $0) } }

    private static let a1 = load(.a1)
    private static let a2 = load(.a2)
    private static let b1 = load(.b1)
    private static let b2 = load(.b2)
    private static let c1 = load(.c1)
    private static let c2 = load(.c2)

    private static func load(_ level: Level) -> [Word] {
        guard let url = Bundle.main.url(forResource: level.rawValue, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let words = try? JSONDecoder().decode([Word].self, from: data)
        else { return fallback }
        return words.isEmpty ? fallback : words
    }

    /// На случай, если файл базы не найден в бандле.
    private static let fallback = [
        Word("word", "/wɜːd/", "noun", "слово",
             [("What does this word mean?", "Что значит это слово?")],
             [("in other words", "другими словами")]),
    ]
}
