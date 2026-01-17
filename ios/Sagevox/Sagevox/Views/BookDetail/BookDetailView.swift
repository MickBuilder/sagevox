import SwiftUI

/// Detailed view for a single book with chapter list
struct BookDetailView: View {
    let bookSummary: BookSummary
    
    @EnvironmentObject var audioPlayer: AudioPlayerService
    @ObservedObject private var progressTracker = ProgressTracker.shared
    @State private var showingPlayer = false
    @State private var book: Book?
    @State private var isLoading = true
    @State private var error: String?
    
    var body: some View {
        Group {
            if isLoading {
                VStack {
                    ProgressView("Loading book details...")
                }
            } else if let error = error {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text(error)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        loadBook()
                    }
                    .buttonStyle(.bordered)
                }
            } else if let book = book {
                bookDetailContent(book: book)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            loadBook()
        }
    }
    
    @ViewBuilder
    private func bookDetailContent(book: Book) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header with cover and info
                HStack(alignment: .top, spacing: 16) {
                    BookCoverView(
                        url: bookSummary.coverUrl.flatMap { URL(string: $0) },
                        width: 120,
                        height: 180,
                        cornerRadius: 12,
                        placeholderIconSize: 40
                    )
                    
                    // Book info
                    VStack(alignment: .leading, spacing: 8) {
                        Text(book.title)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text(book.author)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        // Duration and chapters
                        HStack(spacing: 16) {
                            Label(book.formattedDuration, systemImage: "clock")
                            Label("\(book.totalChapters) chapters", systemImage: "list.bullet")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        
                        // Play button
                        Button(action: { startPlaying(book: book) }) {
                            HStack {
                                Image(systemName: isInProgress ? "play.fill" : "play.circle.fill")
                                Text(isInProgress ? "Continue" : "Start Listening")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(AppTheme.primaryPurple)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                    }
                }
                .padding()
                
                // Description
                if !book.description.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("About")
                            .font(.headline)
                        Text(book.description)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                }
                
                // Chapter list
                VStack(alignment: .leading, spacing: 12) {
                    Text("Chapters")
                        .font(.headline)
                        .padding(.horizontal)

                    if book.chapters.isEmpty {
                        Text("No chapters available for this book.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                    } else {
                        ForEach(book.chapters) { chapter in
                            ChapterRowView(
                                chapter: chapter,
                                isCurrentChapter: chapter.number == currentChapterNumber,
                                onTap: { playChapter(chapter, in: book) }
                            )
                        }
                    }
                }
            }
            .padding(.bottom, 100) // Space for mini player
        }
        .fullScreenCover(isPresented: $showingPlayer) {
            PlayerView(book: book, audioPlayer: audioPlayer)
        }
    }
    
    private var currentProgress: ReadingProgress {
        progressTracker.getProgress(for: bookSummary.id)
    }
    
    /// The currently playing chapter number - uses live player state if this book is playing,
    /// otherwise falls back to persisted progress
    private var currentChapterNumber: Int {
        // If this book is currently loaded in the player, use live state
        if audioPlayer.currentBook?.id == bookSummary.id,
           let chapterNumber = audioPlayer.currentChapter?.number {
            return chapterNumber
        }
        // Otherwise use persisted progress
        return currentProgress.currentChapter
    }
    
    private var isInProgress: Bool {
        currentProgress.currentChapter > 1 || currentProgress.positionSeconds > 0
    }
    
    private func loadBook() {
        isLoading = true
        error = nil

        Task {
            do {
                let fetchedBook = try await APIClient.shared.fetchBook(id: bookSummary.id)
                await MainActor.run {
                    self.book = fetchedBook
                    self.isLoading = false

                    Analytics.shared.trackBookOpened(
                        bookId: fetchedBook.id,
                        title: fetchedBook.title,
                        author: fetchedBook.author
                    )
                }
            } catch {
                await MainActor.run {
                    self.error = "Failed to load book: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    private func startPlaying(book: Book) {
        audioPlayer.loadBook(book)
        audioPlayer.play()
        showingPlayer = true
    }
    
    private func playChapter(_ chapter: Chapter, in book: Book) {
        audioPlayer.loadBook(book)
        audioPlayer.loadChapter(chapter)
        audioPlayer.play()
        showingPlayer = true
    }
}

/// Row view for a single chapter
struct ChapterRowView: View {
    let chapter: Chapter
    let isCurrentChapter: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                // Chapter number
                Text("\(chapter.number)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .frame(width: 30, height: 30)
                    .background(isCurrentChapter ? AppTheme.primaryPurple : Color.gray.opacity(0.2))
                    .foregroundColor(isCurrentChapter ? .white : .primary)
                    .cornerRadius(15)
                
                // Title
                VStack(alignment: .leading, spacing: 2) {
                    Text(chapter.title)
                        .font(.body)
                        .foregroundColor(.primary)
                    
                    Text(chapter.formattedDuration)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Play indicator
                if isCurrentChapter {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundColor(AppTheme.primaryPurple)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(isCurrentChapter ? AppTheme.primaryPurple.opacity(0.1) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        BookDetailView(bookSummary: BookSummary(
            id: "sample",
            title: "Sample Book",
            author: "Sample Author",
            description: "A sample description",
            coverUrl: nil,
            totalChapters: 10,
            totalDurationSeconds: 3600
        ))
        .environmentObject(AudioPlayerService())
    }
}
