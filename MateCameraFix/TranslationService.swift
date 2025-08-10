import Foundation

class TranslationService {
    static let shared = TranslationService()
    
    private init() {}
    
    func translate(text: String, from: String, to: String) async -> String? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = TranslationManager.shared.translateFromText(from, to: to, text: text, autocorrect: true)
                continuation.resume(returning: result?.translated)
            }
        }
    }
    
    func translateBatch(texts: [String], from: String, to: String) async -> [String?] {
        await withTaskGroup(of: (Int, String?).self) { group in
            for (index, text) in texts.enumerated() {
                group.addTask {
                    let result = await self.translate(text: text, from: from, to: to)
                    return (index, result)
                }
            }
            
            var results: [String?] = Array(repeating: nil, count: texts.count)
            for await (index, result) in group {
                results[index] = result
            }
            return results
        }
    }
}
