import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct SessionHubView: View {
    @ObservedObject var appState: AppState
    @State private var selectedTab: Int = 0 // 0: Shared Files, 1: Received Files, 2: History
    @State private var showQRModal: Bool = false
    @State private var showDevicesModal: Bool = false
    @State private var historyDeviceFilter: String? = nil
    @State private var isDragTargeted: Bool = false
    @State private var browsingProvider: DeviceStorageProvider?
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Top Session Toolbar
            HStack(spacing: 12) {
                let activePeers = appState.devices.filter { !$0.isBlocked && !$0.isHost }
                HStack(spacing: 8) {
                    Circle()
                        .fill(activePeers.isEmpty ? Color.blue : Color.green)
                        .frame(width: 8, height: 8)
                    
                    if activePeers.isEmpty {
                        Text("Session Active • Waiting for scan")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("\(activePeers.count) device\(activePeers.count > 1 ? "s" : "") connected")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                    }
                }
                
                Spacer()
                
                Button(action: { showDevicesModal.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "laptopcomputer.and.iphone")
                        Text("Devices (\(appState.devices.filter { !$0.isBlocked }.count))")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button(action: { showQRModal.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "qrcode")
                        Text("QR Code")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button(action: { appState.refreshPairingCode() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Refresh Code")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Issue a new pairing code. Existing devices stay connected.")
                
                Button(action: { appState.openDownloadsFolder() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                        Text("Downloads")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Open Dropit Downloads folder in Finder")
                
                Button(role: .destructive, action: { appState.endSession() }) {
                    Text("End Session")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
            
            Divider()
            
            // Live Transfer Banner (if active)
            if let transfer = appState.activeTransfer {
                VStack(spacing: 6) {
                    HStack {
                        Image(systemName: transfer.isReceiving ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                            .foregroundColor(transfer.isReceiving ? .green : .blue)
                        
                        Text(transfer.isReceiving ? "Receiving from device:" : "Sending to device:")
                            .font(.caption)
                            .fontWeight(.medium)
                        
                        Text(transfer.fileName)
                            .font(.caption)
                            .fontWeight(.bold)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        
                        Spacer()
                        
                        Text("\(Int(transfer.progress * 100))%")
                            .font(.caption)
                            .fontWeight(.bold)
                    }
                    
                    ProgressView(value: transfer.progress)
                        .progressViewStyle(.linear)
                    
                    HStack {
                        Text(transfer.speedFormatted)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(FileMIME.formatBytes(transfer.bytesTransferred)) of \(FileMIME.formatBytes(transfer.totalBytes))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.accentColor.opacity(0.08)))
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }
            
            // Segmented Tab Picker
            Picker("", selection: $selectedTab) {
                Text("Shared (\(appState.sharedFiles.count))").tag(0)
                Text("Received (\(appState.receivedFiles.count))").tag(1)
                Text("History (\(appState.transferHistory.count))").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 6)
            
            // Tab Content
            if selectedTab == 0 {
                sharedFilesView
            } else if selectedTab == 1 {
                receivedFilesView
            } else {
                historyFilesView
            }
        }
        .sheet(isPresented: $showQRModal) {
            qrCodeSheetView
        }
        .sheet(isPresented: $showDevicesModal) {
            devicesSheetView
        }
        .sheet(item: $browsingProvider) { provider in
            DeviceStorageView(appState: appState, provider: provider)
        }
    }
    
    // MARK: - Shared Files Tab
    private var sharedFilesView: some View {
        VStack(spacing: 12) {
            // Drop target banner to add more files anytime
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isDragTargeted ? Color.accentColor : Color.secondary.opacity(0.25),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isDragTargeted ? Color.accentColor.opacity(0.08) : Color(NSColor.controlBackgroundColor).opacity(0.3))
                    )
                
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.accentColor)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add more files to this session")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("Drag and drop files here or click to browse")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Browse Files") {
                        openAddFilesDialog()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .frame(height: 56)
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
                for provider in providers {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        if let url = url {
                            DispatchQueue.main.async {
                                appState.addSharedFiles([url])
                            }
                        }
                    }
                }
                return true
            }
            
            // List of shared files
            if appState.sharedFiles.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "arrow.up.doc")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No files currently shared")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Drop files above to make them instantly available to connected devices")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Spacer()
                }
            } else {
                List {
                    ForEach(appState.sharedFiles) { item in
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.accentColor.opacity(0.12))
                                    .frame(width: 34, height: 34)
                                Image(systemName: item.symbol)
                                    .font(.system(size: 16))
                                    .foregroundColor(.accentColor)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                
                                HStack(spacing: 6) {
                                    Text(item.formattedSize)
                                    if let targetName = item.targetDeviceName {
                                        Text("•")
                                        Text("For \(targetName)")
                                            .foregroundColor(.blue)
                                    }
                                    if let senderName = item.senderDeviceName, item.senderDeviceId != "host_mac" {
                                        Text("•")
                                        Text("From \(senderName)")
                                            .foregroundColor(.purple)
                                    }
                                }
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                appState.removeSharedFile(id: item.id)
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Remove file from session")
                        }
                        .padding(.vertical, 3)
                    }
                }
                .listStyle(.inset)
            }
        }
    }
    
    // MARK: - Received Files Tab
    private var receivedFilesView: some View {
        VStack(spacing: 8) {
            if appState.receivedFiles.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No files received yet")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Tap 'Send to Mac' on the receiver's screen to upload files directly to this Mac")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Spacer()
                }
            } else {
                List {
                    ForEach(appState.receivedFiles) { item in
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.green.opacity(0.12))
                                    .frame(width: 34, height: 34)
                                Image(systemName: item.symbol)
                                    .font(.system(size: 16))
                                    .foregroundColor(.green)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                
                                HStack(spacing: 6) {
                                    Text(item.formattedSize)
                                    Text("•")
                                    Text("From \(item.senderIP)")
                                }
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                appState.showInFinder(filePath: item.savedPath)
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "magnifyingglass")
                                    Text("Finder")
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                        .padding(.vertical, 3)
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(.top, 6)
    }
    
    // MARK: - History Files Tab
    private var historyFilesView: some View {
        VStack(spacing: 8) {
            if let filterId = historyDeviceFilter,
               let device = appState.devices.first(where: { $0.id == filterId }) {
                HStack {
                    Text("Filtered by device: **\(device.name)**")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Clear Filter") {
                        historyDeviceFilter = nil
                    }
                    .controlSize(.mini)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }
            
            let filteredHistory = appState.transferHistory.filter { item in
                if let f = historyDeviceFilter {
                    return item.deviceId == f
                }
                return true
            }
            
            if filteredHistory.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No file transfer history yet")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Files sent to devices and received on this Mac will be recorded here")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Spacer()
                }
            } else {
                List {
                    ForEach(filteredHistory) { record in
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(record.direction == .sentToDevice ? Color.blue.opacity(0.12) : Color.green.opacity(0.12))
                                    .frame(width: 34, height: 34)
                                Image(systemName: record.direction == .sentToDevice ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(record.direction == .sentToDevice ? .blue : .green)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.fileName)
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                
                                HStack(spacing: 6) {
                                    Text(record.direction.label)
                                        .foregroundColor(record.direction == .sentToDevice ? .blue : .green)
                                    Text("•")
                                    Text(record.formattedSize)
                                    Text("•")
                                    Text(record.deviceName)
                                    Text("•")
                                    Text(record.timestamp, style: .time)
                                }
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                        .padding(.vertical, 3)
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(.top, 6)
    }
    
    // MARK: - Connected Devices Sheet
    private var devicesSheetView: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Connected Devices")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    showDevicesModal = false
                }
                .controlSize(.small)
            }
            
            if appState.devices.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "laptopcomputer.and.iphone")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No devices found")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(appState.devices) { device in
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(device.isBlocked ? Color.red.opacity(0.1) : Color.accentColor.opacity(0.12))
                                    .frame(width: 38, height: 38)
                                Image(systemName: device.iconName)
                                    .font(.system(size: 18))
                                    .foregroundColor(device.isBlocked ? .red : .accentColor)
                            }
                            
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(device.name)
                                        .font(.system(size: 13, weight: .semibold))
                                    
                                    if device.isHost {
                                        Text("Host")
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1)
                                            .background(Color.blue.opacity(0.15))
                                            .foregroundColor(.blue)
                                            .cornerRadius(6)
                                    } else if device.isBlocked {
                                        Text("Disconnected")
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1)
                                            .background(Color.red.opacity(0.15))
                                            .foregroundColor(.red)
                                            .cornerRadius(6)
                                    } else {
                                        Text("Active")
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1)
                                            .background(Color.green.opacity(0.15))
                                            .foregroundColor(.green)
                                            .cornerRadius(6)
                                    }
                                }
                                
                                HStack(spacing: 6) {
                                    Text(device.ip)
                                    Text("•")
                                    Text("Last active: \(device.lastActive, style: .time)")
                                }
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            // History button
                            Button(action: {
                                historyDeviceFilter = device.id
                                selectedTab = 2
                                showDevicesModal = false
                            }) {
                                Image(systemName: "clock")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("View file history for this device")
                            
                            // Browse the phone's own storage (Dropit Phone app)
                            if !device.isHost, !device.isBlocked,
                               let provider = appState.deviceProviders.first(where: { $0.address == device.ip }) {
                                Button(action: {
                                    showDevicesModal = false
                                    browsingProvider = provider
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "folder.badge.gearshape")
                                        Text("Storage")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.purple)
                                .controlSize(.small)
                                .help("Browse, read and write files on \(device.name)")
                            }

                            // Send files button
                            if !device.isHost && !device.isBlocked {
                                Button(action: {
                                    showDevicesModal = false
                                    let panel = NSOpenPanel()
                                    panel.allowsMultipleSelection = true
                                    panel.canChooseDirectories = false
                                    panel.canChooseFiles = true
                                    panel.prompt = "Send to \(device.name)"
                                    if panel.runModal() == .OK {
                                        appState.addSharedFiles(panel.urls, targetDevice: device)
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "paperplane.fill")
                                        Text("Send")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .help("Send files directly to \(device.name)")
                            }
                            
                            // Disconnect Button
                            if !device.isHost && !device.isBlocked {
                                Button(role: .destructive, action: {
                                    appState.disconnectDevice(id: device.id)
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "xmark.circle")
                                        Text("Disconnect")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                                .controlSize(.small)
                                .help("Disconnect and block this device from the session")
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(20)
        .frame(width: 480, height: 360)
    }
    
    // MARK: - QR Code Sheet Modal
    private var qrCodeSheetView: some View {
        VStack(spacing: 18) {
            HStack {
                Text("Connect a Device")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    showQRModal = false
                }
                .controlSize(.small)
            }
            
            if let qrImage = appState.qrCodeImage {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 3)
                        .frame(width: 220, height: 220)
                    
                    Image(nsImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200, height: 200)
                }
            }
            
            VStack(spacing: 8) {
                Text(appState.activeURLString())
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                HStack(spacing: 8) {
                    Button(action: { appState.copyLink() }) {
                        HStack(spacing: 4) {
                            Image(systemName: appState.showCopiedAlert ? "checkmark" : "doc.on.doc")
                            Text(appState.showCopiedAlert ? "Copied!" : "Copy Link")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button(action: { appState.openInBrowser() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "safari")
                            Text("Open")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button(action: { appState.refreshPairingCode() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("New Code")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Old codes stop working; connected devices are unaffected")
                }
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                if appState.isSecureAvailable {
                    Toggle(isOn: Binding(
                        get: { appState.useSecureConnection },
                        set: { appState.setUseSecureConnection($0) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Use HTTPS (encrypted)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("Requires this Mac's certificate on your device.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    
                    if appState.useSecureConnection {
                        HStack(spacing: 6) {
                            Image(systemName: "lock.shield")
                                .foregroundColor(.green)
                            Text("Certificates on this Mac: \(appState.certificateInfo?.coveredIPs.count ?? 0) address(es)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        Button(action: { appState.revealCertificateInFinder() }) {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.badge.gearshape")
                                Text("Save Certificate to Install on Device")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                } else {
                    Label("HTTPS unavailable", systemImage: "lock.slash")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(24)
        .frame(width: 340)
    }
    
    private func openAddFilesDialog() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Add to Session"
        
        if panel.runModal() == .OK {
            appState.addSharedFiles(panel.urls)
        }
    }
}
