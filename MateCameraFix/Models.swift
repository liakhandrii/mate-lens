import UIKit
import CoreGraphics

// MARK: - Модель даних для розпізнаного тексту
struct WordData {
    let text: String
    let translatedText: String?
    let frame: CGRect
    let cornerPoints: [CGPoint]?
    let originalImage: UIImage? 
}

// MARK: - Типи контенту
enum ContentType {
    case number
    case date
    case price
    case productName
    case regular
    
    var color: UIColor {
        switch self {
        case .number, .price:
            return .black
        case .date:
            return .systemGreen
        case .productName:
            return .black
        case .regular:
            return .black
        }
    }
    
    var fontWeight: UIFont.Weight {
        switch self {
        case .productName:
            return .regular
        default:
            return .regular
        }
    }
}

// MARK: - Трансформований елемент для малювання
struct TransformedTextItem {
    let text: String
    let translatedText: String
    let cornerPoints: [CGPoint]
    let fontSize: CGFloat
    let contentType: ContentType
    let textColor: UIColor
    let backgroundColor: UIColor
    let estimatedWeight: UIFont.Weight
    let debug: TextTransformDebug?
}

// MARK: - Debug інформація
class TextTransformDebug {
    var originalCornerPoints: [CGPoint]?
    var calculatedTextFrame: CGRect?
    var transformedCornerPoints: [CGPoint]?
    var calculatedFontSize: CGFloat?
    var calculatedRotationAngle: CGFloat?
    var calculatedTextRect: CGRect?
}
