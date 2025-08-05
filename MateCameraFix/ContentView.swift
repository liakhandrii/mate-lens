import SwiftUI
import MLKit

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @State private var showOverlay = false
    @State private var textData: [WordData] = []
    @State private var isProcessing = false
    
    @State private var debugEnabled: Bool = false

    #if DEBUG
    private let drawDebugButton = true
    #else
    private let drawDebugButton = false
    #endif
        
    // Розміри та відступи
    private enum Layout {
        static let captureButtonSize: CGFloat = 70
        static let captureButtonStrokeWidth: CGFloat = 2
        static let captureButtonStrokeOpacity: Double = 0.8
        static let captureButtonBottomPadding: CGFloat = 50
        
        static let previewImageSize: CGFloat = 100
        static let previewImageBorderWidth: CGFloat = 2
        static let previewImagePadding: CGFloat = 16
        
        static let captureDelay: TimeInterval = 1.5
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Камера на повний екран
                CameraView(cameraManager: cameraManager)
                    .ignoresSafeArea()
            
                VStack {
                    Spacer()
                        
                    HStack(spacing: 30) {
                        // DEBUG кнопка (тільки в DEBUG режимі)
                        if drawDebugButton {
                            Button(action: {
                                debugEnabled.toggle()
                            }) {
                                Text("DEBUG")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(debugEnabled ? .black : .white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(debugEnabled ? Color.yellow : Color.black.opacity(0.6))
                                    .cornerRadius(8)
                            }
                        }
                        
                        // Кнопка фото з обробкою
                        Button(action: {
                            isProcessing = true
                            cameraManager.capturePhoto()
                            
                            // Затримка для обробки фото
                            DispatchQueue.main.asyncAfter(deadline: .now() + Layout.captureDelay) {
                                if let image = cameraManager.capturedImage {
                                    recognizeText(in: image)
                                }
                                isProcessing = false
                            }
                        }) {
                            Circle()
                                .fill(Color.white)
                                .frame(width: Layout.captureButtonSize, height: Layout.captureButtonSize)
                                .overlay(
                                    Circle()
                                        .stroke(Color.black.opacity(Layout.captureButtonStrokeOpacity), lineWidth: Layout.captureButtonStrokeWidth)
                                )
                        }
                        
                        // Spacer для симетрії, якщо DEBUG кнопка не показується
                        if !drawDebugButton {
                            Spacer()
                                .frame(width: 60) // Приблизна ширина DEBUG кнопки
                        }
                    }
                    .padding(.bottom, Layout.captureButtonBottomPadding)
                }
            
                // Маленьке фото в кутку
                if let capturedImage = cameraManager.capturedImage {
                    VStack {
                        HStack {
                            Spacer()
                            Image(uiImage: capturedImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: Layout.previewImageSize, height: Layout.previewImageSize)
                                .border(Color.white, width: Layout.previewImageBorderWidth)
                                .padding(Layout.previewImagePadding)
                        }
                        Spacer()
                    }
                }
            
                // Індикатор завантаження
                if isProcessing {
                    ProgressView()
                        .scaleEffect(2)
                        .padding()
                        .background(Color.white.opacity(0.8))
                        .cornerRadius(10)
                }
            }
            .navigationDestination(isPresented: $showOverlay) {
                PositionedTextOverlayView(
                    image: cameraManager.capturedImage,
                    textData: textData,
                    debugEnabled: debugEnabled
                )
            }
        }
    }
    
    // MARK: - Функція розпізнавання тексту
    func recognizeText(in image: UIImage) {
        guard let normalizedImage = Utilities.normalize(image: image) else {
            print("Failed to normalize image")
            return
        }
        
        let visionImage = VisionImage(image: normalizedImage)
        visionImage.orientation = .up
        
        let textRecognizer = TextRecognizer.textRecognizer(options: TextRecognizerOptions())

        textRecognizer.process(visionImage) { result, error in
            if let error = error {
                print("Error: \(error)")
                return
            }

            guard let result = result else {
                print("Text not found")
                return
            }

            var lineItems: [WordData] = []
            for block in result.blocks {
                for line in block.lines {
                    let optimizedText = Utilities.optimizeText(line.text)
                    let lineItem = WordData(
                        text: optimizedText,
                        frame: line.frame,
                        cornerPoints: line.cornerPoints.map { $0.cgPointValue }
                    )
                    lineItems.append(lineItem)
                    print("Found line: \(optimizedText) at position: (\(line.frame.midX), \(line.frame.midY))")
                }
            }
            
            print("Total lines found: \(lineItems.count)")

            DispatchQueue.main.async {
                self.textData = lineItems
                self.showOverlay = true
            }
        }
    }
}


// MARK: - Представлення накладання тексту
struct PositionedTextOverlayView: View {
    let image: UIImage?
    let textData: [WordData]
    let debugEnabled: Bool
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geometry.size.width, height: geometry.size.height)
            
                    PerspectiveTextView(
                        textItems: textData,
                        imageSize: image.size,
                        screenSize: geometry.size,
                        debugEnabled: debugEnabled
                    )
                } else {
                    Text("Photo not made")
                }
            }
        }
        .ignoresSafeArea()
        .navigationTitle("Positioned Text")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - PerspectiveTextView для відображення тексту з перспективою
struct PerspectiveTextView: UIViewRepresentable {
    let textItems: [WordData]
    let imageSize: CGSize
    let screenSize: CGSize
    let debugEnabled: Bool
    
    func makeUIView(context: Context) -> TextDrawingView {
        let view = TextDrawingView()
        view.textItems = transformTextItems(textItems, imageSize: imageSize, screenSize: screenSize)
        view.debugEnabled = debugEnabled
        return view
    }
    
    func updateUIView(_ uiView: TextDrawingView, context: Context) {
        uiView.textItems = transformTextItems(textItems, imageSize: imageSize, screenSize: screenSize)
        uiView.debugEnabled = debugEnabled
        uiView.setNeedsDisplay()
    }
    
    // Конвертуємо координати тексту для екрану
    private func transformTextItems(_ items: [WordData], imageSize: CGSize, screenSize: CGSize) -> [TransformedTextItem] {
        return items.compactMap { item in
            let fontSize = calculateAdaptiveFontSize(for: item, imageSize: imageSize, screenSize: screenSize)
            let contentType = Utilities.detectContentType(for: item.text)
            
            let debugInfo = TextTransformDebug()
            
            let transformedPoints = item.cornerPoints!.map { transform($0, imageSize: imageSize, screenSize: screenSize) }
            
            if let cornerPoints = item.cornerPoints, cornerPoints.count == 4 {
                let padding: CGFloat = 4  // Збільшено для більшого простору
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
                
                return TransformedTextItem(
                    text: item.text,
                    cornerPoints: expandedPoints,
                    fontSize: fontSize,
                    contentType: contentType,
                    debug: debugInfo
                )
            } else {
                return nil
            }
        }
    }
    
    // Підбираємо розмір шрифту під блок
    private func calculateAdaptiveFontSize(for item: WordData, imageSize: CGSize, screenSize: CGSize) -> CGFloat {
        let (scale, _, _) = calculateScaleAndOffsets(imageSize: imageSize, screenSize: screenSize)
        
        guard let cornerPoints = item.cornerPoints, cornerPoints.count >= 4 else {
            return item.frame.height * scale * 0.65
        }
        
        let transformedPoints = cornerPoints.map { transform($0, imageSize: imageSize, screenSize: screenSize) }
        
        // Висота по лівій і правій стороні
        let leftHeight = distance(from: transformedPoints[0], to: transformedPoints[3])
        let rightHeight = distance(from: transformedPoints[1], to: transformedPoints[2])
        let avgHeight = (leftHeight + rightHeight) / 2.0
        
        // Ширина зверху і знизу
        let topWidth = distance(from: transformedPoints[0], to: transformedPoints[1])
        let bottomWidth = distance(from: transformedPoints[3], to: transformedPoints[2])
        let avgWidth = (topWidth + bottomWidth) / 2.0
        
        let textLength = item.text.count
        let widthHeightRatio = avgWidth / avgHeight
        
        // Базовий коефіцієнт - зменшено для кращого відображення
        var scaleFactor: CGFloat = 0.7
        
        // Довгі тексти потребують меншого шрифту
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
        
        // Короткі тексти можуть бути більшими
        if textLength <= 3 {
            scaleFactor *= 1.1
        } else if textLength <= 5 {
            scaleFactor *= 1.05
        }
        
        let fontSize = avgHeight * scaleFactor
        return max(fontSize, 8.0)
    }
    
    // Відстань між точками
    private func distance(from point1: CGPoint, to point2: CGPoint) -> CGFloat {
        let dx = point2.x - point1.x
        let dy = point2.y - point1.y
        return sqrt(dx * dx + dy * dy)
    }
    
    // Збільшуємо полігон щоб покрив весь текст
    private func expandPolygon(_ points: [CGPoint], by padding: CGFloat) -> [CGPoint] {
        guard points.count >= 3 else { return points }
        
        let center = improvedCenterOf(points)
        
        return points.map { point in
            let dx = point.x - center.x
            let dy = point.y - center.y
            let distance = sqrt(dx*dx + dy*dy)
            
            if distance < 0.0001 { return point }
            
            // Адаптивне розширення залежно від розміру
            let adaptivePadding = padding * 1.5
            let scale = (distance + adaptivePadding) / distance
            return CGPoint(
                x: center.x + dx * scale,
                y: center.y + dy * scale
            )
        }
    }
    
    // Знаходимо центр полігону (працює краще для неправильних форм)
    private func improvedCenterOf(_ points: [CGPoint]) -> CGPoint {
        guard points.count >= 3 else {
            let xs = points.map { $0.x }
            let ys = points.map { $0.y }
            return CGPoint(x: xs.reduce(0, +) / CGFloat(xs.count), y: ys.reduce(0, +) / CGFloat(ys.count))
        }
        
        if points.count == 4 {
            // Для чотирикутників - перетин діагоналей
            let p1 = points[0]
            let p2 = points[2]
            let p3 = points[1]
            let p4 = points[3]
            
            let d = (p1.x - p2.x) * (p3.y - p4.y) - (p1.y - p2.y) * (p3.x - p4.x)
            
            if abs(d) < 0.000001 {
                // Якщо діагоналі паралельні
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
        
        // Інакше просто середнє
        let xs = points.map { $0.x }
        let ys = points.map { $0.y }
        return CGPoint(x: xs.reduce(0, +) / CGFloat(xs.count), y: ys.reduce(0, +) / CGFloat(ys.count))
    }
    
    // Масштаб і зміщення для fit на екрані
    private func calculateScaleAndOffsets(imageSize: CGSize, screenSize: CGSize) -> (scale: CGFloat, offsetX: CGFloat, offsetY: CGFloat) {
        let imageAspectRatio = imageSize.width / imageSize.height
        let screenAspectRatio = screenSize.width / screenSize.height
        
        if imageAspectRatio > screenAspectRatio {
            // Картинка ширша
            let scale = screenSize.width / imageSize.width
            return (scale, 0, (screenSize.height - imageSize.height * scale) / 2)
        } else {
            // Картинка вища
            let scale = screenSize.height / imageSize.height
            return (scale, (screenSize.width - imageSize.width * scale) / 2, 0)
        }
    }
    
    // Конвертуємо точку з координат картинки в координати екрану
    private func transform(_ point: CGPoint, imageSize: CGSize, screenSize: CGSize) -> CGPoint {
        let (scale, offsetX, offsetY) = calculateScaleAndOffsets(imageSize: imageSize, screenSize: screenSize)
        return CGPoint(
            x: point.x * scale + offsetX,
            y: point.y * scale + offsetY
        )
    }
}

// MARK: - TextDrawingView для малювання тексту з перспективою
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
            
            // Малюємо фон
            context.beginPath()
            if item.cornerPoints.count >= 4 {
                context.move(to: item.cornerPoints[0])
                for i in 1..<item.cornerPoints.count {
                    context.addLine(to: item.cornerPoints[i])
                }
                context.closePath()
                context.drawPath(using: .fillStroke)
            }
            
            // Текст з поворотом
            drawTextWithPerspective(context: context, item: item)
            
            // Debug режим
            if debugEnabled, let debug = item.debug {
                drawDebugInfo(context: context, debug: debug)
            }
            
            context.restoreGState()
        }
    }
    
    // Debug малювання
    private func drawDebugInfo(context: CGContext, debug: TextTransformDebug) {
        context.saveGState()
        context.setLineWidth(1.0)
        
        // Оригінальні точки - червоні
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
        
        // Розширені точки - жовті
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
        
        // Рамка тексту - синя
        if let textRect = debug.calculatedTextRect,
            let transformedPoints = debug.transformedCornerPoints, transformedPoints.count >= 4 {
            let center = getCenterOfPoints(transformedPoints)
            
            // Позиція рамки на екрані
            let actualTextRect = CGRect(
                x: center.x + textRect.origin.x,
                y: center.y + textRect.origin.y,
                width: textRect.width,
                height: textRect.height
            )
            
            context.setStrokeColor(UIColor.blue.cgColor)
            context.stroke(actualTextRect)
        }
        
        // Frame з MLKit - зелений
        if let textFrame = debug.calculatedTextFrame {
            context.setStrokeColor(UIColor.green.cgColor)
            context.stroke(textFrame)
        }
        
        // Debug інфа: кут і розмір шрифту
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
                    y: center.y + 10, // Під текстом
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
        
        // Тип контенту
        let contentType = Utilities.detectContentType(for: item.text)
        
        // Підбір шрифту
        let font = Utilities.selectAdaptiveFont(for: item.text, baseSize: item.fontSize, contentType: contentType)
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byTruncatingTail  // Змінено назад для коротких текстів
        paragraphStyle.lineHeightMultiple = 0.85  // Трохи збільшено
        
        // Довгі тексти - з переносами
        if item.text.count > 15 {
            paragraphStyle.lineBreakMode = .byWordWrapping
        }
        
        // Атрибути тексту
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: contentType.color,
            .paragraphStyle: paragraphStyle
        ]
        
        // Для важливої інфо додаємо тінь
        var enhancedAttributes = attributes
        if contentType == .price || contentType == .date || contentType == .number {
            let shadow = NSShadow()
            shadow.shadowColor = UIColor.white
            shadow.shadowOffset = CGSize(width: 0, height: 0)
            shadow.shadowBlurRadius = 3
            enhancedAttributes[.shadow] = shadow
        }
        
        let attributedString = NSAttributedString(string: item.text, attributes: enhancedAttributes)
        
        // Максимальна ширина залежить від форми області
        let heightToWidthRatio = areaHeight / areaWidth
        var widthMultiplier: CGFloat = 0.9  // Збільшено базовий множник
        
        if heightToWidthRatio < 0.2 { // Вузька смужка
            widthMultiplier = 0.75
        } else if heightToWidthRatio < 0.3 {
            widthMultiplier = 0.8
        } else if heightToWidthRatio < 0.4 {
            widthMultiplier = 0.85
        }
        
        // Короткі тексти можуть займати більше місця
        if item.text.count <= 10 {
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
            
            // Позиція тексту
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
    
    // Кут нахилу тексту
    private func calculateRotationAngle(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 4 else { return 0 }
        
        // Кут верхньої лінії
        let topDx = points[1].x - points[0].x
        let topDy = points[1].y - points[0].y
        let topAngle = atan2(topDy, topDx)
        
        // Кут нижньої лінії
        let bottomDx = points[2].x - points[3].x
        let bottomDy = points[2].y - points[3].y
        let bottomAngle = atan2(bottomDy, bottomDx)
        
        // Середній кут
        var angle = (topAngle + bottomAngle) / 2.0
        
        // Нормалізація (щоб текст не був догори ногами)
        while angle > .pi / 4 {
            angle -= .pi
        }
        while angle < -.pi / 4 {
            angle += .pi
        }
        
        return angle
    }
    
    // Розмір прямокутника навколо точок
    private func getBoundingSize(for points: [CGPoint]) -> CGSize {
        let xs = points.map { $0.x }
        let ys = points.map { $0.y }
        
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else {
            return .zero
        }
        
        return CGSize(width: maxX - minX, height: maxY - minY)
    }
    
    // Центр полігону
    private func getCenterOfPoints(_ points: [CGPoint]) -> CGPoint {
        let count = CGFloat(points.count)
        let x = points.reduce(0) { $0 + $1.x } / count
        let y = points.reduce(0) { $0 + $1.y } / count
        return CGPoint(x: x, y: y)
    }
}
