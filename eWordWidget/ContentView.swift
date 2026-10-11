//
//  ContentView.swift
//  Приложение-контейнер: текущее слово, озвучка, уровень, прогресс и настройки акцента.
//

import SwiftUI
import WidgetKit

struct ContentView: View {
    @AppStorage("accent", store: WordStore.defaults) private var accent: Accent = .uk
    @State private var level: Level = WordStore.level
    @State private var direction: Direction = WordStore.direction
    @State private var theme: WidgetTheme = WordStore.theme
    @State private var refresh = 0
    @State private var isSpeaking = false
    @State private var confirmReset = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let word = WordStore.word(at: context.date)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header(word, date: context.date)
                    examples(word)
                    idioms(word)
                    progress
                    settings
                }
                .padding(28)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .id(refresh)
        // Та же тема, что у виджета: «как в системе» — nil.
        .preferredColorScheme(theme.colorScheme)
        // Голубой как в виджете вместо системного синего.
        .tint(.word)
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 560)
        #endif
    }

    // MARK: Sections

    /// Скрытый ответ: размыт, по нажатию открывается (и снова скрывается). Состояние общее с виджетом.
    private func answer(_ word: Word, @ViewBuilder _ content: () -> some View) -> some View {
        let revealed = WordStore.isRevealed(word.text)
        return content()
            .blur(radius: revealed ? 0 : 7)
            .contentShape(Rectangle())
            .onTapGesture {
                WordStore.reveal(revealed ? nil : word.text)
                reloadWidgets()
            }
            .help(revealed ? "Скрыть" : "Показать")
    }

    private func header(_ word: Word, date: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(word.partOfSpeech)
                .font(.caption)
                .foregroundStyle(.secondary)
            switch direction {
            case .en:
                Text(word.text)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.tint)
                Text(word.ipa)
                    .font(.system(.title3, design: .serif))
                    .foregroundStyle(.secondary)
                answer(word) {
                    Text(word.translation)
                        .font(.title3)
                }
            case .ru:
                Text(word.translation)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.tint)
                answer(word) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(word.text)
                            .font(.title2.weight(.semibold))
                        Text(word.ipa)
                            .font(.system(.title3, design: .serif))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 10) {
                Button {
                    Task {
                        isSpeaking = true
                        await Pronouncer.shared.speak(word.text)
                        isSpeaking = false
                    }
                } label: {
                    Label("Произнести", systemImage: isSpeaking ? "speaker.wave.3.fill" : "speaker.wave.2.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSpeaking)

                Button {
                    WordStore.advance()
                    reloadWidgets()
                } label: {
                    Label("Следующее", systemImage: "arrow.forward")
                }
                .buttonStyle(.bordered)

                Button {
                    WordStore.markLearned(word.text)
                    reloadWidgets()
                } label: {
                    Label("Запомнил", systemImage: "checkmark")
                }
                .buttonStyle(.bordered)

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "clock")
                    Text(WordStore.nextChange(after: date), style: .time)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("Время смены слова")
            }
            .padding(.top, 8)

            // Произношение: нажатие выбирает акцент и сразу озвучивает слово в нём.
            HStack(spacing: 8) {
                Text("Произношение").font(.subheadline).foregroundStyle(.secondary)
                ForEach(Accent.allCases) { option in
                    Button {
                        accent = option
                        Task {
                            isSpeaking = true
                            await Pronouncer.shared.speak(word.text, cycle: false)
                            isSpeaking = false
                        }
                    } label: {
                        Text(option.title)
                    }
                    .buttonStyle(.bordered)
                    .tint(accent == option ? Color.word : .secondary)
                    .fontWeight(accent == option ? .semibold : .regular)
                    .disabled(isSpeaking)
                }
            }

            if let lastAudio = AudioOrigin.last {
                Text("\(Image(systemName: "speaker.wave.2")) «\(lastAudio.word)» — \(lastAudio.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func examples(_ word: Word) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Примеры").font(.headline)
            ForEach(word.examples, id: \.self) { example in
                let english = Text(Highlight.sentence(example.text, word: word.text, color: .word))
                let russian = Text(example.translation)
                VStack(alignment: .leading, spacing: 2) {
                    (direction == .en ? english : russian)
                        .font(.title3)
                    answer(word) {
                        (direction == .en ? russian : english)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func idioms(_ word: Word) -> some View {
        if !word.idioms.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Идиомы").font(.headline)
                ForEach(word.idioms, id: \.phrase) { idiom in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(direction == .en ? idiom.phrase : idiom.meaning).fontWeight(.semibold)
                        answer(word) {
                            Text(direction == .en ? idiom.meaning : idiom.phrase).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var progress: some View {
        let words = WordBank.words(for: level)
        let learned = WordStore.learned
        let count = words.filter { learned.contains($0.text) }.count
        return VStack(alignment: .leading, spacing: 10) {
            Divider()
            Picker("Задание", selection: $direction) {
                Text("EN — английское слово").tag(Direction.en)
                Text("RU — русское слово").tag(Direction.ru)
            }
            .pickerStyle(.segmented)
            .onChange(of: direction) {
                WordStore.direction = direction
                reloadWidgets()
            }

            Picker("Тема окна и виджета", selection: $theme) {
                ForEach(WidgetTheme.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: theme) {
                WordStore.theme = theme
                reloadWidgets()
            }

            Picker("Уровень", selection: $level) {
                ForEach(Level.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: level) {
                WordStore.level = level
                reloadWidgets()
            }

            ProgressView(value: Double(count), total: Double(max(words.count, 1))) {
                Text("Запомнено \(count) из \(words.count) слов уровня \(level.title)")
                    .font(.subheadline)
            }

            if count > 0 {
                Button("Сбросить прогресс уровня", role: .destructive) {
                    confirmReset = true
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .confirmationDialog(
                    "Сбросить прогресс уровня \(level.title)?",
                    isPresented: $confirmReset,
                    titleVisibility: .visible
                ) {
                    Button("Сбросить", role: .destructive) {
                        WordStore.resetProgress(for: level)
                        reloadWidgets()
                    }
                    Button("Отмена", role: .cancel) {}
                } message: {
                    Text("Запомненные слова (\(count)) снова начнут показываться.")
                }
            }
        }
    }

    private func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
        refresh += 1
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text("Слов в базе: \(WordBank.all.count). Новое слово — каждые 10 минут.")
                .font(.caption)
                .foregroundStyle(.secondary)
            #if os(macOS)
            Text("Как добавить виджет: правый клик по рабочему столу → «Изменить виджеты…» → найдите eWord.")
                .font(.caption)
                .foregroundStyle(.secondary)
            #else
            Text("Как добавить виджет: удерживайте палец на экране «Домой» → «Изменить» → «Добавить виджет» → eWord.")
                .font(.caption)
                .foregroundStyle(.secondary)
            #endif
        }
    }
}

#Preview {
    ContentView()
}

extension WidgetTheme {
    var colorScheme: ColorScheme? {
        switch self {
        case .auto: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
