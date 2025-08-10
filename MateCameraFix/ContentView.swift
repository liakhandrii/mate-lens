import SwiftUI
import MLKit
import Combine

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var textRecognitionService = TextRecognitionService()
    @State private var showOverlay = false
    @State private var debugEnabled: Bool = false
    
    @State private var imageProcessingCancellable: AnyCancellable?

    #if DEBUG
    private let drawDebugButton = true
    #else
    private let drawDebugButton = false
    #endif
        
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
                CameraView(cameraManager: cameraManager)
                    .ignoresSafeArea()
            
                VStack {
                    Spacer()
                    
                        
                    HStack(spacing: 30) {
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
                        
                        Button(action: capturePhotoAction) {
                            Circle()
                                .fill(Color.white)
                                .frame(width: Layout.captureButtonSize, height: Layout.captureButtonSize)
                                .overlay(
                                    Circle()
                                        .stroke(Color.black.opacity(Layout.captureButtonStrokeOpacity), lineWidth: Layout.captureButtonStrokeWidth)
                                )
                        }
                        .disabled(textRecognitionService.isProcessing)
                        
                        if !drawDebugButton {
                            Spacer()
                                .frame(width: 60)
                        }
                    }
                    .padding(.bottom, Layout.captureButtonBottomPadding)
                }
            
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
            
                if textRecognitionService.isProcessing {
                    ProgressView()
                        .scaleEffect(2)
                        .padding()
                        .background(Color.white.opacity(0.8))
                        .cornerRadius(10)
                }
                
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
            }
        }
    }
    
    // MARK: - Налаштування спостереження за зображенням
    private func setupImageObserver() {
        // Підписуємось на оновлення capturedImage
        imageProcessingCancellable = cameraManager.$capturedImage
            .dropFirst()
            .compactMap { $0 }
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
        
        textRecognitionService.clearData()
        
        textRecognitionService.isProcessing = true
        
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
