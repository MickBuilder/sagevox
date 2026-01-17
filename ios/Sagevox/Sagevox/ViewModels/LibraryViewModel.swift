import Foundation
import Combine

/// Connection state for API
enum ConnectionState {
    case connected
    case connecting
    case retrying
    case notConnected
}

/// ViewModel for the library screen
class LibraryViewModel: ObservableObject {
    private enum Constants {
        static let retryDelayNanoseconds: UInt64 = 1_000_000_000
    }
    @Published var books: [BookSummary] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var connectionState: ConnectionState = .connected

    private let apiClient: APIClient
    private var loadTask: Task<Void, Never>?
    
    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
        loadBooks()
    }

    deinit {
        loadTask?.cancel()
    }
    
    func loadBooks() {
        isLoading = true
        error = nil
        connectionState = .connecting
        
        loadTask?.cancel()
        loadTask = Task { @MainActor in
            do {
                    books = try await apiClient.fetchBooks()

                connectionState = .connected
                error = nil
            } catch {
                // Retry once
                connectionState = .retrying
                try? await Task.sleep(nanoseconds: Constants.retryDelayNanoseconds)
                
                do {
                books = try await apiClient.fetchBooks()

                    connectionState = .connected
                    self.error = nil
                } catch {
                    connectionState = .notConnected
                    self.error = "Not connected to server"
                }
            }
            isLoading = false
        }
    }
    
    /// Fetch full book details (with chapters and transcripts)
    func fetchBook(id: String) async throws -> Book {
        return try await apiClient.fetchBook(id: id)
    }
    
    /// Get cover image URL for a book
    func coverURL(for book: BookSummary) -> URL? {
        guard let coverUrlString = book.coverUrl,
              let url = URL(string: coverUrlString) else {
            return nil
        }
        return url
    }
}
