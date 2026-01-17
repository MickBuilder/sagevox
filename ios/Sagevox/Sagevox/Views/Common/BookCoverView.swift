import SwiftUI

/// A reusable view for displaying book covers with consistent styling
struct BookCoverView: View {
    let url: URL?
    let width: CGFloat?
    let height: CGFloat?
    let cornerRadius: CGFloat
    let placeholderIconSize: CGFloat
    
    init(
        url: URL?,
        width: CGFloat? = nil,
        height: CGFloat? = nil,
        cornerRadius: CGFloat = 8,
        placeholderIconSize: CGFloat = 40
    ) {
        self.url = url
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
        self.placeholderIconSize = placeholderIconSize
    }
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.gray.opacity(0.2))
            
            if let url = url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        placeholderView
                    @unknown default:
                        placeholderView
                    }
                }
            } else {
                placeholderView
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
    
    private var placeholderView: some View {
        Image(systemName: "book.closed.fill")
            .font(.system(size: placeholderIconSize))
            .foregroundColor(.secondary)
    }
}
