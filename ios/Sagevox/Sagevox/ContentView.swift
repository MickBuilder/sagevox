import SwiftUI

struct ContentView: View {
    @EnvironmentObject var audioPlayer: AudioPlayerService
    
    var body: some View {
        ZStack(alignment: .bottom) {
            NavigationStack {
                LibraryView()
            }
            
            // Mini player at bottom when playing
            if audioPlayer.currentBook != nil {
                MiniPlayerView()
                    .transition(.move(edge: .bottom))
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AudioPlayerService())
        .environmentObject(LibraryViewModel())
}
