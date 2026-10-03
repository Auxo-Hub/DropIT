import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Lets the Mac browse a connected phone's storage: navigate folders, pull files onto the
/// Mac, push files to the phone, and create, rename or delete items there.
public struct DeviceStorageView: View {
    @ObservedObject var appState: AppState
    let provider: DeviceStorageProvider

    @Environment(\.dismiss) private var dismiss
    @State private var path: String = ""
    @State private var entries: [DeviceStorageClient.Entry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var transfer: TransferStatus?
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var isDragTargeted = false

    struct TransferStatus: Identifiable {
        let id = UUID()
        var title: String
        var sent: Int64
        var total: Int64?
    }

    public init(appState: AppState, provider: DeviceStorageProvider) {
        self.appState = appState
        self.provider = provider
    }

    private var client: DeviceStorageClient {
        DeviceStorageClient(provider: provider)
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let transfer = transfer {
                progressBanner(transfer)
            }

            breadcrumbs

            content

            if let errorMessage = errorMessage {
                errorBanner(errorMessage)
            }

            Divider()
            footer
        }
        .frame(width: 620, height: 560)
        .task { reload() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: "iphone")
                    .font(.system(size: 17))
                    .foregroundColor(.accentColor)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(provider.displayName)
                    .font(.headline)
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("\(provider.address):\(provider.port)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if provider.supportsAllFilesAccess {
                        Text("all-files access on")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.15))
                            .foregroundColor(.green)
                            .clipShape(Capsule())
                    }
                }
            }
            Spacer()
            Button("Done") { dismiss() }
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Breadcrumbs

    private var breadcrumbs: some View {
        HStack(spacing: 4) {
            Button("Phone") { navigate(to: "") }
                .font(.caption.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundColor(path.isEmpty ? .primary : .secondary)

            let segments = path
                .replacingOccurrences(of: "safroot:", with: "")
                .replacingOccurrences(of: "fsroot:", with: "")
                .split(separator: "/")
                .filter { !$0.isEmpty }

            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                Text("/")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button {
                    var candidate = ""
                    for (offset, item) in segments.enumerated() where offset <= index {
                        candidate += "/" + item
                    }
                    navigate(to: pathPrefix(for: index) + candidate)
                } label: {
                    Text(String(segment).replacingOccurrences(of: "@", with: " / "))
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .foregroundColor(index == segments.count - 1 ? .primary : .secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    /// SAF breadcrumbs carry the tree id after `@`, so rebuild the prefix as the user walks up.
    private func pathPrefix(for index: Int) -> String {
        if path.hasPrefix("safroot:") { return "safroot:" }
        if path.hasPrefix("saf:") {
            if let at = path.lastIndex(of: "@") { return "saf:" }
        }
        if path.hasPrefix("fsroot:") { return "fsroot:" }
        return path.hasPrefix("file:") ? "file:" : ""
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading && entries.isEmpty {
            VStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if entries.isEmpty {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "folder")
                    .font(.system(size: 34))
                    .foregroundColor(.secondary.opacity(0.5))
                Text("This folder is empty")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text("Drop files here to copy them onto the phone.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(entries) { entry in
                    row(entry)
                }
            }
            .listStyle(.inset)
            .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
                handleDrop(providers)
                return true
            }
            .overlay {
                if isDragTargeted {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .padding(4)
                }
            }
        }
    }

    private func row(_ entry: DeviceStorageClient.Entry) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill((entry.isDirectory ? Color.purple : Color.accentColor).opacity(0.12))
                    .frame(width: 30, height: 30)
                Image(systemName: entry.isDirectory ? "folder.fill" : "doc")
                    .font(.system(size: 14))
                    .foregroundColor(entry.isDirectory ? .purple : .accentColor)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !entry.isDirectory {
                    Text(entry.formattedSize.isEmpty ? FileMIME.formatBytes(entry.size) : entry.formattedSize)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if entry.isDirectory {
                Button {
                    navigate(to: entry.path)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            } else {
                Button {
                    pull(entry)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.down")
                        Text("Copy to Mac")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Copy to Mac") { pull(entry) }
            Button("Rename...") { rename(entry) }
            Divider()
            Button("Delete", role: .destructive) { delete(entry) }
        }
    }

    // MARK: - Progress / errors

    private func progressBanner(_ status: TransferStatus) -> some View {
        VStack(spacing: 5) {
            HStack {
                Image(systemName: "arrow.up.arrow.down")
                    .foregroundColor(.accentColor)
                Text(status.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if let total = status.total, total > 0 {
                    Text("\(Int(Double(status.sent) / Double(total) * 100))%")
                        .font(.caption)
                        .fontWeight(.bold)
                }
            }
            if let total = status.total, total > 0 {
                ProgressView(value: Double(status.sent), total: Double(total))
                    .progressViewStyle(.linear)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Color.accentColor.opacity(0.08))
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.caption)
                .lineLimit(2)
            Spacer()
            Button("Dismiss") { errorMessage = nil }
                .controlSize(.mini)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                newFolderName = ""
                showNewFolder = true
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }
            .controlSize(.small)

            Button {
                pushFiles()
            } label: {
                Label("Copy Files Here", systemImage: "square.and.arrow.down")
            }
            .controlSize(.small)

            Spacer()

            Button {
                reload()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .alert("New Folder", isPresented: $showNewFolder) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") { createFolder() }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Actions

    private func navigate(to newPath: String) {
        path = newPath
        reload()
    }

    private func reload() {
        isLoading = true
        errorMessage = nil
        let target = path
        let storage = client
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let listing = try storage.list(path: target)
                DispatchQueue.main.async {
                    self.entries = listing.entries.filter { $0.name != ".." }
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.entries = []
                    self.isLoading = false
                }
            }
        }
    }

    private func pull(_ entry: DeviceStorageClient.Entry) {
        guard !entry.isDirectory else { return }
        let destination = appState.downloadsFolder.appendingPathComponent(entry.name)
        transfer = TransferStatus(title: "Copying \(entry.name) from \(provider.name)", sent: 0, total: entry.size)
        errorMessage = nil

        let storage = client
        let target = path
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try storage.download(path: entry.path, startOffset: 0, to: destination) { sent, total in
                    DispatchQueue.main.async {
                        self.transfer = TransferStatus(
                            title: "Copying \(entry.name) from \(provider.name)",
                            sent: sent,
                            total: total ?? entry.size
                        )
                    }
                }
                DispatchQueue.main.async {
                    self.transfer = nil
                    NSSound(named: "Glass")?.play()
                }
            } catch {
                DispatchQueue.main.async {
                    self.transfer = nil
                    self.errorMessage = error.localizedDescription
                }
            }
            _ = target
        }
    }

    private func pushFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.prompt = "Copy to \(provider.name)"
        guard panel.runModal() == .OK else { return }

        let target = path
        for url in panel.urls {
            transfer = TransferStatus(title: "Copying \(url.lastPathComponent) to \(provider.name)", sent: 0, total: nil)
            let storage = client
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try storage.upload(fileURL: url, toDirectory: target) { sent, total in
                        DispatchQueue.main.async {
                            self.transfer = TransferStatus(
                                title: "Copying \(url.lastPathComponent) to \(provider.name)",
                                sent: sent,
                                total: total
                            )
                        }
                    }
                } catch {
                    DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.transfer = nil
            self.reload()
        }
    }

    private func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let target = path
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try client.createDirectory(path: target, name: name)
                DispatchQueue.main.async { self.reload() }
            } catch {
                DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
            }
        }
    }

    private func rename(_ entry: DeviceStorageClient.Entry) {
        let alert = NSAlert()
        alert.messageText = "Rename \"\(entry.name)\""
        alert.informativeText = "Enter a new name."
        let field = NSTextField(string: entry.name)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 22)
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let newName = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty, newName != entry.name else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try client.rename(path: entry.path, to: newName)
                DispatchQueue.main.async { self.reload() }
            } catch {
                DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
            }
        }
    }

    private func delete(_ entry: DeviceStorageClient.Entry) {
        let alert = NSAlert()
        alert.messageText = "Delete \"\(entry.name)\" from \(provider.name)?"
        alert.informativeText = entry.isDirectory
            ? "The folder and everything inside it will be removed from the phone."
            : "The file will be removed from the phone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try client.delete(path: entry.path)
                DispatchQueue.main.async { self.reload() }
            } catch {
                DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url = url else { return }
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try client.upload(fileURL: url, toDirectory: self.path) { _, _ in }
                        DispatchQueue.main.async { self.reload() }
                    } catch {
                        DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
                    }
                }
            }
        }
    }
}
