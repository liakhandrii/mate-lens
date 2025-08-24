import UIKit
import CoreGraphics
import Accelerate

struct ColorAnalyzer {
    
    // MARK: - Configuration
    private enum Config {
        static let thumbnailMaxDimension: CGFloat = 150 // Збільшено для кращої точності
        static let edgeInsetRatio: CGFloat = 0.05 // Зменшено відступ для точнішого захоплення
        static let minContrastRatio: CGFloat = 4.5 // WCAG AAA standard для кращої читабельності
        static let kMeansIterations = 20
        static let adaptiveClusters = 5 // Більше кластерів для точнішого аналізу
        static let colorQuantizationLevel = 16 // Для гістограми
        static let edgeSampleDensity = 3 // Щільність вибірки країв
        static let minSaturationForColor: CGFloat = 0.15 // Мінімальна насиченість для кольорового тексту
        static let dominanceThreshold: CGFloat = 0.6 // Поріг домінування кольору
    }
    
    // MARK: - Cache з LRU
    private static var colorCache = NSCache<NSString, ColorResult>()
    private static let cacheQueue = DispatchQueue(label: "coloranalyzer.cache", attributes: .concurrent)
    
    static func setupCache() {
        colorCache.countLimit = 100 // Максимум 100 елементів
        colorCache.totalCostLimit = 50 * 1024 * 1024 // 50MB
    }
    
    private class ColorResult: NSObject {
        let textColor: UIColor
        let backgroundColor: UIColor
        let confidence: CGFloat
        let colorScheme: ColorScheme
        
        init(textColor: UIColor, backgroundColor: UIColor, confidence: CGFloat = 1.0, colorScheme: ColorScheme = .standard) {
            self.textColor = textColor
            self.backgroundColor = backgroundColor
            self.confidence = confidence
            self.colorScheme = colorScheme
        }
    }
    
    // MARK: - Color Scheme Detection
    enum ColorScheme {
        case standard       // Звичайний текст
        case inverted      // Інвертований (світлий на темному)
        case colorful      // Кольоровий текст/фон
        case gradient      // Градієнтний фон
        case complex       // Складний паттерн
    }
    
    // MARK: - Public Methods
    static func analyzeColors(from item: WordData) -> (text: UIColor, background: UIColor) {
        guard let originalImage = item.originalImage, let cgImage = originalImage.cgImage else {
            return (.black, .white)
        }
        
        // Унікальний ключ для кешу з додатковими параметрами
        let imageHash = originalImage.hashValue
        let cacheKey = "\(item.text)_\(item.frame.hashValue)_\(imageHash)" as NSString
        
        // Перевіряємо кеш
        var cachedResult: ColorResult?
        cacheQueue.sync {
            cachedResult = colorCache.object(forKey: cacheKey)
        }
        
        if let cached = cachedResult {
            return (cached.textColor, cached.backgroundColor)
        }
        
        // Екстракт регіону з адаптивним відступом
        let region = item.frame
        let insetAmount = calculateAdaptiveInset(for: region)
        let sampleRect = region.insetBy(dx: insetAmount, dy: insetAmount)
        
        guard sampleRect.width > 0, sampleRect.height > 0,
              let croppedCGImage = cgImage.cropping(to: sampleRect) else {
            return (.black, .white)
        }
        
        // Аналіз з покращеними стратегіями
        let result = performAdvancedAnalysis(from: croppedCGImage, originalText: item.text)
        
        // Зберігаємо в кеш
        let colorResult = ColorResult(
            textColor: result.text,
            backgroundColor: result.background,
            confidence: result.confidence,
            colorScheme: result.scheme
        )
        
        cacheQueue.async(flags: .barrier) {
            colorCache.setObject(colorResult, forKey: cacheKey, cost: 1)
        }
        
        return (result.text, result.background)
    }
    
    // MARK: - Advanced Analysis
    private static func performAdvancedAnalysis(from image: CGImage, originalText: String) ->
        (text: UIColor, background: UIColor, confidence: CGFloat, scheme: ColorScheme) {
        
        // 1. Швидкий аналіз домінантних кольорів
        let dominantColors = getEnhancedDominantColors(from: image)
        
        // 2. Аналіз розподілу кольорів
        let distribution = analyzeColorDistribution(from: image)
        
        // 3. Визначення схеми кольорів
        let colorScheme = detectColorScheme(distribution: distribution, dominantColors: dominantColors)
        
        // 4. Інтелектуальний вибір кольорів на основі схеми
        let colors = selectOptimalColors(
            dominantColors: dominantColors,
            distribution: distribution,
            scheme: colorScheme,
            textLength: originalText.count
        )
        
        return colors
    }
    
    // MARK: - Enhanced Dominant Colors
    private static func getEnhancedDominantColors(from image: CGImage) -> [(color: UIColor, weight: CGFloat, position: ColorPosition)] {
        // Використовуємо покращений K-Means++ з позиційною інформацією
        let clusters = performEnhancedKMeans(from: image, k: Config.adaptiveClusters)
        
        // Аналізуємо позицію кожного кластера
        return clusters.map { cluster in
            let position = determineColorPosition(cluster: cluster, in: image)
            return (cluster.color, cluster.weight, position)
        }
    }
    
    // MARK: - Color Position
    enum ColorPosition {
        case center
        case edge
        case scattered
        case uniform
    }
    
    // MARK: - Enhanced K-Means++
    private static func performEnhancedKMeans(from image: CGImage, k: Int) -> [(color: UIColor, weight: CGFloat, pixels: [PixelData])] {
        // Зменшуємо зображення для швидкості
        let maxDimension = Config.thumbnailMaxDimension
        let thumbnailSize = calculateThumbnailSize(for: image, maxDimension: maxDimension)
        
        guard let thumbnail = image.resized(to: thumbnailSize),
              let pixelData = extractPixelData(from: thumbnail) else {
            return []
        }
        
        // LAB color space для кращої кластеризації
        let labPixels = pixelData.map { pixel in
            LABColor(from: pixel.rgb)
        }
        
        // K-Means++ initialization
        var centroids = initializeKMeansPlusPlus(pixels: labPixels, k: k)
        var clusters = Array(repeating: [LABColor](), count: k)
        
        // Iterations with early stopping
        for _ in 0..<Config.kMeansIterations {
            // Clear clusters
            clusters = Array(repeating: [LABColor](), count: k)
            
            // Assign pixels to nearest centroid
            for pixel in labPixels {
                let nearestIndex = findNearestCentroid(pixel: pixel, centroids: centroids)
                clusters[nearestIndex].append(pixel)
            }
            
            // Update centroids
            var newCentroids: [LABColor] = []
            for cluster in clusters {
                if !cluster.isEmpty {
                    newCentroids.append(averageLABColor(cluster))
                } else {
                    // Reinitialize empty cluster
                    newCentroids.append(labPixels.randomElement()!)
                }
            }
            
            // Check convergence
            if hasConverged(old: centroids, new: newCentroids) {
                centroids = newCentroids
                break
            }
            
            centroids = newCentroids
        }
        
        // Convert back to UIColor with weights
        return zip(centroids, clusters).map { centroid, cluster in
            let color = centroid.toUIColor()
            let weight = CGFloat(cluster.count) / CGFloat(labPixels.count)
            let pixels = cluster.map { PixelData(rgb: $0.toRGB(), position: CGPoint.zero) }
            return (color, weight, pixels)
        }
    }
    
    // MARK: - LAB Color Space
    private struct LABColor {
        let l: CGFloat // Lightness
        let a: CGFloat // Green-Red
        let b: CGFloat // Blue-Yellow
        
        init(from rgb: RGB) {
            // Convert RGB to XYZ
            let xyz = LABColor.rgbToXYZ(rgb)
            
            // Convert XYZ to LAB
            let lab = LABColor.xyzToLAB(xyz)
            self.l = lab.l
            self.a = lab.a
            self.b = lab.b
        }
        
        init(l: CGFloat, a: CGFloat, b: CGFloat) {
            self.l = l
            self.a = a
            self.b = b
        }
        
        static func rgbToXYZ(_ rgb: RGB) -> (x: CGFloat, y: CGFloat, z: CGFloat) {
            // sRGB to linear RGB
            func linearize(_ channel: CGFloat) -> CGFloat {
                return channel <= 0.04045
                    ? channel / 12.92
                    : pow((channel + 0.055) / 1.055, 2.4)
            }
            
            let r = linearize(CGFloat(rgb.r))
            let g = linearize(CGFloat(rgb.g))
            let b = linearize(CGFloat(rgb.b))
            
            // Linear RGB to XYZ (D65 illuminant)
            let x = r * 0.4124564 + g * 0.3575761 + b * 0.1804375
            let y = r * 0.2126729 + g * 0.7151522 + b * 0.0721750
            let z = r * 0.0193339 + g * 0.1191920 + b * 0.9503041
            
            return (x, y, z)
        }
        
        static func xyzToLAB(_ xyz: (x: CGFloat, y: CGFloat, z: CGFloat)) -> LABColor {
            // Reference white D65
            let xn: CGFloat = 0.95047
            let yn: CGFloat = 1.00000
            let zn: CGFloat = 1.08883
            
            func f(_ t: CGFloat) -> CGFloat {
                let delta: CGFloat = 6.0 / 29.0
                return t > delta * delta * delta
                    ? pow(t, 1.0 / 3.0)
                    : t / (3.0 * delta * delta) + 4.0 / 29.0
            }
            
            let fx = f(xyz.x / xn)
            let fy = f(xyz.y / yn)
            let fz = f(xyz.z / zn)
            
            let l = 116.0 * fy - 16.0
            let a = 500.0 * (fx - fy)
            let b = 200.0 * (fy - fz)
            
            return LABColor(l: l, a: a, b: b)
        }
        
        func toRGB() -> RGB {
            // LAB to XYZ
            let xn: CGFloat = 0.95047
            let yn: CGFloat = 1.00000
            let zn: CGFloat = 1.08883
            
            let fy = (l + 16.0) / 116.0
            let fx = a / 500.0 + fy
            let fz = fy - b / 200.0
            
            func finv(_ t: CGFloat) -> CGFloat {
                let delta: CGFloat = 6.0 / 29.0
                return t > delta
                    ? pow(t, 3.0)
                    : 3.0 * delta * delta * (t - 4.0 / 29.0)
            }
            
            let x = xn * finv(fx)
            let y = yn * finv(fy)
            let z = zn * finv(fz)
            
            // XYZ to linear RGB
            let r = x *  3.2404542 + y * -1.5371385 + z * -0.4985314
            let g = x * -0.9692660 + y *  1.8760108 + z *  0.0415560
            let b = x *  0.0556434 + y * -0.2040259 + z *  1.0572252
            
            // Linear RGB to sRGB
            func gammaCorrect(_ channel: CGFloat) -> Float {
                let c = max(0, min(1, channel))
                return Float(c <= 0.0031308
                    ? c * 12.92
                    : 1.055 * pow(c, 1.0 / 2.4) - 0.055)
            }
            
            return RGB(
                r: gammaCorrect(r),
                g: gammaCorrect(g),
                b: gammaCorrect(b)
            )
        }
        
        func toUIColor() -> UIColor {
            let rgb = toRGB()
            return UIColor(
                red: CGFloat(rgb.r),
                green: CGFloat(rgb.g),
                blue: CGFloat(rgb.b),
                alpha: 1.0
            )
        }
        
        func distance(to other: LABColor) -> CGFloat {
            // CIE76 distance formula
            let dl = l - other.l
            let da = a - other.a
            let db = b - other.b
            return sqrt(dl * dl + da * da + db * db)
        }
    }
    
    // MARK: - Color Distribution Analysis
    private struct ColorDistribution {
        let histogram: [Int: Int]
        let variance: CGFloat
        let entropy: CGFloat
        let dominantHue: CGFloat?
        let saturationStats: (mean: CGFloat, variance: CGFloat)
        let brightnessStats: (mean: CGFloat, variance: CGFloat)
    }
    
    private static func analyzeColorDistribution(from image: CGImage) -> ColorDistribution {
        guard let pixelData = extractPixelData(from: image) else {
            return ColorDistribution(
                histogram: [:],
                variance: 0,
                entropy: 0,
                dominantHue: nil,
                saturationStats: (0, 0),
                brightnessStats: (0, 0)
            )
        }
        
        var histogram: [Int: Int] = [:]
        var hues: [CGFloat] = []
        var saturations: [CGFloat] = []
        var brightnesses: [CGFloat] = []
        
        for pixel in pixelData {
            // Quantize color for histogram
            let quantized = quantizeColor(pixel.rgb, level: Config.colorQuantizationLevel)
            histogram[quantized, default: 0] += 1
            
            // Convert to HSB for analysis
            let hsb = rgbToHSB(pixel.rgb)
            if hsb.saturation > Config.minSaturationForColor {
                hues.append(hsb.hue)
            }
            saturations.append(hsb.saturation)
            brightnesses.append(hsb.brightness)
        }
        
        // Calculate statistics
        let variance = calculateVariance(histogram: histogram)
        let entropy = calculateEntropy(histogram: histogram)
        let dominantHue = hues.isEmpty ? nil : calculateCircularMean(hues)
        let saturationStats = calculateStats(saturations)
        let brightnessStats = calculateStats(brightnesses)
        
        return ColorDistribution(
            histogram: histogram,
            variance: variance,
            entropy: entropy,
            dominantHue: dominantHue,
            saturationStats: saturationStats,
            brightnessStats: brightnessStats
        )
    }
    
    // MARK: - Optimal Color Selection
    private static func selectOptimalColors(
        dominantColors: [(color: UIColor, weight: CGFloat, position: ColorPosition)],
        distribution: ColorDistribution,
        scheme: ColorScheme,
        textLength: Int
    ) -> (text: UIColor, background: UIColor, confidence: CGFloat, scheme: ColorScheme) {
        
        var backgroundColor: UIColor = .white
        var textColor: UIColor = .black
        var confidence: CGFloat = 1.0
        
        switch scheme {
        case .gradient:
            // Для градієнтів беремо найсвітліший колір як фон
            let sortedByLuminance = dominantColors.sorted {
                $0.color.luminance > $1.color.luminance
            }
            backgroundColor = sortedByLuminance.first?.color ?? .white
            
            // Шукаємо контрастний колір для тексту
            textColor = findBestContrastColor(for: backgroundColor, from: dominantColors.map { $0.color })
            confidence = 0.8
            
        case .inverted:
            // Темний фон, світлий текст
            let darkColors = dominantColors.filter { $0.color.luminance < 0.3 }
            let lightColors = dominantColors.filter { $0.color.luminance > 0.7 }
            
            backgroundColor = darkColors.max(by: { $0.weight < $1.weight })?.color ?? .black
            textColor = lightColors.max(by: { $0.weight < $1.weight })?.color ?? .white
            confidence = 0.9
            
        case .colorful:
            // Кольоровий контент - використовуємо адаптивний підхід
            let edgeColors = dominantColors.filter { $0.position == .edge }
            let centerColors = dominantColors.filter { $0.position == .center }
            
            // Фон зазвичай на краях
            if let edgeColor = edgeColors.max(by: { $0.weight < $1.weight }) {
                backgroundColor = edgeColor.color
            } else {
                backgroundColor = dominantColors.max(by: { $0.weight < $1.weight })?.color ?? .white
            }
            
            // Текст в центрі
            if let centerColor = centerColors.first(where: {
                $0.color.contrastRatio(with: backgroundColor) > Config.minContrastRatio
            }) {
                textColor = centerColor.color
            } else {
                textColor = findBestContrastColor(for: backgroundColor, from: dominantColors.map { $0.color })
            }
            confidence = 0.85
            
        case .complex:
            // Складний паттерн - використовуємо статистичний підхід
            let backgroundCandidates = dominantColors.filter { $0.weight > 0.3 }
            
            if let bgCandidate = backgroundCandidates.first {
                backgroundColor = bgCandidate.color
                
                // Знаходимо всі контрастні кольори
                let contrastColors = dominantColors.filter {
                    $0.color.contrastRatio(with: backgroundColor) > Config.minContrastRatio
                }
                
                textColor = contrastColors.max(by: { $0.weight < $1.weight })?.color
                    ?? findBestContrastColor(for: backgroundColor, from: dominantColors.map { $0.color })
            }
            confidence = 0.7
            
        case .standard:
            // Стандартний підхід
            let sorted = dominantColors.sorted { $0.weight > $1.weight }
            
            if let first = sorted.first, let second = sorted.dropFirst().first {
                // Визначаємо що є фоном на основі позиції та ваги
                if first.position == .edge || first.weight > Config.dominanceThreshold {
                    backgroundColor = first.color
                    textColor = second.color
                } else {
                    backgroundColor = second.color
                    textColor = first.color
                }
                
                // Перевіряємо контраст
                if backgroundColor.contrastRatio(with: textColor) < Config.minContrastRatio {
                    textColor = findBestContrastColor(for: backgroundColor, from: dominantColors.map { $0.color })
                }
            }
            confidence = 0.95
        }
        
        // Фінальна перевірка та корекція
        let finalContrast = backgroundColor.contrastRatio(with: textColor)
        if finalContrast < Config.minContrastRatio {
            // Форсуємо максимальний контраст
            textColor = backgroundColor.luminance > 0.5 ? .black : .white
            confidence *= 0.7
        }
        
        // Адаптація для коротких текстів (заголовки)
        if textLength <= 5 {
            // Для заголовків можемо використати більш насичені кольори
            if let saturatedColor = dominantColors.first(where: {
                let hsb = rgbToHSB(uiColorToRGB($0.color))
                return hsb.saturation > 0.5 && $0.color.contrastRatio(with: backgroundColor) > Config.minContrastRatio
            }) {
                textColor = saturatedColor.color
            }
        }
        
        return (textColor, backgroundColor, confidence, scheme)
    }
    
    // MARK: - Helper Functions
    private static func calculateAdaptiveInset(for rect: CGRect) -> CGFloat {
        let minDimension = min(rect.width, rect.height)
        
        // Адаптивний відступ на основі розміру
        if minDimension < 50 {
            return minDimension * 0.02 // Дуже малий відступ для малих областей
        } else if minDimension < 100 {
            return minDimension * Config.edgeInsetRatio * 0.5
        } else {
            return minDimension * Config.edgeInsetRatio
        }
    }
    
    private static func detectColorScheme(
        distribution: ColorDistribution,
        dominantColors: [(color: UIColor, weight: CGFloat, position: ColorPosition)]
    ) -> ColorScheme {
        // Перевірка на градієнт
        if distribution.variance > 0.3 && distribution.entropy > 2.5 {
            return .gradient
        }
        
        // Перевірка на інверсію (темний фон)
        let avgBrightness = distribution.brightnessStats.mean
        if avgBrightness < 0.3 {
            return .inverted
        }
        
        // Перевірка на кольоровість
        if let _ = distribution.dominantHue,
           distribution.saturationStats.mean > 0.4 {
            return .colorful
        }
        
        // Перевірка на складність
        if dominantColors.count >= 4 && distribution.entropy > 2.0 {
            return .complex
        }
        
        return .standard
    }
    
    private static func findBestContrastColor(
        for backgroundColor: UIColor,
        from candidates: [UIColor]
    ) -> UIColor {
        // Знаходимо колір з найкращим контрастом
        let bestCandidate = candidates.max { color1, color2 in
            backgroundColor.contrastRatio(with: color1) < backgroundColor.contrastRatio(with: color2)
        }
        
        if let best = bestCandidate,
           backgroundColor.contrastRatio(with: best) >= Config.minContrastRatio {
            return best
        }
        
        // Якщо жоден кандидат не підходить, генеруємо оптимальний
        return backgroundColor.luminance > 0.5 ? .black : .white
    }
    
    // MARK: - Pixel Data Extraction
    private struct PixelData {
        let rgb: RGB
        let position: CGPoint
    }
    
    private static func extractPixelData(from image: CGImage) -> [PixelData]? {
        guard let dataProvider = image.dataProvider,
              let data = dataProvider.data,
              let pixels = CFDataGetBytePtr(data) else {
            return nil
        }
        
        let width = image.width
        let height = image.height
        let bytesPerPixel = image.bitsPerPixel / 8
        
        var pixelData: [PixelData] = []
        pixelData.reserveCapacity(width * height)
        
        for y in 0..<height {
            for x in 0..<width {
                let index = (width * y + x) * bytesPerPixel
                guard index + 2 < CFDataGetLength(data) else { continue }
                
                let rgb = RGB(
                    r: Float(pixels[index]) / 255.0,
                    g: Float(pixels[index + 1]) / 255.0,
                    b: Float(pixels[index + 2]) / 255.0
                )
                
                let position = CGPoint(
                    x: CGFloat(x) / CGFloat(width),
                    y: CGFloat(y) / CGFloat(height)
                )
                
                pixelData.append(PixelData(rgb: rgb, position: position))
            }
        }
        
        return pixelData
    }
    
    // MARK: - Statistical Calculations
    private static func calculateStats(_ values: [CGFloat]) -> (mean: CGFloat, variance: CGFloat) {
        guard !values.isEmpty else { return (0, 0) }
        
        let mean = values.reduce(0, +) / CGFloat(values.count)
        let variance = values.reduce(0) { sum, value in
            let diff = value - mean
            return sum + diff * diff
        } / CGFloat(values.count)
        
        return (mean, variance)
    }
    
    private static func calculateVariance(histogram: [Int: Int]) -> CGFloat {
        let total = histogram.values.reduce(0, +)
        guard total > 0 else { return 0 }
        
        let mean = CGFloat(histogram.values.reduce(0, +)) / CGFloat(histogram.count)
        let variance = histogram.values.reduce(0.0) { sum, count in
            let diff = CGFloat(count) - mean
            return sum + diff * diff
        } / CGFloat(histogram.count)
        
        return variance / CGFloat(total)
    }
    
    private static func calculateEntropy(histogram: [Int: Int]) -> CGFloat {
        let total = histogram.values.reduce(0, +)
        guard total > 0 else { return 0 }
        
        return histogram.values.reduce(0.0) { entropy, count in
            guard count > 0 else { return entropy }
            let probability = CGFloat(count) / CGFloat(total)
            return entropy - probability * log2(probability)
        }
    }
    
    private static func calculateCircularMean(_ angles: [CGFloat]) -> CGFloat {
        let sumSin = angles.reduce(0.0) { $0 + sin($1 * 2 * .pi) }
        let sumCos = angles.reduce(0.0) { $0 + cos($1 * 2 * .pi) }
        var mean = atan2(sumSin, sumCos) / (2 * .pi)
        if mean < 0 { mean += 1 }
        return mean
    }
    
    // MARK: - Helper Functions
    private static func quantizeColor(_ rgb: RGB, level: Int) -> Int {
        let r = Int(rgb.r * Float(level))
        let g = Int(rgb.g * Float(level))
        let b = Int(rgb.b * Float(level))
        return (r << 16) | (g << 8) | b
    }
    
    private static func rgbToHSB(_ rgb: RGB) -> (hue: CGFloat, saturation: CGFloat, brightness: CGFloat) {
        let r = CGFloat(rgb.r)
        let g = CGFloat(rgb.g)
        let b = CGFloat(rgb.b)
        
        let maxVal = max(r, g, b)
        let minVal = min(r, g, b)
        let delta = maxVal - minVal
        
        // Brightness
        let brightness = maxVal
        
        // Saturation
        let saturation = maxVal == 0 ? 0 : delta / maxVal
        
        // Hue
        var hue: CGFloat = 0
        if delta != 0 {
            if maxVal == r {
                hue = ((g - b) / delta + (g < b ? 6 : 0)) / 6
            } else if maxVal == g {
                hue = ((b - r) / delta + 2) / 6
            } else {
                hue = ((r - g) / delta + 4) / 6
            }
        }
        
        return (hue, saturation, brightness)
    }
    
    private static func uiColorToRGB(_ color: UIColor) -> RGB {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: nil)
        return RGB(r: Float(r), g: Float(g), b: Float(b))
    }
    
    private static func calculateThumbnailSize(for image: CGImage, maxDimension: CGFloat) -> CGSize {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        
        if width > height {
            let scale = maxDimension / width
            return CGSize(width: maxDimension, height: height * scale)
        } else {
            let scale = maxDimension / height
            return CGSize(width: width * scale, height: maxDimension)
        }
    }
    
    private static func determineColorPosition(
        cluster: (color: UIColor, weight: CGFloat, pixels: [PixelData]),
        in image: CGImage
    ) -> ColorPosition {
        guard !cluster.pixels.isEmpty else { return .scattered }
        
        let positions = cluster.pixels.map { $0.position }
        let centerX = positions.map { $0.x }.reduce(0, +) / CGFloat(positions.count)
        let centerY = positions.map { $0.y }.reduce(0, +) / CGFloat(positions.count)
        
        // Перевірка на розташування по краях
        let edgeThreshold: CGFloat = 0.2
        let edgePixels = positions.filter {
            $0.x < edgeThreshold || $0.x > (1 - edgeThreshold) ||
            $0.y < edgeThreshold || $0.y > (1 - edgeThreshold)
        }
        
        if CGFloat(edgePixels.count) / CGFloat(positions.count) > 0.6 {
            return .edge
        }
        
        // Перевірка на центральне розташування
        if centerX > 0.3 && centerX < 0.7 && centerY > 0.3 && centerY < 0.7 {
            return .center
        }
        
        // Перевірка на рівномірний розподіл
        let variance = positions.reduce(0.0) { sum, pos in
            let dx = pos.x - centerX
            let dy = pos.y - centerY
            return sum + dx * dx + dy * dy
        } / CGFloat(positions.count)
        
        if variance > 0.15 {
            return .scattered
        }
        
        return .uniform
    }
    
    // MARK: - K-Means++ Initialization
    private static func initializeKMeansPlusPlus(pixels: [LABColor], k: Int) -> [LABColor] {
        guard !pixels.isEmpty, k > 0 else { return [] }
        
        var centroids: [LABColor] = []
        
        // Choose first centroid randomly
        centroids.append(pixels.randomElement()!)
        
        // Choose remaining centroids
        while centroids.count < k {
            var distances: [CGFloat] = []
            
            for pixel in pixels {
                let minDistance = centroids.map { pixel.distance(to: $0) }.min() ?? 0
                distances.append(minDistance * minDistance) // Square for probability
            }
            
            // Choose next centroid with probability proportional to squared distance
            let totalDistance = distances.reduce(0, +)
            guard totalDistance > 0 else { break }
            
            let randomValue = CGFloat.random(in: 0...totalDistance)
            var cumulativeDistance: CGFloat = 0
            
            for (index, distance) in distances.enumerated() {
                cumulativeDistance += distance
                if cumulativeDistance >= randomValue {
                    centroids.append(pixels[index])
                    break
                }
            }
        }
        
        return centroids
    }
    
    private static func findNearestCentroid(pixel: LABColor, centroids: [LABColor]) -> Int {
        var minDistance = CGFloat.greatestFiniteMagnitude
        var nearestIndex = 0
        
        for (index, centroid) in centroids.enumerated() {
            let distance = pixel.distance(to: centroid)
            if distance < minDistance {
                minDistance = distance
                nearestIndex = index
            }
        }
        
        return nearestIndex
    }
    
    private static func averageLABColor(_ colors: [LABColor]) -> LABColor {
        guard !colors.isEmpty else { return LABColor(l: 0, a: 0, b: 0) }
        
        let sumL = colors.reduce(0) { $0 + $1.l }
        let sumA = colors.reduce(0) { $0 + $1.a }
        let sumB = colors.reduce(0) { $0 + $1.b }
        let count = CGFloat(colors.count)
        
        return LABColor(l: sumL / count, a: sumA / count, b: sumB / count)
    }
    
    private static func hasConverged(old: [LABColor], new: [LABColor]) -> Bool {
        guard old.count == new.count else { return false }
        
        let threshold: CGFloat = 1.0 // LAB distance threshold
        
        for (oldCentroid, newCentroid) in zip(old, new) {
            if oldCentroid.distance(to: newCentroid) > threshold {
                return false
            }
        }
        
        return true
    }
    
    // MARK: - RGB Structure
    private struct RGB: Equatable {
        var r, g, b: Float
        
        static var zero: RGB { RGB(r: 0, g: 0, b: 0) }
        
        static func +(lhs: RGB, rhs: RGB) -> RGB {
            return RGB(r: lhs.r + rhs.r, g: lhs.g + rhs.g, b: lhs.b + rhs.b)
        }
        
        static func /(lhs: RGB, rhs: Float) -> RGB {
            guard rhs != 0 else { return .zero }
            return RGB(r: lhs.r / rhs, g: lhs.g / rhs, b: lhs.b / rhs)
        }
    }
}

// MARK: - UIColor Extensions (залишаються без змін)
extension UIColor {
    var luminance: CGFloat {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: nil)
        
        func toLinear(_ channel: CGFloat) -> CGFloat {
            return channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        
        let linearR = toLinear(red)
        let linearG = toLinear(green)
        let linearB = toLinear(blue)
        
        return 0.2126 * linearR + 0.7152 * linearG + 0.0722 * linearB
    }
    
    var isLight: Bool {
        return luminance > 0.5
    }
    
    func contrastRatio(with other: UIColor) -> CGFloat {
        let l1 = self.luminance
        let l2 = other.luminance
        return l1 > l2 ? (l1 + 0.05) / (l2 + 0.05) : (l2 + 0.05) / (l1 + 0.05)
    }
    
    func colorDistance(to other: UIColor) -> CGFloat {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0
        
        getRed(&r1, green: &g1, blue: &b1, alpha: nil)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: nil)
        
        let dr = r1 - r2
        let dg = g1 - g2
        let db = b1 - b2
        
        return sqrt(dr * dr + dg * dg + db * db)
    }
}

// MARK: - CGImage Extension
extension CGImage {
    func resized(to newSize: CGSize) -> CGImage? {
        guard let colorSpace = self.colorSpace else { return nil }
        
        let context = CGContext(
            data: nil,
            width: Int(newSize.width),
            height: Int(newSize.height),
            bitsPerComponent: self.bitsPerComponent,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: self.bitmapInfo.rawValue
        )
        
        context?.interpolationQuality = .high
        context?.draw(self, in: CGRect(origin: .zero, size: newSize))
        
        return context?.makeImage()
    }
}
