//
//  Intents.swift
//  Озвучка слова. Лежит в общем коде: AudioPlaybackIntent система выполняет в процессе приложения.
//  Остальные кнопки виджета — в WordWidgetExtension/WidgetIntents.swift.
//

import AppIntents
import WidgetKit

nonisolated struct SpeakWordIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Произнести слово"

    @Parameter(title: "Слово")
    var word: String

    init() {}
    init(word: String) { self.word = word }

    @MainActor
    func perform() async throws -> some IntentResult {
        await Pronouncer.shared.speak(word)
        // Обновить подпись «откуда звук» внизу виджета.
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
