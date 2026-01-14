import Foundation

struct DetectedVideo: Identifiable, Codable, Hashable {
    let id: UUID
    let url: String
    let type: VideoType
    let quality: String?
    let size: Int64?
    let detectedAt: Date
    let pageURL: String?
    let pageTitle: String?

    init(
        id: UUID = UUID(),
        url: String,
        type: VideoType,
        quality: String? = nil,
        size: Int64? = nil,
        detectedAt: Date = Date(),
        pageURL: String? = nil,
        pageTitle: String? = nil
    ) {
        self.id = id
        self.url = url
        self.type = type
        self.quality = quality
        self.size = size
        self.detectedAt = detectedAt
        self.pageURL = pageURL
        self.pageTitle = pageTitle
    }

    var displayName: String {
        if let title = pageTitle, !title.isEmpty {
            return title
        }
        return URL(string: url)?.lastPathComponent ?? "Unknown Video"
    }

    var sizeDescription: String {
        guard let size = size else { return "Unknown size" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

enum VideoType: String, Codable {
    case mp4
    case hls
    case webm
    case unknown

    var description: String {
        switch self {
        case .mp4: return "MP4"
        case .hls: return "HLS Stream"
        case .webm: return "WebM"
        case .unknown: return "Unknown"
        }
    }
}

struct DownloadedVideo: Identifiable, Codable {
    let id: UUID
    let originalURL: String
    let localPath: String
    let title: String
    let downloadedAt: Date
    let fileSize: Int64
    var transcriptionStatus: TranscriptionStatus
    var subtitles: [Subtitle]?

    init(
        id: UUID = UUID(),
        originalURL: String,
        localPath: String,
        title: String,
        downloadedAt: Date = Date(),
        fileSize: Int64,
        transcriptionStatus: TranscriptionStatus = .notStarted,
        subtitles: [Subtitle]? = nil
    ) {
        self.id = id
        self.originalURL = originalURL
        self.localPath = localPath
        self.title = title
        self.downloadedAt = downloadedAt
        self.fileSize = fileSize
        self.transcriptionStatus = transcriptionStatus
        self.subtitles = subtitles
    }

    var localURL: URL {
        URL(fileURLWithPath: localPath)
    }

    var sizeDescription: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
}

enum TranscriptionStatus: String, Codable {
    case notStarted
    case extractingAudio
    case transcribing
    case translating
    case completed
    case failed

    var description: String {
        switch self {
        case .notStarted: return "Not processed"
        case .extractingAudio: return "Extracting audio..."
        case .transcribing: return "Transcribing Chinese..."
        case .translating: return "Translating to English..."
        case .completed: return "Ready"
        case .failed: return "Failed"
        }
    }
}
