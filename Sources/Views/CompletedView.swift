import SwiftUI

public struct CompletedView: View {
    @ObservedObject var appState: AppState
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    public var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 90, height: 90)
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.green)
            }
            
            VStack(spacing: 8) {
                Text("Transfer Complete!")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(appState.fileName)
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 320)
                
                Text(appState.formattedFileSize)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Text("The receiver has successfully received and saved the file.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            
            Spacer()
            
            Button(action: {
                appState.resetForNewTransfer()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text("Send Another File")
                }
                .frame(width: 160)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(32)
    }
}
