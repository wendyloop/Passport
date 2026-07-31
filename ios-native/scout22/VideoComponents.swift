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
    var onBroken: (() -> Void)? = nil

    @State private var embedBroken = false

    var body: some View {
        if let urlString, let embed = SocialEmbedConfiguration(urlString: urlString), !embedBroken {
            SocialEmbedSurface(configuration: embed, isActive: isActive, onBroken: {
                embedBroken = true
                onBroken?()
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

    private static let sharedProcessPool = WKProcessPool()

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedConfiguration: SocialEmbedConfiguration?
        var onBroken: (() -> Void)?
        private var brokenFired = false

        func reset() { brokenFired = false }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            probe(webView, delay: 0)
            probe(webView, delay: 2.5)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            fireBroken()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            fireBroken()
        }

        private func probe(_ webView: WKWebView, delay: TimeInterval) {
            let work = { [weak self, weak webView] in
                guard let self, let webView, !self.brokenFired else { return }

                // Instagram redirects removed posts to its root/login — not an embed URL.
                if let url = webView.url {
                    let s = url.absoluteString
                    if !s.hasPrefix("about:") && !s.isEmpty {
                        let isEmbed = s.contains("/p/") || s.contains("/reel/") || s.contains("/tv/")
                            || s.contains("/embed") || s.contains("tiktok.com/player")
                            || s.contains("tiktok.com/@")
                        if !isEmbed { self.fireBroken(); return }
                    }
                }

                // evaluateJavaScript runs in the page's main world — no isolated-world limitations.
                webView.evaluateJavaScript("document.body ? document.body.innerText : ''") { [weak self] result, _ in
                    let text = (result as? String ?? "").lowercased()
                    if self?.isBrokenText(text) == true { self?.fireBroken() }
                }
            }
            delay == 0 ? work() : DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }

        private func isBrokenText(_ text: String) -> Bool {
            guard !text.isEmpty else { return false }
            return text.contains("may be broken")
                || text.contains("post may have been removed")
                || text.contains("sorry, this page")
                || text.contains("page isn't available")
                || text.contains("content isn't available")
                || text.contains("content unavailable")
                || text.contains("video not available")
                || text.contains("this video is unavailable")
                || text.contains("page not found")
        }

        private func fireBroken() {
            guard !brokenFired else { return }
            brokenFired = true
            DispatchQueue.main.async { self.onBroken?() }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let coordinator = context.coordinator
        coordinator.onBroken = onBroken

        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true

        let wkConfig = WKWebViewConfiguration()
        wkConfig.processPool = SocialEmbedSurface.sharedProcessPool
        wkConfig.defaultWebpagePreferences = prefs
        wkConfig.allowsInlineMediaPlayback = true
        wkConfig.mediaTypesRequiringUserActionForPlayback = []
        wkConfig.userContentController.addUserScript(instagramStripScript)

        let webView = WKWebView(frame: .zero, configuration: wkConfig)
        webView.navigationDelegate = coordinator
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onBroken = onBroken
        if !isActive {
            if coordinator.loadedConfiguration != nil {
                coordinator.loadedConfiguration = nil
                webView.load(URLRequest(url: URL(string: "about:blank")!))
            }
        } else {
            guard coordinator.loadedConfiguration != configuration else { return }
            coordinator.loadedConfiguration = configuration
            coordinator.reset()
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
        // Reassigning an AVPlayerLayer's player is not free — SwiftUI calls
        // this on every parent state change (each caption keystroke on the
        // post page), so only touch the layer when something actually moved.
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
        if uiView.playerLayer.videoGravity != videoGravity {
            uiView.playerLayer.videoGravity = videoGravity
        }
    }
}

private final class PlayerContainerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
