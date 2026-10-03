import SwiftUI
import UniformTypeIdentifiers

public struct DropZoneView: View {
    @ObservedObject var appState: AppState
    @State private var isTargeted: Bool = false
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    public var body: some View {
        VStack(spacing: 24) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(
                        isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                        style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color(NSColor.controlBackgroundColor).opacity(0.4))
                    )
                
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 72, height: 72)
                            .shadow(color: Color.blue.opacity(0.3), radius: 12, x: 0, y: 6)
                        
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white)
                    }
                    
                    VStack(spacing: 6) {
                        Text("Drag & Drop Files Here")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Text("Select single or multiple files to start sharing")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: 12) {
                        Button(action: openFileDialog) {
                            HStack(spacing: 6) {
                                Image(systemName: "folder.badge.plus")
                                Text("Choose Files...")
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        
                        Button(action: {
                            appState.startSession(with: [])
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "qrcode")
                                Text("Start Empty Session")
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .help("Start session to let connected devices upload files to this Mac first")
                    }
                }
                .padding(32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                var droppedURLs = [URL]()
                let group = DispatchGroup()
                
                for provider in providers {
                    group.enter()
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        if let url = url {
                            droppedURLs.append(url)
                        }
                        group.leave()
                    }
                }
                
                group.notify(queue: .main) {
                    if !droppedURLs.isEmpty {
                        self.appState.startSession(with: droppedURLs)
                    }
                }
                return true
            }
            
            // Footer hints
            HStack(spacing: 16) {
                Label("Direct local Wi-Fi", systemImage: "wifi")
                Label("Multi-file transfer", systemImage: "square.and.arrow.up.on.square")
                Label("Two-way upload", systemImage: "arrow.left.arrow.right")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(28)
    }
    
    private func openFileDialog() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Select Files"
        
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            appState.startSession(with: panel.urls)
        }
    }
}
