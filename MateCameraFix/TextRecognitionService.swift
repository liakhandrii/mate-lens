import UIKit
import MLKit
import Combine

class TextRecognitionService: ObservableObject {
    @Published var textData: [WordData] = []
    @Published var isProcessing = false
    @Published var error: String?

    private enum Constants {
        static let minTextWidth: CGFloat = 15
        static let minTextHeight: CGFloat = 8
        static let minTextLength = 1
        static let maxTextLength = 200
        static let maxSpecialCharacterRatio = 0.5
        static let characterRepetitionThreshold = 0.7
    }
    
    func recognizeText(in image: UIImage, completion: @escaping (Bool) -> Void) {
        self.error = nil
        
        guard let normalizedImage = Utilities.normalize(image: image) else {
            finish(success: false, errorMessage: "Failed to normalize image", completion: completion)
            return
        }
        
        guard let preprocessedImage = Utilities.preprocessForOCR(image: normalizedImage) else {
            finish(success: false, errorMessage: "Failed to preprocess image", completion: completion)
            return
        }
        
        let visionImage = VisionImage(image: preprocessedImage)
        visionImage.orientation = .up
        
        let textRecognizer = TextRecognizer.textRecognizer(options: TextRecognizerOptions())
        
        textRecognizer.process(visionImage) { [weak self] result, err in
            guard let self = self else { return }
            
            if let err = err {
                self.finish(success: false, errorMessage: err.localizedDescription, completion: completion)
                return
            }
            
            guard let result = result, !result.blocks.isEmpty else {
                self.finish(success: false, errorMessage: "No text found in image", completion: completion)
                return
            }
            
            Task { [weak self] in
                guard let self = self else { return }

                let linesForTranslation = result.blocks.flatMap { $0.lines }
                let textsToTranslate = linesForTranslation.map { $0.text }
                
                let translations = await TranslationService.shared.translateBatch(
                    texts: textsToTranslate,
                    from: "auto",
                    to: "uk"
                )
                
                var collectedLines: [WordData] = []
                for (index, line) in linesForTranslation.enumerated() {
                    let originalText = line.text
                    let translatedText = index < translations.count ? translations[index] : nil
                    
                    let corners = line.cornerPoints.map { $0.cgPointValue }
                    let normCorners = (corners.count == 4) ? self.normalizedQuad(corners) : nil
                    
                    let wordData = WordData(
                        text: originalText,
                        translatedText: translatedText,
                        frame: line.frame,
                        cornerPoints: normCorners
                    )
                    collectedLines.append(wordData)
                }
                
                let filteredLines = self.filterValidTexts(collectedLines)
                
                self.finish(success: true, lines: filteredLines, completion: completion)
            }
        }
    }
    
    // MARK: - Нормалізація порядку cornerPoints
    private func normalizedQuad(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count == 4 else { return points }
        
        // Знаходимо центр
        let center = CGPoint(
            x: points.map { $0.x }.reduce(0, +) / 4.0,
            y: points.map { $0.y }.reduce(0, +) / 4.0
        )
        
        // Сортуємо по куту
        var sortedPoints = points.sorted { p1, p2 in
            let angle1 = atan2(p1.y - center.y, p1.x - center.x)
            let angle2 = atan2(p2.y - center.y, p2.x - center.x)
            return angle1 < angle2
        }
        
        // Знаходимо верхній лівий кут
        var minSum = CGFloat.greatestFiniteMagnitude
        var topLeftIndex = 0
        for (index, point) in sortedPoints.enumerated() {
            let sum = point.x + point.y  // top-left має мінімальну суму
            if sum < minSum {
                minSum = sum
                topLeftIndex = index
            }
        }
        
        // Переставляємо масив так, щоб top-left була ПЕРШОЮ
        if topLeftIndex != 0 {
            sortedPoints = Array(sortedPoints[topLeftIndex...] + sortedPoints[..<topLeftIndex])
        }
        
        return sortedPoints
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

    // MARK: - Фільтрація шуму
    private func filterValidTexts(_ items: [WordData]) -> [WordData] {
        return items.filter { item in
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard item.frame.width > Constants.minTextWidth && item.frame.height > Constants.minTextHeight else { return false }
            guard text.count > Constants.minTextLength else { return false }
            
            let contentType = Utilities.detectContentType(for: text)
            let hasLetters = text.contains { $0.isLetter }
            
            // Якщо немає літер — залишаємо тільки числа/ціни/дати
            if !hasLetters && !(contentType == .number || contentType == .price || contentType == .date) {
                return false
            }
            
            // Для числових типів і дат ігноруємо роздільники та валютні символи.
            let allowedCurrency: Set<Character> = ["€", "$", "£", "¥", "₴"]
            let allowedPunct: Set<Character> = [".", ",", ":", "/", "-", " "]
            let specials = text.filter { !$0.isLetter && !$0.isNumber && !$0.isWhitespace }
            let effectiveSpecialsCount: Int
            if contentType == .number || contentType == .price || contentType == .date {
                effectiveSpecialsCount = specials.filter { !(allowedCurrency.contains($0) || allowedPunct.contains($0)) }.count
            } else {
                effectiveSpecialsCount = specials.count
            }
            if Double(effectiveSpecialsCount) > Double(text.count) * Constants.maxSpecialCharacterRatio {
                return false
            }
            
            guard text.count < Constants.maxTextLength else { return false }
            guard !isSuspiciousSymbolsRow(text, contentType: contentType) else { return false }
            return true
        }
    }
    
    private func isSuspiciousSymbolsRow(_ text: String, contentType: ContentType) -> Bool {
        // повтор одного символа (ігноруємо пробіли)
        let filtered = text.filter { !$0.isWhitespace }
        let maxCharCount = Dictionary(filtered.map { ($0, 1) }, uniquingKeysWith: +).values.max() ?? 0
        if !filtered.isEmpty && Double(maxCharCount) > Double(filtered.count) * Constants.characterRepetitionThreshold { return true }
        
        // тільки спецсимволи
        let lettersAndDigits = filtered.filter { $0.isLetter || $0.isNumber }
        if lettersAndDigits.isEmpty { return true }
        
        // підозріла кількість спецсимволів (для чисел/дат/цін рахується після фільтра дозволених символів)
        let allowedCurrency: Set<Character> = ["€", "$", "£", "¥", "₴"]
        let allowedPunct: Set<Character> = [".", ",", ":", "/", "-", " "]
        let specials = filtered.filter { !$0.isLetter && !$0.isNumber }
        let effectiveSpecials = (contentType == .number || contentType == .price || contentType == .date)
            ? specials.filter { !(allowedCurrency.contains($0) || allowedPunct.contains($0)) }
            : specials
        if effectiveSpecials.count > (filtered.count - effectiveSpecials.count) { return true }
        
        // тільки рамкові символи (ASCII/box-drawing) — найчастіше шум
        let frameChars: Set<Character> = ["─", "═", "━", "│", "║", "╔", "╗", "╝", "╚", "▄", "▀"]
        if !filtered.isEmpty && Set(filtered).isSubset(of: frameChars) { return true }
        
        return false
    }
}
