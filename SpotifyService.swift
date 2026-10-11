import Foundation
import Security

struct OAuthTokens: Codable {
    var accessToken: String; var refreshToken: String; var expiresAt: Date
}
enum TokenVault {
    // Provisioned App Groups also grant Keychain sharing. Use the same group
    // for both targets rather than a build-time team prefix in Info.plist.
    static var group: String { VerseConfig.appGroup }
    static var query: [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                              kSecAttrService as String: "VerseSpotify", kSecAttrAccount as String: "tokens"]
        q[kSecAttrAccessGroup as String] = group
        return q
    }
    static func read() -> OAuthTokens? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &value) == errSecSuccess,
              let data = value as? Data else { return nil }
        return try? JSONDecoder().decode(OAuthTokens.self, from: data)
    }
    static func save(_ tokens: OAuthTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query; q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(q as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw storageError(addStatus) }
        } else if status != errSecSuccess { throw storageError(status) }
    }
    private static func storageError(_ status: OSStatus) -> VerseError {
        .message("Spotify login storage failed (\(status)). Rebuild with the updated sharing workflow and keep the widget extension when installing.")
    }
    static func clear() { SecItemDelete(query as CFDictionary) }
}
enum VerseError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
struct SpotifyService {
    private struct TokenResponse: Decodable { var access_token: String; var refresh_token: String?; var expires_in: Double }
    private struct Artist: Decodable { var name: String }
    private struct Album: Decodable { var name: String }
    private struct Track: Decodable { var id: String?; var uri: String?; var name: String; var duration_ms: Double; var artists: [Artist]; var album: Album? }
    private struct Current: Decodable { var item: Track?; var progress_ms: Double?; var is_playing: Bool; var currently_playing_type: String? }
    private struct Record: Decodable { var syncedLyrics: String?; var plainLyrics: String?; var instrumental: Bool? }
    static func tokenRequest(_ fields: [String: String], previousRefresh: String? = nil) async throws -> OAuthTokens {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"; request.timeoutInterval = 15
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents(); components.queryItems = fields.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw VerseError.message("Spotify sign-in failed. Check the native redirect URI and connect again.") }
        let result = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard let refresh = result.refresh_token ?? previousRefresh else { throw VerseError.message("Spotify did not return a refresh token.") }
        return OAuthTokens(accessToken: result.access_token, refreshToken: refresh, expiresAt: Date().addingTimeInterval(result.expires_in))
    }
    func snapshot() async throws -> PlaybackSnapshot {
        if let until = SharedStore.defaults?.object(forKey: "spotifyRetryAfter") as? Date, until > Date() { throw VerseError.message("Spotify is busy. Waiting before retrying.") }
        guard var tokens = TokenVault.read() else { throw VerseError.message("Spotify is not connected") }
        if tokens.expiresAt.timeIntervalSinceNow < 30 {
            tokens = try await Self.tokenRequest(["grant_type": "refresh_token", "refresh_token": tokens.refreshToken, "client_id": VerseConfig.clientID], previousRefresh: tokens.refreshToken)
            try TokenVault.save(tokens)
        }
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/currently-playing")!)
        request.timeoutInterval = 15; request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        let started = Date(); let (data, response) = try await URLSession.shared.data(for: request); let received = Date()
        guard let http = response as? HTTPURLResponse else { throw VerseError.message("Spotify connection unavailable") }
        switch http.statusCode {
        case 204: throw VerseError.message("No Spotify song playing")
        case 401: throw VerseError.message("Spotify sign-in expired. Reconnect when safe.")
        case 403: throw VerseError.message("Spotify denied access. Check Premium and app user access.")
        case 429:
            let retry = Double(http.value(forHTTPHeaderField: "Retry-After") ?? "30") ?? 30
            SharedStore.defaults?.set(Date().addingTimeInterval(max(1, retry)), forKey: "spotifyRetryAfter")
            throw VerseError.message("Spotify is busy. Waiting before retrying.")
        case 200: break
        default: throw VerseError.message("Spotify playback unavailable")
        }
        let current = try JSONDecoder().decode(Current.self, from: data)
        guard current.currently_playing_type == "track", let track = current.item else { throw VerseError.message("No supported Spotify song playing") }
        let key = track.id ?? track.uri ?? track.name
        let sampled = received.addingTimeInterval(-min(1, received.timeIntervalSince(started) / 2))
        var result = PlaybackSnapshot(trackID: key, title: track.name, artist: track.artists.map(\.name).joined(separator: ", "),
                                      duration: track.duration_ms / 1000, progress: (current.progress_ms ?? 0) / 1000,
                                      sampledAt: sampled, playing: current.is_playing, lines: [], message: "No timed lyrics found")
        if let cached = SharedStore.load(), cached.trackID == key, !["Lyrics service busy", "Lyrics lookup unavailable"].contains(cached.message) { result.lines = cached.lines; result.message = cached.message; return result }
        if let until = SharedStore.defaults?.object(forKey: "lyricsRetryAfter") as? Date, until > Date() {
            result.message = "Lyrics service busy"; return result
        }
        var url = URLComponents(string: "https://lrclib.net/api/get")!
        url.queryItems = [URLQueryItem(name: "track_name", value: track.name), URLQueryItem(name: "artist_name", value: track.artists.first?.name ?? ""),
                          URLQueryItem(name: "duration", value: String(track.duration_ms / 1000))]
        if let album = track.album?.name { url.queryItems?.append(URLQueryItem(name: "album_name", value: album)) }
        var lookup = URLRequest(url: url.url!); lookup.timeoutInterval = 15
        lookup.setValue("VerseWidget v0.1 (https://verse-lyrics-alex.candidpond1.chatgpt.site)", forHTTPHeaderField: "User-Agent")
        do {
            let (lyricsData, lyricsResponse) = try await URLSession.shared.data(for: lookup)
            let lyricsHTTP = lyricsResponse as? HTTPURLResponse
            if lyricsHTTP?.statusCode == 200 {
                let record = try JSONDecoder().decode(Record.self, from: lyricsData)
                if record.instrumental == true { result.message = "Instrumental track" }
                else if let text = record.syncedLyrics { result.lines = parseLRC(text) }
                if result.lines.isEmpty, record.plainLyrics != nil { result.message = "Only untimed lyrics available" }
            } else if lyricsHTTP?.statusCode == 429 {
                let seconds = Double(lyricsHTTP?.value(forHTTPHeaderField: "Retry-After") ?? "30") ?? 30
                SharedStore.defaults?.set(Date().addingTimeInterval(max(1, seconds)), forKey: "lyricsRetryAfter")
                result.message = "Lyrics service busy"
            }
        } catch { result.message = "Lyrics lookup unavailable" }
        return result
    }
}
