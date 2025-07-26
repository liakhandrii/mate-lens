import SwiftUI
import MLKit

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @State private var showOverlay = false
    @State private var textData: [WordData] = []
    @State private var isProcessing = false
    
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
                    
                    // Кнопка фото з обробкою
                    Button(action: {
                        cameraManager.capturePhoto()
                        isProcessing = true
                        
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
                    textData: textData
                )
            }
        }
    }
    
    // MARK: - Функція розпізнавання тексту
    func recognizeText(in image: UIImage) {
        guard let normalizedImage = normalize(image: image) else {
            print("Failed to normalize image")
            return
        }
        
        let visionImage = VisionImage(image: normalizedImage)
        visionImage.orientation = .up
        
        let textRecognizer = TextRecognizer.textRecognizer()

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
                    let optimizedText = optimizeText(line.text)
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

// MARK: - Допоміжні функції

// Функція фіксації орієнтації фото
func normalize(image: UIImage) -> UIImage? {
    guard image.imageOrientation != .up else { return image }

    UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
    defer { UIGraphicsEndImageContext() }
    
    image.draw(in: CGRect(origin: .zero, size: image.size))
    
    return UIGraphicsGetImageFromCurrentImageContext()
}

// Функція корекції типових помилок розпізнавання
func optimizeText(_ text: String) -> String {
    var processed = text
    
    // Заміна типових помилок розпізнавання
    let replacements = [
        "0": "O", "1": "I", "5": "S", "8": "B",
        "rn": "m", "cl": "d", "vv": "w",
        "teh": "the", "adn": "and"
    ]
    
    for (error, correction) in replacements {
        processed = processed.replacingOccurrences(of: error, with: correction)
    }
    
    return processed
}

// на майбутнє, щоб можна було робити фото не тільки в одному положенні
//func visionImageOrientation(from imageOrientation: UIImage.Orientation) -> VisionImage.Orientation {
//    switch imageOrientation {
//    case .up:
//        return .up
//    case .down:
//        return .down
//    case .left:
//        return .left
//    case .right:
//        return .right
//    case .upMirrored:
//        return .upMirrored
//    case .downMirrored:
//        return .downMirrored
//    case .leftMirrored:
//        return .leftMirrored
//    case .rightMirrored:
//        return .rightMirrored
//    @unknown default:
//        return .up
//    }
//}

// MARK: - Модель даних
struct WordData {
    let text: String
    let frame: CGRect
    let cornerPoints: [CGPoint]?
}

// MARK: - Представлення накладання тексту
struct PositionedTextOverlayView: View {
    let image: UIImage?
    let textData: [WordData]
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image = image {
                    // Відображення оригінального фото
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                    
                    // Використовуємо PerspectiveTextView для відображення тексту з перспективою
                    PerspectiveTextView(
                        textItems: textData,
                        imageSize: image.size,
                        screenSize: geometry.size
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
    
    func makeUIView(context: Context) -> TextDrawingView {
        let view = TextDrawingView()
        view.textItems = transformTextItems(textItems, imageSize: imageSize, screenSize: screenSize)
        return view
    }
    
    func updateUIView(_ uiView: TextDrawingView, context: Context) {
        uiView.textItems = transformTextItems(textItems, imageSize: imageSize, screenSize: screenSize)
        uiView.setNeedsDisplay()
    }
    
    // Перетворення текстових елементів для відображення
    private func transformTextItems(_ items: [WordData], imageSize: CGSize, screenSize: CGSize) -> [TransformedTextItem] {
        return items.map { item in
            let fontSize = calculateAdaptiveFontSize(for: item, imageSize: imageSize, screenSize: screenSize)
            
            if let cornerPoints = item.cornerPoints, cornerPoints.count == 4 {
                // Трансформуємо точки в координати екрану
                let transformedPoints = cornerPoints.map { transform($0, imageSize: imageSize, screenSize: screenSize) }
                // Додаємо невелике розширення для кращого вигляду
                let padding: CGFloat = 4
                let expandedPoints = expandPolygon(transformedPoints, by: padding)
                
                return TransformedTextItem(
                    text: item.text,
                    cornerPoints: expandedPoints,
                    fontSize: fontSize
                )
            } else {
                // Використовуємо центр і розміри рамки
                let (scale, offsetX, offsetY) = calculateScaleAndOffsets(imageSize: imageSize, screenSize: screenSize)
                let center = CGPoint(
                    x: item.frame.midX * scale + offsetX,
                    y: item.frame.midY * scale + offsetY
                )
                let width = item.frame.width * scale + 16  // Більший відступ для кращого вигляду
                let height = item.frame.height * scale + 12
                
                // Створюємо кутові точки прямокутника
                let halfWidth = width / 2
                let halfHeight = height / 2
                let corners = [
                    CGPoint(x: center.x - halfWidth, y: center.y - halfHeight),
                    CGPoint(x: center.x + halfWidth, y: center.y - halfHeight),
                    CGPoint(x: center.x + halfWidth, y: center.y + halfHeight),
                    CGPoint(x: center.x - halfWidth, y: center.y + halfHeight)
                ]
                
                return TransformedTextItem(
                    text: item.text,
                    cornerPoints: corners,
                    fontSize: fontSize
                )
            }
        }
    }
    
    // Адаптивний розмір шрифту для різних текстових блоків
    private func calculateAdaptiveFontSize(for item: WordData, imageSize: CGSize, screenSize: CGSize) -> CGFloat {
        let (scale, _, _) = calculateScaleAndOffsets(imageSize: imageSize, screenSize: screenSize)
        let baseSize = item.frame.height * scale
        
        let textLength = item.text.count
        let widthHeightRatio = item.frame.width / item.frame.height
        
        // Використовуємо більш агресивне масштабування для кращої відповідності
        if widthHeightRatio > 7.0 {
            return baseSize * 0.6  // Для дуже широких текстових блоків
        } else if textLength > 30 {
            return baseSize * 0.65  // Для довгих текстів
        } else if textLength > 15 {
            return baseSize * 0.7  // Для середніх текстів
        } else {
            return baseSize * 0.75  // Для коротких текстів
        }
    }
    
    // Розширення багатокутника для кращого покриття тексту
    private func expandPolygon(_ points: [CGPoint], by padding: CGFloat) -> [CGPoint] {
        guard points.count >= 3 else { return points }
        
        let center = improvedCenterOf(points)
        
        return points.map { point in
            let dx = point.x - center.x
            let dy = point.y - center.y
            let distance = sqrt(dx*dx + dy*dy)
            
            if distance < 0.0001 { return point }
            
            let scale = (distance + padding) / distance
            return CGPoint(
                x: center.x + dx * scale,
                y: center.y + dy * scale
            )
        }
    }
    
    // Удосконалений метод центрування для нерівномірних многокутників
    private func improvedCenterOf(_ points: [CGPoint]) -> CGPoint {
        guard points.count >= 3 else {
            let xs = points.map { $0.x }
            let ys = points.map { $0.y }
            return CGPoint(x: xs.reduce(0, +) / CGFloat(xs.count), y: ys.reduce(0, +) / CGFloat(ys.count))
        }
        
        if points.count == 4 {
            // Спеціальна обробка для чотирикутників (використання перетину діагоналей)
            let p1 = points[0]
            let p2 = points[2]
            let p3 = points[1]
            let p4 = points[3]
            
            let d = (p1.x - p2.x) * (p3.y - p4.y) - (p1.y - p2.y) * (p3.x - p4.x)
            
            if abs(d) < 0.000001 {
                // Запобігання діленню на нуль
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
        
        // Загальний випадок - використання середніх значень
        let xs = points.map { $0.x }
        let ys = points.map { $0.y }
        return CGPoint(x: xs.reduce(0, +) / CGFloat(xs.count), y: ys.reduce(0, +) / CGFloat(ys.count))
    }
    
    // Розрахунок масштабу та зміщення для коректного відображення на екрані
    private func calculateScaleAndOffsets(imageSize: CGSize, screenSize: CGSize) -> (scale: CGFloat, offsetX: CGFloat, offsetY: CGFloat) {
        let imageAspectRatio = imageSize.width / imageSize.height
        let screenAspectRatio = screenSize.width / screenSize.height
        
        if imageAspectRatio > screenAspectRatio {
            // Зображення ширше відносно екрану
            let scale = screenSize.width / imageSize.width
            return (scale, 0, (screenSize.height - imageSize.height * scale) / 2)
        } else {
            // Зображення вище відносно екрану
            let scale = screenSize.height / imageSize.height
            return (scale, (screenSize.width - imageSize.width * scale) / 2, 0)
        }
    }
    
    // Трансформація координат із системи зображення в систему екрану
    private func transform(_ point: CGPoint, imageSize: CGSize, screenSize: CGSize) -> CGPoint {
        let (scale, offsetX, offsetY) = calculateScaleAndOffsets(imageSize: imageSize, screenSize: screenSize)
        return CGPoint(
            x: point.x * scale + offsetX,
            y: point.y * scale + offsetY
        )
    }
}

// Структура для передачі даних у TextDrawingView
struct TransformedTextItem {
    let text: String
    let cornerPoints: [CGPoint]
    let fontSize: CGFloat
}

// MARK: - TextDrawingView для малювання тексту з перспективою
class TextDrawingView: UIView {
    var textItems: [TransformedTextItem] = [] {
        didSet {
            setNeedsDisplay()
        }
    }
    
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
            
            // Створюємо і заповнюємо шлях
            context.beginPath()
            if item.cornerPoints.count >= 4 {
                context.move(to: item.cornerPoints[0])
                for i in 1..<item.cornerPoints.count {
                    context.addLine(to: item.cornerPoints[i])
                }
                context.closePath()
                context.drawPath(using: .fillStroke)
            }
            
            // Малювання тексту з перспективною трансформацією
            drawTextWithPerspective(context: context, item: item)
            
            context.restoreGState()
        }
    }
    
    // Функція для малювання тексту з урахуванням перспективи
    private func drawTextWithPerspective(context: CGContext, item: TransformedTextItem) {
        // Знаходимо центр чотирикутника
        let center = getCenterOfPoints(item.cornerPoints)
        
        // Створюємо атрибутний рядок
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byWordWrapping
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: item.fontSize),
            .foregroundColor: UIColor.black,
            .paragraphStyle: paragraphStyle
        ]
        let attributedString = NSAttributedString(string: item.text, attributes: attributes)
        
        // Визначаємо розмір тексту
        let textSize = attributedString.size()
        
        // Визначаємо розмір квадрата (обираємо менше з ширини/висоти для збереження пропорцій)
        let quadWidth = getBoundingSize(for: item.cornerPoints).width
        let maxTextWidth = min(quadWidth * 0.9, textSize.width * 1.1)  // Обмежуємо ширину тексту
        
        // Для тексту з перспективним спотворенням
        if item.cornerPoints.count == 4 {
            // Зберігаємо стан графічного контексту
            context.saveGState()
            
            // Створюємо трансформаційну матрицю для перспективного перетворення
            // Тут можна використати повну перспективну трансформацію,
            // але для простоти обмежимося позиціонуванням
            context.textMatrix = .identity
            context.translateBy(x: center.x, y: center.y)
            
            // Обчислюємо кут нахилу для тексту
            let angle = calculateRotationAngle(item.cornerPoints)
            context.rotate(by: angle)
            
            // Розміщуємо текст з урахуванням центрування і можливого переносу рядків
            let textRect = CGRect(
                x: -maxTextWidth / 2,
                y: -textSize.height / 2,
                width: maxTextWidth,
                height: textSize.height
            )
            
            // Малюємо текст
            attributedString.draw(in: textRect)
            
            // Відновлюємо стан контексту
            context.restoreGState()
        } else {
            // Запасний варіант для випадків з недостатньою кількістю точок
            let textRect = CGRect(
                x: center.x - maxTextWidth / 2,
                y: center.y - textSize.height / 2,
                width: maxTextWidth,
                height: textSize.height
            )
            
            attributedString.draw(in: textRect)
        }
    }
    
    // Обчислення кута повороту на основі точок чотирикутника
    private func calculateRotationAngle(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 2 else { return 0 }
        
        // Використовуємо верхню лінію для визначення кута
        let dx = points[1].x - points[0].x
        let dy = points[1].y - points[0].y
        
        return atan2(dy, dx)
    }
    
    // Отримання розміру обмежуючого прямокутника
    private func getBoundingSize(for points: [CGPoint]) -> CGSize {
        let xs = points.map { $0.x }
        let ys = points.map { $0.y }
        
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else {
            return .zero
        }
        
        return CGSize(width: maxX - minX, height: maxY - minY)
    }
    
    // Отримання центру набору точок
    private func getCenterOfPoints(_ points: [CGPoint]) -> CGPoint {
        let count = CGFloat(points.count)
        let x = points.reduce(0) { $0 + $1.x } / count
        let y = points.reduce(0) { $0 + $1.y } / count
        return CGPoint(x: x, y: y)
    }
}
