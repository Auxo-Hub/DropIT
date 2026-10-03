import SwiftUI
import AppKit

public struct TransferProgressView: View {
    @ObservedObject var appState: AppState
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    public var body: some View {
        VStack(spacing: 28) {
            Spacer()
            
            // Circular / Animated progress indicator
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 12)
                    .frame(width: 150, height: 150)
                
                Circle()
                    .trim(from: 0.0, to: CGFloat(min(appState.transferProgress, 1.0)))
                    .stroke(
                        LinearGradient(
                            colors: [Color.blue, Color.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(Angle(degrees: -90))
                    .frame(width: 150, height: 150)
                    .animation(.linear(duration: 0.2), value: appState.transferProgress)
                
                VStack(spacing: 4) {
                    Text("\(Int(appState.transferProgress * 100))%")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    
                    if !appState.transferSpeedFormatted.isEmpty {
                        Text(appState.transferSpeedFormatted)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Transfer Details
            VStack(spacing: 8) {
                Text("Sending to receiver...")
                    .font(.headline)
                
                Text(appState.fileName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 320)
                
                HStack(spacing: 12) {
                    if !appState.bytesTransferredFormatted.isEmpty {
                        Text(appState.bytesTransferredFormatted)
                    }
                    if !appState.timeRemainingFormatted.isEmpty {
                        Text("•")
                        Text(appState.timeRemainingFormatted)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            if let receiver = appState.receiverIP {
                HStack(spacing: 6) {
                    Image(systemName: "iphone.and.arrow.forward")
                    Text("Connected: \(receiver)")
                }
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.secondary.opacity(0.15)))
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(role: .cancel, action: {
                appState.stopSharing()
            }) {
                Text("Cancel Transfer")
                    .frame(width: 140)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
        .padding(32)
    }
}
