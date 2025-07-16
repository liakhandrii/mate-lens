import SwiftUI
import AVFoundation

// Визначаємо можливі помилки камери з описом для користувача
enum CameraError: Error, LocalizedError {
    case noCameraDevice              // Коли немає доступної камери
    case cannotCreateInput           // Помилка при створенні входу з камери
    case captureError(Error)         // Помилка під час захоплення фото
    case noImageData                 // Не отримано дані зображення
    case invalidImageData            // Дані зображення некоректні
    
    var errorDescription: String? {
        switch self {
        case .noCameraDevice: return "Не знайдено відео пристрій."
        case .cannotCreateInput: return "Не вдалося створити вхідний пристрій."
        case .captureError(let error): return "Помилка захоплення фото: \(error.localizedDescription)"
        case .noImageData: return "Не вдалося отримати дані зображення."
        case .invalidImageData: return "Неможливо створити зображення з отриманих даних."
        }
    }
}

class CameraManager: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    @Published var capturedImage: UIImage?
    @Published var error: CameraError?
    
    private var captureSession: AVCaptureSession?  // Сесія камери
    private var photoOutput = AVCapturePhotoOutput() // Вихід для фото
    
    func setupCamera() -> UIView {
        stopSession()
        
        let view = UIView(frame: UIScreen.main.bounds)
        
        let captureSession = AVCaptureSession()
        captureSession.sessionPreset = .photo  // Якість фото
        
        guard let captureDevice = AVCaptureDevice.default(for: .video) else {
            error = .noCameraDevice
            return view
        }
        
        guard let input = try? AVCaptureDeviceInput(device: captureDevice) else {
            error = .cannotCreateInput
            return view
        }
        
        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }
        
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }
        
        // Створюємо шар для превʼю відео та додаємо його у view
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill  // Заповнення екрану
        
        view.layer.addSublayer(previewLayer)
        
        // Запускаємо сесію асинхронно
        DispatchQueue.global(qos: .userInitiated).async {
            captureSession.startRunning()
        }
        
        self.captureSession = captureSession
        
        return view
    }
    
    /// Зупиняє сесію камери та очищує її
    func stopSession() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession?.stopRunning()
            self?.captureSession = nil
        }
    }
    
    deinit {
        // При видаленні обʼєкту зупинити камеру, щоб не було витоків
        stopSession()
        print("CameraManager deinitialized, session stopped")
    }
    
    /// Захоплення фото з камери
    func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    // Делегат AVCapturePhotoCaptureDelegate — викликається після обробки фото
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            // Якщо сталася помилка — передаємо її у властивість error для UI
            DispatchQueue.main.async { [weak self] in self?.error = .captureError(error) }
            return
        }
        
        // Отримуємо дані фото у форматі JPEG
        guard let imageData = photo.fileDataRepresentation() else {
            DispatchQueue.main.async { [weak self] in self?.error = .noImageData }
            return
        }
        
        // Створюємо UIImage з отриманих даних
        guard let image = UIImage(data: imageData) else {
            DispatchQueue.main.async { [weak self] in self?.error = .invalidImageData }
            return
        }
        
        // Оновлюємо властивість capturedImage у головному потоці, щоб UI міг оновитися
        DispatchQueue.main.async { [weak self] in
            self?.capturedImage = image
        }
    }
}
