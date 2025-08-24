import Foundation

final class TextTransformCache {
    private var cache: [String: TransformedTextItem] = [:]
    
    func getTransformed(for item: WordData, key: String) -> TransformedTextItem? {
        return cache[key]
    }
    
    func store(_ transformed: TransformedTextItem, key: String) {
        cache[key] = transformed
    }
}
