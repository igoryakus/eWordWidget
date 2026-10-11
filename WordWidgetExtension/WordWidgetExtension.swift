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
    /// Тема карточки (выбирается в окне приложения).
    var theme: WidgetTheme = WordStore.theme
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
        let theme = WordStore.theme
        let entries = (0..<12).map { i -> WordEntry in
            let date = i == 0 ? now : start.addingTimeInterval(Double(i) * WordStore.interval)
            let word = rotation.word(at: date)
            return WordEntry(date: date, word: word, level: level, progress: progress, lastAudio: lastAudio,
                             direction: direction, revealed: word.text == revealedWord, theme: theme)
        }
        completion(Timeline(entries: entries, policy: .atEnd))

        // Звук для текущего и двух следующих слов — заранее в общий кэш.
        let upcoming = entries.prefix(3).map(\.word.text)
        let accent = WordStore.accent
        Task { await AudioSource.prefetch(upcoming, accent: accent) }
    }
}

// MARK: - Views

/// Слово-задание и кнопки в одной строке.
/// В маленьком виджете кнопки — круги, и если строка не влезает, они уходят под слово.
struct TitleRow: View {
    let entry: WordEntry
    var titleSize: CGFloat = 22
    var compact = false

    var body: some View {
        if compact {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    title
                    Spacer(minLength: 0)
                    ActionBar(entry: entry, compact: true).fixedSize()
                }
                VStack(alignment: .leading, spacing: 4) {
                    title
                    // Кнопки прижаты вправо, чтобы 🔊 ниже оказалась ровно под «следующим словом».
                    HStack {
                        Spacer(minLength: 0)
                        ActionBar(entry: entry, compact: true)
                    }
                }
            }
        } else {
            // Длинное слово уменьшается, кнопки остаются в строке.
            HStack(spacing: 8) {
                title
                Spacer(minLength: 0)
                ActionBar(entry: entry).fixedSize()
            }
        }
    }

    private var title: some View {
        // Нажатие на слово открывает приложение (остальная площадь — кнопки и открытие перевода).
        Link(destination: WordStore.openAppURL) { titleText }
    }

    private var titleText: some View {
        Text(entry.direction == .en ? entry.word.text : entry.word.translation)
            .font(.system(size: titleSize, weight: .bold))
            .foregroundStyle(Color.word)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
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

/// Транскрипция /ipa/ и часть речи курсивом.
struct Pronunciation: View {
    let word: Word
    var ipaSize: CGFloat = 15
    var showsPartOfSpeech = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(word.ipa)
                .font(.system(size: ipaSize, design: .serif))
                .foregroundStyle(.primary.opacity(0.85))
            if showsPartOfSpeech {
                Text(word.partOfSpeech)
                    .font(.system(size: ipaSize - 3).italic())
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
    }
}

/// Транскрипция, часть речи и ответ под словом-заданием.
/// inline — транскрипция и ответ в одной строке (средний виджет, где мало высоты).
struct WordDetails: View {
    let entry: WordEntry
    var ipaSize: CGFloat = 15
    var answerFont: Font = .body
    var showsPartOfSpeech = true
    var inline = false

    var body: some View {
        if inline {
            HStack(alignment: .firstTextBaseline, spacing: 8) { content }
        } else {
            VStack(alignment: .leading, spacing: 3) { content }
        }
    }

    @ViewBuilder private var content: some View {
        switch entry.direction {
        case .en:
            Pronunciation(word: entry.word, ipaSize: ipaSize, showsPartOfSpeech: showsPartOfSpeech)
                .fixedSize()
            Answer(entry: entry) {
                Text(entry.word.translation)
                    .font(answerFont)
                    .lineLimit(inline ? 1 : 2)
            }
        case .ru:
            Answer(entry: entry) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(entry.word.text)
                        .font(answerFont.weight(.semibold))
                        .foregroundStyle(Color.word)
                    Pronunciation(word: entry.word, ipaSize: ipaSize, showsPartOfSpeech: showsPartOfSpeech)
                }
                .lineLimit(1)
            }
        }
    }
}

/// Кнопки по порядку: EN/RU, уровень, «запомнил» с процентом, следующее. 🔊 — отдельно, см. SpeakCluster.
struct ActionBar: View {
    let entry: WordEntry
    /// Компактный вариант для маленького виджета: круги, процент под галочкой.
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 4 : 5) {
            Button(intent: ToggleDirectionIntent()) {
                Text(entry.direction.title)
            }
            .invalidatableContent()
            .help("Английское слово / русское слово")

            Button(intent: NextLevelIntent()) {
                Text(entry.level.title)
            }
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
            .invalidatableContent()
            .help("Запомнил")

            Button(intent: NextWordIntent()) {
                Image(systemName: "arrow.forward").frame(width: 14)
            }
            .help("Следующее слово")
        }
        .buttonStyle(ChipButtonStyle(compact: compact))
    }

    private var percent: some View {
        // «12%» без пробела, как в макете (русская локаль ставит «12 %»).
        Text("\(Int((entry.progress * 100).rounded()))%")
            .lineLimit(1)
            .fixedSize()
    }
}

/// Кнопка-«чип» как в макете: серая капсула со светлым текстом. compact — круг 22 pt для маленького виджета.
struct ChipButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 10 : 11, weight: .semibold))
            .foregroundStyle(.primary.opacity(0.85))
            .padding(.horizontal, compact ? 0 : 8)
            .frame(minWidth: compact ? 22 : 28, minHeight: compact ? 22 : 24)
            .frame(width: compact ? 22 : nil)
            .background(.primary.opacity(configuration.isPressed ? 0.18 : 0.09), in: Capsule())
    }
}

/// Кнопка 🔊, слева от неё — откуда звук: «Oxford · UK».
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
                Image(systemName: "speaker.wave.2.fill").frame(width: 14)
            }
            .help("Произнести")
            .buttonStyle(ChipButtonStyle(compact: compact))
        }
    }
}

struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }
}

/// Строка «задание — ответ»: ответ в той же строке через тире, размыт, пока не открыт; нажатие открывает/скрывает.
/// Размыть часть Text нельзя, поэтому, пока ответ скрыт, рисуем две копии строки с одинаковой разметкой:
/// снизу — тире и ответ (размытые), сверху — только задание; остальное в каждой копии прозрачное.
struct PromptAnswerRow: View {
    let entry: WordEntry
    /// Задание; аргумент — видим ли текст (false — прозрачный, только для разметки).
    let prompt: (Bool) -> Text
    let answer: (Bool) -> Text
    var font: Font = .footnote
    var answerFont: Font = .caption
    var lineLimit = 4

    var body: some View {
        Button(intent: RevealIntent(word: entry.word.text)) {
            ZStack(alignment: .topLeading) {
                if entry.revealed {
                    line(prompt: true, answer: true)
                } else {
                    line(prompt: false, answer: true).blur(radius: 4)
                    line(prompt: true, answer: false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .invalidatableContent()
    }

    private func line(prompt showsPrompt: Bool, answer showsAnswer: Bool) -> some View {
        let dash = Text(" — ").font(answerFont).foregroundStyle(showsAnswer ? Color.secondary : Color.clear)
        let answer = answer(showsAnswer).font(answerFont)
        return Text("\(prompt(showsPrompt))\(dash)\(answer)")
            .font(font)
            .lineLimit(lineLimit)
            .minimumScaleFactor(0.85)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Пример: задание (английское или русское предложение) — перевод.
struct ExampleRow: View {
    let example: Example
    let entry: WordEntry
    var font: Font = .footnote
    var translationFont: Font = .caption

    var body: some View {
        PromptAnswerRow(entry: entry, prompt: { side($0, prompt: true) }, answer: { side($0, prompt: false) },
                        font: font, answerFont: translationFont)
    }

    private func side(_ visible: Bool, prompt: Bool) -> Text {
        let isEnglish = (entry.direction == .en) == prompt
        if isEnglish {
            // Подсветка слова — цветом в атрибутах, поэтому прозрачную копию строим без цвета.
            let text = Text(Highlight.sentence(example.text, word: entry.word.text, color: visible ? .word : nil))
            return visible ? text.foregroundStyle(prompt ? Color.primary : Color.secondary) : text.foregroundStyle(.clear)
        }
        return Text(example.translation).foregroundStyle(visible ? (prompt ? Color.primary : Color.secondary) : Color.clear)
    }
}

/// Идиома: фраза (цветом слова) — значение; в режиме RU наоборот.
struct IdiomRow: View {
    let idiom: Idiom
    let entry: WordEntry
    var font: Font = .footnote
    var translationFont: Font = .caption

    var body: some View {
        PromptAnswerRow(entry: entry, prompt: { side($0, prompt: true) }, answer: { side($0, prompt: false) },
                        font: font, answerFont: translationFont, lineLimit: 2)
    }

    private func side(_ visible: Bool, prompt: Bool) -> Text {
        let isPhrase = (entry.direction == .en) == prompt
        if isPhrase {
            return Text(idiom.phrase).fontWeight(.semibold).foregroundStyle(visible ? Color.word : .clear)
        }
        return Text(idiom.meaning).foregroundStyle(visible ? (prompt ? Color.primary : Color.secondary) : Color.clear)
    }
}

/// Примеры и идиомы: показываем столько, сколько влезает.
struct ExamplesAndIdioms: View {
    let entry: WordEntry
    var exampleFont: Font = .footnote
    var translationFont: Font = .caption
    var spacing: CGFloat = 4
    var maxExamples = 3

    private var word: Word { entry.word }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .vertical) {
                ForEach(Array((1...maxExamples).reversed()), id: \.self) { examples($0) }
                Color.clear.frame(height: 0)
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
            SectionTitle(text: "Примеры")
            ForEach(word.examples.prefix(count), id: \.self) {
                ExampleRow(example: $0, entry: entry, font: exampleFont, translationFont: translationFont)
            }
        }
    }

    private func idioms(_ count: Int) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            SectionTitle(text: "Идиомы")
            ForEach(word.idioms.prefix(count), id: \.phrase) {
                IdiomRow(idiom: $0, entry: entry, font: exampleFont, translationFont: translationFont)
            }
        }
    }
}

struct SmallWordView: View {
    let entry: WordEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TitleRow(entry: entry, titleSize: 17, compact: true)
            HStack {
                Spacer(minLength: 0)
                SpeakCluster(entry: entry, compact: true)
            }
            WordDetails(entry: entry, ipaSize: 13, answerFont: .footnote, showsPartOfSpeech: false)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct MediumWordView: View {
    let entry: WordEntry
    var body: some View {
        // 🔊 в строке транскрипции у правого края, под «следующим словом».
        VStack(alignment: .leading, spacing: 5) {
            TitleRow(entry: entry, titleSize: 22)
            HStack(alignment: .center, spacing: 6) {
                WordDetails(entry: entry, ipaSize: 13, answerFont: .subheadline, inline: true)
                Spacer(minLength: 0)
                SpeakCluster(entry: entry, compact: true)
            }
            ExamplesAndIdioms(entry: entry, spacing: 2, maxExamples: 2)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct LargeWordView: View {
    let entry: WordEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TitleRow(entry: entry, titleSize: 30)
            // 🔊 у правого края, под «следующим словом».
            HStack(alignment: .top) {
                WordDetails(entry: entry, ipaSize: 16, answerFont: .body)
                Spacer(minLength: 4)
                SpeakCluster(entry: entry)
            }
            ExamplesAndIdioms(entry: entry, exampleFont: .subheadline, translationFont: .subheadline, spacing: 5)
                .padding(.top, 6)
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

/// Фон карточки как в макете на сайте: тёмная (в светлой теме — светлая) заливка, лёгкий блик сверху и рамка с переходом от синего к фиолетовому.
struct CardBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Color.cardBackground
            LinearGradient(
                colors: [.white.opacity(0.08), .white.opacity(0.02), .black.opacity(scheme == .dark ? 0.12 : 0.03)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            ContainerRelativeShape()
                .strokeBorder(
                    LinearGradient(
                        colors: [Color(red: 0.24, green: 0.55, blue: 1), .primary.opacity(0.12),
                                 .primary.opacity(0.06), Color(red: 0.48, green: 0.36, blue: 1)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }
}

/// Тема из настроек: светлая или тёмная принудительно, «как в системе» — без изменений.
struct ThemeModifier: ViewModifier {
    let theme: WidgetTheme

    func body(content: Content) -> some View {
        switch theme {
        case .auto: content
        case .light: content.environment(\.colorScheme, .light)
        case .dark: content.environment(\.colorScheme, .dark)
        }
    }
}

// MARK: - Widget

struct EWordWidget: Widget {
    let kind = "EWordWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            WordWidgetEntryView(entry: entry)
                .modifier(ThemeModifier(theme: entry.theme))
                .widgetURL(WordStore.openAppURL)
                .containerBackground(for: .widget) { CardBackground().modifier(ThemeModifier(theme: entry.theme)) }
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
