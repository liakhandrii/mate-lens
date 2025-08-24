import SwiftUI
import UIKit

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
            let cacheKey = "\(item.text)_\(imageSize.width)x\(imageSize.height)_\(screenSize.width)x\(screenSize.height)"
            
            if let cached = transformCache.getTransformed(for: item, key: cacheKey) {
                print("Using cached transform for: \(item.text)")
                return cached
            }

            // Аналіз кольору тепер виконується через ColorAnalyzer
            let (textColor, bgColor) = ColorAnalyzer.analyzeColors(from: item)
            let estimatedWeight = estimateFontWeight(from: item)
            
            if item.cornerPoints == nil || item.cornerPoints?.count != 4 {
                print("Using frame fallback for: \(item.text)")
                let (scale, offsetX, offsetY) = Utilities.calculateScaleAndOffsets(imageSize: imageSize, screenSize: screenSize)
                
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
                
                let fontSize = calculateAdaptiveFontSize(for: item, imageSize: imageSize, screenSize: screenSize, allItems: items)
                let contentType = Utilities.detectContentType(for: item.text)
                
                let result = TransformedTextItem(
                    text: item.text,
                    translatedText: item.translatedText ?? item.text,
                    cornerPoints: corners,
                    fontSize: fontSize,
                    contentType: contentType,
                    textColor: textColor,
                    backgroundColor: bgColor,
                    estimatedWeight: estimatedWeight,
                    debug: nil
                )
                
                transformCache.store(result, key: cacheKey)
                return result
            }
            
            let fontSize = calculateAdaptiveFontSize(for: item, imageSize: imageSize, screenSize: screenSize, allItems: items)
            let contentType = Utilities.detectContentType(for: item.text)
            
            let debugInfo = TextTransformDebug()
            
            
            let transformedPoints = item.cornerPoints!.map { Utilities.transform($0, imageSize: imageSize, screenSize: screenSize) }
            
            // Трохи розширюємо полігон, щоб гарантовано покрити оригінальний текст
            let finalPoints = Utilities.expandPolygon(transformedPoints, by: 2.0)
            
            debugInfo.originalCornerPoints = transformedPoints
            
            let (scale, offsetX, offsetY) = Utilities.calculateScaleAndOffsets(imageSize: imageSize, screenSize: screenSize)
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
                textColor: textColor,
                backgroundColor: bgColor,
                estimatedWeight: estimatedWeight,
                debug: debugEnabled ? debugInfo : nil
            )
            
            // Зберігаємо в кеш
            transformCache.store(result, key: cacheKey)
            return result
        }
    }
    
    // MARK: - Font Weight Estimation
    private func estimateFontWeight(from item: WordData) -> UIFont.Weight {
        let textLength = CGFloat(item.text.count)
        let frameArea = item.frame.width * item.frame.height
        
        guard textLength > 0, frameArea > 0 else { return .regular }
        
        // Проста щільність символів на площу
        let density = textLength / frameArea
        
        // Ці значення потребуватимуть тюнінгу
        if density > 0.015 {
            return .bold
        } else if density > 0.008 {
            return .medium
        } else {
            return .regular
        }
    }
    
    private func calculateAdaptiveFontSize(for item: WordData,
                                           imageSize: CGSize,
                                           screenSize: CGSize,
                                           allItems: [WordData]) -> CGFloat {
        let (scale, _, _) = Utilities.calculateScaleAndOffsets(imageSize: imageSize, screenSize: screenSize)

        guard let cornerPoints = item.cornerPoints, cornerPoints.count >= 4 else {
            return item.frame.height * scale * 0.7
        }
        
        let transformedPoints = cornerPoints.map { Utilities.transform($0, imageSize: imageSize, screenSize: screenSize) }

        let leftHeight = Utilities.distance(from: transformedPoints[0], to: transformedPoints[3])
        let rightHeight = Utilities.distance(from: transformedPoints[1], to: transformedPoints[2])
        let avgHeight = (leftHeight + rightHeight) / 2.0
        
        let topWidth = Utilities.distance(from: transformedPoints[0], to: transformedPoints[1])
        let bottomWidth = Utilities.distance(from: transformedPoints[3], to: transformedPoints[2])
        let avgWidth = (topWidth + bottomWidth) / 2.0

        let targetSize = CGSize(width: avgWidth * 0.95, height: avgHeight * 0.95)
        
        if targetSize.width < 4 || targetSize.height < 4 {
            return 6.0
        }

        let textToFit = item.translatedText ?? item.text
        let contentType = Utilities.detectContentType(for: item.text)
        let estimatedWeight = estimateFontWeight(from: item)

        // Бінарний пошук оптимального розміру шрифту
        let minFontSize: CGFloat = 6.0
        let maxFontSize: CGFloat = avgHeight
        
        // Точність пошуку (можна налаштувати)
        let precision: CGFloat = 0.5
        
        var low = minFontSize
        var high = maxFontSize
        var bestFitSize = minFontSize
        
        // Функція для перевірки чи вміщається текст
        func textFits(fontSize: CGFloat) -> Bool {
            let font = Utilities.selectAdaptiveFont(for: textToFit, baseSize: fontSize, contentType: contentType, weight: estimatedWeight)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineBreakMode = .byWordWrapping
            
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .paragraphStyle: paragraphStyle
            ]
            
            let attributedString = NSAttributedString(string: textToFit, attributes: attributes)
            
            let calculatedRect = attributedString.boundingRect(
                with: CGSize(width: targetSize.width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
            
            return calculatedRect.height <= targetSize.height
        }
        
        // Бінарний пошук
        while high - low > precision {
            let mid = (low + high) / 2.0
            
            if textFits(fontSize: mid) {
                // Текст вміщається, спробуємо збільшити розмір
                bestFitSize = mid
                low = mid
            } else {
                // Текст не вміщається, зменшуємо розмір
                high = mid
            }
        }
        
        // Фінальна перевірка для округленого значення
        let finalSize = floor(bestFitSize)
        if finalSize >= minFontSize && textFits(fontSize: finalSize) {
            return finalSize
        }
        
        return max(minFontSize, floor(bestFitSize))
    }

    
    
    private func calculateLocalTextDensity(for item: WordData,
                                           allItems: [WordData],
                                           imageSize: CGSize) -> CGFloat {
        let itemBox = item.frame
        
        let checkArea = itemBox.insetBy(dx: -itemBox.width * 0.5, dy: -itemBox.height * 0.5)
        
        var overlappingCount = 0
        var totalOverlapArea: CGFloat = 0
        
        for otherItem in allItems {
            guard otherItem.text != item.text else { continue }
            
            let otherBox = otherItem.frame
            if checkArea.intersects(otherBox) {
                overlappingCount += 1
                let intersection = checkArea.intersection(otherBox)
                totalOverlapArea += (intersection.width * intersection.height)
            }
        }
        
        let checkAreaSize = checkArea.width * checkArea.height
        let density = totalOverlapArea / checkAreaSize
        
        return min(1.0, density)
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
        
        ctx.saveGState()
        // Вмикаємо згладжування для більш якісного рендерингу
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)

        let filtered = removeDuplicateOverlaps(from: textItems)
        
        let backgroundsOrder = filtered.sorted { area(of: $0) < area(of: $1) }
        let textOrder = filtered.sorted { area(of: $0) > area(of: $1) }
        
        // Малюємо фон з ефектом розмиття
        for item in backgroundsOrder {
            guard item.cornerPoints.count >= 4 else { continue }
            ctx.saveGState()
            let path = CGMutablePath()
            path.addLines(between: item.cornerPoints)
            path.closeSubpath()

            // Додаємо пом'якшення країв для кращого блендингу
            ctx.setShadow(offset: .zero, blur: 6.0, color: item.backgroundColor.cgColor)

            // Спробуй експериментувати з blend mode:
            ctx.setBlendMode(.normal) // або .multiply/.overlay

            ctx.setFillColor(item.backgroundColor.cgColor)
            ctx.addPath(path)
            ctx.fillPath()
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
        
        ctx.restoreGState()
    }

    
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
            var isDuplicate = false
            for existing in result {
                let existingBox = boundingBox(of: existing.cornerPoints)
                let iou = intersectionOverUnion(a: itemBox, b: existingBox)
                if iou > 0.85 && similar(item.text, existing.text) {
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
        
        // Використовуємо визначену вагу шрифта
        let font = Utilities.selectAdaptiveFont(for: textToDisplay, baseSize: item.fontSize, contentType: contentType, weight: item.estimatedWeight)
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byClipping
        paragraphStyle.lineHeightMultiple = 0.85
        
        if textToDisplay.contains(" ") && textToDisplay.count > 20 {
            paragraphStyle.lineBreakMode = .byWordWrapping
        }
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: item.textColor, // Використовуємо визначений колір тексту
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
        
        let textSize: CGSize
        if singleLineRect.width <= maxWidth {
            textSize = singleLineRect.size
        } else {
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
        
        // Визначаємо вектори верхньої та нижньої граней
        let topVector = CGPoint(x: points[1].x - points[0].x, y: points[1].y - points[0].y)
        let bottomVector = CGPoint(x: points[2].x - points[3].x, y: points[2].y - points[3].y)
        
        let topLength = sqrt(topVector.x * topVector.x + topVector.y * topVector.y)
        let bottomLength = sqrt(bottomVector.x * bottomVector.x + bottomVector.y * bottomVector.y)
        
        let topAngle = atan2(topVector.y, topVector.x)
        let bottomAngle = atan2(bottomVector.y, bottomVector.x)
        
        // Визначаємо ступінь перспективи
        let perspectiveRatio = min(topLength, bottomLength) / max(topLength, bottomLength)
        
        var angle: CGFloat
        if perspectiveRatio < 0.7 {
            // Сильна перспектива - використовуємо кут довшої грані
            angle = topLength > bottomLength ? topAngle : bottomAngle
        } else {
            // Слабка перспектива - усереднюємо
            angle = (topAngle + bottomAngle) / 2.0
        }
        
        // Нормалізуємо кут
        while angle > .pi / 2 {
            angle -= .pi
        }
        while angle < -.pi / 2 {
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
//h
//fmf
