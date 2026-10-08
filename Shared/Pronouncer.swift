//
//  Pronouncer.swift
//  Озвучка только записями из словарей (Oxford, Cambridge, Free Dictionary), без системного голоса.
//  Звук играет из кэша; если записи ещё нет — скачивается и играет. Виджет заранее качает звук для ближайших слов.
//  Повторные нажатия на одно слово перебирают словари и акценты UK/US.
//

import Foundation
import AVFoundation
import WidgetKit

/// Откуда взят звук.
nonisolated enum AudioOrigin: String, Codable, Sendable, CaseIterable {
    case oxford, cambridge, freeDictionary
    /// Записи нет ни в одном словаре (или нет сети).
    case notFound

    var title: String {
        switch self {
        case .oxford: "Oxford"
        case .cambridge: "Cambridge"
        case .freeDictionary: "Free Dictionary"
        case .notFound: "нет записи"
        }
    }

    /// Последняя озвучка — в файле контейнера App Group, чтобы виджет сразу видел свежее значение.
    struct Last: Codable, Sendable {
        let origin: AudioOrigin
        let word: String
        var accent: Accent?

        /// «Oxford · UK» или «нет записи».
        var label: String {
            guard origin != .notFound, let accent else { return origin.title }
            return "\(origin.title) · \(accent.rawValue.uppercased())"
        }
    }

    private static var lastURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WordStore.appGroup)?
            .appendingPathComponent("lastAudio.json")
    }

    static var last: Last? {
        get {
            guard let url = lastURL, let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(Last.self, from: data)
        }
        set {
            guard let url = lastURL, let newValue, let data = try? JSONEncoder().encode(newValue) else { return }
            try? data.write(to: url, options: .atomic)
            // Подпись источника рядом с кнопкой 🔊 появляется сразу, а не после окончания звука.
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

@MainActor
final class Pronouncer {
    static let shared = Pronouncer()

    private var player: AVAudioPlayer?

    /// Озвучить слово. Повторное нажатие на то же слово перебирает варианты по кругу:
    /// Oxford UK → Oxford US → Cambridge UK → Cambridge US → Free Dictionary UK → US (начиная с выбранного акцента),
    /// пропуская те, которых нет.
    /// `cycle: false` — сразу выбранный акцент, без перебора (например, при смене UK/US в приложении).
    @discardableResult
    func speak(_ word: String, cycle: Bool = true) async -> AudioOrigin {
        #if os(iOS) || os(visionOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif

        let accent = WordStore.accent
        let variants = AudioSource.variants(preferred: accent)
        var found: (data: Data, variant: AudioSource.Variant)?

        if cycle, let last = AudioOrigin.last, last.word == word, last.origin != .notFound, let lastAccent = last.accent,
           let index = variants.firstIndex(of: .init(origin: last.origin, accent: lastAccent)) {
            // Повтор: следующий доступный вариант после прошлого.
            for step in 1...variants.count {
                let variant = variants[(index + step) % variants.count]
                if let data = await AudioSource.audio(word, variant: variant) {
                    found = (data, variant)
                    break
                }
            }
        } else if let (data, origin) = AudioSource.cached(word, accent: accent) {
            found = (data, .init(origin: origin, accent: accent))
        } else if let (data, origin) = await AudioSource.audio(for: word, accent: accent) {
            found = (data, .init(origin: origin, accent: accent))
        }

        guard let found, let player = try? AVAudioPlayer(data: found.data), player.play() else {
            AudioOrigin.last = .init(origin: .notFound, word: word, accent: accent)
            return .notFound
        }
        self.player = player
        AudioOrigin.last = .init(origin: found.variant.origin, word: word, accent: found.variant.accent)
        // Пока звучит — докачиваем остальные варианты, чтобы следующие нажатия были мгновенными.
        // Не ждём их: пока perform не завершился, система не принимает следующее нажатие 🔊.
        Task.detached {
            await withTaskGroup(of: Void.self) { group in
                for variant in variants { group.addTask { _ = await AudioSource.audio(word, variant: variant) } }
            }
        }
        while player.isPlaying {
            try? await Task.sleep(for: .milliseconds(100))
        }
        return found.variant.origin
    }
}

/// Загрузка mp3 с произношением (с кэшем на диске).
nonisolated enum AudioSource {
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"

    private static func key(_ word: String) -> String {
        word.lowercased().trimmingCharacters(in: .whitespaces)
    }

    /// Источник зашит в имя файла кэша: uk-board.oxford.mp3.
    private static func cacheFile(_ word: String, accent: Accent, origin: AudioOrigin) -> URL? {
        cacheDirectory?.appending(path: "\(accent.rawValue)-\(key(word)).\(origin.rawValue).mp3")
    }

    /// Один вариант озвучки: словарь + акцент.
    struct Variant: Equatable, Sendable {
        let origin: AudioOrigin
        let accent: Accent
    }

    static func variants(preferred: Accent) -> [Variant] {
        let accents = preferred == .uk ? [Accent.uk, .us] : [.us, .uk]
        return [AudioOrigin.oxford, .cambridge, .freeDictionary].flatMap { origin in
            accents.map { Variant(origin: origin, accent: $0) }
        }
    }

    /// Метка «у этого словаря такой записи нет», чтобы не ходить в сеть повторно.
    private static func missingFile(_ word: String, variant: Variant) -> URL? {
        cacheDirectory?.appending(path: "\(variant.accent.rawValue)-\(key(word)).\(variant.origin.rawValue).none")
    }

    /// Конкретный вариант: из кэша или из сети этого словаря.
    static func audio(_ word: String, variant: Variant) async -> Data? {
        if let file = cacheFile(word, accent: variant.accent, origin: variant.origin),
           let data = try? Data(contentsOf: file), data.count > 500 {
            return data
        }
        // Метка действует сутки: отказ мог быть из-за сети или VPN.
        if let marker = missingFile(word, variant: variant),
           let date = (try? marker.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
           date.timeIntervalSinceNow > -24 * 3600 {
            return nil
        }
        let word = key(word)
        let data: Data? = switch variant.origin {
        case .oxford: await oxford(word, accent: variant.accent)
        case .cambridge: await cambridge(word, accent: variant.accent)
        case .freeDictionary: await freeDictionary(word, accent: variant.accent)
        case .notFound: nil
        }
        if let data, let file = cacheFile(word, accent: variant.accent, origin: variant.origin) {
            try? data.write(to: file)
        } else if data == nil, let marker = missingFile(word, variant: variant) {
            try? Data().write(to: marker)
        }
        return data
    }

    /// Запись из кэша, без сети.
    static func cached(_ word: String, accent: Accent) -> (Data, AudioOrigin)? {
        for origin in [AudioOrigin.oxford, .cambridge, .freeDictionary] {
            if let file = cacheFile(word, accent: accent, origin: origin),
               let data = try? Data(contentsOf: file), data.count > 500 {
                return (data, origin)
            }
        }
        return nil
    }

    /// Запись из кэша или из сети: словари опрашиваются одновременно, берётся первый ответ.
    static func audio(for word: String, accent: Accent) async -> (Data, AudioOrigin)? {
        if let cached = cached(word, accent: accent) { return cached }
        let word = key(word)

        let result = await withTaskGroup(of: (Data, AudioOrigin)?.self) { group -> (Data, AudioOrigin)? in
            group.addTask { await oxford(word, accent: accent).map { ($0, .oxford) } }
            group.addTask { await cambridge(word, accent: accent).map { ($0, .cambridge) } }
            group.addTask { await freeDictionary(word, accent: accent).map { ($0, .freeDictionary) } }
            for await result in group {
                if let result {
                    group.cancelAll()
                    return result
                }
            }
            return nil
        }

        if let (data, origin) = result, let file = cacheFile(word, accent: accent, origin: origin) {
            try? data.write(to: file)
        }
        return result
    }

    /// Заранее скачивает звук для слов, которые скоро покажет виджет.
    static func prefetch(_ words: [String], accent: Accent) async {
        await withTaskGroup(of: Void.self) { group in
            for word in Set(words) {
                group.addTask { _ = await audio(for: word, accent: accent) }
            }
        }
    }

    // MARK: Oxford Learner's Dictionaries

    private static func oxford(_ word: String, accent: Accent) async -> Data? {
        let suffix = accent == .uk ? "gb" : "us"
        guard let slug = word.replacingOccurrences(of: " ", with: "-")
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let pageURL = URL(string: "https://www.oxfordlearnersdictionaries.com/definition/english/\(slug)"),
              let pageData = await get(pageURL),
              let html = String(data: pageData, encoding: .utf8),
              let regex = try? Regex("https://www\\.oxfordlearnersdictionaries\\.com/media/english/\(accent.rawValue)_pron/[^\"'\\s]+?__\(suffix)_[0-9]+\\.mp3"),
              let match = html.firstMatch(of: regex),
              let audioURL = URL(string: String(html[match.range]))
        else { return nil }
        return await get(audioURL, referer: pageURL)
    }

    // MARK: Cambridge Dictionary

    private static func cambridge(_ word: String, accent: Accent) async -> Data? {
        guard let slug = word.replacingOccurrences(of: " ", with: "-")
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let pageURL = URL(string: "https://dictionary.cambridge.org/dictionary/english/\(slug)"),
              let pageData = await get(pageURL),
              let html = String(data: pageData, encoding: .utf8),
              let regex = try? Regex("/media/english/\(accent.rawValue)_pron/[^\"'\\s]+?\\.mp3"),
              let match = html.firstMatch(of: regex),
              let audioURL = URL(string: "https://dictionary.cambridge.org" + String(html[match.range]))
        else { return nil }
        return await get(audioURL, referer: pageURL)
    }

    // MARK: Free Dictionary API (https://dictionaryapi.dev)

    private static func freeDictionary(_ word: String, accent: Accent) async -> Data? {
        guard let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.dictionaryapi.dev/api/v2/entries/en/\(encoded)"),
              let data = await get(url),
              let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return nil }

        let audios: [String] = entries
            .flatMap { ($0["phonetics"] as? [[String: Any]]) ?? [] }
            .compactMap { $0["audio"] as? String }
            .filter { !$0.isEmpty }

        // Только запись нужного акцента, чтобы подпись UK/US была честной.
        guard var link = audios.first(where: { $0.contains("-\(accent.rawValue).mp3") }) else { return nil }
        if link.hasPrefix("//") { link = "https:" + link }
        guard let audioURL = URL(string: link) else { return nil }
        // Файлы Free Dictionary часто не отдаются вовсе — долго не ждём.
        return await get(audioURL, timeout: 4)
    }

    // MARK: Helpers

    private static func get(_ url: URL, referer: URL? = nil, timeout: TimeInterval = 10) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let referer { request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer") }
        guard let result = try? await URLSession.shared.data(for: request),
              let http = result.1 as? HTTPURLResponse, http.statusCode == 200,
              result.0.count > 500
        else { return nil }
        return result.0
    }

    private static var cacheDirectory: URL? {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WordStore.appGroup)
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        guard let dir = base?.appending(path: "Library/Caches/Pronunciations", directoryHint: .isDirectory) else {
            return nil
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
