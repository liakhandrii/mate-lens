import UIKit
import MLKit
import Combine

class TextRecognitionService: ObservableObject {
    @Published var textData: [WordData] = []
    @Published var isProcessing = false
    @Published var error: String?
    
    func recognizeText(in image: UIImage, completion: @escaping (Bool) -> Void) {
        self.error = nil
        
        guard let normalizedImage = Utilities.normalize(image: image) else {
            finish(success: false, errorMessage: "Failed to normalize image", completion: completion)
            return
        }
        
        let visionImage = VisionImage(image: normalizedImage)
        visionImage.orientation = .up
        
        let textRecognizer = TextRecognizer.textRecognizer(options: TextRecognizerOptions())
        
        textRecognizer.process(visionImage) { [weak self] result, err in
            guard let self = self else { return }
            
            if let err = err {
                self.finish(success: false, errorMessage: err.localizedDescription, completion: completion)
                return
            }
            
            guard let result = result else {
                self.finish(success: false, errorMessage: "No text found in image", completion: completion)
                return
            }
            
            Task {
                var collectedLines: [WordData] = []
                var textsToTranslate: [String] = []
                
                for block in result.blocks {
                    for line in block.lines {
                        let optimized = Utilities.optimizeText(line.text)
                        textsToTranslate.append(optimized)
                    }
                }
                
                let translations = await TranslationService.shared.translateBatch(
                    texts: textsToTranslate,
                    from: "en",
                    to: "uk"
                )
                
                var index = 0
                for block in result.blocks {
                    for line in block.lines {
                        let optimized = Utilities.optimizeText(line.text)
                        let translated = translations[index]
                        
                        let corners = line.cornerPoints.map { $0.cgPointValue }
                        if corners.isEmpty || corners.count != 4 {
                            print("Warning: Line '\(optimized)' has invalid corner points (count: \(corners.count))")
                        }
                        
                        let word = WordData(
                            text: optimized,
                            translatedText: translated,
                            frame: line.frame,
                            cornerPoints: corners.isEmpty ? nil : corners
                        )
                        collectedLines.append(word)
                        
                        print("Found line: '\(optimized)' -> '\(translated ?? "no translation")'")
                        print("  Frame: \(line.frame)")
                        print("  Corners: \(corners.isEmpty ? "empty" : corners.description)")
                        
                        index += 1
                    }
                }
                
                print("Total lines found: \(collectedLines.count)")
                
                self.finish(success: true, lines: collectedLines, completion: completion)
            }
        }
    }
    
    // MARK: - Clear
    func clearData() {
        textData = []
        error = nil
        isProcessing = false
    }
    
    // MARK: - Centralized finish helper
    private func finish(success: Bool,
                        lines: [WordData]? = nil,
                        errorMessage: String? = nil,
                        completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            if let errorMessage = errorMessage {
                self.error = errorMessage
            }
            if let lines = lines, success {
                self.textData = lines
            }
            self.isProcessing = false
            completion(success)
        }
    }
}
