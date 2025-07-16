import SwiftUI
import MLKit

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()

    var body: some View {
        ZStack {
            CameraView(cameraManager: cameraManager)
                .ignoresSafeArea()

            VStack {
                Spacer()

                Button(action: {
                    cameraManager.capturePhoto()

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if let image = cameraManager.capturedImage {
                            recognizeText(in: image)
                        }
                    }
                }) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 70, height: 70)
                        .overlay(
                            Circle()
                                .stroke(Color.black.opacity(0.8), lineWidth: 2)
                        )
                }
                .padding(.bottom, 50)
            }

            // Попередній перегляд останнього фото
            if let capturedImage = cameraManager.capturedImage {
                VStack {
                    HStack {
                        Spacer()
                        Image(uiImage: capturedImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 100, height: 100)
                            .border(Color.white, width: 2)
                            .padding()
                    }
                    Spacer()
                }
            }
        }
    }

    func recognizeText(in image: UIImage) {
        // Створюємо VisionImage, з яким працює ML Kit
        let visionImage = VisionImage(image: image)
        visionImage.orientation = image.imageOrientation // Важливо для точності

        // Отримуємо розпізнавач тексту для латинського алфавіту
        let textRecognizer = TextRecognizer.textRecognizer()

        // Обробляємо зображення
        textRecognizer.process(visionImage) { result, error in
            // Перевіряємо наявність помилок
            if let error = error {
                print("Error recognizing text: \(error.localizedDescription)")
                return
            }

            // Перевіряємо, чи є результат
            guard let result = result else {
                print("Text not found in the image.")
                return
            }

            // Виводимо знайдений текст у консоль
            print("Found text: \(result.text)")
        }
    }
}
