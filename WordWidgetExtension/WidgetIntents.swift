//
//  WidgetIntents.swift
//  Кнопки виджета: следующее слово, «запомнил», смена уровня, EN/RU, открыть перевод.
//  Эти интенты есть только в расширении, поэтому система выполняет их прямо в процессе виджета,
//  без фонового запуска приложения, и сразу перезагружает таймлайн.
//

import AppIntents

nonisolated struct NextWordIntent: AppIntent {
    static let title: LocalizedStringResource = "Следующее слово"

    init() {}

    func perform() async throws -> some IntentResult {
        WordStore.advance()
        return .result()
    }
}

nonisolated struct LearnWordIntent: AppIntent {
    static let title: LocalizedStringResource = "Запомнил слово"

    @Parameter(title: "Слово")
    var word: String

    init() {}
    init(word: String) { self.word = word }

    func perform() async throws -> some IntentResult {
        WordStore.markLearned(word)
        return .result()
    }
}

nonisolated struct NextLevelIntent: AppIntent {
    static let title: LocalizedStringResource = "Сменить уровень"

    init() {}

    func perform() async throws -> some IntentResult {
        WordStore.level = WordStore.level.next
        return .result()
    }
}

nonisolated struct ToggleDirectionIntent: AppIntent {
    static let title: LocalizedStringResource = "Переключить EN/RU"

    init() {}

    func perform() async throws -> some IntentResult {
        WordStore.direction = WordStore.direction.toggled
        return .result()
    }
}

/// Нажатие на размытый ответ: открыть его (повторное нажатие снова скрывает).
nonisolated struct RevealIntent: AppIntent {
    static let title: LocalizedStringResource = "Показать перевод"

    @Parameter(title: "Слово")
    var word: String

    init() {}
    init(word: String) { self.word = word }

    func perform() async throws -> some IntentResult {
        WordStore.reveal(WordStore.isRevealed(word) ? nil : word)
        return .result()
    }
}
