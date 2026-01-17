import Foundation
import Combine

/// Tracks reading progress for a book
struct ReadingProgress: Codable {
    let bookId: String
    var currentChapter: Int
    var positionSeconds: Double
    var playbackSpeed: Float
    var lastPlayedAt: Date
    var questionsAsked: Int
    var totalListeningSeconds: Double
    
    init(
        bookId: String,
        currentChapter: Int = 1,
        positionSeconds: Double = 0,
        playbackSpeed: Float = 1.0,
        lastPlayedAt: Date = Date(),
        questionsAsked: Int = 0,
        totalListeningSeconds: Double = 0
    ) {
        self.bookId = bookId
        self.currentChapter = currentChapter
        self.positionSeconds = positionSeconds
        self.playbackSpeed = playbackSpeed
        self.lastPlayedAt = lastPlayedAt
        self.questionsAsked = questionsAsked
        self.totalListeningSeconds = totalListeningSeconds
    }
    
    /// Calculate overall progress percentage for a book
    func overallProgress(for book: Book) -> Double {
        guard book.totalDurationSeconds > 0 else { return 0 }
        
        // Sum up completed chapters plus current position
        var completedSeconds: Double = 0
        for chapter in book.chapters where chapter.number < currentChapter {
            completedSeconds += chapter.durationSeconds
        }
        completedSeconds += positionSeconds
        
        return min(completedSeconds / book.totalDurationSeconds, 1.0)
    }
}

// MARK: - Progress Storage

class ProgressTracker: ObservableObject {
    private enum Constants {
        static let minSaveInterval: TimeInterval = 5
    }

    static let shared = ProgressTracker()
    
    @Published private(set) var progress: [String: ReadingProgress] = [:]
    
    private let storageKey = "sagevox_reading_progress"
    private let queue = DispatchQueue(label: "com.sagevox.progress.tracker")
    private var lastSaveTimestamps: [String: Date] = [:]
    
    init() {
        loadProgress()
    }
    
    func getProgress(for bookId: String) -> ReadingProgress {
        queue.sync { progress[bookId] ?? ReadingProgress(bookId: bookId) }
    }
    
    func updateProgress(_ newProgress: ReadingProgress, persist: Bool = true) {
        let updatedProgress = queue.sync { () -> [String: ReadingProgress] in
            var snapshot = progress
            snapshot[newProgress.bookId] = newProgress
            if persist {
                saveToStorage(snapshot)
                lastSaveTimestamps[newProgress.bookId] = Date()
            }
            return snapshot
        }

        DispatchQueue.main.async {
            self.progress = updatedProgress
        }
    }
    
    func updatePosition(for bookId: String, chapter: Int, position: Double) {
        let previousProgress = getProgress(for: bookId)
        var currentProgress = previousProgress
        currentProgress.currentChapter = chapter
        currentProgress.positionSeconds = position
        currentProgress.lastPlayedAt = Date()

        let shouldPersist: Bool = queue.sync {
            let lastSave = lastSaveTimestamps[bookId]
            return lastSave == nil
                || currentProgress.currentChapter != previousProgress.currentChapter
                || Date().timeIntervalSince(lastSave ?? .distantPast) >= Constants.minSaveInterval
        }

        updateProgress(currentProgress, persist: shouldPersist)
    }
    
    func addListeningTime(for bookId: String, seconds: Double) {
        var currentProgress = getProgress(for: bookId)
        currentProgress.totalListeningSeconds += seconds
        updateProgress(currentProgress)
    }
    
    private func loadProgress() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: ReadingProgress].self, from: data) else {
            return
        }
        // Initial load is fine in init
        progress = decoded
    }
    
    private func saveToStorage(_ progressSnapshot: [String: ReadingProgress]) {
        guard let data = try? JSONEncoder().encode(progressSnapshot) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
    
    private func saveProgress() {
        // Wrapper for legacy compatibility if needed internally, but now snapshot-based
        saveToStorage(progress)
    }
}
