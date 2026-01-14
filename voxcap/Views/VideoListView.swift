import SwiftUI

struct VideoListView: View {
    @EnvironmentObject var videoStore: VideoStore
    @EnvironmentObject var transcriptionService: TranscriptionService

    var body: some View {
        NavigationStack {
            Group {
                if videoStore.downloadedVideos.isEmpty {
                    EmptyVideosView()
                } else {
                    List {
                        ForEach(videoStore.downloadedVideos) { video in
                            NavigationLink(destination: PlayerView(video: video)) {
                                VideoRow(video: video)
                            }
                        }
                        .onDelete(perform: deleteVideos)
                    }
                }
            }
            .navigationTitle("My Videos")
            .toolbar {
                if !videoStore.downloadedVideos.isEmpty {
                    EditButton()
                }
            }
        }
    }

    private func deleteVideos(at offsets: IndexSet) {
        // Collect videos to delete first to avoid index shifting issues
        let videosToDelete = offsets.map { videoStore.downloadedVideos[$0] }
        for video in videosToDelete {
            videoStore.deleteVideo(video)
        }
    }
}

struct EmptyVideosView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "film.stack")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Videos Yet")
                .font(.headline)

            Text("Browse Chinese video sites and download videos to get started.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

struct VideoRow: View {
    @EnvironmentObject var videoStore: VideoStore
    @EnvironmentObject var transcriptionService: TranscriptionService
    @EnvironmentObject var translationService: TranslationService
    let video: DownloadedVideo

    @State private var isProcessing = false
    @State private var processingStatus = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Thumbnail placeholder
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 80, height: 45)
                    .overlay {
                        Image(systemName: "play.fill")
                            .foregroundColor(.white)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(video.title)
                        .font(.headline)
                        .lineLimit(2)

                    HStack {
                        Text(video.sizeDescription)
                        Text("•")
                        Text(video.downloadedAt, style: .date)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                Spacer()
            }

            // Transcription status
            HStack {
                statusBadge

                Spacer()

                if video.transcriptionStatus == .notStarted && !isProcessing {
                    Button("Process") {
                        processVideo()
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                }

                if isProcessing {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }

            if isProcessing && !processingStatus.isEmpty {
                Text(processingStatus)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    var statusBadge: some View {
        let status = video.transcriptionStatus

        HStack(spacing: 4) {
            Circle()
                .fill(statusColor(for: status))
                .frame(width: 8, height: 8)

            Text(status.description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func statusColor(for status: TranscriptionStatus) -> Color {
        switch status {
        case .notStarted: return .gray
        case .extractingAudio, .transcribing, .translating: return .orange
        case .completed: return .green
        case .failed: return .red
        }
    }

    private func processVideo() {
        isProcessing = true

        Task {
            // Ensure model is loaded
            if !transcriptionService.isModelLoaded {
                processingStatus = "Loading Whisper model..."
                await transcriptionService.loadModel()
            }

            // Update status
            var updatedVideo = video
            updatedVideo.transcriptionStatus = .transcribing
            await MainActor.run {
                videoStore.updateVideo(updatedVideo)
            }

            do {
                // Transcribe
                processingStatus = "Transcribing Chinese audio..."
                let segments = try await transcriptionService.transcribe(
                    videoURL: video.localURL
                ) { progress, status in
                    Task { @MainActor in
                        processingStatus = status
                    }
                }

                // Translate
                processingStatus = "Translating to English..."
                updatedVideo.transcriptionStatus = .translating
                await MainActor.run {
                    videoStore.updateVideo(updatedVideo)
                }

                // Load translation model if needed (uses shared instance)
                if !translationService.isModelLoaded {
                    await translationService.loadModel()
                }

                let subtitles = try await translationService.translate(segments: segments) { progress in
                    Task { @MainActor in
                        processingStatus = "Translating... \(Int(progress * 100))%"
                    }
                }

                // Save results
                updatedVideo.subtitles = subtitles
                updatedVideo.transcriptionStatus = .completed
                await MainActor.run {
                    videoStore.updateVideo(updatedVideo)
                    isProcessing = false
                    processingStatus = ""
                }

            } catch {
                updatedVideo.transcriptionStatus = .failed
                await MainActor.run {
                    videoStore.updateVideo(updatedVideo)
                    isProcessing = false
                    processingStatus = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
}

#Preview {
    VideoListView()
        .environmentObject(VideoStore())
        .environmentObject(TranscriptionService())
        .environmentObject(TranslationService())
}
