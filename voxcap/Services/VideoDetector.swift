import Foundation
import WebKit

class VideoDetector: NSObject, WKScriptMessageHandler {
    weak var videoStore: VideoStore?
    private var currentPageURL: String?
    private var currentPageTitle: String?

    static let detectionScript = """
    (function() {
        if (window.__voxcapInjected) return;
        window.__voxcapInjected = true;

        const detected = {
            videos: [],
            streams: []
        };

        function sendDetected() {
            const unique = {
                videos: [...new Map(detected.videos.map(v => [v.url, v])).values()],
                streams: [...new Map(detected.streams.map(s => [s.url, s])).values()]
            };
            if (unique.videos.length > 0 || unique.streams.length > 0) {
                window.webkit.messageHandlers.videoDetected.postMessage(JSON.stringify(unique));
            }
        }

        // 1. Find existing <video> elements
        function scanVideoElements() {
            document.querySelectorAll('video').forEach(video => {
                if (video.src && video.src.length > 0) {
                    detected.videos.push({
                        url: video.src,
                        type: guessType(video.src),
                        quality: video.videoHeight ? video.videoHeight + 'p' : null
                    });
                }
                video.querySelectorAll('source').forEach(source => {
                    if (source.src && source.src.length > 0) {
                        detected.videos.push({
                            url: source.src,
                            type: source.type || guessType(source.src),
                            quality: null
                        });
                    }
                });
            });
        }

        function guessType(url) {
            if (!url) return 'unknown';
            const lower = url.toLowerCase();
            if (lower.includes('.m3u8')) return 'hls';
            if (lower.includes('.mp4')) return 'mp4';
            if (lower.includes('.webm')) return 'webm';
            return 'unknown';
        }

        // 2. Monitor XHR requests
        const originalXHROpen = XMLHttpRequest.prototype.open;
        XMLHttpRequest.prototype.open = function(method, url) {
            if (typeof url === 'string') {
                const lower = url.toLowerCase();
                if (lower.includes('.m3u8') || lower.includes('.mp4') ||
                    lower.includes('/video') || lower.includes('playurl')) {
                    detected.streams.push({
                        url: url,
                        type: guessType(url),
                        source: 'xhr'
                    });
                    sendDetected();
                }
            }
            return originalXHROpen.apply(this, arguments);
        };

        // 3. Monitor Fetch requests
        const originalFetch = window.fetch;
        window.fetch = function(resource, init) {
            const url = typeof resource === 'string' ? resource : resource.url;
            if (url) {
                const lower = url.toLowerCase();
                if (lower.includes('.m3u8') || lower.includes('.mp4') ||
                    lower.includes('/video') || lower.includes('playurl') ||
                    lower.includes('.ts')) {
                    detected.streams.push({
                        url: url,
                        type: guessType(url),
                        source: 'fetch'
                    });
                    sendDetected();
                }
            }
            return originalFetch.apply(this, arguments);
        };

        // 4. Check Chinese player configs
        function checkPlayerConfigs() {
            const configKeys = [
                '__playinfo__',
                'PLAYER_CONFIG',
                'VIDEO_PLAYER_CONFIG',
                'videoInfo',
                '__INITIAL_STATE__',
                'player'
            ];

            configKeys.forEach(key => {
                try {
                    const config = window[key];
                    if (config) {
                        const urls = extractVideoURLs(config);
                        urls.forEach(url => {
                            detected.videos.push({
                                url: url,
                                type: guessType(url),
                                source: key
                            });
                        });
                    }
                } catch(e) {}
            });
        }

        function extractVideoURLs(obj, depth = 0) {
            const urls = [];
            if (depth > 15 || !obj) return urls;

            if (typeof obj === 'string') {
                if (isVideoURL(obj)) urls.push(obj);
            } else if (Array.isArray(obj)) {
                obj.forEach(item => urls.push(...extractVideoURLs(item, depth + 1)));
            } else if (typeof obj === 'object') {
                for (const key in obj) {
                    const lower = key.toLowerCase();
                    if (lower.includes('url') || lower.includes('src') ||
                        lower.includes('video') || lower.includes('play')) {
                        urls.push(...extractVideoURLs(obj[key], depth + 1));
                    }
                }
            }
            return urls;
        }

        function isVideoURL(str) {
            if (typeof str !== 'string') return false;
            const lower = str.toLowerCase();
            return (str.startsWith('http') || str.startsWith('//')) &&
                   (lower.includes('.mp4') || lower.includes('.m3u8') ||
                    lower.includes('.webm') || lower.includes('.ts') ||
                    lower.includes('/video'));
        }

        // 5. Observe DOM for dynamically added videos
        const observer = new MutationObserver((mutations) => {
            let hasNewVideo = false;
            mutations.forEach(mutation => {
                mutation.addedNodes.forEach(node => {
                    if (node.nodeName === 'VIDEO' ||
                        (node.querySelectorAll && node.querySelectorAll('video').length > 0)) {
                        hasNewVideo = true;
                    }
                });
            });
            if (hasNewVideo) {
                setTimeout(() => {
                    scanVideoElements();
                    sendDetected();
                }, 500);
            }
        });

        observer.observe(document.body, {
            childList: true,
            subtree: true
        });

        // Initial scan
        setTimeout(() => {
            scanVideoElements();
            checkPlayerConfigs();
            sendDetected();
        }, 1000);

        // Periodic re-scan for lazy-loaded content
        setInterval(() => {
            scanVideoElements();
            checkPlayerConfigs();
            sendDetected();
        }, 3000);
    })();
    """

    @MainActor
    func updatePageInfo(url: String?, title: String?) {
        currentPageURL = url
        currentPageTitle = title
    }

    // WKScriptMessageHandler
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "videoDetected",
              let jsonString = message.body as? String,
              let data = jsonString.data(using: .utf8) else {
            return
        }

        do {
            let result = try JSONDecoder().decode(DetectionResult.self, from: data)
            Task { @MainActor in
                processDetectionResult(result)
            }
        } catch {
            print("Failed to decode detection result: \(error)")
        }
    }

    @MainActor
    private func processDetectionResult(_ result: DetectionResult) {
        // Process video elements
        for video in result.videos {
            guard let rawURL = video.url, !rawURL.isEmpty else { continue }
            guard let url = normalizeURL(rawURL) else { continue }

            let detected = DetectedVideo(
                url: url,
                type: parseVideoType(video.type),
                quality: video.quality,
                pageURL: currentPageURL,
                pageTitle: currentPageTitle
            )
            videoStore?.addDetectedVideo(detected)
        }

        // Process streams
        for stream in result.streams {
            guard let rawURL = stream.url, !rawURL.isEmpty else { continue }
            guard let url = normalizeURL(rawURL) else { continue }

            let detected = DetectedVideo(
                url: url,
                type: parseVideoType(stream.type),
                pageURL: currentPageURL,
                pageTitle: currentPageTitle
            )
            videoStore?.addDetectedVideo(detected)
        }
    }

    private func normalizeURL(_ url: String) -> String? {
        // Handle protocol-relative URLs
        if url.hasPrefix("//") {
            return "https:" + url
        }
        // Only accept http/https URLs
        if url.hasPrefix("http://") || url.hasPrefix("https://") {
            return url
        }
        return nil
    }

    private func parseVideoType(_ typeString: String?) -> VideoType {
        switch typeString?.lowercased() {
        case "mp4", "video/mp4": return .mp4
        case "hls", "application/x-mpegurl", "application/vnd.apple.mpegurl": return .hls
        case "webm", "video/webm": return .webm
        default: return .unknown
        }
    }
}

// MARK: - Detection Result Models

private struct DetectionResult: Codable {
    let videos: [VideoInfo]
    let streams: [StreamInfo]
}

private struct VideoInfo: Codable {
    let url: String?
    let type: String?
    let quality: String?
    let source: String?
}

private struct StreamInfo: Codable {
    let url: String?
    let type: String?
    let source: String?
}
