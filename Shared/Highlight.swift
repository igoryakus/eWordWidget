//
//  Highlight.swift
//  Подсветка изучаемого слова в примерах.
//

import SwiftUI

nonisolated enum Highlight {
    static func sentence(_ sentence: String, word: String) -> AttributedString {
        var result = AttributedString(sentence)
        let lower = word.lowercased()
        let stem = String(lower.prefix(max(3, lower.count - 1)))
        guard !stem.isEmpty else { return result }

        var searchStart = result.startIndex
        while searchStart < result.endIndex,
              let range = result[searchStart..<result.endIndex].range(of: stem, options: .caseInsensitive) {
            // Начало должно быть границей слова.
            let atWordStart: Bool = {
                guard range.lowerBound > result.startIndex else { return true }
                let prev = result.characters[result.characters.index(before: range.lowerBound)]
                return !prev.isLetter
            }()
            // Дотягиваем выделение до конца слова (breaks, breaking…).
            var end = range.upperBound
            while end < result.endIndex, result.characters[end].isLetter {
                end = result.characters.index(after: end)
            }
            if atWordStart {
                result[range.lowerBound..<end].inlinePresentationIntent = .stronglyEmphasized
                result[range.lowerBound..<end].foregroundColor = Color.accentColor
            }
            searchStart = end
        }
        return result
    }
}
