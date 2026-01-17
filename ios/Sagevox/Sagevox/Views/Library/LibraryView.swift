import SwiftUI

/// Main library view showing all available books
struct LibraryView: View {
    @EnvironmentObject var libraryViewModel: LibraryViewModel
    @EnvironmentObject var audioPlayer: AudioPlayerService

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)
    ]

    var body: some View {
        ZStack {
            // Background
            AppTheme.backgroundLavender
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Connection state banner
                if libraryViewModel.connectionState == .notConnected {
                    HStack {
                        Image(systemName: "wifi.slash")
                        Text("Not connected to server")
                        Spacer()
                        Button("Retry") {
                            libraryViewModel.loadBooks()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding()
                    .background(Color.red.opacity(0.15))
                    .foregroundColor(.red)
                } else if libraryViewModel.connectionState == .retrying {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Reconnecting...")
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Color.orange.opacity(0.15))
                    .foregroundColor(.orange)
                }

                // Content
                ScrollView {
                    if libraryViewModel.isLoading && libraryViewModel.books.isEmpty {
                        ProgressView("Loading books...")
                            .padding(.top, 100)
                    } else if let error = libraryViewModel.error, libraryViewModel.books.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.largeTitle)
                                .foregroundColor(.orange)
                            Text(error)
                                .multilineTextAlignment(.center)
                            Button("Retry") {
                                libraryViewModel.loadBooks()
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.top, 100)
                    } else if libraryViewModel.books.isEmpty {
                        VStack(spacing: 16) {
                            Image("Logo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 120, height: 120)
                            Text("No Books Available")
                                .font(.title2)
                                .foregroundColor(AppTheme.primaryPurple)
                            Text("Add audiobooks to get started")
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 100)
                    } else {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(libraryViewModel.books) { book in
                                NavigationLink(destination: BookDetailView(bookSummary: book)) {
                                    BookCardView(book: book)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                }
            }
        }
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { libraryViewModel.loadBooks() }) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(AppTheme.primaryPurple)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        LibraryView()
            .environmentObject(LibraryViewModel())
            .environmentObject(AudioPlayerService())
    }
}
