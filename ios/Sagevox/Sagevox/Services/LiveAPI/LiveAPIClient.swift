import Foundation
import LiveKit
import Combine

/// LiveKit client for connecting to the SageVox backend and Voice Agent.
/// Handles connection, room management, and audio track subscription.
final class LiveAPIClient: NSObject, ObservableObject {
    
    // MARK: - Types
    
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected(roomName: String)
        case failed(Error)
        
        static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
            switch (lhs, rhs) {
            case (.disconnected, .disconnected): return true
            case (.connecting, .connecting): return true
            case (.connected(let a), .connected(let b)): return a == b
            case (.failed, .failed): return true
            default: return false
            }
        }
    }
    
    struct BookParams {
        let bookId: String
        let participantName: String
        let title: String
        let author: String
        let narratorVoice: String
        let currentChapter: Int
        let totalChapters: Int
        let timeOffset: Double
        let description: String
        let currentContext: String  // Text around current position
    }
    
    // MARK: - Properties

    private enum Constants {
        static let connectionTimeoutNanoseconds: UInt64 = 15_000_000_000
        static let contextDelayNanoseconds: UInt64 = 500_000_000
        static let defaultCommandSeconds = 30
    }

    private let tokenServiceURL: URL
    private let lockQueue = DispatchQueue(label: "com.sagevox.liveapi.lock")
    private var room: Room?
    private var pendingContextParams: BookParams?  // Params to send after connection

    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var isAgentSpeaking: Bool = false
    
    // Callbacks
    var onConnectionStateChange: ((ConnectionState) -> Void)?
    var onAgentSpeakingChange: ((Bool) -> Void)?
    var onAudioTrackSubscribed: ((RemoteAudioTrack) -> Void)?
    var onCommand: ((AgentCommand) -> Void)?

    // MARK: - Agent Commands

    enum AgentCommandType: String {
        case resumePlayback = "resume_playback"
        case skipBack = "skip_back"
        case skipForward = "skip_forward"
        case goToChapter = "go_to_chapter"
    }

    enum AgentCommand {
        case resumePlayback
        case skipBack(seconds: Int)
        case skipForward(seconds: Int)
        case goToChapter(Int)
    }

    
    // MARK: - Init

    init(baseURL: URL = APIClient.serverURL) {
        self.tokenServiceURL = baseURL
        super.init()
    }
    
    // MARK: - Connection
    
    func connect(with params: BookParams) async throws {
        // Store params to send context after connection (thread-safe)
        lockQueue.sync { self.pendingContextParams = params }

        // 1. Fetch Token from Backend
        let (token, url) = try await fetchToken(params: params)
        
        // 2. Connect to LiveKit Room
        let roomOptions = RoomOptions(
            defaultCameraCaptureOptions: CameraCaptureOptions(
                dimensions: .h720_169
            ),
            defaultAudioCaptureOptions: AudioCaptureOptions(
                echoCancellation: true,
                autoGainControl: true,
                noiseSuppression: true
            ),
            adaptiveStream: true,
            dynacast: true
        )
        
        let room = Room(delegate: self, connectOptions: ConnectOptions(
            autoSubscribe: true // Subscribe to Agent's audio automatically
        ), roomOptions: roomOptions)
        
        lockQueue.sync { self.room = room }
        
        updateConnectionState(.connecting)
        
        do {
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        try await room.connect(url: url, token: token)
                    }
                    
                    group.addTask {
                        try await Task.sleep(nanoseconds: Constants.connectionTimeoutNanoseconds)
                        throw LiveAPIError.connectionTimeout
                    }
                    
                    try await group.next()
                    group.cancelAll()
                }
            } catch {
                if case LiveAPIError.connectionTimeout = error {
                    try? await room.disconnect()
                }
                throw error
            }

            updateConnectionState(.connected(roomName: room.name ?? "Unknown"))

            // 3. Publish Microphone automatically
            try await room.localParticipant.setMicrophone(enabled: true)

            // 4. Send context to agent after connection established
            let contextParams = lockQueue.sync { self.pendingContextParams }
            if let params = contextParams {
                // Small delay to ensure agent is ready
                try? await Task.sleep(nanoseconds: Constants.contextDelayNanoseconds)
                sendContextUpdate(params: params)
            }

        } catch {
            lockQueue.sync { self.room = nil }
            updateConnectionState(.failed(error))
            throw error
        }
    }
    
    func disconnect() {
        let currentRoom = lockQueue.sync { () -> Room? in
            let room = self.room
            self.room = nil
            return room
        }

        Task {
            await currentRoom?.disconnect()
            updateConnectionState(.disconnected)
        }
    }

    /// Send context update to the agent via data channel
    func sendContextUpdate(params: BookParams) {
        let currentRoom = lockQueue.sync { self.room }
        
        guard let room = currentRoom, room.connectionState == .connected else {
            print("[LiveAPIClient] Cannot send context - not connected")
            return
        }

        // Build context payload matching competitor format
        let contextPayload: [String: Any] = [
            "type": "context_update",
            "context": [
                "systemInstruction": "Book: \(params.title)\nAuthor: \(params.author)\nChapter: \(params.currentChapter) of \(params.totalChapters)\n\nCurrent context: \(params.currentContext)",
                "bookId": params.bookId,
                "audioPosition": [
                    "chapter": params.currentChapter,
                    "timeOffset": params.timeOffset
                ],
                "bookInfo": [
                    "id": params.bookId,
                    "title": params.title,
                    "author": params.author,
                    "description": params.description,
                    "chapters": params.totalChapters,
                    "narratorVoice": params.narratorVoice
                ]
            ]
        ]

        do {
            let data = try JSONSerialization.data(withJSONObject: contextPayload)
            Task {
                try? await room.localParticipant.publish(data: data, options: DataPublishOptions(reliable: true))
                print("[LiveAPIClient] Sent context update to agent")
            }
        } catch {
            print("[LiveAPIClient] Failed to encode context: \(error)")
        }
    }
    
    // MARK: - Token Fetching
    
    private func fetchToken(params: BookParams) async throws -> (String, String) {
        var components = URLComponents(url: tokenServiceURL.appendingPathComponent("engage/token"), resolvingAgainstBaseURL: false)!
        
        // Only send minimal params for token - context sent via data channel
        components.queryItems = [
            URLQueryItem(name: "book_id", value: params.bookId),
            URLQueryItem(name: "participant_name", value: params.participantName),
            URLQueryItem(name: "title", value: params.title),
            URLQueryItem(name: "voice", value: params.narratorVoice),
        ]
        
        guard let url = components.url else {
            throw LiveAPIError.invalidURL
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        
        struct TokenResponse: Decodable {
            let token: String
            let url: String
        }
        
        let response = try JSONDecoder().decode(TokenResponse.self, from: data)
        return (response.token, response.url)
    }
    
    // MARK: - State Updates
    
    private func updateConnectionState(_ state: ConnectionState) {
        Task { @MainActor in
            self.connectionState = state
            self.onConnectionStateChange?(state)
        }
    }
    
    private func updateSpeakingState(isSpeaking: Bool) {
        Task { @MainActor in
            self.isAgentSpeaking = isSpeaking
            self.onAgentSpeakingChange?(isSpeaking)
        }
    }
}

// MARK: - RoomDelegate

extension LiveAPIClient: RoomDelegate {
    
    func room(_ room: Room, didUpdateConnectionState connectionState: LiveKit.ConnectionState, from oldValue: LiveKit.ConnectionState) {
        // Handle LiveKit internal connection state changes if needed
        if case .disconnected = connectionState {
            updateConnectionState(.disconnected)
        }
    }
    
    func room(_ room: Room, participant: RemoteParticipant, didSubscribe track: RemoteTrack, publication: RemoteTrackPublication) {
        if let audioTrack = track as? RemoteAudioTrack {
            print("[LiveAPIClient] Subscribed to audio track from: \(participant.identity)")
            onAudioTrackSubscribed?(audioTrack)
            
            // Optionally perform raw audio attachment or analysis here
        }
    }
    
    func room(_ room: Room, participant: Participant, didUpdateIsSpeaking isSpeaking: Bool) {
        // Detect if the Agent (not us) is speaking
        if participant is RemoteParticipant {
            print("[LiveAPIClient] Agent speaking: \(isSpeaking)")
            updateSpeakingState(isSpeaking: isSpeaking)
        }
    }
    
    func room(_ room: Room, didDisconnectWithError error: Error?) {
        if let error = error {
            updateConnectionState(.failed(error))
        } else {
            updateConnectionState(.disconnected)
        }
    }

    func room(_ room: Room, participant: RemoteParticipant?, didReceiveData data: Data, forTopic topic: String, encryptionType: EncryptionType) {
        // Handle data channel commands from the agent
        do {
            let object = try JSONSerialization.jsonObject(with: data)
            guard let json = object as? [String: Any] else {
                print("[LiveAPIClient] Ignoring non-object data channel message")
                return
            }

            guard let commandValue = json["command"] as? String, !commandValue.isEmpty else {
                print("[LiveAPIClient] Missing command in data channel message")
                return
            }

            guard let command = AgentCommandType(rawValue: commandValue) else {
                print("[LiveAPIClient] Unknown command: \(commandValue)")
                return
            }

            let commandPayload: AgentCommand
            switch command {
            case .resumePlayback:
                commandPayload = .resumePlayback
            case .skipBack:
                let seconds = (json["data"] as? [String: Any])?["seconds"] as? Int
                    ?? Constants.defaultCommandSeconds
                commandPayload = .skipBack(seconds: seconds)
            case .skipForward:
                let seconds = (json["data"] as? [String: Any])?["seconds"] as? Int
                    ?? Constants.defaultCommandSeconds
                commandPayload = .skipForward(seconds: seconds)
            case .goToChapter:
                guard let chapter = (json["data"] as? [String: Any])?["chapter"] as? Int else {
                    print("[LiveAPIClient] Missing chapter in command payload")
                    return
                }
                commandPayload = .goToChapter(chapter)
            }

            print("[LiveAPIClient] Received command: \(command.rawValue)")

            Task { @MainActor in
                self.onCommand?(commandPayload)
            }
        } catch {
            print("[LiveAPIClient] Failed to parse data channel message: \(error)")
        }
    }
}

// MARK: - Errors

enum LiveAPIError: LocalizedError {
    case invalidURL
    case connectionFailed
    case connectionTimeout
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid Token URL"
        case .connectionFailed: return "Failed to connect to LiveKit"
        case .connectionTimeout: return "Connection timed out (15s)"
        }
    }
}
