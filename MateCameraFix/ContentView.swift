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
                CameraView(cameraManager: cameraManager)
                    .ignoresSafeArea()
                
                VStack {
                    Spacer()
                    
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
                    let lineItem = WordData(
                        text: line.text,
                        frame: line.frame
                    )
                    lineItems.append(lineItem)
                    print("Found line: \(line.text) at position: (\(line.frame.midX), \(line.frame.midY))")
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

// Функція фіксації орієнтації фото
func normalize(image: UIImage) -> UIImage? {
    guard image.imageOrientation != .up else { return image }

    UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
    defer { UIGraphicsEndImageContext() }
    
    image.draw(in: CGRect(origin: .zero, size: image.size))
    
    return UIGraphicsGetImageFromCurrentImageContext()
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

struct PositionedTextOverlayView: View {
    let image: UIImage?
    let textData: [WordData]
    
    // Функція для обчислення масштабу та зміщень
    func calculateScaleAndOffsets(imageSize: CGSize, screenSize: CGSize) -> (scale: CGFloat, offsetX: CGFloat, offsetY: CGFloat) {
        let imageAspectRatio = imageSize.width / imageSize.height
        let screenAspectRatio = screenSize.width / screenSize.height
        
        if imageAspectRatio > screenAspectRatio {
            let scale = screenSize.width / imageSize.width
            return (scale, 0, (screenSize.height - imageSize.height * scale) / 2)
        } else {
            let scale = screenSize.height / imageSize.height
            return (scale, (screenSize.width - imageSize.width * scale) / 2, 0)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                    
                    let transform = calculateScaleAndOffsets(
                        imageSize: image.size,
                        screenSize: geometry.size
                    )

                    // Відображення тексту з врахуванням масштабу та розмірів
                    ForEach(Array(textData.enumerated()), id: \.offset) { index, item in
                        ZStack {
                            // Червона рамка навколо тексту
                            Rectangle()
                                .stroke(Color.red, lineWidth: 2)
                                .frame(width: item.frame.width * transform.scale, height: item.frame.height * transform.scale)
                                .position(
                                    x: item.frame.midX * transform.scale + transform.offsetX,
                                    y: item.frame.midY * transform.scale + transform.offsetY
                                )
                            
                            // Текст з білим фоном
                            Text(item.text)
                                .font(.system(size: item.frame.height * transform.scale * 0.8)) // Масштабування шрифту з коефіцієнтом
                                .foregroundColor(.black) // Чорний текст
                                .background(Color.white) // Суцільний білий фон
                                .padding(4) // Відступи
                                .cornerRadius(2) // Закруглені кути
                                .position(
                                    x: item.frame.midX * transform.scale + transform.offsetX,
                                    y: item.frame.midY * transform.scale + transform.offsetY
                                )
                        }
                    }
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

struct WordData {
    let text: String
    let frame: CGRect
}

/*
  
 let allElements = result.blocks.flatMap { $0.lines.flatMap { $0.elements } }
 let confidence = allElements.isEmpty ? 0.0 : allElements.reduce(0.0) { $0 + $1.confidence } / Float(allElements.count)
 print("Confidence: \(Int(confidence * 100))%")
 */

/*
  
 var text = result.text
 
 // цифри vs букви
 text = text.replacingOccurrences(of: "0", with: "O")
 text = text.replacingOccurrences(of: "1", with: "l")
 text = text.replacingOccurrences(of: "5", with: "S")
 text = text.replacingOccurrences(of: "8", with: "B")
 
 text = text.replacingOccurrences(of: "rn", with: "m")
 text = text.replacingOccurrences(of: "cl", with: "d")
 
 text = text.replacingOccurrences(of: "teh", with: "the")
 text = text.replacingOccurrences(of: "adn", with: "and")
 
 print("Fixed text: \(text)")
 */
