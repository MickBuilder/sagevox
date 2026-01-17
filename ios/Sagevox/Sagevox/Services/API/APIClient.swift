import Foundation

/// API client for SageVox backend
actor APIClient {
    static let shared = APIClient()
    
    // Centralized Server URL configuration
    static let serverURL: URL = {
        if let urlString = ProcessInfo.processInfo.environment["SAGEVOX_SERVER_URL"],
           let url = URL(string: urlString) {
            return url
        }
        return URL(string: "http://localhost:8000")
            ?? URL(string: "http://localhost")!
    }()
    
    // Instance property using the static configuration
    private let baseURL = APIClient.serverURL
    
    private let session: URLSession
    private let decoder: JSONDecoder
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
        
        self.decoder = JSONDecoder()
        // Note: Models use explicit CodingKeys for snake_case conversion
    }
    
    // MARK: - API Endpoints
    
    /// Fetch all books in library
    func fetchBooks() async throws -> [BookSummary] {
        let url = baseURL.appendingPathComponent("api/books")
        let (data, response) = try await session.data(from: url)
        
        try validateResponse(response)
        return try decoder.decode([BookSummary].self, from: data)
    }
    
    /// Fetch full book details with transcripts
    func fetchBook(id: String) async throws -> Book {
        let url = baseURL.appendingPathComponent("api/books/\(id)")
        let (data, response) = try await session.data(from: url)
        
        try validateResponse(response)
        return try decoder.decode(Book.self, from: data)
    }
    
    // MARK: - URL Builders (nonisolated for synchronous access)
    
    private nonisolated func bookAssetsRootURL(bookId: String) -> URL {
        APIClient.serverURL
            .appendingPathComponent("books")
            .appendingPathComponent(bookId)
    }

    /// Construct audio URL for a chapter
    nonisolated func audioURL(bookId: String, audioFile: String) -> URL {
        bookAssetsRootURL(bookId: bookId)
            .appendingPathComponent(audioFile)
    }
    
    /// Construct cover image URL
    nonisolated func coverURL(bookId: String, coverImage: String) -> URL {
        bookAssetsRootURL(bookId: bookId)
            .appendingPathComponent(coverImage)
    }

    /// Get the base URL for a book's assets
    nonisolated func bookAssetsBaseURL(bookId: String) -> URL {
        bookAssetsRootURL(bookId: bookId)
    }
    
    // MARK: - Helpers
    
    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200..<300:
            return
        case 401:
            throw APIError.unauthorized
        case 404:
            throw APIError.notFound
        case 429:
            throw APIError.rateLimited
        case 500..<600:
            throw APIError.serverError(httpResponse.statusCode)
        default:
            throw APIError.httpError(httpResponse.statusCode)
        }
    }
}

// MARK: - API Errors

enum APIError: LocalizedError {
    case invalidResponse
    case unauthorized
    case notFound
    case rateLimited
    case serverError(Int)
    case httpError(Int)
    case notConnected
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response"
        case .unauthorized:
            return "Unauthorized"
        case .notFound:
            return "Resource not found"
        case .rateLimited:
            return "Too many requests"
        case .serverError(let code):
            return "Server error (\(code))"
        case .httpError(let code):
            return "HTTP error (\(code))"
        case .notConnected:
            return "Not connected to server"
        }
    }
}
