import SwiftUI
import Combine

/// Text follow-along view with synchronized sentence highlighting
struct TextFollowAlongView: View {
    let book: Book
    
    @EnvironmentObject var audioPlayer: AudioPlayerService
    @Environment(\.dismiss) private var dismiss
    
    @State private var transcript: Transcript?
    @State private var currentSegmentIndex: Int?
    @State private var isLoading = true
    @State private var error: String?
    
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    if isLoading {
                        ProgressView("Loading transcript...")
                            .padding(.top, 100)
                    } else if let error = error {
                        VStack(spacing: 16) {
                            Image(systemName: "doc.text")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text(error)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 100)
                    } else if let transcript = transcript {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(Array(transcript.segments.enumerated()), id: \.offset) { index, segment in
                                Text(segment.text)
                                    .font(.system(size: 18, design: .serif))
                                    .foregroundColor(index == currentSegmentIndex ? .primary : .secondary)
                                    .padding(.horizontal, index == currentSegmentIndex ? 8 : 0)
                                    .padding(.vertical, index == currentSegmentIndex ? 4 : 0)
                                    .background(
                                        index == currentSegmentIndex ?
                                        RoundedRectangle(cornerRadius: 8).fill(AppTheme.primaryPurple.opacity(0.15)) :
                                        RoundedRectangle(cornerRadius: 8).fill(Color.clear)
                                    )
                                    .id(index)
                                    .onTapGesture {
                                        // Seek to this segment
                                        audioPlayer.seek(to: segment.start)
                                    }
                            }
                        }
                        .padding()
                    }
                }
                .onChange(of: currentSegmentIndex) { _, newIndex in
                    if let index = newIndex {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(index, anchor: .center)
                        }
                    }
                }
            }
            .navigationTitle(audioPlayer.currentChapter?.title ?? "Transcript")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear(perform: loadTranscript)
            .onReceive(audioPlayer.$currentTime) { time in
                updateCurrentSegment(at: time)
            }
            .onReceive(audioPlayer.$currentChapter) { _ in
                loadTranscript()
            }
        }
    }
    
    private func loadTranscript() {
        guard let chapter = audioPlayer.currentChapter else {
            isLoading = false
            error = "No chapter selected"
            return
        }

        isLoading = true
        error = nil

        // Track text follow-along opened
        Analytics.shared.trackTextFollowAlongOpened(bookId: book.id, chapter: chapter.number)

        // Get transcript directly from the chapter (embedded in API response)
        if let chapterTranscript = chapter.transcript {
            if chapterTranscript.segments.isEmpty {
                self.error = "No text segments available for this chapter"
            } else {
                transcript = chapterTranscript
            }
            isLoading = false
        } else {
            self.error = "Transcript not available"
            isLoading = false
        }
    }
    
    private func updateCurrentSegment(at time: Double) {
        guard let transcript = transcript else { return }
        let segments = transcript.segments
        guard !segments.isEmpty else {
            currentSegmentIndex = nil
            return
        }

        if let currentIndex = currentSegmentIndex, currentIndex < segments.count {
            let currentSegment = segments[currentIndex]
            if time >= currentSegment.start && time < currentSegment.end {
                return
            }

            var newIndex = currentIndex
            if time >= currentSegment.end {
                while newIndex + 1 < segments.count, time >= segments[newIndex + 1].end {
                    newIndex += 1
                }
            } else if time < currentSegment.start {
                while newIndex > 0, time < segments[newIndex].start {
                    newIndex -= 1
                }
            }

            if time >= segments[newIndex].start && time < segments[newIndex].end {
                currentSegmentIndex = newIndex
            } else {
                currentSegmentIndex = transcript.segmentIndex(at: time)
            }
            return
        }

        currentSegmentIndex = transcript.segmentIndex(at: time)
    }
}

#Preview {
    TextFollowAlongView(book: Book.sample)
        .environmentObject(AudioPlayerService())
}
