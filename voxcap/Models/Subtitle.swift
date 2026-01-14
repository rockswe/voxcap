import Foundation

struct Subtitle: Identifiable, Codable {
    let id: UUID
    let startTime: TimeInterval
    let endTime: TimeInterval
    let originalText: String  // Chinese
    let translatedText: String  // English

    init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        endTime: TimeInterval,
        originalText: String,
        translatedText: String
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.originalText = originalText
        self.translatedText = translatedText
    }

    var formattedTimeRange: String {
        "\(formatTime(startTime)) --> \(formatTime(endTime))"
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        let milliseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, milliseconds)
    }
}

extension Array where Element == Subtitle {
    func toSRT() -> String {
        var srt = ""
        for (index, subtitle) in self.enumerated() {
            srt += "\(index + 1)\n"
            srt += "\(subtitle.formattedTimeRange)\n"
            srt += "\(subtitle.translatedText)\n\n"
        }
        return srt
    }

    func toVTT() -> String {
        var vtt = "WEBVTT\n\n"
        for subtitle in self {
            let startVTT = formatVTTTime(subtitle.startTime)
            let endVTT = formatVTTTime(subtitle.endTime)
            vtt += "\(startVTT) --> \(endVTT)\n"
            vtt += "\(subtitle.translatedText)\n\n"
        }
        return vtt
    }

    private func formatVTTTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        let milliseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d:%02d.%03d", hours, minutes, seconds, milliseconds)
    }

    func subtitle(at time: TimeInterval) -> Subtitle? {
        first { time >= $0.startTime && time <= $0.endTime }
    }
}
