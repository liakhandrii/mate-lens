import SwiftUI
import UIKit

class TextTransformCache {
    private var cache: [String: TransformedTextItem] = [:]
    
    func getTransformed(for item: WordData, key: String) -> TransformedTextItem? {
        return cache[key]
    }
    
    func store(_ transformed: TransformedTextItem, key: String) {
        cache[key] = transformed
    }
}

// MARK: - UIViewRepresentable для малювання тексту з урахуванням перспективи
struct PerspectiveTextView: UIViewRepresentable {
    let textItems: [WordData]
    let imageSize: CGSize
    let screenSize: CGSize
    let debugEnabled: Bool
    
    private let transformCache = TextTransformCache()

    
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
    
    private func transformTextItems(_ items: [WordData], imageSize: CGSize, screenSize: CGSize) -> [TransformedTextItem] {
        print("Transforming \(items.count) text items")
        print("Image size: \(imageSize), Screen size: \(screenSize)")
        
        return items.compactMap { item in
            // Генеруємо унікальний ключ для кешу
            let cacheKey = "\(item.text)_\(imageSize.width)x\(imageSize.height)_\(screenSize.width)x\(screenSize.height)"
            
            // Перевіряємо чи є в кеші
            if let cached = transformCache.getTransformed(for: item, key: cacheKey) {
                print("Using cached transform for: \(item.text)")
                return cached
            }
            
            if item.cornerPoints == nil || item.cornerPoints?.count != 4 {
                print("Using frame fallback for: \(item.text)")
                let (scale, offsetX, offsetY) = calculateScaleAndOffsets(imageSize: imageSize, screenSize: screenSize)
                
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
                
                let fontSize = transformedFrame.height * 0.45  // Зменшено ще більше
                let contentType = Utilities.detectContentType(for: item.text)
                
                let result = TransformedTextItem(
                    text: item.text,
                    translatedText: item.translatedText ?? item.text,
                    cornerPoints: corners,
                    fontSize: fontSize,
                    contentType: contentType,
                    debug: nil
                )
                
                // Зберігаємо в кеш
                transformCache.store(result, key: cacheKey)
                return result
            }
            
            let fontSize = calculateAdaptiveFontSize(for: item, imageSize: imageSize, screenSize: screenSize)
            let contentType = Utilities.detectContentType(for: item.text)
            
            let debugInfo = TextTransformDebug()
            
            let transformedPoints = item.cornerPoints!.map { transform($0, imageSize: imageSize, screenSize: screenSize) }
            
            let finalPoints = transformedPoints  // Без стискання
            
            debugInfo.originalCornerPoints = transformedPoints
            
            let (scale, offsetX, offsetY) = calculateScaleAndOffsets(imageSize: imageSize, screenSize: screenSize)
            let transformedFrame = CGRect(
                x: item.frame.origin.x * scale + offsetX,
                y: item.frame.origin.y * scale + offsetY,
                width: item.frame.width * scale,
                height: item.frame.height * scale
            )
            debugInfo.calculatedTextFrame = transformedFrame
            
            debugInfo.transformedCornerPoints = finalPoints
            debugInfo.calculatedFontSize = fontSize
            
            print("Transformed: \(item.text) -> corners: \(finalPoints[0])")
            
            let result = TransformedTextItem(
                text: item.text,
                translatedText: item.translatedText ?? item.text,
                cornerPoints: finalPoints,
                fontSize: fontSize,
                contentType: contentType,
                debug: debugEnabled ? debugInfo : nil
            )
            
            // Зберігаємо в кеш
            transformCache.store(result, key: cacheKey)
            return result
        }
    }
    
    private func shrinkPolygon(_ points: [CGPoint], by padding: CGFloat) -> [CGPoint] {
        guard points.count >= 3 else { return points }
        
        let center = improvedCenterOf(points)
        
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
    
    private func calculateAdaptiveFontSize(for item: WordData, imageSize: CGSize, screenSize: CGSize) -> CGFloat {
        let (scale, _, _) = calculateScaleAndOffsets(imageSize: imageSize, screenSize: screenSize)
        
        guard let cornerPoints = item.cornerPoints, cornerPoints.count >= 4 else {
            return item.frame.height * scale * 0.45  // Зменшено для fallback
        }
        
        let transformedPoints = cornerPoints.map { transform($0, imageSize: imageSize, screenSize: screenSize) }
        
        let leftHeight = distance(from: transformedPoints[0], to: transformedPoints[3])
        let rightHeight = distance(from: transformedPoints[1], to: transformedPoints[2])
        let avgHeight = (leftHeight + rightHeight) / 2.0
        
        let topWidth = distance(from: transformedPoints[0], to: transformedPoints[1])
        let bottomWidth = distance(from: transformedPoints[3], to: transformedPoints[2])
        let avgWidth = (topWidth + bottomWidth) / 2.0
        
        let textLength = item.text.count
        let widthHeightRatio = avgWidth / avgHeight
        
        var scaleFactor: CGFloat = 0.45
        
        if item.text.allSatisfy({ $0.isUppercase || $0.isNumber || !$0.isLetter }) {
            scaleFactor = 0.55
        } else if item.text.contains(where: { "gjpqy".contains($0.lowercased()) }) {
            scaleFactor = 0.42
        }
        
        if textLength > 20 {
            scaleFactor *= 0.5
        } else if textLength > 15 {
            scaleFactor *= 0.6
        } else if textLength > 10 {
            scaleFactor *= 0.7
        }
        
        if widthHeightRatio > 10.0 {
            scaleFactor *= 0.6
        } else if widthHeightRatio > 6.0 {
            scaleFactor *= 0.7
        }
        
        if textLength <= 3 {
            scaleFactor *= 1.05
        } else if textLength <= 5 {
            scaleFactor *= 1.02
        }
        
        let fontSize = avgHeight * scaleFactor
        return max(fontSize, 8.0)
    }
    
    private func distance(from point1: CGPoint, to point2: CGPoint) -> CGFloat {
        let dx = point2.x - point1.x
        let dy = point2.y - point1.y
        return sqrt(dx * dx + dy * dy)
    }
    
    private func expandPolygon(_ points: [CGPoint], by padding: CGFloat) -> [CGPoint] {
        guard points.count >= 3 else { return points }
        
        let center = improvedCenterOf(points)
        
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
    
    private func improvedCenterOf(_ points: [CGPoint]) -> CGPoint {
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
        didSet { setNeedsDisplay() }
    }
    var debugEnabled: Bool = false
    
    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        
        let filtered = removeDuplicateOverlaps(from: textItems)
        
        let backgroundsOrder = filtered.sorted { area(of: $0) < area(of: $1) }
        let textOrder = filtered.sorted { area(of: $0) > area(of: $1) }
        
        for item in backgroundsOrder {
            guard item.cornerPoints.count >= 4 else { continue }
            ctx.saveGState()
            ctx.setFillColor(UIColor.white.withAlphaComponent(0.85).cgColor)
            ctx.setStrokeColor(UIColor.gray.withAlphaComponent(0.05).cgColor)
            ctx.setLineWidth(0.25)
            ctx.beginPath()
            ctx.move(to: item.cornerPoints[0])
            for i in 1..<item.cornerPoints.count {
                ctx.addLine(to: item.cornerPoints[i])
            }
            ctx.closePath()
            ctx.drawPath(using: .fillStroke)
            ctx.restoreGState()
        }
        
        for item in textOrder {
            drawTextWithPerspective(context: ctx, item: item)
        }
        
        if debugEnabled {
            for item in filtered {
                if let debug = item.debug {
                    drawDebugInfo(context: ctx, debug: debug)
                }
            }
        }
    }
    
    // Обчислення площі bounding box
    private func area(of item: TransformedTextItem) -> CGFloat {
        let xs = item.cornerPoints.map { $0.x }
        let ys = item.cornerPoints.map { $0.y }
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return 0 }
        return (maxX - minX) * (maxY - minY)
    }
    
    private func removeDuplicateOverlaps(from items: [TransformedTextItem]) -> [TransformedTextItem] {
        var result: [TransformedTextItem] = []
        for item in items {
            let itemBox = boundingBox(of: item.cornerPoints)
            // Знайдемо чи сильно перекривається з уже доданим
            var isDuplicate = false
            for existing in result {
                let existingBox = boundingBox(of: existing.cornerPoints)
                let iou = intersectionOverUnion(a: itemBox, b: existingBox)
                if iou > 0.85 && similar(item.text, existing.text) {
                    // Дубль — пропускаємо
                    isDuplicate = true
                    break
                }
            }
            if !isDuplicate {
                result.append(item)
            }
        }
        return result
    }
    
    private func boundingBox(of pts: [CGPoint]) -> CGRect {
        let xs = pts.map { $0.x }
        let ys = pts.map { $0.y }
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return .zero }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
    
    private func intersectionOverUnion(a: CGRect, b: CGRect) -> CGFloat {
        let inter = a.intersection(b)
        if inter.isNull { return 0 }
        let interArea = inter.width * inter.height
        let unionArea = a.width * a.height + b.width * b.height - interArea
        if unionArea <= 0 { return 0 }
        return interArea / unionArea
    }
    
    // Проста текстова схожість (без Levenshtein) — досить для дублів
    private func similar(_ s1: String, _ s2: String) -> Bool {
        if s1 == s2 { return true }
        let upper1 = s1.uppercased()
        let upper2 = s2.uppercased()
        if upper1 == upper2 { return true }
        // Якщо довгі і одна з них містить іншу
        if upper1.count > 4 && upper2.count > 4 &&
            (upper1.contains(upper2) || upper2.contains(upper1)) {
            return true
        }
        return false
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
        
        if let textFrame = debug.calculatedTextFrame {
            context.setStrokeColor(UIColor.green.cgColor)
            context.stroke(textFrame)
        }
        
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
                    y: center.y + 10,
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
        
        let textToDisplay = item.translatedText
        
        let contentType = Utilities.detectContentType(for: item.text)
        
        let font = Utilities.selectAdaptiveFont(for: textToDisplay, baseSize: item.fontSize, contentType: contentType)
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byClipping
        paragraphStyle.lineHeightMultiple = 0.85
        
        if textToDisplay.contains(" ") && textToDisplay.count > 20 {
            paragraphStyle.lineBreakMode = .byWordWrapping
        }
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: contentType.color,
            .paragraphStyle: paragraphStyle
        ]
        
        let attributedString = NSAttributedString(string: textToDisplay, attributes: attributes)
        
        let heightToWidthRatio = areaHeight / areaWidth
        var widthMultiplier: CGFloat = 0.95
        
        if heightToWidthRatio < 0.2 {
            widthMultiplier = 0.9
        } else if heightToWidthRatio < 0.3 {
            widthMultiplier = 0.92
        }
        
        if textToDisplay.count <= 10 {
            widthMultiplier = min(widthMultiplier * 1.05, 0.98)
        }
        
        let maxWidth = areaWidth * widthMultiplier
        let maxHeight = areaHeight
        
        let singleLineRect = attributedString.boundingRect(
            with: CGSize(width: .greatestFiniteMagnitude, height: maxHeight),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        
        // Якщо вміщається - використовуємо один рядок
        let textSize: CGSize
        if singleLineRect.width <= maxWidth {
            textSize = singleLineRect.size
        } else {
            // Інакше дозволяємо перенос
            let multiLineRect = attributedString.boundingRect(
                with: CGSize(width: maxWidth, height: maxHeight),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
            textSize = multiLineRect.size
        }
        
        if item.cornerPoints.count == 4 {
            context.saveGState()
            
            context.textMatrix = .identity
            context.translateBy(x: center.x, y: center.y)
            
            let angle = calculateRotationAngle(item.cornerPoints)
            item.debug?.calculatedRotationAngle = angle
            context.rotate(by: angle)
            
            
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
