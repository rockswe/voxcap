import SwiftUI
import WebKit

struct BrowserView: View {
    @EnvironmentObject var videoStore: VideoStore
    @StateObject private var webViewState = WebViewState()
    @State private var urlText = "https://www.bilibili.com"
    @State private var showDetectedVideos = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // URL Bar
                HStack(spacing: 8) {
                    Button(action: { webViewState.goBack() }) {
                        Image(systemName: "chevron.left")
                            .foregroundColor(webViewState.canGoBack ? .blue : .gray)
                    }
                    .disabled(!webViewState.canGoBack)

                    Button(action: { webViewState.goForward() }) {
                        Image(systemName: "chevron.right")
                            .foregroundColor(webViewState.canGoForward ? .blue : .gray)
                    }
                    .disabled(!webViewState.canGoForward)

                    TextField("Enter URL", text: $urlText)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .onSubmit {
                            loadURL()
                        }

                    Button(action: { webViewState.reload() }) {
                        Image(systemName: webViewState.isLoading ? "xmark" : "arrow.clockwise")
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.systemBackground))

                // Loading indicator
                if webViewState.isLoading {
                    ProgressView(value: webViewState.loadProgress)
                        .progressViewStyle(.linear)
                }

                // WebView
                WebViewContainer(state: webViewState, videoStore: videoStore)
                    .ignoresSafeArea(edges: .bottom)

                // Detected Videos Bar
                if !videoStore.detectedVideos.isEmpty {
                    Button(action: { showDetectedVideos = true }) {
                        HStack {
                            Image(systemName: "film")
                            Text("\(videoStore.detectedVideos.count) video(s) found")
                            Spacer()
                            Image(systemName: "chevron.up")
                        }
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                    }
                }
            }
            .navigationTitle("Browser")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { videoStore.clearDetectedVideos() }) {
                        Image(systemName: "trash")
                    }
                    .disabled(videoStore.detectedVideos.isEmpty)
                }
            }
            .sheet(isPresented: $showDetectedVideos) {
                DetectedVideosSheet(videos: videoStore.detectedVideos)
            }
            .onAppear {
                if webViewState.currentURL == nil {
                    loadURL()
                }
            }
        }
    }

    private func loadURL() {
        var urlString = urlText.trimmingCharacters(in: .whitespaces)
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            urlString = "https://" + urlString
        }
        if let url = URL(string: urlString) {
            webViewState.load(url)
        }
    }
}

// MARK: - WebView State

class WebViewState: ObservableObject {
    @Published var isLoading = false
    @Published var loadProgress: Double = 0
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var currentURL: URL?
    @Published var currentTitle: String?

    weak var webView: WKWebView?

    func load(_ url: URL) {
        webView?.load(URLRequest(url: url))
    }

    func reload() {
        if isLoading {
            webView?.stopLoading()
        } else {
            webView?.reload()
        }
    }

    func goBack() {
        webView?.goBack()
    }

    func goForward() {
        webView?.goForward()
    }
}

// MARK: - WebView Container

struct WebViewContainer: UIViewRepresentable {
    @ObservedObject var state: WebViewState
    var videoStore: VideoStore

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        // Add video detection script
        let userScript = WKUserScript(
            source: VideoDetector.detectionScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        configuration.userContentController.addUserScript(userScript)

        // Set up message handler
        let detector = context.coordinator.videoDetector
        detector.videoStore = videoStore
        configuration.userContentController.add(detector, name: "videoDetected")
        context.coordinator.userContentController = configuration.userContentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        // Custom user agent to avoid mobile-specific blocks
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

        state.webView = webView
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Update coordinator's reference
        context.coordinator.videoDetector.videoStore = videoStore
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var state: WebViewState
        let videoDetector = VideoDetector()
        weak var userContentController: WKUserContentController?

        init(state: WebViewState) {
            self.state = state
            super.init()
        }

        deinit {
            userContentController?.removeScriptMessageHandler(forName: "videoDetected")
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.state.isLoading = true
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.state.isLoading = false
                self.state.loadProgress = 1.0
                self.state.canGoBack = webView.canGoBack
                self.state.canGoForward = webView.canGoForward
                self.state.currentURL = webView.url
                self.state.currentTitle = webView.title

                self.videoDetector.updatePageInfo(
                    url: webView.url?.absoluteString,
                    title: webView.title
                )
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.state.isLoading = false
            }
        }
    }
}

// MARK: - Detected Videos Sheet

struct DetectedVideosSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var videoStore: VideoStore
    let videos: [DetectedVideo]

    var body: some View {
        NavigationStack {
            List(videos) { video in
                DetectedVideoRow(video: video)
            }
            .navigationTitle("Detected Videos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct DetectedVideoRow: View {
    @EnvironmentObject var videoStore: VideoStore
    let video: DetectedVideo
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(video.displayName)
                .font(.headline)
                .lineLimit(2)

            HStack {
                Label(video.type.description, systemImage: "film")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let quality = video.quality {
                    Text(quality)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isDownloading {
                    ProgressView(value: downloadProgress)
                        .frame(width: 60)
                } else {
                    Button(action: downloadVideo) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(video.url)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private func downloadVideo() {
        isDownloading = true
        errorMessage = nil

        Task {
            let downloader = VideoDownloader()
            let filename = "\(UUID().uuidString).mp4"
            let destination = videoStore.videoPath(for: filename)

            do {
                let localURL = try await downloader.download(
                    video: video,
                    to: destination
                ) { progress in
                    Task { @MainActor in
                        self.downloadProgress = progress
                    }
                }

                let attributes = try FileManager.default.attributesOfItem(atPath: localURL.path)
                let fileSize = (attributes[.size] as? Int64) ?? 0

                let downloadedVideo = DownloadedVideo(
                    originalURL: video.url,
                    localPath: localURL.path,
                    title: video.displayName,
                    fileSize: fileSize
                )

                await MainActor.run {
                    videoStore.addDownloadedVideo(downloadedVideo)
                    isDownloading = false
                }
            } catch {
                await MainActor.run {
                    isDownloading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

#Preview {
    BrowserView()
        .environmentObject(VideoStore())
}
