import SwiftUI

@main
struct VoxCapApp: App {
    @StateObject private var videoStore = VideoStore()
    @StateObject private var transcriptionService = TranscriptionService()
    @StateObject private var translationService = TranslationService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(videoStore)
                .environmentObject(transcriptionService)
                .environmentObject(translationService)
        }
    }
}

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            BrowserView()
                .tabItem {
                    Image(systemName: "globe")
                    Text("Browse")
                }
                .tag(0)

            VideoListView()
                .tabItem {
                    Image(systemName: "film.stack")
                    Text("Videos")
                }
                .tag(1)

            SettingsView()
                .tabItem {
                    Image(systemName: "gear")
                    Text("Settings")
                }
                .tag(2)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(VideoStore())
        .environmentObject(TranscriptionService())
        .environmentObject(TranslationService())
}
