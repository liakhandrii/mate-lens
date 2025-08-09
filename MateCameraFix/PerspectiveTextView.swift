import SwiftUI
import UIKit

// MARK: - UIViewRepresentable для малювання тексту з урахуванням перспективи
struct PerspectiveTextView: UIViewRepresentable {
    let textItems: [WordData]
    let imageSize: CGSize
    let screenSize: CGSize
    let debugEnabled: Bool
    
    func makeUIView(context: Context) -> TextDrawingView {
        let view = TextDrawingView(frame: CGRect(origin: .zero, size: screenSize))
        view.backgroundColor = .clear
        view.isOpaque = false
        view.textItems = transformTextItems(textItems, imageSize: imageSize, screenSize: screenSize)
        view.debugEnabled = debugEnabled
        return view
    }
    
    func updateUIView(_ uiView: TextDrawingView, context: Context) {
        uiView.frame = CGRect(origin: .zero, size: screenSize)
        uiView.textItems = transformTextItems(textItems, imageSize: imageSize, screenSize: screenSize)
        uiView.debugEnabled = debugEnabled
        uiView.setNeedsDisplay()
    }
    
    // Трансформація координат з простору зображення в простір екрану
    private func transformTextItems(_ items: [WordData], imageSize: CGSize, screenSize: CGSize) -> [TransformedTextItem] {
        print("Transforming \(items.count) text items")
        print("Image size: \(imageSize), Screen size: \(screenSize)")
        
        return items.compactMap { item in
            // Фолбек на frame якщо немає кутових точок
            if item.cornerPoints == nil || item.cornerPoints?.count != 4 {
                print("Using frame fallback for: \(item.text)")
                let (scale, offsetX, offsetY) = calculateScaleAndOffsets(imageSize: imageSize, screenSize: screenSize)
                
                // Генеруємо кутові точки з frame
                let transformedFrame = CGRect(
                    x: item.frame.origin.x * scale + offsetX,
                    y: item.frame.origin.y * scale + offsetY,
                    width: item.frame.width * scale,
                    height: item.frame.height * scale
                )
                
                let corners = [
                    CGPoint(x: transformedFrame.minX, y: transformedFrame.minY),
                    CGPoint(x: transformedFrame.maxX, y: transformedFrame.minY),
                    CGPoint(x: transformedFrame.maxX, y: transformedFrame.maxY),
                    CGPoint(x: transformedFrame.minX, y: transformedFrame.maxY)
                ]
                
                let fontSize = transformedFrame.height * 0.7
                let contentType = Utilities.detectContentType(for: item.text)
                
                return TransformedTextItem(
                    text: item.text,
                    translatedText: item.translatedText ?? item.text,
                    cornerPoints: corners,
                    fontSize: fontSize,
                    contentType: contentType,
                    debug: nil
                )
            }
            
            // Стандартна обробка з кутовими точками
            let fontSize = calculateAdaptiveFontSize(for: item, imageSize: imageSize, screenSize: screenSize)
            let contentType = Utilities.detectContentType(for: item.text)
            
            let debugInfo = TextTransformDebug()
            
            let transformedPoints = item.cornerPoints!.map { transform($0, imageSize: imageSize, screenSize: screenSize) }
            
            let padding: CGFloat = 4
            let expandedPoints = expandPolygon(transformedPoints, by: padding)
            
            debugInfo.originalCornerPoints = transformedPoints
            
            let (scale, offsetX, offsetY) = calculateScaleAndOffsets(imageSize: imageSize, screenSize: screenSize)
            let transformedFrame = CGRect(
                x: item.frame.origin.x * scale + offsetX,
                y: item.frame.origin.y * scale + offsetY,
                width: item.frame.width * scale,
                height: item.frame.height * scale
            )
            debugInfo.calculatedTextFrame = transformedFrame
            
            debugInfo.transformedCornerPoints = expandedPoints
            debugInfo.calculatedFontSize = fontSize
            
            print("Transformed: \(item.text) -> corners: \(expandedPoints[0])")
            
            return TransformedTextItem(
                text: item.text,
                translatedText: item.translatedText ?? item.text,
                cornerPoints: expandedPoints,
                fontSize: fontSize,
                contentType: contentType,
                debug: debugEnabled ? debugInfo : nil
            )
        }
    }
    
    // Адаптивний розрахунок розміру шрифту
    private func calculateAdaptiveFontSize(for item: WordData, imageSize: CGSize, screenSize: CGSize) -> CGFloat {
        let (scale, _, _) = calculateScaleAndOffsets(imageSize: imageSize, screenSize: screenSize)
        
        guard let cornerPoints = item.cornerPoints, cornerPoints.count >= 4 else {
            return item.frame.height * scale * 0.65
        }
        
        let transformedPoints = cornerPoints.map { transform($0, imageSize: imageSize, screenSize: screenSize) }
        
        // Розраховуємо середню висоту блоку
        let leftHeight = distance(from: transformedPoints[0], to: transformedPoints[3])
        let rightHeight = distance(from: transformedPoints[1], to: transformedPoints[2])
        let avgHeight = (leftHeight + rightHeight) / 2.0
        
        // Розраховуємо середню ширину блоку
        let topWidth = distance(from: transformedPoints[0], to: transformedPoints[1])
        let bottomWidth = distance(from: transformedPoints[3], to: transformedPoints[2])
        let avgWidth = (topWidth + bottomWidth) / 2.0
        
        let textLength = item.text.count
        let widthHeightRatio = avgWidth / avgHeight
        
        // Базовий масштаб для шрифту
        var scaleFactor: CGFloat = 0.7
        
        // Корегуємо для довгих текстів
        if textLength > 20 {
            scaleFactor = 0.5
        } else if textLength > 12 {
            scaleFactor = 0.55
        } else if textLength > 10 && widthHeightRatio > 5.0 {
            scaleFactor = 0.6
        } else if widthHeightRatio > 8.0 {
            scaleFactor = 0.65
        } else if widthHeightRatio > 5.0 {
            scaleFactor = 0.7
        } else if widthHeightRatio > 3.0 {
            scaleFactor = 0.75
        }
        
        // Збільшуємо для коротких текстів
        if textLength <= 3 {
            scaleFactor *= 1.1
        } else if textLength <= 5 {
            scaleFactor *= 1.05
        }
        
        let fontSize = avgHeight * scaleFactor
        return max(fontSize, 8.0)
    }
    
    // Обчислення відстані між двома точками
    private func distance(from point1: CGPoint, to point2: CGPoint) -> CGFloat {
        let dx = point2.x - point1.x
        let dy = point2.y - point1.y
        return sqrt(dx * dx + dy * dy)
    }
    
    // Розширення полігону для кращого покриття тексту
    private func expandPolygon(_ points: [CGPoint], by padding: CGFloat) -> [CGPoint] {
        guard points.count >= 3 else { return points }
        
        let center = improvedCenterOf(points)
        
        return points.map { point in
            let dx = point.x - center.x
            let dy = point.y - center.y
            let distance = sqrt(dx*dx + dy*dy)
            
            if distance < 0.0001 { return point }
            
            // Масштабуємо від центру назовні
            let adaptivePadding = padding * 1.5
            let scale = (distance + adaptivePadding) / distance
            return CGPoint(
                x: center.x + dx * scale,
                y: center.y + dy * scale
            )
        }
    }
    
    // Пошук центру полігону з урахуванням його форми
    private func improvedCenterOf(_ points: [CGPoint]) -> CGPoint {
        guard points.count >= 3 else {
            let xs = points.map { $0.x }
            let ys = points.map { $0.y }
            return CGPoint(x: xs.reduce(0, +) / CGFloat(xs.count), y: ys.reduce(0, +) / CGFloat(ys.count))
        }
        
        if points.count == 4 {
            // Для чотирикутника знаходимо перетин діагоналей
            let p1 = points[0]
            let p2 = points[2]
            let p3 = points[1]
            let p4 = points[3]
            
            let d = (p1.x - p2.x) * (p3.y - p4.y) - (p1.y - p2.y) * (p3.x - p4.x)
            
            if abs(d) < 0.000001 {
                // Діагоналі паралельні - беремо середнє арифметичне
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
        
        // Для інших випадків - середнє арифметичне
        let xs = points.map { $0.x }
        let ys = points.map { $0.y }
        return CGPoint(x: xs.reduce(0, +) / CGFloat(xs.count), y: ys.reduce(0, +) / CGFloat(ys.count))
    }
    
    // Розрахунок масштабу та відступів для aspect fit
    private func calculateScaleAndOffsets(imageSize: CGSize, screenSize: CGSize) -> (scale: CGFloat, offsetX: CGFloat, offsetY: CGFloat) {
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
    private func transform(_ point: CGPoint, imageSize: CGSize, screenSize: CGSize) -> CGPoint {
        let (scale, offsetX, offsetY) = calculateScaleAndOffsets(imageSize: imageSize, screenSize: screenSize)
        return CGPoint(
            x: point.x * scale + offsetX,
            y: point.y * scale + offsetY
        )
    }
}

// MARK: - UIView для кастомного малювання тексту
class TextDrawingView: UIView {
    var textItems: [TransformedTextItem] = [] {
        didSet {
            setNeedsDisplay()
        }
    }
    
    var debugEnabled: Bool = false
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
    }
    
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        
        for item in textItems {
            context.saveGState()
            context.setFillColor(UIColor.white.withAlphaComponent(0.85).cgColor)
            context.setStrokeColor(UIColor.gray.withAlphaComponent(0.3).cgColor)
            context.setLineWidth(0.5)
            
            // Малюємо білий фон під текстом
            context.beginPath()
            if item.cornerPoints.count >= 4 {
                context.move(to: item.cornerPoints[0])
                for i in 1..<item.cornerPoints.count {
                    context.addLine(to: item.cornerPoints[i])
                }
                context.closePath()
                context.drawPath(using: .fillStroke)
            }
            
            // Малюємо сам текст з урахуванням перспективи
            drawTextWithPerspective(context: context, item: item)
            
            // Відображаємо дебаг інформацію якщо потрібно
            if debugEnabled, let debug = item.debug {
                drawDebugInfo(context: context, debug: debug)
            }
            
            context.restoreGState()
        }
    }
    
    // Малювання дебаг інформації
    private func drawDebugInfo(context: CGContext, debug: TextTransformDebug) {
        context.saveGState()
        context.setLineWidth(1.0)
        
        // Червоні лінії - оригінальні кутові точки
        if let originalPoints = debug.originalCornerPoints, originalPoints.count >= 4 {
            context.setStrokeColor(UIColor.red.cgColor)
            context.beginPath()
            context.move(to: originalPoints[0])
            for i in 1..<originalPoints.count {
                context.addLine(to: originalPoints[i])
            }
            context.closePath()
            context.strokePath()
        }
        
        // Жовті лінії - розширені кутові точки
        if let transformedPoints = debug.transformedCornerPoints, transformedPoints.count >= 4 {
            context.setStrokeColor(UIColor.yellow.cgColor)
            context.beginPath()
            context.move(to: transformedPoints[0])
            for i in 1..<transformedPoints.count {
                context.addLine(to: transformedPoints[i])
            }
            context.closePath()
            context.strokePath()
        }
        
        // Синя рамка - область малювання тексту
        if let textRect = debug.calculatedTextRect,
            let transformedPoints = debug.transformedCornerPoints, transformedPoints.count >= 4 {
            let center = getCenterOfPoints(transformedPoints)
            
            // Розраховуємо позицію рамки на екрані
            let actualTextRect = CGRect(
                x: center.x + textRect.origin.x,
                y: center.y + textRect.origin.y,
                width: textRect.width,
                height: textRect.height
            )
            
            context.setStrokeColor(UIColor.blue.cgColor)
            context.stroke(actualTextRect)
        }
        
        // Зелена рамка - frame від MLKit
        if let textFrame = debug.calculatedTextFrame {
            context.setStrokeColor(UIColor.green.cgColor)
            context.stroke(textFrame)
        }
        
        // Виводимо числові значення дебагу
        if let transformedPoints = debug.transformedCornerPoints, transformedPoints.count >= 4 {
            let center = getCenterOfPoints(transformedPoints)
            var debugTexts: [String] = []
            
            if let angle = debug.calculatedRotationAngle {
                let angleInDegrees = angle * 180 / .pi
                debugTexts.append(String(format: "%.1f°", angleInDegrees))
            }
            
            if let fontSize = debug.calculatedFontSize {
                debugTexts.append(String(format: "%.1fpt", fontSize))
            }
            
            if !debugTexts.isEmpty {
                let debugText = debugTexts.joined(separator: " | ")
                
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 12),
                    .foregroundColor: UIColor.purple
                ]
                let attributedString = NSAttributedString(string: debugText, attributes: attributes)
                let textSize = attributedString.size()
                
                let textRect = CGRect(
                    x: center.x - textSize.width / 2,
                    y: center.y + 10, // Розміщуємо під основним текстом
                    width: textSize.width,
                    height: textSize.height
                )
                
                attributedString.draw(in: textRect)
            }
        }
        
        context.restoreGState()
    }
    
    private func drawTextWithPerspective(context: CGContext, item: TransformedTextItem) {
        let center = getCenterOfPoints(item.cornerPoints)
        let areaSize = getBoundingSize(for: item.cornerPoints)
        let areaWidth = areaSize.width
        let areaHeight = areaSize.height
        
        // Використовуємо перекладений текст замість оригінального
        let textToDisplay = item.translatedText
        
        // Визначаємо тип контенту для стилізації
        let contentType = Utilities.detectContentType(for: item.text)
        
        // Вибираємо відповідний шрифт
        let font = Utilities.selectAdaptiveFont(for: textToDisplay, baseSize: item.fontSize, contentType: contentType)
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byTruncatingTail  // Обрізаємо довгий текст
        paragraphStyle.lineHeightMultiple = 0.85  // Зменшуємо міжрядковий інтервал
        
        // Для довгих текстів дозволяємо перенос по словах
        if textToDisplay.count > 15 {
            paragraphStyle.lineBreakMode = .byWordWrapping
        }
        
        // Базові атрибути тексту
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: contentType.color,
            .paragraphStyle: paragraphStyle
        ]
        
        // Додаємо ефекти для важливих типів контенту
        var enhancedAttributes = attributes
        if contentType == .price || contentType == .date || contentType == .number {
            let shadow = NSShadow()
            shadow.shadowColor = UIColor.white
            shadow.shadowOffset = CGSize(width: 0, height: 0)
            shadow.shadowBlurRadius = 3
            enhancedAttributes[.shadow] = shadow
        }
        
        let attributedString = NSAttributedString(string: textToDisplay, attributes: enhancedAttributes)
        
        // Адаптуємо ширину тексту до форми області
        let heightToWidthRatio = areaHeight / areaWidth
        var widthMultiplier: CGFloat = 0.9  // Базове заповнення області
        
        if heightToWidthRatio < 0.2 { // Дуже вузька смужка
            widthMultiplier = 0.75
        } else if heightToWidthRatio < 0.3 {
            widthMultiplier = 0.8
        } else if heightToWidthRatio < 0.4 {
            widthMultiplier = 0.85
        }
        
        // Короткі тексти можуть використовувати більше простору
        if textToDisplay.count <= 10 {
            widthMultiplier = min(widthMultiplier * 1.1, 0.95)
        }
        
        let maxWidth = areaWidth * widthMultiplier
        let boundingRect = attributedString.boundingRect(
            with: CGSize(width: maxWidth, height: areaHeight * 0.9),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let textSize = boundingRect.size
        
        if item.cornerPoints.count == 4 {
            context.saveGState()
            
            context.textMatrix = .identity
            context.translateBy(x: center.x, y: center.y)
            
            let angle = calculateRotationAngle(item.cornerPoints)
            item.debug?.calculatedRotationAngle = angle
            context.rotate(by: angle)
            
            // Центруємо текст відносно повернутої системи координат
            let textRect = CGRect(
                x: -textSize.width / 2,
                y: -textSize.height / 2,
                width: textSize.width,
                height: textSize.height
            )
            item.debug?.calculatedTextRect = textRect
            
            attributedString.draw(in: textRect)
            
            context.restoreGState()
        } else {
            let textRect = CGRect(
                x: center.x - textSize.width / 2,
                y: center.y - textSize.height / 2,
                width: textSize.width,
                height: textSize.height
            )
            
            item.debug?.calculatedTextRect = textRect
            
            attributedString.draw(in: textRect)
        }
    }
    
    // Розрахунок кута повороту тексту на основі кутових точок
    private func calculateRotationAngle(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 4 else { return 0 }
        
        // Обчислюємо кут верхньої грані
        let topDx = points[1].x - points[0].x
        let topDy = points[1].y - points[0].y
        let topAngle = atan2(topDy, topDx)
        
        // Обчислюємо кут нижньої грані
        let bottomDx = points[2].x - points[3].x
        let bottomDy = points[2].y - points[3].y
        let bottomAngle = atan2(bottomDy, bottomDx)
        
        // Усереднюємо кути для компенсації перспективи
        var angle = (topAngle + bottomAngle) / 2.0
        
        // Коригуємо кут щоб текст не був перевернутий
        while angle > .pi / 4 {
            angle -= .pi
        }
        while angle < -.pi / 4 {
            angle += .pi
        }
        
        return angle
    }
    
    // Обчислення габаритного прямокутника для набору точок
    private func getBoundingSize(for points: [CGPoint]) -> CGSize {
        let xs = points.map { $0.x }
        let ys = points.map { $0.y }
        
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else {
            return .zero
        }
        
        return CGSize(width: maxX - minX, height: maxY - minY)
    }
    
    // Знаходження геометричного центру набору точок
    private func getCenterOfPoints(_ points: [CGPoint]) -> CGPoint {
        let count = CGFloat(points.count)
        let x = points.reduce(0) { $0 + $1.x } / count
        let y = points.reduce(0) { $0 + $1.y } / count
        return CGPoint(x: x, y: y)
    }
}
