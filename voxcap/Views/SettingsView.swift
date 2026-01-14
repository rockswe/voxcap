import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var transcriptionService: TranscriptionService
    @EnvironmentObject var videoStore: VideoStore
    @AppStorage("captionFontSize") private var captionFontSize: Double = 18
    @AppStorage("showOriginalByDefault") private var showOriginalByDefault = false
    @AppStorage("autoProcessVideos") private var autoProcessVideos = false

    @State private var showClearConfirmation = false
    @State private var storageUsed: String = "Calculating..."

    var body: some View {
        NavigationStack {
            Form {
                // Model Status Section
                Section("Whisper Model") {
                    HStack {
                        Text("Status")
                        Spacer()
                        if transcriptionService.isLoading {
                            ProgressView()
                        } else if transcriptionService.isModelLoaded {
                            Label("Ready", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Label("Not Loaded", systemImage: "xmark.circle.fill")
                                .foregroundColor(.orange)
                        }
                    }

                    if !transcriptionService.isModelLoaded && !transcriptionService.isLoading {
                        Button("Download Model (~500MB)") {
                            Task {
                                await transcriptionService.loadModel()
                            }
                        }
                    }

                    if let error = transcriptionService.error {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                // Caption Settings
                Section("Captions") {
                    HStack {
                        Text("Font Size")
                        Spacer()
                        Picker("", selection: $captionFontSize) {
                            Text("Small").tag(14.0)
                            Text("Medium").tag(18.0)
                            Text("Large").tag(22.0)
                            Text("Extra Large").tag(26.0)
                        }
                        .pickerStyle(.menu)
                    }

                    Toggle("Show Chinese by Default", isOn: $showOriginalByDefault)
                }

                // Processing Settings
                Section("Processing") {
                    Toggle("Auto-process after Download", isOn: $autoProcessVideos)

                    Text("When enabled, videos will automatically be transcribed and translated after downloading.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Storage Section
                Section("Storage") {
                    HStack {
                        Text("Videos Storage")
                        Spacer()
                        Text(storageUsed)
                            .foregroundColor(.secondary)
                    }

                    Button("Clear All Videos", role: .destructive) {
                        showClearConfirmation = true
                    }
                }

                // About Section
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }

                    Link(destination: URL(string: "https://github.com/argmaxinc/WhisperKit")!) {
                        HStack {
                            Text("WhisperKit")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.secondary)
                        }
                    }

                    Link(destination: URL(string: "https://github.com/Helsinki-NLP/Opus-MT")!) {
                        HStack {
                            Text("OPUS-MT")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Privacy Info
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Privacy First", systemImage: "lock.shield")
                            .font(.headline)

                        Text("All processing happens on your device. No audio or video data is ever sent to external servers.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                calculateStorageUsed()
            }
            .confirmationDialog(
                "Clear All Videos?",
                isPresented: $showClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear All", role: .destructive) {
                    clearAllVideos()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will delete all downloaded videos and their transcriptions. This cannot be undone.")
            }
        }
    }

    private func calculateStorageUsed() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let videosPath = documentsPath.appendingPathComponent("Videos")

        var totalSize: Int64 = 0

        if let enumerator = FileManager.default.enumerator(
            at: videosPath,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator {
                if let attributes = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                   let size = attributes.fileSize {
                    totalSize += Int64(size)
                }
            }
        }

        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        storageUsed = formatter.string(fromByteCount: totalSize)
    }

    private func clearAllVideos() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let videosPath = documentsPath.appendingPathComponent("Videos")

        try? FileManager.default.removeItem(at: videosPath)
        try? FileManager.default.createDirectory(at: videosPath, withIntermediateDirectories: true)

        // Clear metadata file
        let metadataPath = documentsPath.appendingPathComponent("videos_metadata.json")
        try? FileManager.default.removeItem(at: metadataPath)

        // Sync VideoStore in-memory state
        videoStore.downloadedVideos.removeAll()
        videoStore.detectedVideos.removeAll()

        calculateStorageUsed()
    }
}

#Preview {
    SettingsView()
        .environmentObject(TranscriptionService())
        .environmentObject(VideoStore())
}
