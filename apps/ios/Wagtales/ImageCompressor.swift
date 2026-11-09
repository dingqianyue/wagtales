import UIKit

struct ImageCompressor {
    /// Resizes and compresses an image from Data.
    /// - Parameters:
    ///   - data: The original image Data
    ///   - maxDimension: The maximum width or height (e.g., 500 for avatars, 1080 for posts)
    ///   - compressionQuality: 0.0 to 1.0 (0.6 is usually a great balance of size/quality)
    /// - Returns: The compressed JPEG Data
    static func compress(data: Data, maxDimension: CGFloat = 500, compressionQuality: CGFloat = 0.6) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        
        // Calculate new size, keeping aspect ratio
        var newSize = image.size
        if image.size.width > maxDimension || image.size.height > maxDimension {
            let ratio = max(image.size.width, image.size.height) / maxDimension
            newSize = CGSize(width: image.size.width / ratio, height: image.size.height / ratio)
        }
        
        // Resize the image
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0 // Prevents the system from secretly scaling it back up for Retina displays
        
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        let resizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        
        // Compress to JPEG
        return resizedImage.jpegData(compressionQuality: compressionQuality)
    }
    
    /// Crops an image to a perfect square from the center, then resizes and compresses it.
    static func compressAndCropToSquare(data: Data, maxDimension: CGFloat = 1080, compressionQuality: CGFloat = 0.8) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        
        // Find the shortest side to make a perfect square
        let originalWidth = image.size.width
        let originalHeight = image.size.height
        let shortestSide = min(originalWidth, originalHeight)
        
        // Calculate offsets to crop exactly from the center
        let xOffset = (originalWidth - shortestSide) / 2.0
        let yOffset = (originalHeight - shortestSide) / 2.0
        
        let cropRect = CGRect(x: xOffset, y: yOffset, width: shortestSide, height: shortestSide)
        
        // Perform the actual crop
        guard let cgImage = image.cgImage?.cropping(to: cropRect) else { return nil }
        let croppedImage = UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
        
        // Resize the new square image to the max dimension (e.g., 1080x1080)
        let newSize = CGSize(width: maxDimension, height: maxDimension)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0 // Prevents sneaky Retina upscaling
        
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        let resizedImage = renderer.image { _ in
            croppedImage.draw(in: CGRect(origin: .zero, size: newSize))
        }
        
        // Compress to JPEG
        return resizedImage.jpegData(compressionQuality: compressionQuality)
    }
}
