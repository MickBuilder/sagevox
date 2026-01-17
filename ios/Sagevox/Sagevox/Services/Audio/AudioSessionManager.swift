import AVFoundation

/// Manages AVAudioSession configuration for the application
class AudioSessionManager {
    static let shared = AudioSessionManager()
    
    private init() {}
    
    enum SessionMode {
        case playback
        case voiceChat
    }
    
    func setupSession(mode: SessionMode) throws {
        let session = AVAudioSession.sharedInstance()
        
        switch mode {
        case .playback:
            try session.setCategory(.playback, mode: .spokenAudio)
        case .voiceChat:
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.defaultToSpeaker, .allowBluetooth]
            )
        }
        
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        print("[AudioSessionManager] Session configured for \(mode)")
    }
    
    func deactivate() throws {
        try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        print("[AudioSessionManager] Session deactivated")
    }
}
