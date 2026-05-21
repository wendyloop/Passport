import SwiftUI
import AVFoundation
import UIKit

struct RemoteVideoSurface: View {
    let urlString: String?
    var isActive: Bool = true
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill
    var autoPlay: Bool = true
    var allowsTapToTogglePlayback: Bool = false
    var showsPlayOverlayWhenPaused: Bool = false

    var body: some View {
        if let urlString, let url = URL(string: urlString) {
            LoopingVideoSurface(
                url: url,
                isActive: isActive,
                videoGravity: videoGravity,
                autoPlay: autoPlay,
                allowsTapToTogglePlayback: allowsTapToTogglePlayback,
                showsPlayOverlayWhenPaused: showsPlayOverlayWhenPaused
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

struct LoopingVideoSurface: View {
    let url: URL
    let isActive: Bool
    let videoGravity: AVLayerVideoGravity
    let autoPlay: Bool
    let allowsTapToTogglePlayback: Bool
    let showsPlayOverlayWhenPaused: Bool

    @StateObject private var playerStore = LoopingPlayerStore()
    @State private var userInitiatedPlayback = false

    private var shouldPlay: Bool {
        isActive && (autoPlay || userInitiatedPlayback)
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
                    userInitiatedPlayback = true
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
            userInitiatedPlayback.toggle()
            playerStore.setPlaying(shouldPlay)
        }
        .onAppear {
            playerStore.configure(url: url)
            playerStore.setPlaying(shouldPlay)
        }
        .onChange(of: isActive) { _, _ in
            playerStore.setPlaying(shouldPlay)
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
