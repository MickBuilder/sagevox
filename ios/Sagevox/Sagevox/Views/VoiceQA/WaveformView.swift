import SwiftUI

/// A view that renders a live audio visualizer with symmetric bars.
/// Displays real-time audio levels as a frequency-style visualization.
struct WaveformView: View {
    /// Array of levels (0.0 to 1.0)
    let levels: [CGFloat]
    /// True when user is speaking (listening state), false when AI is speaking (responding state)
    var isUserSpeaking: Bool = true
    
    private var waveformColor: Color {
        isUserSpeaking ? AppTheme.primaryPurple : AppTheme.accentGold
    }
    
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<levels.count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(waveformColor)
                    .frame(width: 4)
                    .frame(height: max(4, levels[index] * 64))
                    .animation(.easeOut(duration: 0.08), value: levels[index])
            }
        }
        .frame(height: 80)
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.15), value: isUserSpeaking)
    }
}

#Preview("User Speaking") {
    WaveformView(levels: (0..<40).map { _ in CGFloat.random(in: 0.1...1.0) }, isUserSpeaking: true)
        .padding()
}

#Preview("AI Speaking") {
    WaveformView(levels: (0..<40).map { _ in CGFloat.random(in: 0.1...1.0) }, isUserSpeaking: false)
        .padding()
}
