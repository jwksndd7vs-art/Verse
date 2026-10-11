import SwiftUI
import WidgetKit

struct VerseEntry: TimelineEntry { let date: Date; let title: String; let artist: String; let line: String }
struct VerseProvider: TimelineProvider {
    func placeholder(in context: Context) -> VerseEntry { .init(date: .now, title: "Verse", artist: "Spotify + LRCLIB", line: "Your music, one line at a time.") }
    func getSnapshot(in context: Context, completion: @escaping (VerseEntry) -> Void) {
        if let state = SharedStore.load() { completion(entry(state, at: .now)) } else { completion(placeholder(in: context)) }
    }
    private func entry(_ state: PlaybackSnapshot, at date: Date) -> VerseEntry {
        .init(date: date, title: state.title, artist: state.artist, line: state.lyric(at: date, offset: SharedStore.offset))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<VerseEntry>) -> Void) {
        Task {
            var state: PlaybackSnapshot?
            var errorText = "Spotify is not connected"
            if TokenVault.read() != nil {
                do { let fetched = try await SpotifyService().snapshot(); SharedStore.save(fetched); state = fetched }
                catch { errorText = error.localizedDescription }
            } else if let demo = SharedStore.load(), demo.trackID == "demo" { state = demo }
            let now = Date()
            guard let state else {
                completion(Timeline(entries: [.init(date: now, title: "Verse", artist: "Playback unavailable", line: errorText)], policy: .after(now.addingTimeInterval(300)))); return
            }
            var entries = [entry(state, at: now)]
            // Experimental: short timeline entries are requests, not guaranteed display times.
            // Apple recommends wider spacing; this cannot guarantee karaoke synchronization.
            let end = now.addingTimeInterval(max(0, state.duration - state.position(at: now)))
            if state.playing {
                for line in state.lines {
                    let date = state.sampledAt.addingTimeInterval(line.time - SharedStore.offset - state.progress)
                    if date > now && date < end && entries.count < 200 { entries.append(entry(state, at: date.addingTimeInterval(0.01))) }
                }
                entries.append(.init(date: end.addingTimeInterval(1), title: "Verse", artist: "Waiting for playback update", line: "Refreshing song information…"))
            }
            let refresh = max(now.addingTimeInterval(300), end.addingTimeInterval(2))
            completion(Timeline(entries: entries.sorted { $0.date < $1.date }, policy: .after(refresh)))
        }
    }
}
struct VerseWidgetView: View {
    let entry: VerseEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Image(systemName: "music.note"); Text("VERSE").font(.caption2.bold()); Spacer() }.foregroundStyle(.mint)
            Text(entry.title).font(.caption.bold()).lineLimit(1)
            Text(entry.line).font(.system(size: 18, weight: .semibold)).lineLimit(4).minimumScaleFactor(0.75).contentTransition(.opacity)
            Spacer(minLength: 0)
            Text(entry.artist).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }.containerBackground(for: .widget) { LinearGradient(colors: [Color(red: 0.08, green: 0.23, blue: 0.19), .black], startPoint: .topLeading, endPoint: .bottomTrailing) }
    }
}
@main struct VerseLyricsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: VerseConfig.widgetKind, provider: VerseProvider()) { VerseWidgetView(entry: $0) }
            .configurationDisplayName("Verse Lyrics")
            .description("An experimental Spotify lyrics card. iOS controls refresh timing.")
            .supportedFamilies([.systemSmall])
    }
}
