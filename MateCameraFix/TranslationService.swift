import Foundation

class TranslationService {
    static let shared = TranslationService()
    
    private init() {}
    
    func translate(text: String, from: String, to: String) async -> String? {
        let startTime = CFAbsoluteTimeGetCurrent()
        Analytics.trackEvent(name: "translation_requested", value: "\(from)_to_\(to)")
        
        let result = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let translation = TranslationManager.shared.translateFromText(from, to: to, text: text, autocorrect: true)
                continuation.resume(returning: translation?.translated)
            }
        }
        
        let duration = String(format: "%.3f", CFAbsoluteTimeGetCurrent() - startTime)
        
        if result != nil {
            Analytics.trackEvent(name: "translation_success", value: duration)
        } else {
            Analytics.trackEvent(name: "translation_failed", value: duration)
        }
        
        return result
    }
    
    func translateBatch(texts: [String], from: String, to: String) async -> [String?] {
        if texts.isEmpty {
            return []
        }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        Analytics.trackEvent(name: "batch_translation_requested", value: "\(texts.count)")
        
        // Try batch translation first
        let batchResults = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = TranslationManager.shared.translateFromTextBatch(from, to: to, texts: texts, autocorrect: true)
                continuation.resume(returning: result)
            }
        }
        
        let results: [String?]
        if let batchTranslations = batchResults {
            // Batch translation succeeded
            results = batchTranslations.map { $0?.translated }
        } else {
            // Fallback to concurrent individual translations
            results = await withTaskGroup(of: (Int, String?).self) { group in
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
        
        let duration = String(format: "%.3f", CFAbsoluteTimeGetCurrent() - startTime)
        let successCount = results.compactMap { $0 }.count
        Analytics.trackEvent(name: "batch_translation_completed", value: duration)
        Analytics.trackEvent(name: "batch_translation_success_rate", value: "\(successCount)_of_\(texts.count)")
        
        return results
    }
}
