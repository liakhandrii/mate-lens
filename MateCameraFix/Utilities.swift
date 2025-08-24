import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

struct Utilities {
    
    // MARK: - Text Processing
    
    static func detectContentType(for text: String) -> ContentType {
        let trimmedText = text.trimmingCharacters(in: .whitespaces)
        if trimmedText.isEmpty { return .regular }
        
        let pricePattern = #"(?:€|\$|£|¥|\b(?:EUR|USD|GBP|UAH)\b|\d+[.,]\d{2})"#
        if trimmedText.range(of: pricePattern, options: .regularExpression) != nil {
            return .price
        }
        
        // Перевірка на дату (різні формати)
        let datePatterns = [
            #"\d{1,2}[./\-]\d{1,2}[./\-]\d{2,4}"#,  // DD/MM/YYYY або MM/DD/YYYY
            #"\d{4}[./\-]\d{1,2}[./\-]\d{1,2}"#,    // YYYY/MM/DD
            #"\d{1,2}\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d{2,4}"#
        ]
        for pattern in datePatterns {
            if trimmedText.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                return .date
            }
        }
        
        let digitCount = trimmedText.filter { $0.isNumber }.count
        let totalCount = trimmedText.count
        if totalCount > 0 && Double(digitCount) / Double(totalCount) > 0.5 {
            return .number
        }
        
        // Перевірка на назву продукту (довші тексти з великої літери + ключові слова)
        if trimmedText.count > 5, trimmedText.first?.isUppercase == true {
            let productKeywords = ["STÄBCHEN", "bevola", "Stück", "Pack", "Box", "Dose"]
            for keyword in productKeywords {
                if trimmedText.localizedCaseInsensitiveContains(keyword) {
                    return .productName
                }
            }
        }
        
        return .regular
    }

    static func optimizeText(_ text: String, contentType: ContentType? = nil) -> String {
        var processed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        processed = processed.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        
        return processed
    }
    
    static func optimizeText(_ text: String) -> String {
        return optimizeText(text, contentType: nil)
    }
    
    private static func digitRatio(in s: String) -> Double {
        guard !s.isEmpty else { return 0 }
        let digits = s.filter { $0.isNumber }.count
        return Double(digits) / Double(s.count)
    }
    
    private static func replaceRegex(_ pattern: String,
                                     in text: String,
                                     with template: String,
                                     options: NSRegularExpression.Options = []) -> String {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: options)
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
        } catch {
            return text
        }
    }

    // MARK: - Font Selection
    static func selectAdaptiveFont(for text: String, baseSize: CGFloat, contentType: ContentType, weight: UIFont.Weight) -> UIFont {
        let fontName: String
        if baseSize < 12 {
            fontName = "Helvetica Neue"
        } else {
            fontName = "System"
        }
        
        let finalWeight = weight == .regular ? contentType.fontWeight : weight
        
        if fontName == "System" {
            return UIFont.systemFont(ofSize: baseSize, weight: finalWeight)
        } else {
            let helveticaVariant: String
            switch finalWeight {
            case .bold, .semibold:
                helveticaVariant = "HelveticaNeue-Bold"
            case .medium:
                helveticaVariant = "HelveticaNeue-Medium"
            default:
                helveticaVariant = "HelveticaNeue"
            }
            return UIFont(name: helveticaVariant, size: baseSize)
                ?? UIFont.systemFont(ofSize: baseSize, weight: finalWeight)
        }
    }
    
    // MARK: - Image Processing
    
    static func preprocessForOCR(image: UIImage) -> UIImage? {
        guard let ciImage = CIImage(image: image) else { return nil }
        
        let filter = ciImage
            // Підвищити контраст
            .applyingFilter("CIColorControls", parameters: [
                "inputContrast": 1.5,
                "inputBrightness": 0.1
            ])
            // Збільшити різкість
            .applyingFilter("CISharpenLuminance", parameters: [
                "inputSharpness": 0.8
            ])

        let context = CIContext()
        guard let cgImage = context.createCGImage(filter, from: filter.extent) else { return nil }
        
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }
    
    static func normalize(image: UIImage) -> UIImage? {
        guard image.imageOrientation != .up else { return image }
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        defer { UIGraphicsEndImageContext() }
        image.draw(in: CGRect(origin: .zero, size: image.size))
        return UIGraphicsGetImageFromCurrentImageContext()
    }
    
    // MARK: - Coordinate Transformation
    
    // Розрахунок масштабу та відступів для aspect fit
    static func calculateScaleAndOffsets(imageSize: CGSize, screenSize: CGSize) -> (scale: CGFloat, offsetX: CGFloat, offsetY: CGFloat) {
        let imageAspectRatio = imageSize.width / imageSize.height
        let screenAspectRatio = screenSize.width / screenSize.height
        
        if imageAspectRatio > screenAspectRatio {
            // Зображення ширше за екран
            let scale = screenSize.width / imageSize.width
            return (scale, 0, (screenSize.height - imageSize.height * scale) / 2)
        } else {
            // Зображення вище за екран
            let scale = screenSize.height / imageSize.height
            return (scale, (screenSize.width - imageSize.width * scale) / 2, 0)
        }
    }
    
    // Трансформація точки з координат зображення в координати екрану
    static func transform(_ point: CGPoint, imageSize: CGSize, screenSize: CGSize) -> CGPoint {
        let (scale, offsetX, offsetY) = calculateScaleAndOffsets(imageSize: imageSize, screenSize: screenSize)
        return CGPoint(
            x: point.x * scale + offsetX,
            y: point.y * scale + offsetY
        )
    }
    
    // MARK: - Geometry Utils
    
    static func distance(from point1: CGPoint, to point2: CGPoint) -> CGFloat {
        let dx = point2.x - point1.x
        let dy = point2.y - point1.y
        return sqrt(dx * dx + dy * dy)
    }
    
    static func expandPolygon(_ points: [CGPoint], by padding: CGFloat) -> [CGPoint] {
        guard points.count >= 3 else { return points }
        
        let center = Utilities.improvedCenterOf(points)
        
        return points.map { point in
            let dx = point.x - center.x
            let dy = point.y - center.y
            let distance = sqrt(dx*dx + dy*dy)
            
            if distance < 0.0001 { return point }
            
            let adaptivePadding = padding * 1.5
            let scale = (distance + adaptivePadding) / distance
            return CGPoint(
                x: center.x + dx * scale,
                y: center.y + dy * scale
            )
        }
    }
    
    static func shrinkPolygon(_ points: [CGPoint], by padding: CGFloat) -> [CGPoint] {
        guard points.count >= 3 else { return points }
        
        let center = Utilities.improvedCenterOf(points)
        
        return points.map { point in
            let dx = point.x - center.x
            let dy = point.y - center.y
            let distance = sqrt(dx*dx + dy*dy)
            
            if distance < 0.0001 { return point }
            
            let scale = max(0.0, (distance - padding) / distance)
            return CGPoint(
                x: center.x + dx * scale,
                y: center.y + dy * scale
            )
        }
    }
    
    static func improvedCenterOf(_ points: [CGPoint]) -> CGPoint {
        guard points.count >= 3 else {
            let xs = points.map { $0.x }
            let ys = points.map { $0.y }
            return CGPoint(x: xs.reduce(0, +) / CGFloat(xs.count), y: ys.reduce(0, +) / CGFloat(ys.count))
        }
        
        if points.count == 4 {
            let p1 = points[0]
            let p2 = points[2]
            let p3 = points[1]
            let p4 = points[3]
            
            let d = (p1.x - p2.x) * (p3.y - p4.y) - (p1.y - p2.y) * (p3.x - p4.x)
            
            if abs(d) < 0.000001 {
                return CGPoint(
                    x: (p1.x + p2.x + p3.x + p4.x) / 4.0,
                    y: (p1.y + p2.y + p3.y + p4.y) / 4.0
                )
            }
            
            let t = ((p1.x - p3.x) * (p3.y - p4.y) - (p1.y - p3.y) * (p3.x - p4.x)) / d
            
            return CGPoint(
                x: p1.x + t * (p2.x - p1.x),
                y: p1.y + t * (p2.y - p1.y)
            )
        }
        
        let xs = points.map { $0.x }
        let ys = points.map { $0.y }
        return CGPoint(x: xs.reduce(0, +) / CGFloat(xs.count), y: ys.reduce(0, +) / CGFloat(ys.count))
    }
}
