import SwiftUI
import AppKit

public struct ShareView: View {
    @ObservedObject var appState: AppState
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    public var body: some View {
        VStack(spacing: 20) {
            // File Header Card
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 48, height: 48)
                    Image(systemName: appState.sfSymbol)
                        .font(.system(size: 24))
                        .foregroundColor(.accentColor)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(appState.fileName)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    HStack(spacing: 8) {
                        Text(appState.formattedFileSize)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text("•")
                            .foregroundColor(.secondary)
                        
                        Text("Port \(appState.serverPort)")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .cornerRadius(4)
                    }
                }
                
                Spacer()
                
                Button(action: {
                    appState.stopSharing()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Cancel sharing")
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(NSColor.controlBackgroundColor).opacity(0.5)))
            
            // Connection Status Banner
            if case .clientConnected(let ip) = appState.state {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("Device connected from \(ip)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                }
                .padding(.vertical, 4)
            } else {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                    Text("Scan with iPhone, Android, or any device camera")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
            
            // QR Code Box
            if let qrImage = appState.qrCodeImage {
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 4)
                        .frame(width: 250, height: 250)
                    
                    Image(nsImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 230, height: 230)
                }
                .padding(.vertical, 6)
            } else {
                ProgressView("Generating QR Code...")
                    .frame(height: 250)
            }
            
            // Network interface selector if multiple are available
            if appState.availableInterfaces.count > 1 {
                HStack(spacing: 8) {
                    Text("Network:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: Binding(
                        get: { appState.selectedInterface ?? appState.availableInterfaces.first! },
                        set: { appState.updateSelectedInterface($0) }
                    )) {
                        ForEach(appState.availableInterfaces) { iface in
                            Text(iface.displayName).tag(iface)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                }
            }
            
            // Link & Copy Box
            HStack(spacing: 8) {
                Text(appState.serverURLString)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.textBackgroundColor).opacity(0.5)))
                
                Button(action: {
                    appState.copyLink()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: appState.showCopiedAlert ? "checkmark" : "doc.on.doc")
                        Text(appState.showCopiedAlert ? "Copied!" : "Copy")
                    }
                    .frame(width: 70)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                
                Button(action: {
                    appState.openInBrowser()
                }) {
                    Image(systemName: "safari")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Open in Browser preview")
            }
            
            Spacer(minLength: 0)
        }
        .padding(24)
    }
}
