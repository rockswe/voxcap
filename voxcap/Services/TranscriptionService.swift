import Foundation
import AVFoundation
#if canImport(WhisperKit)
import WhisperKit
#endif

@MainActor
class TranscriptionService: ObservableObject {
    @Published var isModelLoaded = false
    @Published var isLoading = false
    @Published var loadingProgress: Double = 0
    @Published var currentTask: String = ""
    @Published var error: String?

    #if canImport(WhisperKit)
    private var whisperKit: WhisperKit?
    #endif

    private let modelName = "openai/whisper-small"  // Good balance of speed and accuracy

    enum TranscriptionError: Error, LocalizedError {
        case modelNotLoaded
        case audioExtractionFailed
        case transcriptionFailed(String)

        var errorDescription: String? {
            switch self {
            case .modelNotLoaded: return "Whisper model not loaded"
            case .audioExtractionFailed: return "Failed to extract audio from video"
            case .transcriptionFailed(let msg): return "Transcription failed: \(msg)"
            }
        }
    }

    // MARK: - Model Loading

    func loadModel() async {
        guard !isModelLoaded && !isLoading else { return }

        isLoading = true
        currentTask = "Downloading Whisper model..."
        error = nil

        #if canImport(WhisperKit)
        do {
            // Initialize WhisperKit with model download
            whisperKit = try await WhisperKit(
                model: "small",
                downloadBase: nil,
                modelRepo: "argmaxinc/whisperkit-coreml",
                computeOptions: nil
            )
            isModelLoaded = true
            currentTask = ""
        } catch {
            self.error = "Failed to load model: \(error.localizedDescription)"
        }
        #else
        // Fallback when WhisperKit is not available (development)
        // Simulate model loading
        for i in 0...10 {
            try? await Task.sleep(nanoseconds: 200_000_000)
            loadingProgress = Double(i) / 10.0
        }
        isModelLoaded = true
        currentTask = ""
        #endif

        isLoading = false
    }

    // MARK: - Transcription

    func transcribe(videoURL: URL, progress: @escaping (Double, String) -> Void) async throws -> [TranscriptionSegment] {
        guard isModelLoaded else {
            throw TranscriptionError.modelNotLoaded
        }

        // Extract audio
        currentTask = "Extracting audio..."
        progress(0.1, "Extracting audio from video...")

        let audioURL = try await extractAudio(from: videoURL)

        // Transcribe
        currentTask = "Transcribing Chinese audio..."
        progress(0.2, "Transcribing Chinese speech...")

        #if canImport(WhisperKit)
        guard let whisper = whisperKit else {
            throw TranscriptionError.modelNotLoaded
        }

        let result = try await whisper.transcribe(
            audioPath: audioURL.path,
            decodeOptions: DecodingOptions(
                language: "zh",  // Chinese
                task: .transcribe,
                wordTimestamps: true
            )
        )

        // Convert to our segment format
        var segments: [TranscriptionSegment] = []
        for transcription in result {
            for segment in transcription.segments {
                segments.append(TranscriptionSegment(
                    startTime: TimeInterval(segment.start),
                    endTime: TimeInterval(segment.end),
                    text: segment.text
                ))
            }
        }

        // Cleanup temp audio file
        try? FileManager.default.removeItem(at: audioURL)

        currentTask = ""
        progress(1.0, "Transcription complete")
        return segments
        #else
        // Development fallback - return mock data
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        progress(1.0, "Transcription complete")
        currentTask = ""

        return [
            TranscriptionSegment(startTime: 0, endTime: 3, text: "你好，欢迎观看这个视频"),
            TranscriptionSegment(startTime: 3, endTime: 6, text: "今天我们要讨论一个重要的话题"),
            TranscriptionSegment(startTime: 6, endTime: 10, text: "请继续观看以了解更多内容")
        ]
        #endif
    }

    // MARK: - Audio Extraction

    private func extractAudio(from videoURL: URL) async throws -> URL {
        let asset = AVAsset(url: videoURL)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw TranscriptionError.audioExtractionFailed
        }

        // First export as M4A
        let m4aURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        exportSession.outputURL = m4aURL
        exportSession.outputFileType = .m4a

        await exportSession.export()

        if exportSession.status != .completed {
            throw TranscriptionError.audioExtractionFailed
        }

        // Convert M4A to WAV for Whisper (16kHz mono)
        let convertedURL = try await convertToWAV(m4aURL)
        try? FileManager.default.removeItem(at: m4aURL)

        return convertedURL
    }

    private func convertToWAV(_ inputURL: URL) async throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        let asset = AVAsset(url: inputURL)
        let reader = try AVAssetReader(asset: asset)

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = audioTracks.first else {
            throw TranscriptionError.audioExtractionFailed
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        reader.add(readerOutput)

        guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .wav) else {
            throw TranscriptionError.audioExtractionFailed
        }

        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings)
        writer.add(writerInput)

        guard reader.startReading() else {
            throw TranscriptionError.audioExtractionFailed
        }

        guard writer.startWriting() else {
            throw TranscriptionError.audioExtractionFailed
        }

        writer.startSession(atSourceTime: .zero)

        while let buffer = readerOutput.copyNextSampleBuffer() {
            if !writerInput.append(buffer) {
                // Append failed - check writer status
                if writer.status == .failed {
                    throw TranscriptionError.audioExtractionFailed
                }
                break
            }
        }

        // Check reader completed successfully
        if reader.status == .failed {
            throw TranscriptionError.audioExtractionFailed
        }

        writerInput.markAsFinished()
        await writer.finishWriting()

        // Verify writer completed and file exists
        if writer.status != .completed {
            throw TranscriptionError.audioExtractionFailed
        }

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw TranscriptionError.audioExtractionFailed
        }

        return outputURL
    }
}

// MARK: - Transcription Segment

struct TranscriptionSegment {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
}
