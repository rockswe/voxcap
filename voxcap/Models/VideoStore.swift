import Foundation
import Combine

@MainActor
class VideoStore: ObservableObject {
    @Published var downloadedVideos: [DownloadedVideo] = []
    @Published var detectedVideos: [DetectedVideo] = []
    @Published var activeDownloads: [UUID: Double] = [:]  // id -> progress

    private let videosDirectory: URL
    private let metadataFile: URL

    init() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        videosDirectory = documentsPath.appendingPathComponent("Videos", isDirectory: true)
        metadataFile = documentsPath.appendingPathComponent("videos_metadata.json")

        createVideosDirectoryIfNeeded()
        loadMetadata()
    }

    private func createVideosDirectoryIfNeeded() {
        if !FileManager.default.fileExists(atPath: videosDirectory.path) {
            try? FileManager.default.createDirectory(at: videosDirectory, withIntermediateDirectories: true)
        }
    }

    private func loadMetadata() {
        guard FileManager.default.fileExists(atPath: metadataFile.path),
              let data = try? Data(contentsOf: metadataFile),
              let videos = try? JSONDecoder().decode([DownloadedVideo].self, from: data) else {
            return
        }
        downloadedVideos = videos.filter { FileManager.default.fileExists(atPath: $0.localPath) }
    }

    private func saveMetadata() {
        guard let data = try? JSONEncoder().encode(downloadedVideos) else { return }
        try? data.write(to: metadataFile)
    }

    func addDetectedVideo(_ video: DetectedVideo) {
        if !detectedVideos.contains(where: { $0.url == video.url }) {
            detectedVideos.append(video)
        }
    }

    func clearDetectedVideos() {
        detectedVideos.removeAll()
    }

    func addDownloadedVideo(_ video: DownloadedVideo) {
        downloadedVideos.append(video)
        saveMetadata()
    }

    func updateVideo(_ video: DownloadedVideo) {
        if let index = downloadedVideos.firstIndex(where: { $0.id == video.id }) {
            downloadedVideos[index] = video
            saveMetadata()
        }
    }

    func deleteVideo(_ video: DownloadedVideo) {
        try? FileManager.default.removeItem(atPath: video.localPath)
        downloadedVideos.removeAll { $0.id == video.id }
        saveMetadata()
    }

    func videoPath(for filename: String) -> URL {
        videosDirectory.appendingPathComponent(filename)
    }

    func updateDownloadProgress(id: UUID, progress: Double) {
        activeDownloads[id] = progress
    }

    func removeDownloadProgress(id: UUID) {
        activeDownloads.removeValue(forKey: id)
    }
}
