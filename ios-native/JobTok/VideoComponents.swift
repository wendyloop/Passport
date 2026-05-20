import SwiftUI
import AVFoundation
import UIKit

struct RemoteVideoSurface: View {
    let urlString: String?
    var isActive: Bool = true

    var body: some View {
        if let urlString, let url = URL(string: urlString) {
            LoopingVideoSurface(url: url, isActive: isActive)
        } else {
            LinearGradient(
                colors: [
                    PassportTheme.card,
                    Color(red: 0.09, green: 0.16, blue: 0.28),
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
    @StateObject private var playerStore = LoopingPlayerStore()

    var body: some View {
        LoopingPlayerLayerView(player: playerStore.player)
            .onAppear {
                playerStore.configure(url: url)
                playerStore.setPlaying(isActive)
            }
            .onChange(of: isActive) { _, newValue in
                playerStore.setPlaying(newValue)
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
    }

    func pause() {
        player.pause()
    }

    func setPlaying(_ isPlaying: Bool) {
        if isPlaying {
            player.play()
        } else {
            player.pause()
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

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        uiView.playerLayer.player = player
        uiView.playerLayer.videoGravity = .resizeAspectFill
    }
}

private final class PlayerContainerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        self.layer as! AVPlayerLayer
    }
}
