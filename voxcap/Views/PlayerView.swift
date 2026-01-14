import SwiftUI
import AVKit

struct PlayerView: View {
    @EnvironmentObject var videoStore: VideoStore
    let video: DownloadedVideo

    @State private var player: AVPlayer?
    @State private var currentTime: TimeInterval = 0
    @State private var showOriginalText = false
    @State private var captionFontSize: CGFloat = 18
    @State private var timeObserver: Any?

    var currentSubtitle: Subtitle? {
        video.subtitles?.subtitle(at: currentTime)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Video Player
                if let player = player {
                    VideoPlayer(player: player)
                        .ignoresSafeArea()
                } else {
                    Color.black
                        .ignoresSafeArea()
                        .overlay {
                            ProgressView()
                                .tint(.white)
                        }
                }

                // Caption Overlay
                VStack {
                    Spacer()

                    if let subtitle = currentSubtitle {
                        CaptionView(
                            subtitle: subtitle,
                            showOriginal: showOriginalText,
                            fontSize: captionFontSize
                        )
                        .padding(.horizontal)
                        .padding(.bottom, geometry.safeAreaInsets.bottom + 60)
                    }
                }
            }
        }
        .navigationTitle(video.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { showOriginalText.toggle() }) {
                        Label(
                            showOriginalText ? "Hide Chinese" : "Show Chinese",
                            systemImage: showOriginalText ? "text.badge.minus" : "text.badge.plus"
                        )
                    }

                    Menu("Caption Size") {
                        Button("Small") { captionFontSize = 14 }
                        Button("Medium") { captionFontSize = 18 }
                        Button("Large") { captionFontSize = 22 }
                        Button("Extra Large") { captionFontSize = 26 }
                    }

                    if video.subtitles != nil {
                        Divider()
                        Button(action: exportSRT) {
                            Label("Export SRT", systemImage: "square.and.arrow.up")
                        }
                        Button(action: exportVTT) {
                            Label("Export VTT", systemImage: "square.and.arrow.up")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            cleanupPlayer()
        }
    }

    private func setupPlayer() {
        let playerItem = AVPlayerItem(url: video.localURL)
        let newPlayer = AVPlayer(playerItem: playerItem)

        // Use AVPlayer's periodic time observer for accurate subtitle sync
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [self] time in
            currentTime = time.seconds
        }

        player = newPlayer
        newPlayer.play()
    }

    private func cleanupPlayer() {
        // Remove time observer to prevent memory leak
        if let observer = timeObserver, let player = player {
            player.removeTimeObserver(observer)
        }
        timeObserver = nil
        player?.pause()
        player = nil
    }

    private func exportSRT() {
        guard let subtitles = video.subtitles else { return }
        let srtContent = subtitles.toSRT()
        shareFile(content: srtContent, filename: "\(video.title).srt")
    }

    private func exportVTT() {
        guard let subtitles = video.subtitles else { return }
        let vttContent = subtitles.toVTT()
        shareFile(content: vttContent, filename: "\(video.title).vtt")
    }

    private func shareFile(content: String, filename: String) {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? content.write(to: tempURL, atomically: true, encoding: .utf8)

        let activityVC = UIActivityViewController(
            activityItems: [tempURL],
            applicationActivities: nil
        )

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}

// MARK: - Caption View

struct CaptionView: View {
    let subtitle: Subtitle
    let showOriginal: Bool
    let fontSize: CGFloat

    var body: some View {
        VStack(spacing: 4) {
            // English translation
            Text(subtitle.translatedText)
                .font(.system(size: fontSize, weight: .medium))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.75))
                )

            // Original Chinese (optional)
            if showOriginal {
                Text(subtitle.originalText)
                    .font(.system(size: fontSize - 2))
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.black.opacity(0.6))
                    )
            }
        }
        .animation(.easeInOut(duration: 0.2), value: subtitle.id)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PlayerView(video: DownloadedVideo(
            originalURL: "https://example.com/video.mp4",
            localPath: "/path/to/video.mp4",
            title: "Sample Video",
            fileSize: 1024 * 1024 * 50,
            subtitles: [
                Subtitle(startTime: 0, endTime: 3, originalText: "你好世界", translatedText: "Hello World"),
                Subtitle(startTime: 3, endTime: 6, originalText: "欢迎观看", translatedText: "Welcome to watch")
            ]
        ))
        .environmentObject(VideoStore())
    }
}
