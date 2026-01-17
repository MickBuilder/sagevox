import Foundation

/// Lightweight book info for library listing
struct BookSummary: Identifiable, Codable {
    let id: String
    let title: String
    let author: String
    let description: String
    let coverUrl: String?
    let totalChapters: Int
    let totalDurationSeconds: Double
    
    enum CodingKeys: String, CodingKey {
        case id, title, author, description
        case coverUrl = "cover_url"
        case totalChapters = "total_chapters"
        case totalDurationSeconds = "total_duration_seconds"
    }
    
    var formattedDuration: String {
        TimeFormatter.formatDuration(totalDurationSeconds)
    }
}
