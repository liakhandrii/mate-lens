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
    private weak var previewLayer: AVCaptureVideoPreviewLayer? // Слабка референція на preview layer
    private weak var previewView: UIView? // Слабка референція на view
    
    // Completion handler для захоплення фото
    private var photoCaptureCompletion: ((Bool, CameraError?) -> Void)?
    
    func setupCamera() -> UIView {
        // Спочатку очищаємо попередню сесію
        cleanupSession()
        
        let view = UIView(frame: UIScreen.main.bounds)
        self.previewView = view // Зберігаємо слабку референцію
        
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
        
        // Створюємо новий photoOutput замість повторного використання
        let newPhotoOutput = AVCapturePhotoOutput()
        if captureSession.canAddOutput(newPhotoOutput) {
            captureSession.addOutput(newPhotoOutput)
        }
        self.photoOutput = newPhotoOutput
        
        // Створюємо шар для превʼю відео та додаємо його у view
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill  // Заповнення екрану
        
        view.layer.addSublayer(previewLayer)
        self.previewLayer = previewLayer // Зберігаємо слабку референцію
        
        // Запускаємо сесію асинхронно з weak self
        DispatchQueue.global(qos: .userInitiated).async { [weak captureSession] in
            captureSession?.startRunning()
        }
        
        self.captureSession = captureSession
        
        return view
    }
    
    /// Очищає всі ресурси сесії камери
    private func cleanupSession() {
        // Зупиняємо сесію
        if let session = captureSession {
            if session.isRunning {
                session.stopRunning()
            }
            
            // Видаляємо всі inputs
            session.inputs.forEach { input in
                session.removeInput(input)
            }
            
            // Видаляємо всі outputs
            session.outputs.forEach { output in
                session.removeOutput(output)
            }
        }
        
        // Видаляємо preview layer з superlayer
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
        
        // Очищаємо view
        previewView?.layer.sublayers?.removeAll()
        previewView = nil
        
        // Очищаємо сесію
        captureSession = nil
    }
    
    /// Зупиняє сесію камери та очищає її
    func stopSession() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.cleanupSession()
        }
    }
    
    deinit {
        // При видаленні обʼєкту зупинити камеру, щоб не було витоків
        cleanupSession()
        photoCaptureCompletion = nil // Очищаємо completion handler
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
            photoCaptureCompletion = nil // Очищаємо handler
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
        // Створюємо локальну копію completion handler і очищаємо властивість
        let completion = photoCaptureCompletion
        photoCaptureCompletion = nil
        
        if let error = error {
            // Якщо сталася помилка — передаємо її у властивість error для UI
            let cameraError = CameraError.captureError(error)
            DispatchQueue.main.async { [weak self] in
                self?.error = cameraError
                completion?(false, cameraError)
            }
            return
        }
        
        guard let imageData = photo.fileDataRepresentation() else {
            let cameraError = CameraError.noImageData
            DispatchQueue.main.async { [weak self] in
                self?.error = cameraError
                completion?(false, cameraError)
            }
            return
        }
        
        guard let image = UIImage(data: imageData) else {
            let cameraError = CameraError.invalidImageData
            DispatchQueue.main.async { [weak self] in
                self?.error = cameraError
                completion?(false, cameraError)
            }
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.capturedImage = image
            completion?(true, nil)
            print("Photo captured successfully")
        }
    }
    
    func clearCapturedImage() {
        DispatchQueue.main.async { [weak self] in
            self?.capturedImage = nil
        }
    }
}
