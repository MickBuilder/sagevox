#if os(iOS)
import AVFoundation
import Foundation
import Combine

/// Manages real-time audio capture and playback for voice Q&A.
/// Handles microphone input (PCM 16-bit, 16kHz) and plays back AI responses.
/// Supports simultaneous recording and playback for Live API VAD interruption detection.
final class AudioStreamManager: ObservableObject {

    // MARK: - Types

    enum State {
        case idle
        case recording
        case playing
        case recordingAndPlaying  // Simultaneous I/O for VAD
    }

    enum AudioStreamError: Error {
        case formatInitializationFailed
        case bufferCreationFailed
    }
    
    // MARK: - Audio Format (Gemini Live API requirements)
    
    /// Gemini Live API expects 16-bit PCM at 16kHz mono for input
    static let sampleRate: Double = 16000
    static let inputChannels: AVAudioChannelCount = 1
    
    /// Gemini Live API outputs 24kHz PCM audio
    static let outputSampleRate: Double = 24000
    
    private lazy var inputFormat: AVAudioFormat? = {
        AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Self.sampleRate,
            channels: Self.inputChannels,
            interleaved: true
        )
    }()

    private lazy var outputFormat: AVAudioFormat? = {
        AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Self.outputSampleRate,
            channels: 1,
            interleaved: true
        )
    }()
    
    // MARK: - Properties
    
    private let audioEngine = AVAudioEngine()
    private var inputNode: AVAudioInputNode { audioEngine.inputNode }
    private let playerNode = AVAudioPlayerNode()

    private var audioConverter: AVAudioConverter?
    private var isEngineConfigured = false
    private var isAudioSessionConfigured = false
    
    @Published private(set) var state: State = .idle
    @Published private(set) var currentLevel: Float = 0

    private let stateQueue = DispatchQueue(label: "com.sagevox.audio.state")
    private var internalState: State = .idle
    
    private enum Constants {
        static let bufferSize = 4096
        static let playbackChunkSize = 4800
        static let maxChunksPerCall = 5
        static let scheduleDelay: TimeInterval = 0.01
    }

    // Buffer for accumulating audio before sending
    private let bufferQueue = DispatchQueue(label: "com.sagevox.audio.buffer")
    private var audioBuffer = Data()
    
    // Noise Gate settings
    private let noiseGateThreshold: Float = 0.003 // Lowered for better sensitivity. Filter background hum but catch speech.
    private var lastObservedInputLevel: Float = 0
    
    // Callbacks
    var onAudioCaptured: ((Data) -> Void)?
    var onPlaybackFinished: (() -> Void)?
    var onError: ((Error) -> Void)?
    
    // Playback queue
    private var playbackQueue = DispatchQueue(label: "com.sagevox.audio.playback")
    private var pendingAudioData = Data()
    private var isSchedulingAudio = false
    private var scheduledBufferCount = 0
    
    // MARK: - Setup
    
    func setupAudioSession() throws {
        // Don't reconfigure if already set up and active
        guard !isAudioSessionConfigured else {
            return
        }

        try AudioSessionManager.shared.setupSession(mode: .voiceChat)

        isAudioSessionConfigured = true
        print("[AudioStreamManager] Audio session configured")
    }
    
    private func configureEngine() throws {
        guard !isEngineConfigured else { return }

        guard let outputFmt = outputFormat else {
            throw AudioStreamError.formatInitializationFailed
        }

        // Attach player node
        audioEngine.attach(playerNode)

        // Connect player to main mixer
        let mainMixer = audioEngine.mainMixerNode
        audioEngine.connect(playerNode, to: mainMixer, format: outputFmt)

        // Prepare converter for input audio (mic format -> 16kHz PCM)
        let micFormat = inputNode.inputFormat(forBus: 0)
        if micFormat.sampleRate != Self.sampleRate, let inputFmt = inputFormat {
            audioConverter = AVAudioConverter(from: micFormat, to: inputFmt)
        }

        isEngineConfigured = true
        print("[AudioStreamManager] Audio engine configured")
    }
    
    // MARK: - Recording
    
    /// Start capturing audio from microphone
    /// Can be called while playing - supports simultaneous I/O for VAD
    func startRecording() throws {
        // Already recording - nothing to do
        guard !isRecording else {
            print("[AudioStreamManager] Already recording, skipping")
            return
        }
        
        try setupAudioSession()
        try configureEngine()
        
        let micFormat = inputNode.inputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: micFormat) { [weak self] buffer, time in
            self?.processInputBuffer(buffer)
        }
        
        if !audioEngine.isRunning {
            try audioEngine.start()
        }
        
        updateState(isRecording: true)
        print("[AudioStreamManager] Recording started")
    }
    
    /// Stop capturing audio
    func stopRecording() {
        guard isRecording else { return }
        
        inputNode.removeTap(onBus: 0)
        
        // Flush any remaining audio in buffer
        bufferQueue.sync {
            if !audioBuffer.isEmpty {
                onAudioCaptured?(audioBuffer)
                audioBuffer.removeAll()
            }
        }
        
        updateState(isRecording: false)
        print("[AudioStreamManager] Recording stopped")
    }
    
    /// Update the combined state based on I/O flags
    private func updateState(isRecording: Bool? = nil, isPlaying: Bool? = nil) {
        let currentState = stateQueue.sync { internalState }
        let currentRecording = currentState == .recording || currentState == .recordingAndPlaying
        let currentPlaying = currentState == .playing || currentState == .recordingAndPlaying

        let newIsRecording = isRecording ?? currentRecording
        let newIsPlaying = isPlaying ?? currentPlaying

        let nextState: State
        switch (newIsRecording, newIsPlaying) {
        case (true, true):
            nextState = .recordingAndPlaying
        case (true, false):
            nextState = .recording
        case (false, true):
            nextState = .playing
        case (false, false):
            nextState = .idle
        }

        stateQueue.sync {
            internalState = nextState
        }

        DispatchQueue.main.async {
            self.state = nextState
        }
    }

    var isRecording: Bool {
        stateQueue.sync {
            internalState == .recording || internalState == .recordingAndPlaying
        }
    }

    var isPlaying: Bool {
        stateQueue.sync {
            internalState == .playing || internalState == .recordingAndPlaying
        }
    }
    
    private func processInputBuffer(_ buffer: AVAudioPCMBuffer) {
        // Convert to target format if needed
        let outputBuffer: AVAudioPCMBuffer

        if let converter = audioConverter, let inputFmt = inputFormat {
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: inputFmt,
                frameCapacity: AVAudioFrameCount(inputFmt.sampleRate * 0.1)
            ) else { return }
            
            var error: NSError?
            let status = converter.convert(to: convertedBuffer, error: &error) { inNumPackets, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            
            if status == .error {
                print("[AudioStreamManager] Conversion error: \(error?.localizedDescription ?? "unknown")")
                return
            }
            
            outputBuffer = convertedBuffer
        } else {
            outputBuffer = buffer
        }
        
        // Calculate power (RMS) for visualization only
        _ = calculatePower(from: outputBuffer)
        
        // IMPORTANT: Send ALL audio continuously - do NOT filter with noise gate!
        // Gemini's VAD needs continuous audio stream to detect speech boundaries.
        // If we skip "quiet" frames, VAD can't detect when user stops speaking.
        guard let channelData = outputBuffer.int16ChannelData else { return }
        
        let frameCount = Int(outputBuffer.frameLength)
        let data = Data(bytes: channelData[0], count: frameCount * 2) // 16-bit = 2 bytes
        
        // Accumulate in buffer and send in chunks
        bufferQueue.async { [weak self] in
            guard let self = self else { return }
            self.audioBuffer.append(data)
            
            if self.audioBuffer.count >= Constants.bufferSize {
                let chunk = self.audioBuffer
                self.audioBuffer.removeAll()
                self.onAudioCaptured?(chunk)
            }
        }
    }
    
    @discardableResult
    private func calculatePower(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.int16ChannelData else { return 0 }
        let frameCount = Int(buffer.frameLength)
        
        var sum: Float = 0
        for i in 0..<frameCount {
            let sample = Float(channelData[0][i]) / 32768.0
            sum += sample * sample
        }
        
        let rms = sqrt(sum / Float(frameCount))
        let db = 20 * log10(max(rms, 0.0001))
        
        // Normalize to 0.0 - 1.0 range (assuming -60dB to 0dB range)
        let normalized = max(0, (db + 60) / 60)
        
        DispatchQueue.main.async {
            self.currentLevel = normalized
        }
        return rms
    }
    
    // MARK: - Playback
    
    /// Queue audio data for playback (streaming from server)
    func queueAudioForPlayback(_ data: Data) {
        playbackQueue.async { [weak self] in
            self?.pendingAudioData.append(data)
            self?.scheduleNextChunk()
        }
    }
    
    private func scheduleNextChunk() {
        guard !isSchedulingAudio else { return }
        isSchedulingAudio = true

        // Process in chunks
        let chunkSize = Constants.playbackChunkSize

        // Limit how many chunks we schedule at once to avoid overwhelming the main thread
        var chunksScheduled = 0

        while pendingAudioData.count >= chunkSize && chunksScheduled < Constants.maxChunksPerCall {
            let chunk = pendingAudioData.prefix(chunkSize)
            pendingAudioData.removeFirst(chunkSize)

            if let buffer = createPCMBuffer(from: Data(chunk)) {
                DispatchQueue.main.async { [weak self] in
                    self?.scheduleBuffer(buffer)
                }
                chunksScheduled += 1
            } else {
                onError?(AudioStreamError.bufferCreationFailed)
                print("[AudioStreamManager] Failed to create PCM buffer")
            }
        }

        isSchedulingAudio = false

        // If there's still more audio to schedule, do it after a small delay
        // to let the main thread breathe and process WebSocket messages
        if pendingAudioData.count >= chunkSize {
            playbackQueue.asyncAfter(deadline: .now() + Constants.scheduleDelay) { [weak self] in
                self?.scheduleNextChunk()
            }
        }
    }
    
    private func createPCMBuffer(from data: Data) -> AVAudioPCMBuffer? {
        guard let outputFmt = outputFormat else { return nil }

        let frameCount = AVAudioFrameCount(data.count / 2) // 16-bit = 2 bytes per sample

        guard let buffer = AVAudioPCMBuffer(pcmFormat: outputFmt, frameCapacity: frameCount) else {
            return nil
        }

        buffer.frameLength = frameCount

        guard let channelData = buffer.int16ChannelData else { return nil }

        data.withUnsafeBytes { rawBuffer in
            if let baseAddress = rawBuffer.baseAddress {
                memcpy(channelData[0], baseAddress, data.count)
            }
        }

        return buffer
    }
    
    private func scheduleBuffer(_ buffer: AVAudioPCMBuffer) {
        // Setup audio infrastructure if needed (these have guards to prevent redundant setup)
        do {
            try setupAudioSession()
            try configureEngine()
        } catch {
            print("[AudioStreamManager] Failed to setup audio: \(error)")
            return
        }

        // Ensure engine is running
        if !audioEngine.isRunning {
            do {
                try audioEngine.start()
            } catch {
                print("[AudioStreamManager] Failed to start engine: \(error)")
                return
            }
        }

        // Start player if needed (only log once when starting)
        if !playerNode.isPlaying {
            playerNode.play()
            if !isPlaying {
                updateState(isPlaying: true)
                print("[AudioStreamManager] Playback started (via scheduleBuffer)")
            }
        }

        playbackQueue.sync {
            scheduledBufferCount += 1
        }

        playerNode.scheduleBuffer(buffer) { [weak self] in
            self?.playbackQueue.async {
                guard let self = self else { return }
                self.scheduledBufferCount = max(0, self.scheduledBufferCount - 1)
                if self.pendingAudioData.isEmpty && self.scheduledBufferCount == 0 {
                    DispatchQueue.main.async {
                        self.updateState(isPlaying: false)
                        self.onPlaybackFinished?()
                    }
                }
            }
        }
    }
    
    /// Start playback immediately (used for preparing the player)
    func startPlayback() {
        // Guard against repeated calls - don't reconfigure if already playing
        guard !isPlaying else {
            print("[AudioStreamManager] Already playing, skipping")
            return
        }

        do {
            // Setup session and engine (these methods have their own guards)
            try setupAudioSession()
            try configureEngine()

            // Start engine if needed
            if !audioEngine.isRunning {
                try audioEngine.start()
            }

            // Start player if needed
            if !playerNode.isPlaying {
                playerNode.play()
            }

            updateState(isPlaying: true)
            print("[AudioStreamManager] Playback started")
        } catch {
            print("[AudioStreamManager] Playback start error: \(error)")
            onError?(error)
        }
    }
    
    /// Stop all playback and clear queue (for interruption handling)
    func stopPlayback() {
        playerNode.stop()
        
        // Synchronously clear pending data to prevent "ghost" audio playback
        playbackQueue.sync {
            self.pendingAudioData.removeAll()
        }
        
        updateState(isPlaying: false)
        print("[AudioStreamManager] Playback stopped and buffer cleared")
    }
    
    // MARK: - Cleanup
    
    /// Stop everything and clean up
    func stop() {
        stopRecording()
        stopPlayback()
        
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        
        // State is already updated by stopRecording/stopPlayback via updateState()
        print("[AudioStreamManager] Audio manager stopped")
    }
    
    /// Reset audio session (call when leaving voice Q&A)
    func deactivateAudioSession() {
        stop()

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            print("[AudioStreamManager] Audio session deactivated")
        } catch {
            print("[AudioStreamManager] Failed to deactivate audio session: \(error)")
        }

        isEngineConfigured = false
        isAudioSessionConfigured = false
    }
    
    // MARK: - Interruption Handling
    
    private var wasRecordingBeforeInterruption = false
    
    func handleInterruption(started: Bool) {
        if started {
            wasRecordingBeforeInterruption = isRecording
            stop()
        } else {
            // Attempt to restart if we were recording before interruption
            if wasRecordingBeforeInterruption {
                try? startRecording()
                wasRecordingBeforeInterruption = false
            }
        }
    }
}

// MARK: - Audio Level Monitoring

extension AudioStreamManager {

    /// Get current input audio level (0.0 - 1.0) for visualization
    var inputLevel: Float {
        guard audioEngine.isRunning else { return 0 }
        // Return the actual calculated level from processInputBuffer
        return currentLevel
    }
}
#endif
