import UIKit
import MLKit
import Combine

class TextRecognitionService: ObservableObject {
    @Published var textData: [WordData] = []
    @Published var isProcessing = false
    @Published var error: String?
    
    // MARK: - Розпізнавання тексту на зображенні
    func recognizeText(in image: UIImage, completion: @escaping (Bool) -> Void) {
        // Очищаємо тільки помилку, дані вже очищені в capturePhotoAction
        self.error = nil
        
        guard let normalizedImage = Utilities.normalize(image: image) else {
            print("Failed to normalize image")
            DispatchQueue.main.async {
                self.error = "Failed to normalize image"
                self.isProcessing = false
                completion(false)
            }
            return
        }
        
        let visionImage = VisionImage(image: normalizedImage)
        visionImage.orientation = .up
        
        let textRecognizer = TextRecognizer.textRecognizer(options: TextRecognizerOptions())

        textRecognizer.process(visionImage) { [weak self] result, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Text recognition error: \(error)")
                DispatchQueue.main.async {
                    self.error = error.localizedDescription
                    self.isProcessing = false
                    completion(false)
                }
                return
            }

            guard let result = result else {
                print("No text found in image")
                DispatchQueue.main.async {
                    self.error = "No text found in image"
                    self.isProcessing = false
                    completion(false)
                }
                return
            }

            // Обробляємо результати асинхронно для перекладу
            Task {
                var lineItems: [WordData] = []
                var textsToTranslate: [String] = []
                
                // Спочатку збираємо всі тексти
                for block in result.blocks {
                    for line in block.lines {
                        let optimizedText = Utilities.optimizeText(line.text)
                        textsToTranslate.append(optimizedText)
                    }
                }
                
                // Перекладаємо всі тексти
                let translations = await TranslationService.shared.translateBatch(
                    texts: textsToTranslate,
                    from: "en",
                    to: "uk"
                )
                
                // Створюємо WordData з перекладами
                var textIndex = 0
                for block in result.blocks {
                    for line in block.lines {
                        let optimizedText = Utilities.optimizeText(line.text)
                        let translatedText = translations[textIndex]
                        
                        // Отримуємо кутові точки тексту
                        let corners = line.cornerPoints.map { $0.cgPointValue }
                        
                        // Перевіряємо валідність кутових точок
                        if corners.isEmpty || corners.count != 4 {
                            print("Warning: Line '\(optimizedText)' has invalid corner points (count: \(corners.count))")
                        }
                        
                        let lineItem = WordData(
                            text: optimizedText,
                            translatedText: translatedText,
                            frame: line.frame,
                            cornerPoints: corners.isEmpty ? nil : corners  // Якщо немає точок - передаємо nil
                        )
                        lineItems.append(lineItem)
                        print("Found line: '\(optimizedText)' -> '\(translatedText ?? "no translation")'")
                        print("  Frame: \(line.frame)")
                        print("  Corners: \(corners.isEmpty ? "empty" : corners.description)")
                        
                        textIndex += 1
                    }
                }
                
                print("Total lines found: \(lineItems.count)")

                DispatchQueue.main.async {
                    self.textData = lineItems
                    self.isProcessing = false
                    completion(true)
                }
            }
        }
    }
    
    // Метод для очищення даних
    func clearData() {
        textData = []
        error = nil
        isProcessing = false
    }
}
