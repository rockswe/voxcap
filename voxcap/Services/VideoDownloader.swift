import Foundation
import AVFoundation

actor VideoDownloader {
    private var activeTasks: [UUID: URLSessionDownloadTask] = [:]

    enum DownloadError: Error, LocalizedError {
        case invalidURL
        case downloadFailed(String)
        case hlsParsingFailed
        case segmentDownloadFailed
        case exportFailed

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid video URL"
            case .downloadFailed(let msg): return "Download failed: \(msg)"
            case .hlsParsingFailed: return "Failed to parse HLS playlist"
            case .segmentDownloadFailed: return "Failed to download video segments"
            case .exportFailed: return "Failed to export video"
            }
        }
    }

    // MARK: - Public Methods

    func download(
        video: DetectedVideo,
        to destination: URL,
        progress: @escaping (Double) -> Void
    ) async throws -> URL {
        switch video.type {
        case .mp4, .webm, .unknown:
            return try await downloadDirect(url: video.url, to: destination, progress: progress)
        case .hls:
            return try await downloadHLS(url: video.url, to: destination, progress: progress)
        }
    }

    func cancelDownload(id: UUID) {
        activeTasks[id]?.cancel()
        activeTasks.removeValue(forKey: id)
    }

    // MARK: - Direct Download (MP4/WebM)

    private func downloadDirect(
        url: String,
        to destination: URL,
        progress: @escaping (Double) -> Void
    ) async throws -> URL {
        guard let videoURL = URL(string: url) else {
            throw DownloadError.invalidURL
        }

        var request = URLRequest(url: videoURL)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        // Use bytes async sequence for progress tracking
        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw DownloadError.downloadFailed("Server returned error")
        }

        let expectedLength = httpResponse.expectedContentLength
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        // Download with progress
        var downloadedData = Data()
        downloadedData.reserveCapacity(expectedLength > 0 ? Int(expectedLength) : 10_000_000)

        var lastReportedProgress: Double = 0
        for try await byte in asyncBytes {
            downloadedData.append(byte)

            // Report progress every 1%
            if expectedLength > 0 {
                let currentProgress = Double(downloadedData.count) / Double(expectedLength)
                if currentProgress - lastReportedProgress >= 0.01 {
                    lastReportedProgress = currentProgress
                    await MainActor.run { progress(currentProgress) }
                }
            }
        }

        // Write to temp file
        try downloadedData.write(to: tempURL)

        // Move to final destination
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempURL, to: destination)

        await MainActor.run { progress(1.0) }
        return destination
    }

    // MARK: - HLS Download

    private func downloadHLS(
        url: String,
        to destination: URL,
        progress: @escaping (Double) -> Void
    ) async throws -> URL {
        guard let playlistURL = URL(string: url) else {
            throw DownloadError.invalidURL
        }

        // Fetch and parse playlist
        let (playlistData, _) = try await URLSession.shared.data(from: playlistURL)
        guard let playlistContent = String(data: playlistData, encoding: .utf8) else {
            throw DownloadError.hlsParsingFailed
        }

        let segments = parseM3U8(playlistContent, baseURL: playlistURL)
        if segments.isEmpty {
            // Might be a master playlist - try to find a variant
            if let variantURL = findVariantPlaylist(playlistContent, baseURL: playlistURL) {
                return try await downloadHLS(url: variantURL.absoluteString, to: destination, progress: progress)
            }
            throw DownloadError.hlsParsingFailed
        }

        // Download segments
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        var downloadedSegments: [URL] = []
        var failedSegmentCount = 0
        let totalSegments = segments.count
        let maxFailureRate = 0.1  // Allow up to 10% segment failures

        for (index, segmentURL) in segments.enumerated() {
            let segmentFile = tempDir.appendingPathComponent("segment_\(String(format: "%05d", index)).ts")

            do {
                let (data, _) = try await URLSession.shared.data(from: segmentURL)
                try data.write(to: segmentFile)
                downloadedSegments.append(segmentFile)

                let currentProgress = Double(index + 1) / Double(totalSegments) * 0.8  // 80% for download
                await MainActor.run { progress(currentProgress) }
            } catch {
                failedSegmentCount += 1
                print("Failed to download segment \(index): \(error)")

                // Check if failure rate exceeds threshold
                let failureRate = Double(failedSegmentCount) / Double(totalSegments)
                if failureRate > maxFailureRate {
                    // Clean up temp directory before throwing
                    try? FileManager.default.removeItem(at: tempDir)
                    throw DownloadError.downloadFailed("Too many segment failures (\(failedSegmentCount)/\(totalSegments))")
                }
            }
        }

        if downloadedSegments.isEmpty {
            try? FileManager.default.removeItem(at: tempDir)
            throw DownloadError.segmentDownloadFailed
        }

        // Concatenate segments
        await MainActor.run { progress(0.85) }
        let outputURL = try await concatenateSegments(downloadedSegments, to: destination)

        // Cleanup temp files
        try? FileManager.default.removeItem(at: tempDir)

        await MainActor.run { progress(1.0) }
        return outputURL
    }

    private func parseM3U8(_ content: String, baseURL: URL) -> [URL] {
        var segments: [URL] = []
        let lines = content.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            // This is a segment URL
            if let segmentURL = URL(string: trimmed, relativeTo: baseURL)?.absoluteURL {
                segments.append(segmentURL)
            } else if let segmentURL = URL(string: trimmed) {
                segments.append(segmentURL)
            }
        }

        return segments
    }

    private func findVariantPlaylist(_ content: String, baseURL: URL) -> URL? {
        let lines = content.components(separatedBy: .newlines)
        var nextIsVariant = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("#EXT-X-STREAM-INF") {
                nextIsVariant = true
                continue
            }

            if nextIsVariant && !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                return URL(string: trimmed, relativeTo: baseURL)?.absoluteURL
            }
        }

        return nil
    }

    private func concatenateSegments(_ segments: [URL], to output: URL) async throws -> URL {
        // Create a file list for concatenation
        let listFile = FileManager.default.temporaryDirectory.appendingPathComponent("segments.txt")
        let listContent = segments.map { "file '\($0.path)'" }.joined(separator: "\n")
        try listContent.write(to: listFile, atomically: true, encoding: .utf8)

        // Use AVAssetExportSession for proper concatenation
        let composition = AVMutableComposition()

        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ),
        let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw DownloadError.exportFailed
        }

        var currentTime = CMTime.zero

        for segmentURL in segments {
            let asset = AVAsset(url: segmentURL)

            do {
                let duration = try await asset.load(.duration)
                let videoTracks = try await asset.loadTracks(withMediaType: .video)
                let audioTracks = try await asset.loadTracks(withMediaType: .audio)

                if let assetVideoTrack = videoTracks.first {
                    try videoTrack.insertTimeRange(
                        CMTimeRange(start: .zero, duration: duration),
                        of: assetVideoTrack,
                        at: currentTime
                    )
                }

                if let assetAudioTrack = audioTracks.first {
                    try audioTrack.insertTimeRange(
                        CMTimeRange(start: .zero, duration: duration),
                        of: assetAudioTrack,
                        at: currentTime
                    )
                }

                currentTime = CMTimeAdd(currentTime, duration)
            } catch {
                print("Failed to add segment: \(error)")
            }
        }

        // Export
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw DownloadError.exportFailed
        }

        try? FileManager.default.removeItem(at: output)
        exportSession.outputURL = output
        exportSession.outputFileType = .mp4

        await exportSession.export()

        if exportSession.status == .completed {
            return output
        } else {
            throw DownloadError.exportFailed
        }
    }
}

