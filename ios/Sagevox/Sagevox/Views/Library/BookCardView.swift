import SwiftUI

/// Card view for a book in the library grid
struct BookCardView: View {
    let book: BookSummary
    
    @ObservedObject private var progressTracker = ProgressTracker.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BookCoverView(
                url: book.coverUrl.flatMap { URL(string: $0) },
                cornerRadius: 8,
                placeholderIconSize: 40
            )
            .aspectRatio(2/3, contentMode: .fit)
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                // Progress indicator
                if progress > 0 {
                    ProgressRing(progress: progress)
                        .frame(width: 30, height: 30)
                        .padding(8)
                }
            }
            
            // Title
            Text(book.title)
                .font(.headline)
                .lineLimit(2)
                .foregroundColor(.primary)
            
            // Author
            Text(book.author)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            
            // Duration
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.caption2)
                Text(book.formattedDuration)
                    .font(.caption2)
            }
            .foregroundColor(.secondary)
        }
    }
    
    private var progress: Double {
        let bookProgress = progressTracker.getProgress(for: book.id)
        guard book.totalDurationSeconds > 0, book.totalChapters > 0 else { return 0 }
        let averageChapterDuration = book.totalDurationSeconds / Double(book.totalChapters)
        let completedSeconds = Double(max(bookProgress.currentChapter - 1, 0)) * averageChapterDuration
            + max(bookProgress.positionSeconds, 0)
        let overallProgress = completedSeconds / book.totalDurationSeconds
        return min(max(overallProgress, 0), 1.0)
    }
}

/// Circular progress ring indicator
struct ProgressRing: View {
    let progress: Double
    
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.5))
            
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AppTheme.accentGold,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            
            Text("\(Int(progress * 100))%")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white)
        }
    }
}

#Preview {
    BookCardView(book: BookSummary(
        id: "sample",
        title: "Sample Book",
        author: "Sample Author",
        description: "A sample book",
        coverUrl: nil,
        totalChapters: 10,
        totalDurationSeconds: 3600
    ))
    .frame(width: 160)
    .padding()
}
