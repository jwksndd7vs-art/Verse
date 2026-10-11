import Foundation

struct LyricLine: Codable, Equatable { var time: Double; var text: String }
struct PlaybackSnapshot: Codable {
    var trackID: String
    var title: String
    var artist: String
    var duration: Double
    var progress: Double
    var sampledAt: Date
    var playing: Bool
    var lines: [LyricLine]
    var message: String
    func position(at date: Date) -> Double {
        min(duration, max(0, progress + (playing ? max(0, date.timeIntervalSince(sampledAt)) : 0)))
    }
    func lyric(at date: Date, offset: Double = 0) -> String {
        let p = position(at: date) + offset
        return lines.last(where: { $0.time <= p })?.text ?? (lines.isEmpty ? message : "Waiting for first lyric…")
    }
    static var demo: PlaybackSnapshot {
        .init(trackID: "demo", title: "Open Road", artist: "Verse demo", duration: 40, progress: 0,
              sampledAt: Date(), playing: true,
              lines: [.init(time: 0, text: "The morning opens wide"), .init(time: 5, text: "A little light across the fields"),
                      .init(time: 10, text: "We take the quiet road"), .init(time: 15, text: "And leave the rush behind"),
                      .init(time: 20, text: "The sky has room for every dream"), .init(time: 25, text: "The mountains catch the sun"),
                      .init(time: 30, text: "We find our way a mile at a time"), .init(time: 35, text: "And let the evening come")], message: "")
    }
}
enum VerseConfig {
    static let clientID = "acf10b74dd804574b69538e49d41a9d3"
    static let redirect = "verse-lyrics-alex-login://spotify/callback"
    static let appGroup = "group.com.alexfagan.verse"
    static let widgetKind = "VerseLyricsWidget"
}
enum SharedStore {
    static var defaults: UserDefaults? { UserDefaults(suiteName: VerseConfig.appGroup) }
    static func save(_ snapshot: PlaybackSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) { defaults?.set(data, forKey: "snapshot") }
    }
    static func load() -> PlaybackSnapshot? {
        guard let data = defaults?.data(forKey: "snapshot") else { return nil }
        return try? JSONDecoder().decode(PlaybackSnapshot.self, from: data)
    }
    static var offset: Double {
        get { defaults?.double(forKey: "offset") ?? 0 }
        set { defaults?.set(max(-30, min(30, newValue)), forKey: "offset") }
    }
    static func clear() { defaults?.removeObject(forKey: "snapshot"); defaults?.removeObject(forKey: "offset") }
}
func parseLRC(_ text: String) -> [LyricLine] {
    guard let regex = try? NSRegularExpression(pattern: #"\[(\d+):([0-5]?\d(?:\.\d+)?)\]"#),
          let tags = try? NSRegularExpression(pattern: #"\[[^\]]*\]"#) else { return [] }
    var result: [LyricLine] = []
    for row in text.components(separatedBy: .newlines) {
        let range = NSRange(row.startIndex..., in: row)
        let value = tags.stringByReplacingMatches(in: row, range: range, withTemplate: "").trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { continue }
        for match in regex.matches(in: row, range: range) {
            guard let mr = Range(match.range(at: 1), in: row), let sr = Range(match.range(at: 2), in: row),
                  let minutes = Double(row[mr]), let seconds = Double(row[sr]) else { continue }
            result.append(.init(time: minutes * 60 + seconds, text: value))
        }
    }
    return result.sorted { $0.time < $1.time }
}
