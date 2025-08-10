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
    
    // Completion handler для захоплення фото
    private var photoCaptureCompletion: ((Bool, CameraError?) -> Void)?
    
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
    
    /// Зупиняє сесію камери та очищає її
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
    
    /// Захоплення фото з камери з completion handler
    func capturePhoto(completion: @escaping (Bool, CameraError?) -> Void) {
        // Зберігаємо completion handler
        self.photoCaptureCompletion = completion
        
        // Налаштування для захоплення
        let settings = AVCapturePhotoSettings()
        
        // Перевіряємо, чи можемо захопити фото
        guard captureSession?.isRunning == true else {
            completion(false, .noCameraDevice)
            return
        }
        
        // Захоплюємо фото
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    /// Стара версія без completion (для зворотної сумісності)
    func capturePhoto() {
        capturePhoto { _, _ in }
    }
    
    // MARK: - AVCapturePhotoCaptureDelegate
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            // Якщо сталася помилка — передаємо її у властивість error для UI
            let cameraError = CameraError.captureError(error)
            DispatchQueue.main.async { [weak self] in
                self?.error = cameraError
                self?.photoCaptureCompletion?(false, cameraError)
                self?.photoCaptureCompletion = nil
            }
            return
        }
        
        guard let imageData = photo.fileDataRepresentation() else {
            let cameraError = CameraError.noImageData
            DispatchQueue.main.async { [weak self] in
                self?.error = cameraError
                self?.photoCaptureCompletion?(false, cameraError)
                self?.photoCaptureCompletion = nil
            }
            return
        }
        
        guard let image = UIImage(data: imageData) else {
            let cameraError = CameraError.invalidImageData
            DispatchQueue.main.async { [weak self] in
                self?.error = cameraError
                self?.photoCaptureCompletion?(false, cameraError)
                self?.photoCaptureCompletion = nil
            }
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.capturedImage = image
            self?.photoCaptureCompletion?(true, nil)
            self?.photoCaptureCompletion = nil
            print("Photo captured successfully")
        }
    }
    
    func clearCapturedImage() {
        DispatchQueue.main.async { [weak self] in
            self?.capturedImage = nil
        }
    }
}
