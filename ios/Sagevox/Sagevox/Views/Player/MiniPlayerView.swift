import SwiftUI

/// Mini player bar shown at bottom of screen during playback
struct MiniPlayerView: View {
    @EnvironmentObject var audioPlayer: AudioPlayerService
    @State private var showingFullPlayer = false
    
    var body: some View {
        if let book = audioPlayer.currentBook {
            VStack(spacing: 0) {
                // Progress bar
                GeometryReader { geometry in
                    Rectangle()
                        .fill(AppTheme.primaryPurple)
                        .frame(width: geometry.size.width * progressPercent)
                }
                .frame(height: 2)
                
                // Mini player content
                HStack(spacing: 12) {
                    // Cover thumbnail
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary)
                    }
                    
                    // Title and chapter
                    VStack(alignment: .leading, spacing: 2) {
                        Text(book.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        
                        Text(audioPlayer.currentChapter?.title ?? "")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    // Play/Pause button
                    Button(action: { audioPlayer.togglePlayPause() }) {
                        Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                    }
                    .foregroundColor(.primary)
                    
                    // Skip forward
                    Button(action: { audioPlayer.seekForward(15) }) {
                        Image(systemName: "goforward.15")
                            .font(.title3)
                    }
                    .foregroundColor(.primary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
            }
            .onTapGesture {
                showingFullPlayer = true
            }
            .fullScreenCover(isPresented: $showingFullPlayer) {
                PlayerView(book: book, audioPlayer: audioPlayer)
            }
        }
    }
    
    private var progressPercent: Double {
        guard audioPlayer.duration > 0 else { return 0 }
        return audioPlayer.currentTime / audioPlayer.duration
    }
}

#Preview {
    VStack {
        Spacer()
        MiniPlayerView()
    }
    .environmentObject({
        let player = AudioPlayerService()
        // Would need to load a book for preview
        return player
    }())
}
