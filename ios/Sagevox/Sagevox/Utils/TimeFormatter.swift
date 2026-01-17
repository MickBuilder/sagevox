import Foundation

/// Utility for shared time and duration formatting
enum TimeFormatter {
    /// Formats a duration in seconds to a string (e.g., "1h 30m" or "45 min")
    static func formatDuration(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes) min"
        }
    }
    
    /// Formats a time in seconds to a string (e.g., "3:45")
    static func formatTime(_ seconds: Double) -> String {
        let mins = Int(abs(seconds)) / 60
        let secs = Int(abs(seconds)) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
