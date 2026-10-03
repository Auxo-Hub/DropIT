import Foundation
import CoreImage
import AppKit

public class QRCodeGenerator {
    public static func generateImage(from string: String, size: CGFloat = 280) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        guard let data = string.data(using: .utf8) else { return nil }
        
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        
        guard let outputCIImage = filter.outputImage else { return nil }
        
        let extent = outputCIImage.extent
        guard extent.size.width > 0 && extent.size.height > 0 else { return nil }
        
        let scaleX = size / extent.size.width
        let scaleY = size / extent.size.height
        let transformedImage = outputCIImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        
        let rep = NSCIImageRep(ciImage: transformedImage)
        rep.size = NSSize(width: size, height: size)
        
        let nsImage = NSImage(size: NSSize(width: size, height: size))
        nsImage.addRepresentation(rep)
        
        return nsImage
    }
}
