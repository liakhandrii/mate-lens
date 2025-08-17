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
    static func selectAdaptiveFont(for text: String, baseSize: CGFloat, contentType: ContentType) -> UIFont {
        let fontName: String
        if baseSize < 12 {
            fontName = "Helvetica Neue"
        } else {
            fontName = "System"
        }
        
        if fontName == "System" {
            return UIFont.systemFont(ofSize: baseSize, weight: contentType.fontWeight)
        } else {
            let helveticaVariant: String
            switch contentType.fontWeight {
            case .bold, .semibold:
                helveticaVariant = "HelveticaNeue-Bold"
            case .medium:
                helveticaVariant = "HelveticaNeue-Medium"
            default:
                helveticaVariant = "HelveticaNeue"
            }
            return UIFont(name: helveticaVariant, size: baseSize)
                ?? UIFont.systemFont(ofSize: baseSize, weight: contentType.fontWeight)
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
}
