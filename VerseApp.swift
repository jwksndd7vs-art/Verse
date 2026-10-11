import SwiftUI
import AuthenticationServices
import CryptoKit
import WidgetKit
import UIKit

@MainActor final class VerseController: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published var snapshot: PlaybackSnapshot?
    @Published var status = "Connect Spotify, or try the demo."
    @Published var offset = SharedStore.offset
    private var session: ASWebAuthenticationSession?
    private var loop: Task<Void, Never>?
    private var generation = 0
    private var fetching = false
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
    private func random() -> String { UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "") }
    func connect() {
        let verifier = random(), state = random()
        let hash = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = ["client_id": VerseConfig.clientID, "response_type": "code", "redirect_uri": VerseConfig.redirect,
                                 "scope": "user-read-currently-playing", "state": state, "code_challenge_method": "S256", "code_challenge": hash].map { URLQueryItem(name: $0.key, value: $0.value) }
        session = ASWebAuthenticationSession(url: components.url!, callbackURLScheme: "verse-lyrics-alex-login") { [weak self] url, error in
            Task { @MainActor in
                guard let self else { return }
                guard error == nil, let url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
                      parts.queryItems?.first(where: { $0.name == "state" })?.value == state,
                      let code = parts.queryItems?.first(where: { $0.name == "code" })?.value else { self.status = "Spotify sign-in canceled or could not be verified."; return }
                do {
                    let tokens = try await SpotifyService.tokenRequest(["grant_type": "authorization_code", "code": code, "redirect_uri": VerseConfig.redirect, "client_id": VerseConfig.clientID, "code_verifier": verifier])
                    try TokenVault.save(tokens); self.status = "Spotify connected"; self.start()
                } catch { self.status = error.localizedDescription }
            }
        }
        session?.presentationContextProvider = self; session?.prefersEphemeralWebBrowserSession = false
        if session?.start() != true { status = "Unable to open Spotify sign-in." }
    }
    func start() {
        loop?.cancel()
        guard TokenVault.read() != nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.sync()
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
        }
    }
    func stop() { loop?.cancel(); loop = nil; generation += 1 }
    func sync() async {
        guard !fetching else { return }; fetching = true; defer { fetching = false }
        let gen = generation
        do {
            let updated = try await SpotifyService().snapshot()
            guard gen == generation, !Task.isCancelled else { return }
            let changed = snapshot?.trackID != updated.trackID || snapshot?.playing != updated.playing || abs((snapshot?.position(at: updated.sampledAt) ?? 0) - updated.progress) > 2
            snapshot = updated; SharedStore.save(updated); status = "Lyrics from LRCLIB · Widget timing is experimental"
            if changed { WidgetCenter.shared.reloadTimelines(ofKind: VerseConfig.widgetKind) }
        } catch {
            guard gen == generation else { return }
            status = error.localizedDescription
            if var old = snapshot { old.progress = old.position(at: Date()); old.sampledAt = Date(); old.playing = false; snapshot = old; SharedStore.save(old) }
        }
    }
    func demo() { stop(); TokenVault.clear(); snapshot = .demo; SharedStore.save(snapshot!); status = "Original demo text · No audio"; WidgetCenter.shared.reloadTimelines(ofKind: VerseConfig.widgetKind) }
    func disconnect() { stop(); TokenVault.clear(); SharedStore.clear(); snapshot = nil; status = "Disconnected"; WidgetCenter.shared.reloadTimelines(ofKind: VerseConfig.widgetKind) }
    func adjustOffset() { SharedStore.offset = offset; WidgetCenter.shared.reloadTimelines(ofKind: VerseConfig.widgetKind) }
}
@main struct VerseApp: App {
    @StateObject private var controller = VerseController()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        Text("Verse").font(.largeTitle.bold())
                        TimelineView(.periodic(from: .now, by: 0.2)) { clock in
                            let lyric = controller.snapshot?.lyric(at: clock.date, offset: controller.offset) ?? "Your music, one line at a time."
                            VStack(alignment: .leading, spacing: 16) {
                                Text(controller.snapshot?.title ?? "Not connected").font(.headline)
                                Text(controller.snapshot?.artist ?? "Spotify + LRCLIB").font(.subheadline).foregroundStyle(.secondary)
                                Text(lyric).font(.system(size: 30, weight: .semibold)).foregroundStyle(Color.mint).frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
                                    .id(lyric).transition(.opacity.combined(with: .move(edge: .bottom)))
                            }.padding(24).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 26))
                                .animation(.easeOut(duration: 0.35), value: lyric)
                        }
                        Text(controller.status).font(.footnote).foregroundStyle(.secondary)
                        Button("Connect Spotify", action: controller.connect).buttonStyle(.borderedProminent)
                        HStack { Button("Sync now") { Task { await controller.sync() } }; Button("Try demo", action: controller.demo) }.buttonStyle(.bordered)
                        Stepper("Timing adjustment: \(controller.offset, specifier: "%.1f") s", value: $controller.offset, in: -30...30, step: 0.1)
                            .onChange(of: controller.offset) { _, _ in controller.adjustOffset() }
                        Text("Positive values advance lyrics. Negative values delay them.").font(.caption).foregroundStyle(.secondary)
                        Text("Add the Verse Lyrics small widget in Settings → General → CarPlay → your vehicle → Widgets. Requires iOS 26 or later and a CarPlay vehicle.").font(.footnote)
                        Text("iOS chooses widget update times. Planned line changes may be delayed or skipped, and background song changes may take minutes to appear. Smooth phone animation does not carry over exactly to widgets. Test while parked.").font(.footnote).foregroundStyle(.secondary)
                        Button("Disconnect", role: .destructive, action: controller.disconnect)
                    }.padding()
                }.preferredColorScheme(.dark)
            }.task { controller.start() }
              .onChange(of: scenePhase) { _, phase in if phase == .active { controller.start() } else { controller.stop() } }
        }
    }
}
