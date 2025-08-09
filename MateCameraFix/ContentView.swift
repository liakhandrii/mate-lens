import SwiftUI
import MLKit
import Combine

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var textRecognitionService = TextRecognitionService()
    @State private var showOverlay = false
    @State private var debugEnabled: Bool = false
    
    // Підписка на зміни зображення з камери
    @State private var imageProcessingCancellable: AnyCancellable?

    #if DEBUG
    private let drawDebugButton = true
    #else
    private let drawDebugButton = false
    #endif
        
    // Константи для UI елементів
    private enum Layout {
        static let captureButtonSize: CGFloat = 70
        static let captureButtonStrokeWidth: CGFloat = 2
        static let captureButtonStrokeOpacity: Double = 0.8
        static let captureButtonBottomPadding: CGFloat = 50
        
        static let previewImageSize: CGFloat = 100
        static let previewImageBorderWidth: CGFloat = 2
        static let previewImagePadding: CGFloat = 16
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Прев'ю з камери на весь екран
                CameraView(cameraManager: cameraManager)
                    .ignoresSafeArea()
            
                VStack {
                    Spacer()
                    
                        
                    HStack(spacing: 30) {
                        // Кнопка для дебагу (показується тільки в DEBUG збірці)
                        if drawDebugButton {
                            Button(action: {
                                debugEnabled.toggle()
                            }) {
                                Text("DEBUG")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(debugEnabled ? .black : .white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(debugEnabled ? Color.yellow : Color.black.opacity(0.6))
                                    .cornerRadius(8)
                            }
                        }
                        
                        // Основна кнопка захоплення фото
                        Button(action: capturePhotoAction) {
                            Circle()
                                .fill(Color.white)
                                .frame(width: Layout.captureButtonSize, height: Layout.captureButtonSize)
                                .overlay(
                                    Circle()
                                        .stroke(Color.black.opacity(Layout.captureButtonStrokeOpacity), lineWidth: Layout.captureButtonStrokeWidth)
                                )
                        }
                        .disabled(textRecognitionService.isProcessing) // Блокуємо під час обробки
                        
                        // Spacer для балансу UI коли DEBUG кнопка прихована
                        if !drawDebugButton {
                            Spacer()
                                .frame(width: 60) // Ширина відповідає DEBUG кнопці
                        }
                    }
                    .padding(.bottom, Layout.captureButtonBottomPadding)
                }
            
                // Мініатюра останнього знімка в правому верхньому куті
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
            
                // Спінер під час обробки
                if textRecognitionService.isProcessing {
                    ProgressView()
                        .scaleEffect(2)
                        .padding()
                        .background(Color.white.opacity(0.8))
                        .cornerRadius(10)
                }
                
                // Відображення помилки якщо є
                if let errorMessage = textRecognitionService.error {
                    VStack {
                        Spacer()
                        Text(errorMessage)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.red.opacity(0.8))
                            .cornerRadius(8)
                            .padding()
                        Spacer()
                    }
                }
            }
            .navigationDestination(isPresented: $showOverlay) {
                PositionedTextOverlayView(
                    image: cameraManager.capturedImage,
                    textData: textRecognitionService.textData,
                    debugEnabled: debugEnabled
                )
            }
            .onAppear {
                setupImageObserver()
            }
            .onDisappear {
                imageProcessingCancellable?.cancel()
                // Не очищаємо дані тут - вони потрібні для PositionedTextOverlayView
            }
        }
    }
    
    // MARK: - Налаштування спостереження за зображенням
    private func setupImageObserver() {
        // Підписуємось на оновлення capturedImage
        imageProcessingCancellable = cameraManager.$capturedImage
            .dropFirst() // Пропускаємо початкове nil значення
            .compactMap { $0 } // Відфільтровуємо nil
            .receive(on: DispatchQueue.main)
            .sink { image in
                guard self.textRecognitionService.isProcessing else { return }
                
                print("Image captured, starting text recognition...")
                
                self.textRecognitionService.recognizeText(in: image) { success in
                    if success {
                        self.showOverlay = true
                    }
                }
            }
    }
    
    // MARK: - Обробка натискання кнопки захоплення
    private func capturePhotoAction() {
        print("Capture button pressed")
        
        // Очищаємо попередні дані перед новим захопленням
        textRecognitionService.clearData()
        
        // Встановлюємо прапор обробки ПЕРЕД захопленням
        textRecognitionService.isProcessing = true
        
        // Викликаємо захоплення з колбеком
        cameraManager.capturePhoto { success, error in
            if let error = error {
                print("Capture error: \(error)")
                DispatchQueue.main.async {
                    self.textRecognitionService.isProcessing = false
                }
                return
            }
            
            if !success {
                print("Capture failed without error")
                DispatchQueue.main.async {
                    self.textRecognitionService.isProcessing = false
                }
            }
            // При успіху обробка продовжиться через observer
        }
    }
}

// MARK: - View для відображення тексту поверх зображення
struct PositionedTextOverlayView: View {
    let image: UIImage?
    let textData: [WordData]
    let debugEnabled: Bool
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .position(x: geometry.size.width/2, y: geometry.size.height/2)
            
                    PerspectiveTextView(
                        textItems: textData,
                        imageSize: image.size,
                        screenSize: geometry.size,
                        debugEnabled: debugEnabled
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .position(x: geometry.size.width/2, y: geometry.size.height/2)
                    
                    // Лічильник знайдених текстів для дебагу
                    if debugEnabled {
                        VStack {
                            Text("Texts found: \(textData.count)")
                                .foregroundColor(.red)
                                .padding()
                                .background(Color.white.opacity(0.8))
                                .cornerRadius(8)
                            Spacer()
                        }
                        .padding()
                    }
                } else {
                    Text("Photo not made")
                }
            }
        }
        .ignoresSafeArea()
        .navigationTitle("Positioned Text")
        .navigationBarTitleDisplayMode(.inline)
    }
}
