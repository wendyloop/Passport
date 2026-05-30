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

    @State private var embedBroken = false

    var body: some View {
        if let urlString, let embed = SocialEmbedConfiguration(urlString: urlString), !embedBroken {
            SocialEmbedSurface(configuration: embed, isActive: isActive, onBroken: {
                embedBroken = true
            })
        } else if let urlString, let url = URL(string: urlString), !embedBroken {
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
                colors: [PassportTheme.card, PassportTheme.accentSoft, Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

// MARK: - Social embed

private struct SocialEmbedConfiguration: Equatable {
    enum Platform { case tiktok, instagram }

    let platform: Platform
    let originalURL: URL
    let embedURL: URL

    init?(urlString: String) {
        guard let url = URL(string: urlString), let host = url.host?.lowercased() else { return nil }

        if host.contains("tiktok.com") {
            self.platform = .tiktok
            self.originalURL = url
            // Extract numeric video ID from /@user/video/{ID} paths
            if let id = url.absoluteString
                .components(separatedBy: "/video/").last?
                .components(separatedBy: CharacterSet(charactersIn: "?#/")).first,
               !id.isEmpty, id.allSatisfy(\.isNumber),
               let playerURL = URL(string: "https://www.tiktok.com/player/v1/\(id)?autoplay=1&loop=1&muted=0&controls=1&music_info=0&description=0&rel=0&native_context_menu=0&fullscreen_button=0") {
                self.embedURL = playerURL
            } else {
                self.embedURL = url
            }
        } else if host.contains("instagram.com") {
            self.platform = .instagram
            self.originalURL = url
            // Extract shortcode from /p/{code}/, /reel/{code}/, /tv/{code}/
            let parts = url.pathComponents
            if let idx = parts.firstIndex(where: { ["p", "reel", "tv"].contains($0) }),
               idx + 1 < parts.count,
               !parts[idx + 1].isEmpty,
               let embedURL = URL(string: "https://www.instagram.com/p/\(parts[idx + 1])/embed/") {
                self.embedURL = embedURL
            } else {
                self.embedURL = url
            }
        } else {
            return nil
        }
    }
}

// Detects Instagram "broken post" error pages and notifies Swift so we can hide them.
private let instagramBrokenDetectScript = WKUserScript(
    source: """
    (function() {
        if (!location.hostname.includes('instagram.com')) return;
        function checkBroken() {
            var bodyText = (document.body && document.body.innerText) || '';
            if (bodyText.toLowerCase().includes('may be broken') ||
                bodyText.toLowerCase().includes('post may have been removed') ||
                bodyText.toLowerCase().includes('this page isn') ||
                bodyText.toLowerCase().includes('content unavailable')) {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.embedBroken) {
                    window.webkit.messageHandlers.embedBroken.postMessage('broken');
                }
            }
        }
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', checkBroken);
        } else {
            checkBroken();
        }
        setTimeout(checkBroken, 1500);
    })();
    """,
    injectionTime: .atDocumentEnd,
    forMainFrameOnly: true,
    in: .defaultClient
)

// JavaScript injected into the Instagram embed page (runs in an isolated world,
// bypassing CSP). Hides all social chrome and makes the video fill the screen.
private let instagramStripScript = WKUserScript(
    source: """
    (function() {
        if (!location.hostname.includes('instagram.com')) return;
        function applyVideoFullscreen() {
            var v = document.querySelector('video');
            if (!v) { setTimeout(applyVideoFullscreen, 200); return; }
            var s = document.createElement('style');
            s.textContent = [
                'html,body{background:#000!important;overflow:hidden!important;',
                'margin:0!important;padding:0!important}',
                '*{visibility:hidden!important}',
                'video{visibility:visible!important;position:fixed!important;',
                'inset:0!important;width:100%!important;height:100%!important;',
                'object-fit:cover!important;z-index:9999!important}'
            ].join('');
            document.head.appendChild(s);
            v.muted = false;
            v.loop = true;
            v.play().catch(function(){ v.muted = true; v.play().catch(function(){}); });
        }
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', applyVideoFullscreen);
        } else {
            applyVideoFullscreen();
        }
    })();
    """,
    injectionTime: .atDocumentEnd,
    forMainFrameOnly: true,
    in: .defaultClient  // isolated world — bypasses page CSP
)

private struct SocialEmbedSurface: UIViewRepresentable {
    let configuration: SocialEmbedConfiguration
    let isActive: Bool
    let onBroken: (() -> Void)?

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var loadedConfiguration: SocialEmbedConfiguration?
        var onBroken: (() -> Void)?

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "embedBroken" {
                DispatchQueue.main.async { self.onBroken?() }
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let coordinator = context.coordinator
        coordinator.onBroken = onBroken

        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true

        let wkConfig = WKWebViewConfiguration()
        wkConfig.defaultWebpagePreferences = prefs
        wkConfig.allowsInlineMediaPlayback = true
        wkConfig.mediaTypesRequiringUserActionForPlayback = []
        wkConfig.userContentController.add(coordinator, name: "embedBroken")
        wkConfig.userContentController.addUserScript(instagramBrokenDetectScript)
        wkConfig.userContentController.addUserScript(instagramStripScript)

        let webView = WKWebView(frame: .zero, configuration: wkConfig)
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onBroken = onBroken
        let coordinator = context.coordinator
        if !isActive {
            if coordinator.loadedConfiguration != nil {
                coordinator.loadedConfiguration = nil
                webView.load(URLRequest(url: URL(string: "about:blank")!))
            }
        } else {
            guard coordinator.loadedConfiguration != configuration else { return }
            coordinator.loadedConfiguration = configuration
            var request = URLRequest(url: configuration.embedURL)
            request.setValue(configuration.originalURL.absoluteString, forHTTPHeaderField: "Referer")
            webView.load(request)
        }
    }
}

// MARK: - Native looping video

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
            LoopingPlayerLayerView(player: playerStore.player, videoGravity: videoGravity)
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

    func pause() { player.pause() }
    func setMuted(_ isMuted: Bool) { player.isMuted = isMuted }

    func setPlaying(_ isPlaying: Bool) {
        if isPlaying { player.play() }
        else { player.pause(); player.seek(to: .zero) }
    }

    private func configureAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
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
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
