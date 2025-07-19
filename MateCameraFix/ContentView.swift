import SwiftUI
import MLKit

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @State private var showOverlay = false
    @State private var recognizedText: [String] = []  // тут зберігаємо текст який знайшов ML Kit
    
    // тут всі розміри і відступи щоб не захаращувати код
    private enum Layout {
        static let captureButtonSize: CGFloat = 70
        static let captureButtonStrokeWidth: CGFloat = 2
        static let captureButtonStrokeOpacity: Double = 0.8
        static let captureButtonBottomPadding: CGFloat = 50
        
        static let previewImageSize: CGFloat = 100
        static let previewImageBorderWidth: CGFloat = 2
        static let previewImagePadding: CGFloat = 16
        
        static let captureDelay: TimeInterval = 1.5
        
        static let angleThreshold: Double = 5
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                CameraView(cameraManager: cameraManager)
                    .ignoresSafeArea()
                
                VStack {
                    Spacer()
                    
                    Button(action: {
                        cameraManager.capturePhoto()
                        
                        // затримка і потім шукаємо текст на фото
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
                
                // маленьке фото в кутку
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
                
                // невидимий лінк який веде на екран з текстом поверх фото
                NavigationLink(
                    destination: RealTextOverlayView(
                        image: cameraManager.capturedImage,
                        textList: recognizedText
                    ),
                    isActive: $showOverlay
                ) {
                    EmptyView()
                }
                .hidden()
            }
        }
    }
    
    // функція яка шукає текст на фото
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

            // збираємо всі рядки тексту в масив
            var textLines: [String] = []
            for block in result.blocks {
                for line in block.lines {
                    textLines.append(line.text)
                    print("Found text: \(line.text)")
                }
            }
            
            print("Total lines found: \(textLines.count)") // скільки всього рядків знайшли

            // оновлюємо UI в головному потоці
            DispatchQueue.main.async {
                self.recognizedText = textLines
                self.showOverlay = true
            }
        }
    }
}

// функція яка фіксить орієнтацію фото (бо камера може знімати під різними кутами)
func normalize(image: UIImage) -> UIImage? {
    guard image.imageOrientation != .up else { return image }

    UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
    defer { UIGraphicsEndImageContext() }
    
    image.draw(in: CGRect(origin: .zero, size: image.size))
    
    return UIGraphicsGetImageFromCurrentImageContext()
}

// екран де показуємо фото з текстом поверх
struct RealTextOverlayView: View {
    let image: UIImage?
    let textList: [String]

    var body: some View {
        ZStack {
            // спочатку показуємо саме фото
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .ignoresSafeArea()

                ForEach(Array(textList.enumerated()), id: \.offset) { index, text in
                    Text(text)
                        .font(.title2)
                        .foregroundColor(.red)
                        .background(Color.white.opacity(0.8))
                        .padding(4)
                        .position(
                            x: CGFloat(100 + (index * 50) % 200),
                            y: CGFloat(200 + (index * 80) % 300)
                        )
                }
            } else {
                Text("Фото не зроблено")
            }
        }
        .navigationTitle("Real Text Overlay")
        .navigationBarTitleDisplayMode(.inline)
    }
}


/*
  
 let allElements = result.blocks.flatMap { $0.lines.flatMap { $0.elements } }
 let confidence = allElements.isEmpty ? 0.0 : allElements.reduce(0.0) { $0 + $1.confidence } / Float(allElements.count)
 print("Confidence: \(Int(confidence * 100))%")
 */

/*
  
 var text = result.text
 
  цифри vs букви
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
