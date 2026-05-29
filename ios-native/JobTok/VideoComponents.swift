import SwiftUI
import AVFoundation
import UIKit
import WebKit

struct RemoteVideoSurface: View {
    let urlString: String?
    var isActive: Bool = true
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill
    var autoPlay: Bool = true
    var allowsTapToTogglePlayback: Bool = false
    var showsPlayOverlayWhenPaused: Bool = false
    var isMuted: Bool = false

    var body: some View {
        if let urlString, let embed = SocialEmbedConfiguration(urlString: urlString) {
            SocialEmbedSurface(configuration: embed, isActive: isActive)
        } else if let urlString, let url = URL(string: urlString) {
            LoopingVideoSurface(
                url: url,
                isActive: isActive,
                videoGravity: videoGravity,
                autoPlay: autoPlay,
                allowsTapToTogglePlayback: allowsTapToTogglePlayback,
                showsPlayOverlayWhenPaused: showsPlayOverlayWhenPaused,
                isMuted: isMuted
            )
        } else {
            LinearGradient(
                colors: [
                    PassportTheme.card,
                    PassportTheme.accentSoft,
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

private struct SocialEmbedConfiguration: Equatable {
    enum Platform {
        case tiktok
        case instagram
    }

    let platform: Platform
    let url: URL

    init?(urlString: String) {
        guard let url = URL(string: urlString), let host = url.host?.lowercased() else {
            return nil
        }
        if host.contains("tiktok.com") {
            self.platform = .tiktok
            self.url = url
        } else if host.contains("instagram.com") {
            self.platform = .instagram
            self.url = url
        } else {
            return nil
        }
    }

    var html: String {
        switch platform {
        case .tiktok: return tiktokHTML
        case .instagram: return instagramHTML
        }
    }

    private var tiktokHTML: String {
        // Extract numeric video ID from /@user/video/{ID} or /video/{ID}
        let embedSrc: String
        if let id = url.absoluteString
            .components(separatedBy: "/video/").last?
            .components(separatedBy: CharacterSet(charactersIn: "?#/")).first,
           !id.isEmpty, id.allSatisfy(\.isNumber) {
            // TikTok player v1 API — autoplay=1, loop=1, no extra chrome
            embedSrc = "https://www.tiktok.com/player/v1/\(id)?autoplay=1&loop=1&muted=0&controls=1&music_info=0&description=0&rel=0&native_context_menu=0&closed_caption=0&fullscreen_button=0"
        } else {
            // Short URL or unknown format — load the page directly
            embedSrc = url.absoluteString
        }
        return iframeHTML(src: embedSrc)
    }

    private var instagramHTML: String {
        // Extract shortcode from /p/{code}/, /reel/{code}/, /tv/{code}/
        let embedSrc: String
        let pathParts = url.pathComponents
        if let idx = pathParts.firstIndex(where: { ["p", "reel", "tv"].contains($0) }),
           idx + 1 < pathParts.count {
            let shortcode = pathParts[idx + 1]
            if !shortcode.isEmpty {
                // Instagram's server-rendered embed — no JS required, works in WKWebView
                embedSrc = "https://www.instagram.com/p/\(shortcode)/embed/"
            } else {
                embedSrc = url.absoluteString
            }
        } else {
            embedSrc = url.absoluteString
        }
        return iframeHTML(src: embedSrc)
    }

    private func iframeHTML(src: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
          <style>
            * { margin: 0; padding: 0; box-sizing: border-box; }
            html, body { width: 100%; height: 100%; background: #000; overflow: hidden; }
            iframe { position: absolute; inset: 0; width: 100%; height: 100%; border: 0; }
          </style>
        </head>
        <body>
          <iframe
            src="\(src)"
            allow="autoplay; encrypted-media; fullscreen; picture-in-picture"
            allowfullscreen
          ></iframe>
        </body>
        </html>
        """
    }
}

private struct SocialEmbedSurface: UIViewRepresentable {
    let configuration: SocialEmbedConfiguration
    let isActive: Bool

    final class Coordinator {
        var loadedConfiguration: SocialEmbedConfiguration?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true

        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences = prefs
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        if !isActive {
            // Unload when scrolled off — stops audio and releases memory
            if coordinator.loadedConfiguration != nil {
                coordinator.loadedConfiguration = nil
                webView.load(URLRequest(url: URL(string: "about:blank")!))
            }
        } else {
            guard coordinator.loadedConfiguration != configuration else { return }
            coordinator.loadedConfiguration = configuration
            webView.loadHTMLString(configuration.html, baseURL: configuration.url)
        }
    }
}

struct LoopingVideoSurface: View {
    let url: URL
    let isActive: Bool
    let videoGravity: AVLayerVideoGravity
    let autoPlay: Bool
    let allowsTapToTogglePlayback: Bool
    let showsPlayOverlayWhenPaused: Bool
    var isMuted: Bool = false

    @StateObject private var playerStore = LoopingPlayerStore()
    @State private var userPaused = false

    private var shouldPlay: Bool {
        guard isActive else { return false }
        if allowsTapToTogglePlayback && userPaused { return false }
        return autoPlay
    }

    var body: some View {
        ZStack {
            LoopingPlayerLayerView(
                player: playerStore.player,
                videoGravity: videoGravity
            )
            .background(Color.black)

            if showsPlayOverlayWhenPaused && !shouldPlay {
                Button {
                    userPaused = false
                    playerStore.setPlaying(true)
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.62))
                            .frame(width: 72, height: 72)

                        Image(systemName: "play.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                            .offset(x: 2)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard allowsTapToTogglePlayback else { return }
            userPaused.toggle()
            playerStore.setPlaying(!userPaused && isActive)
        }
        .onAppear {
            playerStore.configure(url: url)
            playerStore.setMuted(isMuted)
            playerStore.setPlaying(shouldPlay)
        }
        .onChange(of: isActive) { _, newValue in
            if !newValue { playerStore.setPlaying(false) }
            else if !userPaused { playerStore.setPlaying(autoPlay) }
        }
        .onChange(of: isMuted) { _, newValue in
            playerStore.setMuted(newValue)
        }
        .onDisappear {
            playerStore.pause()
        }
    }
}

private final class LoopingPlayerStore: ObservableObject {
    let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private var currentURL: URL?

    init() {
        player.isMuted = false
        configureAudioSession()
        player.actionAtItemEnd = .none
    }

    func configure(url: URL) {
        guard currentURL != url else { return }
        currentURL = url
        looper = nil
        player.removeAllItems()
        let item = AVPlayerItem(url: url)
        looper = AVPlayerLooper(player: player, templateItem: item)
        player.seek(to: .zero)
    }

    func pause() {
        player.pause()
    }

    func setMuted(_ isMuted: Bool) {
        player.isMuted = isMuted
    }

    func setPlaying(_ isPlaying: Bool) {
        if isPlaying {
            player.play()
        } else {
            player.pause()
            player.seek(to: .zero)
        }
    }

    private func configureAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playback, mode: .moviePlayback, options: [])
        try? audioSession.setActive(true)
    }
}

private struct LoopingPlayerLayerView: UIViewRepresentable {
    let player: AVQueuePlayer
    let videoGravity: AVLayerVideoGravity

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.backgroundColor = .black
        view.playerLayer.player = player
        view.playerLayer.videoGravity = videoGravity
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        uiView.playerLayer.player = player
        uiView.playerLayer.videoGravity = videoGravity
    }
}

private final class PlayerContainerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        self.layer as! AVPlayerLayer
    }
}
