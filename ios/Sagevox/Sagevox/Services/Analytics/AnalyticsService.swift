import Foundation
import PostHog

/// Centralized analytics tracking for SageVox
final class Analytics {
    static let shared = Analytics()

    private init() {}

    // MARK: - Setup

    static func configure() {
        guard let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
              let config = NSDictionary(contentsOfFile: path),
              let apiKey = config["PostHogAPIKey"] as? String,
              let host = config["PostHogHost"] as? String else {
            print("[Analytics] Config.plist not found or missing keys")
            return
        }

        let posthogConfig = PostHogConfig(apiKey: apiKey, host: host)
        PostHogSDK.shared.setup(posthogConfig)
        print("[Analytics] PostHog initialized")
    }

    // MARK: - Library Events

    func trackLibraryViewed(bookCount: Int) {
        PostHogSDK.shared.capture("library_viewed", properties: [
            "book_count": bookCount
        ])
    }

    // MARK: - Book Events

    func trackBookOpened(bookId: String, title: String, author: String) {
        PostHogSDK.shared.capture("book_opened", properties: [
            "book_id": bookId,
            "book_title": title,
            "book_author": author
        ])
    }

    func trackPlaybackStarted(bookId: String, chapter: Int, position: Double) {
        PostHogSDK.shared.capture("playback_started", properties: [
            "book_id": bookId,
            "chapter": chapter,
            "position_seconds": position
        ])
    }

    func trackPlaybackPaused(bookId: String, chapter: Int, position: Double) {
        PostHogSDK.shared.capture("playback_paused", properties: [
            "book_id": bookId,
            "chapter": chapter,
            "position_seconds": position
        ])
    }

    func trackChapterChanged(bookId: String, fromChapter: Int, toChapter: Int) {
        PostHogSDK.shared.capture("chapter_changed", properties: [
            "book_id": bookId,
            "from_chapter": fromChapter,
            "to_chapter": toChapter
        ])
    }

    func trackPlaybackSpeedChanged(bookId: String, speed: Float) {
        PostHogSDK.shared.capture("playback_speed_changed", properties: [
            "book_id": bookId,
            "speed": speed
        ])
    }

    // MARK: - Voice Q&A Events

    func trackVoiceQAStarted(bookId: String, chapter: Int, position: Double) {
        PostHogSDK.shared.capture("voice_qa_started", properties: [
            "book_id": bookId,
            "chapter": chapter,
            "position_seconds": position
        ])
    }

    func trackVoiceQAEnded(bookId: String, chapter: Int, durationSeconds: Double) {
        PostHogSDK.shared.capture("voice_qa_ended", properties: [
            "book_id": bookId,
            "chapter": chapter,
            "session_duration_seconds": durationSeconds
        ])
    }

    func trackVoiceQAError(bookId: String, error: String) {
        PostHogSDK.shared.capture("voice_qa_error", properties: [
            "book_id": bookId,
            "error": error
        ])
    }

    // MARK: - Text Follow-Along Events

    func trackTextFollowAlongOpened(bookId: String, chapter: Int) {
        PostHogSDK.shared.capture("text_follow_along_opened", properties: [
            "book_id": bookId,
            "chapter": chapter
        ])
    }

    func trackTextTapped(bookId: String, chapter: Int, segmentIndex: Int) {
        PostHogSDK.shared.capture("text_segment_tapped", properties: [
            "book_id": bookId,
            "chapter": chapter,
            "segment_index": segmentIndex
        ])
    }
}
