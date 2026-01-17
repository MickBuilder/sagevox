import SwiftUI

/// Full-screen audio player view
struct PlayerView: View {
    let book: Book
    
    @EnvironmentObject var audioPlayer: AudioPlayerService
    @Environment(\.dismiss) private var dismiss
    @State private var showingTextFollowAlong = false
    @State private var showingSpeedPicker = false
    
    @StateObject private var voiceQA: VoiceQAViewModel
    
    init(book: Book, audioPlayer: AudioPlayerService) {
        self.book = book
        let chapterNumber = audioPlayer.currentChapter?.number ?? 1
        _voiceQA = StateObject(wrappedValue: VoiceQAViewModel(
            book: book,
            chapter: chapterNumber,
            audioPlayer: audioPlayer
        ))
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background with theme
                AppTheme.backgroundLavender
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Network error banner
                    if let error = audioPlayer.playbackError {
                        HStack {
                            Image(systemName: "wifi.slash")
                            Text(error)
                            Spacer()
                        }
                        .padding()
                        .background(Color.red.opacity(0.15))
                        .foregroundColor(.red)
                    }
                    
                    // Cover art (remote)
                    BookCoverView(
                        url: book.coverImage.map { APIClient.shared.coverURL(bookId: book.id, coverImage: $0) },
                        width: 280,
                        height: 280,
                        cornerRadius: 16,
                        placeholderIconSize: 80
                    )
                    .shadow(radius: 10)
                    .padding(.top, 40)
                    .overlay {
                        // Buffering overlay
                        if audioPlayer.isBuffering {
                            Color.black.opacity(0.3)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.white)
                        }
                    }
                    
                    // Title and chapter
                    VStack(spacing: 8) {
                        Text(book.title)
                            .font(.title2)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                        
                        Text(audioPlayer.currentChapter?.title ?? "")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 20)
                    .padding(.horizontal)
                    
                    Spacer()
                    
                    // Progress slider OR Voice Waveform
                    VStack(spacing: 8) {
                        if isVoiceActive {
                            WaveformView(
                                levels: voiceQA.visualizerLevels,
                                isUserSpeaking: isUserSpeaking
                            )
                            .onTapGesture {
                                // Tap waveform to end user's turn (only when listening)
                                if case .listening = voiceQA.state {
                                    voiceQA.endTurn()
                                }
                            }
                        } else {
                            Slider(
                                value: Binding(
                                    get: { audioPlayer.currentTime },
                                    set: { audioPlayer.seek(to: $0) }
                                ),
                                in: 0...max(audioPlayer.duration, 1)
                            )
                            .tint(AppTheme.primaryPurple)
                            
                            HStack {
                                Text(formatTime(audioPlayer.currentTime))
                                Spacer()
                                Text("-\(formatTime(audioPlayer.duration - audioPlayer.currentTime))")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 24)
                    .frame(height: 80) // Keep height consistent
                    
                    // Playback controls
                    PlaybackControlsView()
                        .padding(.top, 20)
                    
                    // Additional controls
                    HStack(spacing: 40) {
                        // Speed button
                        Button(action: { showingSpeedPicker = true }) {
                            VStack(spacing: 4) {
                                Image(systemName: "speedometer")
                                    .font(.title3)
                                Text("\(String(format: "%.1fx", audioPlayer.playbackSpeed))")
                                    .font(.caption2)
                            }
                        }
                        .foregroundColor(.primary)
                        
                        // Text follow-along toggle
                        Button(action: { showingTextFollowAlong.toggle() }) {
                            VStack(spacing: 4) {
                                Image(systemName: showingTextFollowAlong ? "text.alignleft" : "text.alignleft")
                                    .font(.title3)
                                Text("Text")
                                    .font(.caption2)
                            }
                        }
                        .foregroundColor(showingTextFollowAlong ? .accentColor : .primary)
                        
                        // Voice Q&A button (owl icon when inactive)
                        Button(action: toggleVoiceQA) {
                            VStack(spacing: 4) {
                                if isVoiceActive {
                                    Image(systemName: "stop.circle.fill")
                                        .font(.title3)
                                } else {
                                    Image("Logo")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 28, height: 28)
                                }
                                Text(isVoiceActive ? "Stop" : "Ask")
                                    .font(.caption2)
                            }
                        }
                        .foregroundColor(isVoiceActive ? .red : AppTheme.primaryPurple)
                    }
                    .padding(.vertical, 20)
                    
                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.down")
                            .font(.title3)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: {}) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        Button(action: {}) {
                            Label("Chapters", systemImage: "list.bullet")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showingTextFollowAlong) {
                TextFollowAlongView(book: book)
            }
            .onDisappear {
                voiceQA.disconnect()
            }
            .onChange(of: voiceQA.state) { _, newState in
                if case .resuming = newState {
                    audioPlayer.play()
                }
            }
            .onChange(of: audioPlayer.currentChapter?.number) { _, newChapter in
                if let chapter = newChapter {
                    voiceQA.updateCurrentChapter(chapter)
                }
            }
            .onReceive(voiceQA.commands) { command in
                switch command {
                case .skipBack(let seconds):
                    audioPlayer.seekBackward(Double(seconds))
                case .skipForward(let seconds):
                    audioPlayer.seekForward(Double(seconds))
                case .goToChapter(let number):
                    audioPlayer.goToChapter(number)
                }
            }
            .confirmationDialog("Playback Speed", isPresented: $showingSpeedPicker) {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { speed in
                    Button("\(String(format: "%.2gx", speed))") {
                        audioPlayer.setPlaybackSpeed(Float(speed))
                    }
                }
            }
        }
    }
    
    private var isVoiceActive: Bool {
        switch voiceQA.state {
        case .listening:
            return true
        case .connecting, .waiting, .resuming, .error:
            return false
        }
    }
    
    private var isUserSpeaking: Bool {
        if case .listening(let isAgentSpeaking) = voiceQA.state {
            return !isAgentSpeaking
        }
        return false
    }
    
    private func toggleVoiceQA() {
        if isVoiceActive {
            // Stop voice Q&A and resume audiobook playback
            voiceQA.resumePlayback()
        } else {
            // Pause audiobook and start voice Q&A
            audioPlayer.pause()
            voiceQA.connect()
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        TimeFormatter.formatTime(seconds)
    }
}

/// Playback control buttons
struct PlaybackControlsView: View {
    @EnvironmentObject var audioPlayer: AudioPlayerService
    
    var body: some View {
        HStack(spacing: 40) {
            // Previous chapter / Rewind
            Button(action: { audioPlayer.previousChapter() }) {
                Image(systemName: "backward.end.fill")
                    .font(.title)
            }
            .foregroundColor(.primary)
            
            // Skip back 15s
            Button(action: { audioPlayer.seekBackward(15) }) {
                Image(systemName: "gobackward.15")
                    .font(.title)
            }
            .foregroundColor(.primary)
            
            // Play/Pause
            Button(action: { audioPlayer.togglePlayPause() }) {
                Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 70))
            }
            .foregroundColor(AppTheme.primaryPurple)
            
            // Skip forward 15s
            Button(action: { audioPlayer.seekForward(15) }) {
                Image(systemName: "goforward.15")
                    .font(.title)
            }
            .foregroundColor(.primary)
            
            // Next chapter
            Button(action: { audioPlayer.nextChapter() }) {
                Image(systemName: "forward.end.fill")
                    .font(.title)
            }
            .foregroundColor(.primary)
        }
    }
}

#Preview {
    let service = AudioPlayerService()
    PlayerView(book: Book.sample, audioPlayer: service)
        .environmentObject(service)
}
