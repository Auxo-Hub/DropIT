import Foundation
import UniformTypeIdentifiers

public struct FileMIME {
    public static func mimeType(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension) {
            if let mime = type.preferredMIMEType {
                return mime
            }
        }
        return "application/octet-stream"
    }

    public static func sfSymbolName(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "heic", "webp", "svg", "bmp", "tiff":
            return "photo.fill"
        case "mp4", "mov", "m4v", "mkv", "avi", "webm":
            return "film.fill"
        case "mp3", "wav", "m4a", "flac", "aac", "ogg":
            return "music.note"
        case "zip", "tar", "gz", "tgz", "rar", "7z", "bz2", "dmg", "iso":
            return "archivebox.fill"
        case "pdf":
            return "doc.richtext.fill"
        case "doc", "docx", "pages", "txt", "rtf", "md":
            return "doc.text.fill"
        case "xls", "xlsx", "numbers", "csv":
            return "tablecells.fill"
        case "ppt", "pptx", "key":
            return "rectangle.fill.on.rectangle.fill"
        case "swift", "js", "ts", "py", "html", "css", "json", "xml", "cpp", "c", "h", "sh":
            return "chevron.left.forwardslash.chevron.right"
        default:
            return "doc.fill"
        }
    }

    public static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
