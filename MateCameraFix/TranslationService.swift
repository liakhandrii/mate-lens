import Foundation

class TranslationService {
    static let shared = TranslationService()
    
    private init() {}
    
    // Проста заглушка для перекладу - просто повертає той самий текст
    func translate(text: String, from: String, to: String) async -> String? {
        // Заглушка - просто повертаємо оригінальний текст
        return text
    }
    
    func translateBatch(texts: [String], from: String, to: String) async -> [String?] {
        return texts.map { $0 }
    }
}
