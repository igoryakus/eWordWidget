//
//  Word.swift
//  Общий код для приложения и виджета.
//

import Foundation

nonisolated struct Idiom: Hashable, Sendable {
    let phrase: String
    let meaning: String
}

nonisolated struct Example: Hashable, Sendable {
    let text: String
    let translation: String
}

nonisolated struct Word: Identifiable, Hashable, Sendable, Decodable {
    var id: String { text }
    let text: String
    let ipa: String
    let partOfSpeech: String
    let translation: String
    let examples: [Example]
    let idioms: [Idiom]

    init(_ text: String, _ ipa: String, _ partOfSpeech: String, _ translation: String,
         _ examples: [(String, String)], _ idioms: [(String, String)]) {
        self.text = text
        self.ipa = ipa
        self.partOfSpeech = partOfSpeech
        self.translation = translation
        self.examples = examples.map { Example(text: $0.0, translation: $0.1) }
        self.idioms = idioms.map { Idiom(phrase: $0.0, meaning: $0.1) }
    }

    // Формат JSON-баз (Words/*.json): примеры и идиомы — пары [англ., рус.].
    private enum CodingKeys: String, CodingKey {
        case text = "w", ipa, partOfSpeech = "pos", translation = "tr", examples = "ex", idioms = "id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decode(String.self, forKey: .text)
        ipa = try c.decode(String.self, forKey: .ipa)
        partOfSpeech = try c.decode(String.self, forKey: .partOfSpeech)
        translation = try c.decode(String.self, forKey: .translation)
        examples = try c.decode([[String]].self, forKey: .examples).compactMap {
            $0.count == 2 ? Example(text: $0[0], translation: $0[1]) : nil
        }
        idioms = try c.decode([[String]].self, forKey: .idioms).compactMap {
            $0.count == 2 ? Idiom(phrase: $0[0], meaning: $0[1]) : nil
        }
    }
}

/// Уровень владения языком (CEFR).
nonisolated enum Level: String, CaseIterable, Identifiable, Sendable {
    case a1, a2, b1, b2, c1, c2
    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
    /// Следующий уровень по кругу (C2 → A1).
    var next: Level {
        let all = Level.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

/// Акцент для озвучки.
nonisolated enum Accent: String, CaseIterable, Identifiable, Codable, Sendable {
    case uk, us
    var id: String { rawValue }
    var title: String { self == .uk ? "🇬🇧 UK" : "🇺🇸 US" }
    var voiceLanguage: String { self == .uk ? "en-GB" : "en-US" }
}

/// Что показываем как задание: английское слово (перевод скрыт) или русское (английское скрыто).
nonisolated enum Direction: String, CaseIterable, Identifiable, Sendable {
    case en, ru
    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
    var toggled: Direction { self == .en ? .ru : .en }
}

/// Хранилище состояния, общее для приложения и виджета (App Group).
nonisolated enum WordStore {
    static let appGroup = "group.com.yakus.ewordwidget"
    /// Ссылка из виджета, по которой открывается окно приложения.
    static let openAppURL = URL(string: "eword://open")!
    /// Как часто меняется слово (секунды).
    static let interval: TimeInterval = 10 * 60

    static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    /// Состояние (уровень, сдвиг, запомненные слова) хранится в файле в контейнере App Group,
    /// а не в UserDefaults: кнопки виджета могут выполняться в процессе приложения,
    /// и расширение тогда видело бы закэшированное старое значение до следующего обновления.
    private struct State: Codable {
        var offset = 0
        var level = Level.a1.rawValue
        var learned: [String] = []
        var direction = Direction.en.rawValue
        /// Слово, у которого открыт (не размыт) ответ. Для следующего слова ответ снова скрыт.
        var revealed: String?

        init(offset: Int = 0, level: String = Level.a1.rawValue, learned: [String] = []) {
            self.offset = offset
            self.level = level
            self.learned = learned
        }

        // Ключи читаются по отдельности, чтобы старый state.json без новых полей не терял прогресс.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            offset = try c.decodeIfPresent(Int.self, forKey: .offset) ?? 0
            level = try c.decodeIfPresent(String.self, forKey: .level) ?? Level.a1.rawValue
            learned = try c.decodeIfPresent([String].self, forKey: .learned) ?? []
            direction = try c.decodeIfPresent(String.self, forKey: .direction) ?? Direction.en.rawValue
            revealed = try c.decodeIfPresent(String.self, forKey: .revealed)
        }
    }

    private static var stateURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("state.json")
    }

    private static func loadState() -> State {
        if let url = stateURL, let data = try? Data(contentsOf: url),
           let state = try? JSONDecoder().decode(State.self, from: data) {
            return state
        }
        // Первый запуск после перехода на файл — забираем то, что было в UserDefaults.
        return State(offset: defaults.integer(forKey: "offset"),
                     level: defaults.string(forKey: "level") ?? Level.a1.rawValue,
                     learned: defaults.stringArray(forKey: "learned") ?? [])
    }

    private static func updateState(_ change: (inout State) -> Void) {
        var state = loadState()
        change(&state)
        guard let url = stateURL, let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Сдвиг, который увеличивает кнопка «Следующее слово».
    static var offset: Int {
        get { loadState().offset }
        set { updateState { $0.offset = newValue } }
    }

    static var accent: Accent {
        get { Accent(rawValue: defaults.string(forKey: "accent") ?? "") ?? .uk }
        set { defaults.set(newValue.rawValue, forKey: "accent") }
    }

    static var level: Level {
        get { Level(rawValue: loadState().level) ?? .a1 }
        set { updateState { $0.level = newValue.rawValue } }
    }

    /// Слова, отмеченные как запомненные.
    static var learned: Set<String> {
        get { Set(loadState().learned) }
        set { updateState { $0.learned = newValue.sorted() } }
    }

    static var direction: Direction {
        get { Direction(rawValue: loadState().direction) ?? .en }
        set { updateState { $0.direction = newValue.rawValue; $0.revealed = nil } }
    }

    /// Открыт ли ответ (перевод) для слова.
    static func isRevealed(_ word: String) -> Bool { revealedWord == word }

    static var revealedWord: String? { loadState().revealed }

    static func reveal(_ word: String?) { updateState { $0.revealed = word } }

    static func advance() { offset += 1 }

    static func markLearned(_ word: String) { learned.insert(word) }

    static func resetProgress(for level: Level) {
        learned.subtract(WordBank.words(for: level).map(\.text))
    }

    /// Доля запомненных слов уровня, 0…1.
    static func progress(for level: Level) -> Double {
        let words = WordBank.words(for: level)
        guard !words.isEmpty else { return 0 }
        let learned = learned
        return Double(words.filter { learned.contains($0.text) }.count) / Double(words.count)
    }

    /// Начало текущего 10-минутного интервала.
    static func slotStart(for date: Date) -> Date {
        let t = (date.timeIntervalSince1970 / interval).rounded(.down) * interval
        return Date(timeIntervalSince1970: t)
    }

    static func nextChange(after date: Date) -> Date {
        slotStart(for: date).addingTimeInterval(interval)
    }

    /// Слово, которое показывается в момент `date`: из выбранного уровня,
    /// без запомненных. Когда запомнено всё — показываем весь уровень по кругу.
    static func word(at date: Date) -> Word {
        Rotation.current().word(at: date)
    }

    /// Снимок очереди слов: считается один раз и используется для всех записей таймлайна.
    struct Rotation {
        let list: [Word]
        let offset: Int

        static func current() -> Rotation {
            let state = loadState()
            let level = Level(rawValue: state.level) ?? .a1
            let words = WordBank.words(for: level)
            let learned = Set(state.learned)
            let ordered = order(for: level).map { words[$0] }
            let pool = ordered.filter { !learned.contains($0.text) }
            return Rotation(list: pool.isEmpty ? ordered : pool, offset: state.offset)
        }

        func word(at date: Date) -> Word {
            let slot = Int(date.timeIntervalSince1970 / WordStore.interval)
            let n = list.count
            return list[((slot + offset) % n + n) % n]
        }
    }

    /// Фиксированный «перемешанный» порядок слов уровня, одинаковый в приложении и виджете.
    static func order(for level: Level) -> [Int] {
        var rng = SeededGenerator(seed: 20_261_002 &+ UInt64(Level.allCases.firstIndex(of: level)!))
        return Array(WordBank.words(for: level).indices).shuffled(using: &rng)
    }
}

nonisolated struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
