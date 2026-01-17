#if os(iOS)
import Foundation
import Combine
import AVFoundation
import LiveKit

/// State of the voice Q&A interaction
enum VoiceQAState: Equatable {
    case connecting
    case listening(isAgentSpeaking: Bool)
    case waiting
    case resuming // Handling audio session restoration
    case error(String)
}

/// Commands received from the agent to control the player
enum VoiceQACommand: Equatable {
    case skipBack(seconds: Int)
    case skipForward(seconds: Int)
    case goToChapter(number: Int)
}

/// ViewModel that orchestrates voice Q&A interaction using LiveKit.
@MainActor
final class VoiceQAViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var state: VoiceQAState = .connecting
    @Published private(set) var visualizerLevels: [CGFloat] = Array(repeating: 0.1, count: 40)

    /// Stream of commands from the agent
    let commands = PassthroughSubject<VoiceQACommand, Never>()
    
    // MARK: - Private Properties
    
    private let book: Book
    private weak var audioPlayer: AudioPlayerService?
    private var currentChapter: Int
    
    private enum Constants {
        static let visualizerInterval: TimeInterval = 0.1
        static let resumeDelayNanoseconds: UInt64 = 500_000_000
    }

    private let liveClient: LiveAPIClient
    private var connectionTask: Task<Void, Never>?

    private var cancellables = Set<AnyCancellable>()
    private var isResumingPlayback = false
    private var visualizerTimer: AnyCancellable?
    // Audio analyzer for visualization
    
    // MARK: - Init

    init(
        book: Book,
        chapter: Int,
        audioPlayer: AudioPlayerService,
        liveClient: LiveAPIClient? = nil
    ) {
        self.book = book
        self.currentChapter = chapter
        self.audioPlayer = audioPlayer
        self.liveClient = liveClient ?? LiveAPIClient(baseURL: APIClient.serverURL)

        setupCallbacks()
    }
    
    deinit {
        connectionTask?.cancel()
        visualizerTimer?.cancel()
        liveClient.disconnect()
    }
    
    func updateAudioPlayer(_ player: AudioPlayerService) {
        self.audioPlayer = player
    }

    func updateCurrentChapter(_ chapter: Int) {
        self.currentChapter = chapter
    }
    
    // MARK: - Setup

    private func startVisualizer() {
        guard visualizerTimer == nil else { return }
        visualizerTimer = Timer.publish(every: Constants.visualizerInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                if case .listening(let isAgentSpeaking) = self.state {
                    let baseLevel = isAgentSpeaking ? 0.6 : 0.2
                    self.updateVisualizerLevels(with: CGFloat.random(in: 0.1...baseLevel))
                }
            }
    }
    
    private func setupCallbacks() {
        // Connection state changes
        liveClient.onConnectionStateChange = { [weak self] connectionState in
            Task { @MainActor in
                self?.handleConnectionStateChange(connectionState)
            }
        }
        
        // Agent Speaking State
        liveClient.onAgentSpeakingChange = { [weak self] isSpeaking in
            Task { @MainActor in
                if case .listening = self?.state {
                    self?.state = .listening(isAgentSpeaking: isSpeaking)
                }
            }
        }
        
        // Handle Audio Track (for visualization)
        liveClient.onAudioTrackSubscribed = { [weak self] track in
            // Ideally attach a visualizer here
            // track.addRenderer(self)
        }

        // Handle agent commands (playback control)
        liveClient.onCommand = { [weak self] command in
            Task { @MainActor in
                self?.handleAgentCommand(command)
            }
        }
        
    }
    
    // MARK: - Public Methods
    
    func connect() {
        connectionTask?.cancel()
        connectionTask = nil
        startVisualizer()

        // Check permissions
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            guard let self = self else { return }
            if granted {
                Task { @MainActor in
                    self.startConnection()
                }
            } else {
                Task { @MainActor in
                    self.state = .error("Microphone permission denied")
                    self.visualizerTimer?.cancel()
                    self.visualizerTimer = nil
                }
            }
        }
    }
    
    func disconnect() {
        connectionTask?.cancel()
        connectionTask = nil
        liveClient.disconnect()
        visualizerTimer?.cancel()
        visualizerTimer = nil
        if case .resuming = state { return } // Don't reset if we are intentionally resuming
        state = .connecting // Reset for next time
    }
    
    func endTurn() {
        // In LiveKit/VAD, end turn is automatic.
        // If we want a "Force Send" button, we typically just need to silence the mic momentarily or use a data message.
        // For now, no-op or implementation dependant.
    }
    
    func resumePlayback() {
        isResumingPlayback = true

        // Track session end
        if let startTime = sessionStartTime {
            let duration = Date().timeIntervalSince(startTime)
            Analytics.shared.trackVoiceQAEnded(
                bookId: book.id,
                chapter: currentChapter,
                durationSeconds: duration
            )
        }
        sessionStartTime = nil

        disconnect()

        // Restore audio session for playback (LiveKit changes it for voice chat)
        // Add small delay to ensure LiveKit fully releases audio session
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: Constants.resumeDelayNanoseconds)

            do {
                try AudioSessionManager.shared.setupSession(mode: .playback)
            } catch {
                print("[VoiceQA] Failed to restore audio session: \(error)")
            }

            self.state = .resuming
            self.isResumingPlayback = false
        }
    }
    
    // MARK: - Private Methods

    /// Build context string from current position in the audiobook
    private func buildCurrentContext() -> String {
        let currentTime = audioPlayer?.currentTime ?? 0
        let fallbackDescription = book.description.isEmpty ? "No description available." : book.description
        return book.chapters.first(where: { $0.number == currentChapter })?
            .transcript?.contextText(at: currentTime) ?? fallbackDescription
    }

    private var sessionStartTime: Date?

    private func startConnection() {
        connectionTask?.cancel()
        connectionTask = nil
        sessionStartTime = Date()

        // Track voice Q&A started
        Analytics.shared.trackVoiceQAStarted(
            bookId: book.id,
            chapter: currentChapter,
            position: audioPlayer?.currentTime ?? 0
        )

        // Get current playback position for focused context
        let timeOffset = audioPlayer?.currentTime ?? 0

        // Build current context from transcript around current position
        let currentContext = buildCurrentContext()

        let params = LiveAPIClient.BookParams(
            bookId: book.id,
            participantName: "User",
            title: book.title,
            author: book.author,
            narratorVoice: book.narratorVoice,
            currentChapter: currentChapter,
            totalChapters: book.totalChapters,
            timeOffset: timeOffset,
            description: book.description,
            currentContext: currentContext
        )
        
        state = .connecting

        connectionTask = Task {
            do {
                try await liveClient.connect(with: params)
                // If successful, state handler will switch to listening
            } catch {
                guard !Task.isCancelled else { return }
                let errorMessage = "Failed to connect: \(error.localizedDescription)"
                state = .error(errorMessage)
                Analytics.shared.trackVoiceQAError(bookId: book.id, error: errorMessage)
            }
        }
    }
    
    private func handleConnectionStateChange(_ connectionState: LiveAPIClient.ConnectionState) {
        if isResumingPlayback { return }
        switch connectionState {
        case .disconnected:
            // Don't overwrite error state
            if case .error = state { return }
            state = .connecting
            
        case .connecting:
            state = .connecting
            
        case .connected(let roomName):
            print("[VoiceQA] Connected to room: \(roomName)")
            state = .listening(isAgentSpeaking: false)
            
        case .failed(let error):
            state = .error("Connection failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Visualizer
    
    private func updateVisualizerLevels(with level: CGFloat) {
        let barCount = visualizerLevels.count
        let center = barCount / 2
        var newLevels: [CGFloat] = []
        for i in 0..<barCount {
            let distanceFromCenter = abs(i - center)
            let falloff = 1.0 - (CGFloat(distanceFromCenter) / CGFloat(center)) * 0.5
            let jitter = CGFloat.random(in: 0.8...1.2)
            let barLevel = level * falloff * jitter
            newLevels.append(max(0.08, min(1.0, barLevel)))
        }
        visualizerLevels = newLevels
    }

    // MARK: - Agent Command Handling

    private func handleAgentCommand(_ command: LiveAPIClient.AgentCommand) {
        switch command {
        case .resumePlayback:
            print("[VoiceQA] Handling command: resume_playback")
            resumePlayback()

        case .skipBack(let seconds):
            print("[VoiceQA] Handling command: skip_back")
            commands.send(.skipBack(seconds: seconds))

        case .skipForward(let seconds):
            print("[VoiceQA] Handling command: skip_forward")
            commands.send(.skipForward(seconds: seconds))

        case .goToChapter(let chapter):
            print("[VoiceQA] Handling command: go_to_chapter")
            commands.send(.goToChapter(number: chapter))
        }
    }
}
#endif
