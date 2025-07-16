import SwiftUI
import MLKit

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    
    // Константи для layout
    private enum Layout {
        static let captureButtonSize: CGFloat = 70
        static let captureButtonStrokeWidth: CGFloat = 2
        static let captureButtonStrokeOpacity: Double = 0.8
        static let captureButtonBottomPadding: CGFloat = 50
        
        static let previewImageSize: CGFloat = 100
        static let previewImageBorderWidth: CGFloat = 2
        static let previewImagePadding: CGFloat = 16
        
        static let captureDelay: TimeInterval = 0.5
        
        static let angleThreshold: Double = 5
    }
    
    var body: some View {
        ZStack {
            CameraView(cameraManager: cameraManager)
                .ignoresSafeArea()
            
            VStack {
                Spacer()
                
                Button(action: {
                    cameraManager.capturePhoto()
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + Layout.captureDelay) {
                        if let image = cameraManager.capturedImage {
                            recognizeText(in: image)
                        }
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
            
            // Попередній перегляд останнього фото
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
        }
    }
    
    func recognizeText(in image: UIImage) {
        guard let normalizedImage = normalize(image: image) else {
            print("Не вдалося нормалізувати зображення.")
            return
        }
        
        let visionImage = VisionImage(image: normalizedImage)
        visionImage.orientation = .up

        // Створюємо опції для розпізнавача тексту
        let options = TextRecognizerOptions()
        let textRecognizer = TextRecognizer.textRecognizer(options: options)
        
        textRecognizer.process(visionImage) { result, error in
            if let error = error {
                print("Помилка розпізнавання: \(error.localizedDescription)")
                return
            }
            
            guard let result = result, !result.text.isEmpty else {
                print("Текст не знайдено.")
                return
            }
            
            print("=== ЗНАЙДЕНО ТЕКСТ З КУТАМИ ===")
            print("Повний текст: \(result.text)")
            
            // Дивимось на кожен рядок тексту
            for (i, block) in result.blocks.enumerated() {
                for (j, line) in block.lines.enumerated() {
                    print("\nРядок \(i)-\(j): '\(line.text)'")
                    print("Позиція: x=\(Int(line.frame.minX)), y=\(Int(line.frame.minY))")
                    
                    let cornerPoints = line.cornerPoints
                    if !cornerPoints.isEmpty, cornerPoints.count >= 2 {
                        
                        let point1 = cornerPoints[0].cgPointValue
                        let point2 = cornerPoints[1].cgPointValue
                        
                        let deltaX = point2.x - point1.x
                        let deltaY = point2.y - point1.y
                        
                        // Ця математика тепер дасть правильний кут
                        let angle = atan2(deltaY, deltaX) * 180 / .pi
                        
                        print("Кут нахилу: \(Int(angle))°")
                        
                        if abs(angle) < Layout.angleThreshold {
                            print("Статус: Текст рівний")
                        } else {
                            print("Статус: Текст нахилений!")
                        }
                    } else {
                        print("Неможливо визначити кутові точки.")
                    }
                }
            }
            print("=== КІНЕЦЬ ===")
        }
    }
}

func normalize(image: UIImage) -> UIImage? {
    guard image.imageOrientation != .up else { return image }

    UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
    defer { UIGraphicsEndImageContext() }
    
    image.draw(in: CGRect(origin: .zero, size: image.size))
    
    return UIGraphicsGetImageFromCurrentImageContext()
}


/*
  Confidence
 let allElements = result.blocks.flatMap { $0.lines.flatMap { $0.elements } }
 let confidence = allElements.isEmpty ? 0.0 : allElements.reduce(0.0) { $0 + $1.confidence } / Float(allElements.count)
 print("Confidence: \(Int(confidence * 100))%")
 */

/*
  Fix common OCR mistakes
 var text = result.text
 
  Numbers vs letters
 text = text.replacingOccurrences(of: "0", with: "O")
 text = text.replacingOccurrences(of: "1", with: "l")
 text = text.replacingOccurrences(of: "5", with: "S")
 text = text.replacingOccurrences(of: "8", with: "B")
 
  Common combinations
 text = text.replacingOccurrences(of: "rn", with: "m")
 text = text.replacingOccurrences(of: "cl", with: "d")
 
  English words
 text = text.replacingOccurrences(of: "teh", with: "the")
 text = text.replacingOccurrences(of: "adn", with: "and")
 
 print("Fixed text: \(text)")
 */
