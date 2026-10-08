//
//  WordWidgetExtension.swift
//  Виджет: новое английское слово каждые 10 минут.
//

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Timeline

struct WordEntry: TimelineEntry {
    let date: Date
    let word: Word
    var level: Level = WordStore.level
    var progress: Double = WordStore.progress(for: WordStore.level)
    var lastAudio: AudioOrigin.Last? = AudioOrigin.last
    /// EN — показываем английское слово, скрыт перевод; RU — наоборот.
    var direction: Direction = WordStore.direction
    /// Ответ (перевод) открыт нажатием.
    var revealed = false
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> WordEntry {
        WordEntry(date: .now, word: WordBank.words(for: .a1)[0])
    }

    func getSnapshot(in context: Context, completion: @escaping (WordEntry) -> Void) {
        let word = WordStore.word(at: .now)
        completion(WordEntry(date: .now, word: word, revealed: WordStore.isRevealed(word.text)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WordEntry>) -> Void) {
        // Записи на 2 часа вперёд — по одной на каждую смену слова (раз в 10 минут).
        let now = Date.now
        let start = WordStore.slotStart(for: now)
        let level = WordStore.level
        let progress = WordStore.progress(for: level)
        let rotation = WordStore.Rotation.current()
        let lastAudio = AudioOrigin.last
        let direction = WordStore.direction
        let revealedWord = WordStore.revealedWord
        let entries = (0..<12).map { i -> WordEntry in
            let date = i == 0 ? now : start.addingTimeInterval(Double(i) * WordStore.interval)
            let word = rotation.word(at: date)
            return WordEntry(date: date, word: word, level: level, progress: progress, lastAudio: lastAudio,
                             direction: direction, revealed: word.text == revealedWord)
        }
        completion(Timeline(entries: entries, policy: .atEnd))

        // Звук для текущего и двух следующих слов — заранее в общий кэш.
        let upcoming = entries.prefix(3).map(\.word.text)
        let accent = WordStore.accent
        Task { await AudioSource.prefetch(upcoming, accent: accent) }
    }
}

// MARK: - Views

/// Слово-задание и кнопки в одной строке. Если строка не влезает (маленький виджет) — кнопки под словом.
struct TitleRow: View {
    let entry: WordEntry
    var titleSize: CGFloat = 15
    var compact = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                title
                Spacer(minLength: 0)
                ActionBar(entry: entry, compact: compact)
                    .fixedSize()
            }
            VStack(alignment: .leading, spacing: 4) {
                title
                // Кнопки прижаты вправо, чтобы 🔊 ниже оказалась ровно под «следующим словом».
                HStack {
                    Spacer(minLength: 0)
                    ActionBar(entry: entry, compact: compact)
                }
            }
        }
    }

    private var title: some View {
        // Нажатие на слово открывает приложение (остальная площадь — кнопки и открытие перевода).
        Link(destination: WordStore.openAppURL) { titleText }
    }

    private var titleText: some View {
        Text(entry.direction == .en ? entry.word.text : entry.word.translation)
            .font(.system(size: titleSize, weight: .bold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .widgetAccentable()
            // Пока таймлайн перезагружается после нажатия, система приглушает это место.
            .invalidatableContent()
    }
}

/// Скрытый ответ: размыт, по нажатию открывается (и снова скрывается).
struct Answer<Content: View>: View {
    let entry: WordEntry
    @ViewBuilder let content: Content

    var body: some View {
        Button(intent: RevealIntent(word: entry.word.text)) {
            content
                .blur(radius: entry.revealed ? 0 : 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .invalidatableContent()
        .help(entry.revealed ? "Скрыть" : "Показать")
    }
}

/// Транскрипция, часть речи и ответ под словом-заданием.
struct WordDetails: View {
    let entry: WordEntry
    var showsPartOfSpeech = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch entry.direction {
            case .en:
                pronunciation
                Answer(entry: entry) {
                    Text(entry.word.translation)
                        .font(.footnote)
                        .lineLimit(2)
                }
            case .ru:
                Answer(entry: entry) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.word.text)
                            .font(.footnote.weight(.semibold))
                            .lineLimit(1)
                        pronunciation
                    }
                }
            }
        }
    }

    private var pronunciation: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(entry.word.ipa)
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(.secondary)
            if showsPartOfSpeech {
                Text(entry.word.partOfSpeech)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .lineLimit(1)
    }
}

/// Кнопки по порядку: EN/RU, уровень, «запомнил» с процентом, следующее. 🔊 — под ними, см. SpeakCluster.
struct ActionBar: View {
    let entry: WordEntry
    /// Компактный вариант для маленького виджета: маленькие круги, процент под галочкой.
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            Button(intent: ToggleDirectionIntent()) {
                Text(entry.direction.title)
            }
            .buttonBorderShape(.capsule)
            .invalidatableContent()
            .help("Английское слово / русское слово")

            Button(intent: NextLevelIntent()) {
                Text(entry.level.title)
            }
            .buttonBorderShape(.capsule)
            .invalidatableContent()
            .help("Сменить уровень")

            Button(intent: LearnWordIntent(word: entry.word.text)) {
                if compact {
                    VStack(spacing: -1) {
                        Image(systemName: "checkmark")
                        percent.font(.system(size: 7, weight: .semibold))
                    }
                } else {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark")
                        percent
                    }
                }
            }
            .buttonBorderShape(.capsule)
            .invalidatableContent()
            .help("Запомнил")

            Button(intent: NextWordIntent()) {
                ButtonIcon(systemName: "arrow.forward")
            }
            .help("Следующее слово")
        }
        .modifier(ActionBarStyle(compact: compact))
    }

    private var percent: some View {
        Text(entry.progress, format: .percent.precision(.fractionLength(0)))
            .lineLimit(1)
            .fixedSize()
    }
}

/// Обычные кнопки — системные .bordered; в маленьком виджете — круги фиксированного размера, чтобы всё влезло в строку.
struct ActionBarStyle: ViewModifier {
    let compact: Bool

    func body(content: Content) -> some View {
        if compact {
            content
                .buttonStyle(CompactCircleButtonStyle())
                .font(.system(size: 10, weight: .semibold))
        } else {
            content
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .tint(.accentColor)
                .font(.footnote.weight(.semibold))
        }
    }
}

struct CompactCircleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.accentColor)
            .frame(width: 22, height: 22)
            .background(Color.accentColor.opacity(configuration.isPressed ? 0.3 : 0.15), in: Circle())
    }
}

/// Кнопка 🔊 у правого края (под «следующим словом»), слева от неё — откуда звук: «Oxford · UK».
struct SpeakCluster: View {
    let entry: WordEntry
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            // Подпись только для текущего слова: появляется после нажатия.
            if let last = entry.lastAudio, last.word == entry.word.text {
                Text(last.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Button(intent: SpeakWordIntent(word: entry.word.text)) {
                ButtonIcon(systemName: "speaker.wave.2.fill")
            }
            .help("Произнести")
            .modifier(ActionBarStyle(compact: compact))
        }
    }
}

/// Иконка в квадрате фиксированного размера: круглые кнопки «следующее» и 🔊 получаются одинаковыми
/// и стоят друг под другом по центру, независимо от ширины самого значка.
struct ButtonIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .frame(width: 18, height: 18)
    }
}

struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

/// Идиома: задание (фраза или её значение) и, если ответ открыт, через тире — ответ.
struct IdiomRow: View {
    let idiom: Idiom
    let entry: WordEntry

    var body: some View {
        let (prompt, answer) = entry.direction == .en ? (idiom.phrase, idiom.meaning) : (idiom.meaning, idiom.phrase)
        Group {
            if entry.revealed {
                Text("\(Text(prompt).fontWeight(.semibold)) — \(Text(answer).foregroundStyle(.secondary))")
            } else {
                Text(prompt).fontWeight(.semibold)
            }
        }
        .font(.caption)
        .lineLimit(2)
    }
}

/// Пример: задание (английское или русское предложение) и, если ответ открыт, через тире — перевод.
struct ExampleRow: View {
    let example: Example
    let entry: WordEntry
    var font: Font = .footnote
    var translationFont: Font = .caption

    var body: some View {
        let english = Text(Highlight.sentence(example.text, word: entry.word.text))
        let russian = Text(example.translation)
        let (prompt, answer) = entry.direction == .en ? (english, russian) : (russian, english)
        Group {
            if entry.revealed {
                Text("\(prompt) \(Text("— ").font(translationFont).foregroundStyle(.secondary))\(answer.font(translationFont).foregroundStyle(.secondary))")
            } else {
                prompt
            }
        }
        .font(font)
        .lineLimit(4)
        .minimumScaleFactor(0.85)
    }
}

/// Примеры и идиомы: показываем столько, сколько влезает. Переводы видны, когда открыт ответ (нажатием на размытое).
struct ExamplesAndIdioms: View {
    let entry: WordEntry
    var exampleFont: Font = .footnote
    var translationFont: Font = .caption
    var spacing: CGFloat = 4
    /// Кнопка 🔊 в строке заголовка «Примеры» (в среднем виджете).
    var showsSpeak = false

    private var word: Word { entry.word }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionTitle(text: "Примеры")
                Spacer(minLength: 4)
                if showsSpeak { SpeakCluster(entry: entry, compact: true) }
            }
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .vertical) {
                examples(3)
                examples(2)
                examples(1)
            }
            if !word.idioms.isEmpty {
                ViewThatFits(in: .vertical) {
                    idioms(3)
                    idioms(2)
                    idioms(1)
                    Color.clear.frame(height: 0)
                }
                .layoutPriority(-1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func examples(_ count: Int) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(word.examples.prefix(count), id: \.self) {
                ExampleRow(example: $0, entry: entry, font: exampleFont, translationFont: translationFont)
            }
        }
    }

    private func idioms(_ count: Int) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            SectionTitle(text: "Идиомы").padding(.top, 2)
            ForEach(word.idioms.prefix(count), id: \.phrase) { IdiomRow(idiom: $0, entry: entry) }
        }
    }
}

struct SmallWordView: View {
    let entry: WordEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TitleRow(entry: entry, titleSize: 13, compact: true)
            HStack {
                Spacer(minLength: 0)
                SpeakCluster(entry: entry, compact: true)
            }
            WordDetails(entry: entry)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct MediumWordView: View {
    let entry: WordEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TitleRow(entry: entry, titleSize: 14, compact: true)
            HStack(alignment: .top, spacing: 14) {
                WordDetails(entry: entry)
                    .frame(width: 110, alignment: .leading)
                ExamplesAndIdioms(entry: entry, showsSpeak: true)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

struct LargeWordView: View {
    let entry: WordEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TitleRow(entry: entry, titleSize: 17)
            HStack(alignment: .top) {
                WordDetails(entry: entry, showsPartOfSpeech: true)
                Spacer(minLength: 4)
                SpeakCluster(entry: entry)
            }
            Divider()
            ExamplesAndIdioms(entry: entry, exampleFont: .subheadline, translationFont: .footnote, spacing: 6)
                .frame(maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct WordWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WordEntry

    var body: some View {
        switch family {
        case .systemSmall: SmallWordView(entry: entry)
        case .systemMedium: MediumWordView(entry: entry)
        default: LargeWordView(entry: entry)
        }
    }
}

// MARK: - Widget

struct EWordWidget: Widget {
    let kind = "EWordWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            WordWidgetEntryView(entry: entry)
                .widgetURL(WordStore.openAppURL)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.18), Color.accentColor.opacity(0.04)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                }
        }
        .configurationDisplayName("eWord")
        .description("Новое английское слово каждые 10 минут: уровни A1–C2, озвучка, примеры, идиомы и прогресс.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

#Preview(as: .systemMedium) {
    EWordWidget()
} timeline: {
    WordEntry(date: .now, word: WordBank.words(for: .a1)[0])
    WordEntry(date: .now, word: WordBank.words(for: .a1)[1])
}

#Preview(as: .systemLarge) {
    EWordWidget()
} timeline: {
    WordEntry(date: .now, word: WordBank.words(for: .a1)[2])
}
