import Foundation

/// Represents an audiobook in the library
struct Book: Identifiable, Codable {
    let id: String
    let title: String
    let author: String
    let description: String
    let narratorVoice: String
    let languageCode: String
    let coverImage: String?
    let totalChapters: Int
    let totalDurationSeconds: Double
    let chapters: [Chapter]
    
    enum CodingKeys: String, CodingKey {
        case id, title, author, description
        case narratorVoice = "narrator_voice"
        case languageCode = "language_code"
        case coverImage = "cover_image"
        case totalChapters = "total_chapters"
        case totalDurationSeconds = "total_duration_seconds"
        case chapters
    }
    
    var formattedDuration: String {
        TimeFormatter.formatDuration(totalDurationSeconds)
    }
}

/// Represents a single chapter in a book
struct Chapter: Identifiable, Codable {
    let number: Int
    let title: String
    let audioFile: String?
    let durationSeconds: Double
    /// Embedded transcript (loaded from API, not separate file)
    let transcript: Transcript?
    
    var id: Int { number }
    
    enum CodingKeys: String, CodingKey {
        case number, title
        case audioFile = "audio_file"
        case durationSeconds = "duration_seconds"
        case transcript
    }
    
    var formattedDuration: String {
        TimeFormatter.formatTime(durationSeconds)
    }
}

/// A segment of text with timing (sentence-level)
struct TranscriptSegment: Codable {
    let text: String
    let start: Double
    let end: Double
}

/// Transcript with sentence-level timestamps
struct Transcript: Codable {
    let text: String
    let duration: Double
    let segments: [TranscriptSegment]
    
    /// Find segment at given time
    func segment(at time: Double) -> TranscriptSegment? {
        segments.first { time >= $0.start && time < $0.end }
    }
    
    /// Find segment index at given time
    func segmentIndex(at time: Double) -> Int? {
        segments.firstIndex { time >= $0.start && time < $0.end }
    }
    
    /// Generate a context window of segments around a given time
    func contextWindow(at time: Double, windowSize: Int = 3) -> [TranscriptSegment] {
        guard !segments.isEmpty else { return [] }
        
        let currentIndex = segmentIndex(at: time) ?? 0
        let startIdx = max(0, currentIndex - windowSize)
        let endIdx = min(segments.count - 1, currentIndex + windowSize)
        
        return Array(segments[startIdx...endIdx])
    }
    
    /// Generate a context text string around a given time
    func contextText(at time: Double, windowSize: Int = 3) -> String {
        let window = contextWindow(at: time, windowSize: windowSize)
        if window.isEmpty {
            return String(text.prefix(500))
        }
        return window.map { $0.text }.joined(separator: " ")
    }
}

// MARK: - Sample Data

extension Book {
    static let sample = Book(
        id: "sample-book",
        title: "Sample Book",
        author: "Sample Author",
        description: "A sample book for testing.",
        narratorVoice: "Kore",
        languageCode: "en-US",
        coverImage: "cover.jpg",
        totalChapters: 2,
        totalDurationSeconds: 120,
        chapters: [
            Chapter(number: 1, title: "Chapter 1", audioFile: "chapter-01.mp3", durationSeconds: 60, transcript: nil),
            Chapter(number: 2, title: "Chapter 2", audioFile: "chapter-02.mp3", durationSeconds: 60, transcript: nil),
        ]
    )
}
