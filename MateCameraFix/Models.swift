import UIKit
import CoreGraphics // Для CGRect та CGPoint

// MARK: - Модель даних для розпізнаного тексту
struct WordData {
    let text: String
    let translatedText: String?  // Новий: перекладений текст
    let frame: CGRect
    let cornerPoints: [CGPoint]?
}

// MARK: - Enum для типів контенту
enum ContentType {
    case number
    case date
    case price
    case productName
    case regular
    
    var color: UIColor {
        switch self {
        case .number, .price:
            return UIColor.black
        case .date:
            return UIColor.systemGreen
        case .productName:
            return UIColor.label
        case .regular:
            return UIColor.black
        }
    }
    
    var fontWeight: UIFont.Weight {
        return .regular  // Однакова вага для всіх типів
    }
}

// MARK: - Структура для передачі даних у TextDrawingView
struct TransformedTextItem {
    let text: String
    let translatedText: String  // Новий: перекладений текст
    let cornerPoints: [CGPoint]
    let fontSize: CGFloat
    let contentType: ContentType
    let debug: TextTransformDebug?
}

// MARK: - Клас для зберігання відлагоджувальної інформації
class TextTransformDebug {
    /// Original corners as recognized by MLKit. Draws red
    var originalCornerPoints: [CGPoint]?
    /// Frame as calculated by recognizeText. Draws green
    var calculatedTextFrame: CGRect?
    /// Corners from the transformTextItems function. Draws yellow
    var transformedCornerPoints: [CGPoint]?
    /// Font size from calculateAdaptiveFontSize. Draws purple
    var calculatedFontSize: CGFloat?
    /// Angle from drawTextWithPerspective. Draws purple
    var calculatedRotationAngle: CGFloat?
    /// Text frame from drawTextWithPerspective. Draws blue
    var calculatedTextRect: CGRect?
}

