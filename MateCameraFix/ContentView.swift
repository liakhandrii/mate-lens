import SwiftUI
import MLKit

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    
    var body: some View {
        ZStack {
            CameraView(cameraManager: cameraManager)
                .ignoresSafeArea()
            
            VStack {
                Spacer()
                
                Button(action: {
                    cameraManager.capturePhoto()
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if let image = cameraManager.capturedImage {
                            recognizeText(in: image)
                        }
                    }
                }) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 70, height: 70)
                        .overlay(
                            Circle()
                                .stroke(Color.black.opacity(0.8), lineWidth: 2)
                        )
                }
                .padding(.bottom, 50)
            }
            
            // Попередній перегляд останнього фото
            if let capturedImage = cameraManager.capturedImage {
                VStack {
                    HStack {
                        Spacer()
                        Image(uiImage: capturedImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 100, height: 100)
                            .border(Color.white, width: 2)
                            .padding()
                    }
                    Spacer()
                }
            }
        }
    }
    
    // Розпізнавання тексту з виявленням кута
    func recognizeText(in image: UIImage) {
        let visionImage = VisionImage(image: image)
        visionImage.orientation = image.imageOrientation // Важливо для точності
        
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
            
            print("=== FOUND TEXT WITH CORNERS ===")
            print("Повний текст: \(result.text)")
            
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
            
            // Дивимось на кожен рядок тексту
            for (i, block) in result.blocks.enumerated() {
                for (j, line) in block.lines.enumerated() {
                    print("\nRow \(i)-\(j): '\(line.text)'")
                    print("Position: x=\(Int(line.frame.minX)), y=\(Int(line.frame.minY))")
                    
                    // Перевіряємо чи є кутові точки (для розрахунку кута)
                    let cornerPoints = line.cornerPoints
                    if !cornerPoints.isEmpty {
                        print("Text has corners: \(cornerPoints.count)")
                        
                        // Розраховуємо кут якщо є принаймні 2 точки
                        if cornerPoints.count >= 2 {
                            let point1 = cornerPoints[0].cgPointValue
                            let point2 = cornerPoints[1].cgPointValue
                            
                            let deltaX = point2.x - point1.x
                            let deltaY = point2.y - point1.y
                            // Трохи математики, яка має дати нам кут на основі кутових координат
                            let angle = atan2(deltaY, deltaX) * 180 / .pi
                            
                            print("Angle: \(Int(angle)) degrees")
                            
                            if abs(angle) < 5 {
                                print("Text is straight")
                            } else {
                                print("Text is tilted!")
                            }
                        }
                    } else {
                        print("Can't detect corners")
                    }
                }
            }
            print("=== END ===")
        }
    }
}
