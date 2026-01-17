import Foundation
import AVFoundation
import MediaPlayer
import Combine

/// Manages audiobook playback using AVPlayer
class AudioPlayerService: NSObject, ObservableObject {
    private enum Constants {
        static let maxRetries = 1
        static let retryDelay: TimeInterval = 1
        static let previousChapterRestartThreshold: Double = 3
        static let timeObserverInterval: Double = 0.5
        static let timeObserverTimescale: CMTimeScale = 600
        static let chapterEndThreshold: Double = 0.5
        static let skipIntervalSeconds: Double = 15
    }

    // MARK: - Published Properties
    
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var playbackSpeed: Float = 1.0
    @Published var currentBook: Book?
    @Published var currentChapter: Chapter?
    @Published var currentSegment: TranscriptSegment?
    @Published var isLoading = false
    @Published var isBuffering = false
    @Published var playbackError: String?
    
    // MARK: - Private Properties
    
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var progressTracker = ProgressTracker.shared
    private var cancellables = Set<AnyCancellable>()
    private var currentTranscript: Transcript?
    private let stateLock = NSLock()
    private var _retryCount = 0
    private let maxRetries = Constants.maxRetries

    private var retryCount: Int {
        get { stateLock.withLock { _retryCount } }
        set { stateLock.withLock { _retryCount = newValue } }
    }
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupAudioSession()
        setupRemoteCommandCenter()
    }
    
    deinit {
        removeTimeObserver()
    }
    
    // MARK: - Audio Session
    
    private func setupAudioSession() {
        do {
            try AudioSessionManager.shared.setupSession(mode: .playback)
        } catch {
            print("Failed to setup audio session: \(error)")
            playbackError = "Audio system error: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Remote Command Center (Lock Screen Controls)
    
    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.play()
            return .success
        }
        
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        
        commandCenter.skipForwardCommand.preferredIntervals = [NSNumber(value: Constants.skipIntervalSeconds)]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            self?.seekForward(Constants.skipIntervalSeconds)
            return .success
        }
        
        commandCenter.skipBackwardCommand.preferredIntervals = [NSNumber(value: Constants.skipIntervalSeconds)]
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            self?.seekBackward(Constants.skipIntervalSeconds)
            return .success
        }
        
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self?.seek(to: event.positionTime)
            return .success
        }
    }
    
    private func updateNowPlayingInfo() {
        guard let book = currentBook, let chapter = currentChapter else { return }
        
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: chapter.title,
            MPMediaItemPropertyArtist: book.author,
            MPMediaItemPropertyAlbumTitle: book.title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? playbackSpeed : 0,
        ]
        
        // Artwork is loaded asynchronously from remote URL now
        // TODO: Cache and display cover image for Now Playing
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    
    // MARK: - Playback Control
    
    /// Load a book for playback (fetches audio from remote server)
    func loadBook(_ book: Book) {
        self.currentBook = book
        self.playbackError = nil
        
        guard !book.chapters.isEmpty else {
            playbackError = "This book has no chapters"
            return
        }
        
        // Restore progress
        let progress = progressTracker.getProgress(for: book.id)
        
        // Load chapter
        if let chapter = book.chapters.first(where: { $0.number == progress.currentChapter }) {
            loadChapter(chapter, seekTo: progress.positionSeconds)
        } else if let firstChapter = book.chapters.first {
            loadChapter(firstChapter)
        }
        
        // Restore playback speed
        playbackSpeed = progress.playbackSpeed
    }
    
    func loadChapter(_ chapter: Chapter, seekTo position: Double = 0) {
        // Clear old subscriptions to the previous player item
        cancellables.removeAll()
        
        guard let book = currentBook,
              let audioFile = chapter.audioFile,
              !audioFile.isEmpty else {
            playbackError = "Audio file missing for this chapter"
            isLoading = false
            return
        }
        
        isLoading = true
        isBuffering = false
        playbackError = nil
        currentChapter = chapter
        
        // Load transcript from embedded data (no file fetch needed)
        currentTranscript = chapter.transcript
        currentSegment = nil
        
        // Construct remote audio URL
        let audioURL = APIClient.shared.audioURL(bookId: book.id, audioFile: audioFile)
        let playerItem = AVPlayerItem(url: audioURL)
        
        // Observe player item status
        playerItem.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self = self else { return }
                switch status {
                case .readyToPlay:
                    self.isLoading = false
                    self.retryCount = 0
                    let durationSeconds = playerItem.duration.seconds
                    if durationSeconds.isFinite, durationSeconds > 0 {
                        self.duration = durationSeconds
                    } else {
                        self.duration = 0
                    }
                    if position > 0 {
                        self.seek(to: position)
                    }
                case .failed:
                    self.handlePlaybackError(playerItem.error)
                default:
                    break
                }
            }
            .store(in: &cancellables)
        
        // Observe buffering state
        playerItem.publisher(for: \.isPlaybackBufferEmpty)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEmpty in
                self?.isBuffering = isEmpty
            }
            .store(in: &cancellables)
        
        playerItem.publisher(for: \.isPlaybackLikelyToKeepUp)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] canKeepUp in
                if canKeepUp {
                    self?.isBuffering = false
                }
            }
            .store(in: &cancellables)
        
        if player == nil {
            player = AVPlayer(playerItem: playerItem)
        } else {
            player?.replaceCurrentItem(with: playerItem)
        }
        
        player?.rate = playbackSpeed
        setupTimeObserver()
        updateNowPlayingInfo()
        
        // Save progress
        progressTracker.updatePosition(for: book.id, chapter: chapter.number, position: position)
    }
    
    private func handlePlaybackError(_ error: Error?) {
        if retryCount < maxRetries {
            retryCount += 1
            playbackError = "Connection lost. Retrying..."
            
            // Retry after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + Constants.retryDelay) { [weak self] in
                guard let self = self, let chapter = self.currentChapter else { return }
                self.loadChapter(chapter, seekTo: self.currentTime)
            }
        } else {
            isLoading = false
            playbackError = "Not connected to server"
        }
    }
    
    func play() {
        player?.play()
        player?.rate = playbackSpeed
        isPlaying = true
        updateNowPlayingInfo()

        if let book = currentBook, let chapter = currentChapter {
            Analytics.shared.trackPlaybackStarted(
                bookId: book.id,
                chapter: chapter.number,
                position: currentTime
            )
        }
    }
    
    func pause() {
        player?.pause()
        isPlaying = false
        saveCurrentProgress()
        updateNowPlayingInfo()

        if let book = currentBook, let chapter = currentChapter {
            Analytics.shared.trackPlaybackPaused(
                bookId: book.id,
                chapter: chapter.number,
                position: currentTime
            )
        }
    }
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime) { [weak self] finished in
            guard let self = self else { return }
            if finished {
                self.currentTime = time
                self.updateNowPlayingInfo()
            } else {
                print("[AudioPlayer] Seek interrupted or failed")
                // Clear any transient error - seek interruption is usually not critical
                // (e.g., user sought again before previous seek completed)
            }
        }
    }
    
    func seekForward(_ seconds: Double) {
        let newTime = min(currentTime + seconds, duration)
        seek(to: newTime)
    }
    
    func seekBackward(_ seconds: Double) {
        let newTime = max(currentTime - seconds, 0)
        seek(to: newTime)
    }
    
    func setPlaybackSpeed(_ speed: Float) {
        playbackSpeed = speed
        if isPlaying {
            player?.rate = speed
        }

        // Save speed preference
        if let book = currentBook {
            var progress = progressTracker.getProgress(for: book.id)
            progress.playbackSpeed = speed
            progressTracker.updateProgress(progress)

            Analytics.shared.trackPlaybackSpeedChanged(bookId: book.id, speed: speed)
        }

        updateNowPlayingInfo()
    }
    
    func nextChapter() {
        guard let book = currentBook,
              let current = currentChapter,
              let nextIndex = book.chapters.firstIndex(where: { $0.number == current.number + 1 }) else {
            return
        }
        loadChapter(book.chapters[nextIndex])
        play()
    }
    
    func previousChapter() {
        guard let book = currentBook,
              let current = currentChapter else { return }

        // If more than 3 seconds into chapter, restart current chapter
        if currentTime > Constants.previousChapterRestartThreshold {
            seek(to: 0)
            return
        }

        // Otherwise go to previous chapter
        guard let prevIndex = book.chapters.firstIndex(where: { $0.number == current.number - 1 }) else {
            return
        }
        loadChapter(book.chapters[prevIndex])
        play()
    }

    func goToChapter(_ chapterNumber: Int) {
        guard let book = currentBook,
              let chapter = book.chapters.first(where: { $0.number == chapterNumber }) else {
            print("[AudioPlayer] Chapter \(chapterNumber) not found")
            return
        }
        loadChapter(chapter)
        play()
    }
    
    // MARK: - Time Observer
    
    private func setupTimeObserver() {
        removeTimeObserver()
        
        let interval = CMTime(seconds: Constants.timeObserverInterval, preferredTimescale: Constants.timeObserverTimescale)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            self.currentTime = time.seconds
            
            // Update current segment
            if let transcript = self.currentTranscript {
                self.currentSegment = transcript.segment(at: self.currentTime)
            }
            
            // Check for chapter end
            if self.duration.isFinite, self.duration > 0,
               self.currentTime >= self.duration - Constants.chapterEndThreshold {
                self.handleChapterEnd()
            }
        }
    }
    
    private func removeTimeObserver() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
    }
    
    private func handleChapterEnd() {
        guard let book = currentBook,
              let current = currentChapter,
              let nextIndex = book.chapters.firstIndex(where: { $0.number == current.number + 1 }) else {
            // End of book
            pause()
            return
        }
        
        // Auto-advance to next chapter
        loadChapter(book.chapters[nextIndex])
        play()
    }
    
    // MARK: - Progress Saving
    
    private func saveCurrentProgress() {
        guard let book = currentBook,
              let chapter = currentChapter else { return }
        
        progressTracker.updatePosition(for: book.id, chapter: chapter.number, position: currentTime)
    }
    
    // Transcript is now embedded in Chapter - no separate loading needed
    func generateContextPayload() -> [String: Any] {
        guard let book = currentBook else { return [:] }
        
        // 1. Book Info
        var bookInfo: [String: Any] = [
            "id": book.id,
            "title": book.title,
            "author": book.author,
            "totalDuration": book.totalDurationSeconds,
            "chapters": book.totalChapters,
            "description": book.description
        ]
        
        // 2. Audio Position & Context
        var audioPosition: [String: Any] = [
            "timeOffset": currentTime
        ]
        
        if let transcript = currentTranscript,
           let index = transcript.segmentIndex(at: currentTime) {
            audioPosition["sentenceIndex"] = index
        }
        
        let currentContextText = currentTranscript?.contextText(at: currentTime) ?? ""
        
        // 3. System Instruction
        let systemInstruction = """
        Book: \(book.title)
        Author: \(book.author)
        
        Current context: \(currentContextText)
        """
        
        return [
            "systemInstruction": systemInstruction,
            "bookId": book.id,
            "audioPosition": audioPosition,
            "bookInfo": bookInfo
        ]
    }
}
