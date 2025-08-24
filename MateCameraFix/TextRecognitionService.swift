import UIKit
import MLKit
import Combine
import NaturalLanguage

class TextRecognitionService: ObservableObject {
    @Published var textData: [WordData] = []
    @Published var isProcessing = false
    @Published var error: String?

    private let languageRecognizer = NLLanguageRecognizer()

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

                let allLines = result.blocks.flatMap { $0.lines }
                var translations = Array<String?>(repeating: nil, count: allLines.count)
                
                var linesToTranslateByLang: [String: [(index: Int, text: String)]] = [:]
                
                for (index, line) in allLines.enumerated() {
                    let text = line.text
                    self.languageRecognizer.processString(text)
                    
                    // Визначаємо мову рядка
                    guard let langCode = self.languageRecognizer.dominantLanguage?.rawValue else {
                        continue
                    }
                    
                    // Не перекладаємо український текст
                    if langCode != "uk" {
                        linesToTranslateByLang[langCode, default: []].append((index, text))
                    } else {
                        // Якщо текст український, його "переклад" - це він сам
                        translations[index] = text
                    }
                }
                
                // Робимо пакетні запити на переклад для кожної мови
                for (lang, linesWithIndices) in linesToTranslateByLang {
                    let texts = linesWithIndices.map { $0.text }
                    let translatedResults = await TranslationService.shared.translateBatch(
                        texts: texts, from: lang, to: "uk"
                    )
                    
                    for (resultIndex, translatedText) in translatedResults.enumerated() {
                        let originalIndex = linesWithIndices[resultIndex].index
                        translations[originalIndex] = translatedText
                    }
                }
                
                var collectedLines: [WordData] = []
                for (index, line) in allLines.enumerated() {
                    let originalText = line.text
                    let translatedText = translations[index]
                    
                    var finalTranslatedText: String?
                    if let translation = translatedText, translation != originalText {
                        finalTranslatedText = translation
                    }
                    
                    let corners = line.cornerPoints.map { $0.cgPointValue }
                    let normCorners = (corners.count == 4) ? self.normalizedQuad(corners) : nil
                    
                    let wordData = WordData(
                        text: originalText,
                        translatedText: finalTranslatedText,
                        frame: line.frame,
                        cornerPoints: normCorners,
                        originalImage: normalizedImage
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

        var topLeftIndex = 0
        var minSum = CGFloat.greatestFiniteMagnitude
        
        for (index, point) in points.enumerated() {
            let sum = point.x + point.y
            if sum < minSum {
                minSum = sum
                topLeftIndex = index
            }
        }
        
        let rotatedPoints = Array(points[topLeftIndex...] + points[..<topLeftIndex])
        
        return rotatedPoints
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
