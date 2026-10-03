import SwiftUI

public struct ContentView: View {
    @ObservedObject var appState: AppState
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // App Header Bar
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.blue)
                    
                    Text("Dropit")
                        .font(.headline)
                        .fontWeight(.bold)
                }
                
                Spacer()
                
                // Status indicator
                if appState.isSessionActive {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Hub Active")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.12))
                    .clipShape(Capsule())
                } else {
                    Text("Ready")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.12))
                        .foregroundColor(.secondary)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.85))
            
            Divider()
            
            // Dynamic Screen Navigation
            Group {
                if !appState.isSessionActive {
                    DropZoneView(appState: appState)
                } else {
                    SessionHubView(appState: appState)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 480, idealWidth: 520, maxWidth: 580, minHeight: 540, idealHeight: 580, maxHeight: 660)
    }
}
