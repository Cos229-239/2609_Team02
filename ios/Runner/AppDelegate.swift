import AVFoundation
import Flutter
import CoreImage
import ImageIO
import NaturalLanguage
import UIKit
import Vision

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Device time zone (IANA id, e.g. "America/Chicago") for the household's
    // 9 AM reminders. Read by lib/core/services/time_zone_service.dart.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "FamotiveTimeZone") {
      let channel = FlutterMethodChannel(name: "famotive/timezone", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        if call.method == "getLocalTimeZone" {
          result(TimeZone.current.identifier)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }

    // Task photo checks (lib/core/services/task_photo_scanner.dart).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "FamotiveVision") {
      let channel = FlutterMethodChannel(name: "famotive/vision", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "classifyImage":
          guard let path = args["path"] as? String else {
            result(FlutterError(code: "bad_args", message: "path is required", details: nil))
            return
          }
          TaskPhotoVision.classify(path: path) { outcome in
            DispatchQueue.main.async {
              switch outcome {
              case .success(let labels): result(labels)
              case .failure(let error):
                result(FlutterError(code: "vision_failed", message: error.localizedDescription, details: nil))
              }
            }
          }
        case "screenCheck":
          guard let path = args["path"] as? String else {
            result(FlutterError(code: "bad_args", message: "path is required", details: nil))
            return
          }
          DispatchQueue.global(qos: .userInitiated).async {
            let check = TaskPhotoVision.screenCheck(path: path)
            DispatchQueue.main.async { result(check) }
          }
        case "captureWithDepth":
          TaskPhotoVision.captureWithDepth(result: result)
        case "wordSimilarities":
          let keywords = args["keywords"] as? [String] ?? []
          let labels = args["labels"] as? [String] ?? []
          DispatchQueue.global(qos: .userInitiated).async {
            let similarities = TaskPhotoVision.similarities(keywords: keywords, labels: labels)
            DispatchQueue.main.async { result(similarities) }
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}

// MARK: Task photo checks

enum TaskPhotoVision {
  static let minConfidence: Float = 0.05
  static let maxLabels = 20

  static func classify(path: String, completion: @escaping (Result<[[String: Any]], Error>) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let url = URL(fileURLWithPath: path)
        let handler = VNImageRequestHandler(url: url, orientation: orientation(of: url), options: [:])
        let request = VNClassifyImageRequest()
        try handler.perform([request])
        let observations = (request.results ?? [])
          .filter { $0.confidence >= minConfidence }
          .sorted { $0.confidence > $1.confidence }
          .prefix(maxLabels)
        completion(.success(observations.map { ["identifier": $0.identifier, "confidence": Double($0.confidence)] }))
      } catch {
        completion(.failure(error))
      }
    }
  }

  static func screenCheck(path: String) -> [String: Any] {
    let url = URL(fileURLWithPath: path)
    guard let raw = CIImage(contentsOf: url) else { return ["likelihood": 0.0] }
    let image = raw.oriented(orientation(of: url))
    let e = image.extent
    let context = CIContext(options: [.workingColorSpace: NSNull()])

    func luma(_ rect: CGRect) -> Double {
      guard rect.width >= 1, rect.height >= 1,
            let filter = CIFilter(name: "CIAreaAverage") else { return 0 }
      filter.setValue(image, forKey: kCIInputImageKey)
      filter.setValue(CIVector(cgRect: rect), forKey: kCIInputExtentKey)
      guard let out = filter.outputImage else { return 0 }
      var px = [UInt8](repeating: 0, count: 4)
      context.render(out, toBitmap: &px, rowBytes: 4,
                     bounds: CGRect(x: out.extent.minX, y: out.extent.minY, width: 1, height: 1),
                     format: .RGBA8, colorSpace: nil)
      return (0.2126 * Double(px[0]) + 0.7152 * Double(px[1]) + 0.0722 * Double(px[2])) / 255
    }

    // 1. Dark corners vs bright centre.
    let cw = e.width * 0.07, ch = e.height * 0.07
    let corners = [
      CGRect(x: e.minX, y: e.minY, width: cw, height: ch),
      CGRect(x: e.maxX - cw, y: e.minY, width: cw, height: ch),
      CGRect(x: e.minX, y: e.maxY - ch, width: cw, height: ch),
      CGRect(x: e.maxX - cw, y: e.maxY - ch, width: cw, height: ch),
    ].map(luma)
    let center = luma(e.insetBy(dx: e.width * 0.3, dy: e.height * 0.3))
    let darkCorners = corners.filter { $0 < 0.10 }.count
    var cornerScore = 0.0
    if center >= 0.35 {
      cornerScore = darkCorners >= 2 ? 0.6 : (darkCorners == 1 ? 0.15 : 0)
    }

    // 2. A big bright rectangle on a dark surround.
    var rectScore = 0.0
    var rectArea = 0.0, inside = 0.0, outside = 0.0
    let request = VNDetectRectanglesRequest()
    request.minimumSize = 0.3
    request.minimumAspectRatio = 0.3
    request.quadratureTolerance = 25
    request.minimumConfidence = 0.5
    request.maximumObservations = 4
    if (try? VNImageRequestHandler(ciImage: image, options: [:]).perform([request])) != nil,
       let best = (request.results ?? []).max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }) {
      let bb = best.boundingBox
      rectArea = Double(bb.width * bb.height)
      if rectArea >= 0.3 && rectArea <= 0.97 {
        let r = CGRect(x: e.minX + bb.minX * e.width, y: e.minY + bb.minY * e.height,
                       width: bb.width * e.width, height: bb.height * e.height)
        inside = luma(r)
        let whole = luma(e)
        outside = max(0, (whole - inside * rectArea) / (1 - rectArea))
        if inside - outside >= 0.25 && outside < 0.2 {
          rectScore = 0.7 * Double(best.confidence)
        }
      }
    }

    let likelihood = 1 - (1 - cornerScore) * (1 - rectScore)
    return [
      "likelihood": likelihood,
      "darkCorners": darkCorners,
      "centerLuma": center,
      "cornerLuma": corners,
      "rectArea": rectArea,
      "rectInsideLuma": inside,
      "rectOutsideLuma": outside,
    ]
  }

  // MARK: Depth camera

  static func captureWithDepth(result: @escaping FlutterResult) {
    guard let device = DepthCameraViewController.depthDevice() else {
      result(FlutterError(code: "unsupported", message: "This iPhone has no depth camera.", details: nil))
      return
    }
    let start = {
      guard let presenter = topViewController() else {
        result(FlutterError(code: "camera_failed", message: "No screen to show the camera on.", details: nil))
        return
      }
      let camera = DepthCameraViewController(device: device)
      camera.completion = { output, error in
        if let error = error {
          result(FlutterError(code: "camera_failed", message: error.localizedDescription, details: nil))
        } else {
          result(output)
        }
      }
      presenter.present(camera, animated: true)
    }
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      start()
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { granted in
        DispatchQueue.main.async {
          if granted { start() } else { result(FlutterError(code: "camera_denied", message: nil, details: nil)) }
        }
      }
    default:
      result(FlutterError(code: "camera_denied", message: nil, details: nil))
    }
  }

  static func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let windows = scenes.flatMap { $0.windows }
    var top = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }

  static func flatness(of depthData: AVDepthData) -> [String: Any]? {
    let converted = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
    let map = converted.depthDataMap
    CVPixelBufferLockBaseAddress(map, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
    let w = CVPixelBufferGetWidth(map), h = CVPixelBufferGetHeight(map)
    guard w > 8, h > 8, let base = CVPixelBufferGetBaseAddress(map) else { return nil }
    let rowBytes = CVPixelBufferGetBytesPerRow(map)

    let n = 32
    var xs: [Double] = [], ys: [Double] = [], zs: [Double] = []
    for j in 0..<n {
      for i in 0..<n {
        let x = 0.05 + 0.9 * (Double(i) + 0.5) / Double(n)
        let y = 0.05 + 0.9 * (Double(j) + 0.5) / Double(n)
        let px = min(w - 1, Int(x * Double(w)))
        let py = min(h - 1, Int(y * Double(h)))
        let z = Double(base.advanced(by: py * rowBytes).assumingMemoryBound(to: Float32.self)[px])
        if z.isFinite && z > 0 { xs.append(x); ys.append(y); zs.append(z) }
      }
    }
    let validFraction = Double(zs.count) / Double(n * n)
    let accuracy = depthData.depthDataAccuracy == .absolute ? "absolute" : "relative"
    guard zs.count >= 30 else { return ["validFraction": validFraction, "accuracy": accuracy] }

    var sxx = 0.0, sxy = 0.0, syy = 0.0, sx = 0.0, sy = 0.0, sxz = 0.0, syz = 0.0, sz = 0.0
    let m = Double(zs.count)
    for k in 0..<zs.count {
      let x = xs[k], y = ys[k], z = zs[k]
      sxx += x * x; sxy += x * y; syy += y * y; sx += x; sy += y
      sxz += x * z; syz += y * z; sz += z
    }
    // Normal equations, solved with Cramer's rule.
    func det(_ a: [[Double]]) -> Double {
      a[0][0] * (a[1][1] * a[2][2] - a[1][2] * a[2][1])
        - a[0][1] * (a[1][0] * a[2][2] - a[1][2] * a[2][0])
        + a[0][2] * (a[1][0] * a[2][1] - a[1][1] * a[2][0])
    }
    let A = [[sxx, sxy, sx], [sxy, syy, sy], [sx, sy, m]]
    let B = [sxz, syz, sz]
    let d = det(A)
    let mean = sz / m
    guard abs(d) > 1e-12, mean > 0 else { return ["validFraction": validFraction, "meanDepth": mean, "accuracy": accuracy] }
    func replaced(_ col: Int) -> [[Double]] { A.enumerated().map { r, row in row.enumerated().map { c, v in c == col ? B[r] : v } } }
    let a = det(replaced(0)) / d, b = det(replaced(1)) / d, c = det(replaced(2)) / d

    var ss = 0.0
    for k in 0..<zs.count {
      let r = zs[k] - (a * xs[k] + b * ys[k] + c)
      ss += r * r
    }
    let sorted = zs.sorted()
    let p10 = sorted[Int(Double(sorted.count - 1) * 0.1)]
    let p90 = sorted[Int(Double(sorted.count - 1) * 0.9)]
    return [
      "validFraction": validFraction,
      "meanDepth": mean,
      "planeResidual": (ss / m).squareRoot() / mean,
      "depthSpread": (p90 - p10) / mean,
      "accuracy": accuracy,
    ]
  }

  static func resizedJPEG(_ image: UIImage, maxSide: CGFloat, quality: CGFloat) -> Data? {
    let size = image.size
    guard size.width > 0, size.height > 0 else { return nil }
    let scale = min(1, maxSide / max(size.width, size.height))
    let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: target))
    }
    return resized.jpegData(compressionQuality: quality)
  }

  private static func orientation(of url: URL) -> CGImagePropertyOrientation {
    guard
      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let raw = props[kCGImagePropertyOrientation] as? UInt32,
      let value = CGImagePropertyOrientation(rawValue: raw)
    else { return .up }
    return value
  }

  static func similarities(keywords: [String], labels: [String]) -> [String: [String: Double]] {
    guard let embedding = NLEmbedding.wordEmbedding(for: .english) else { return [:] }
    var cache: [String: [Double]?] = [:]
    func vector(_ phrase: String) -> [Double]? {
      if let cached = cache[phrase] { return cached }
      let words = phrase.lowercased().split(separator: " ").map(String.init)
      let vectors = words.compactMap { embedding.vector(for: $0) }
      var result: [Double]? = nil
      if !vectors.isEmpty {
        var sum = [Double](repeating: 0, count: vectors[0].count)
        for v in vectors { for i in 0..<sum.count { sum[i] += v[i] } }
        result = sum.map { $0 / Double(vectors.count) }
      }
      cache[phrase] = result
      return result
    }
    func cosine(_ a: [Double], _ b: [Double]) -> Double {
      var dot = 0.0, na = 0.0, nb = 0.0
      for i in 0..<min(a.count, b.count) { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
      return (na == 0 || nb == 0) ? 0 : dot / (na.squareRoot() * nb.squareRoot())
    }

    var out: [String: [String: Double]] = [:]
    for keyword in keywords {
      guard let kv = vector(keyword) else { continue }
      var row: [String: Double] = [:]
      for label in labels {
        guard let lv = vector(label) else { continue }
        row[label] = cosine(kv, lv)
      }
      if !row.isEmpty { out[keyword] = row }
    }
    return out
  }
}

// MARK: Depth camera UI

final class DepthCameraViewController: UIViewController, AVCapturePhotoCaptureDelegate {
  enum CameraError: LocalizedError {
    case setup, noImage
    var errorDescription: String? {
      switch self {
      case .setup: return "The camera couldn't start."
      case .noImage: return "The photo couldn't be saved."
      }
    }
  }

  static func depthDevice() -> AVCaptureDevice? {
    if #available(iOS 15.4, *), let lidar = AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back) {
      return lidar
    }
    return AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back)
      ?? AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back)
      ?? AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back)
  }

  var completion: (([String: Any]?, Error?) -> Void)?

  private let device: AVCaptureDevice
  private let session = AVCaptureSession()
  private let output = AVCapturePhotoOutput()
  private let sessionQueue = DispatchQueue(label: "org.famotive.depthcamera")
  private var previewLayer: AVCaptureVideoPreviewLayer?
  private let shutter = UIButton(type: .custom)
  private var finished = false

  init(device: AVCaptureDevice) {
    self.device = device
    super.init(nibName: nil, bundle: nil)
    modalPresentationStyle = .fullScreen
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var prefersStatusBarHidden: Bool { true }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black

    let preview = AVCaptureVideoPreviewLayer(session: session)
    preview.videoGravity = .resizeAspect
    view.layer.addSublayer(preview)
    previewLayer = preview

    shutter.translatesAutoresizingMaskIntoConstraints = false
    shutter.backgroundColor = .white
    shutter.layer.cornerRadius = 36
    shutter.layer.borderWidth = 5
    shutter.layer.borderColor = UIColor(white: 0.75, alpha: 1).cgColor
    shutter.accessibilityLabel = "Take Photo"
    shutter.isEnabled = false
    shutter.alpha = 0.5
    shutter.addTarget(self, action: #selector(takePhoto), for: .touchUpInside)
    view.addSubview(shutter)

    let cancel = UIButton(type: .system)
    cancel.translatesAutoresizingMaskIntoConstraints = false
    cancel.setTitle("Cancel", for: .normal)
    cancel.setTitleColor(.white, for: .normal)
    cancel.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
    cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
    view.addSubview(cancel)

    NSLayoutConstraint.activate([
      shutter.widthAnchor.constraint(equalToConstant: 72),
      shutter.heightAnchor.constraint(equalToConstant: 72),
      shutter.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      shutter.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
      cancel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
      cancel.centerYAnchor.constraint(equalTo: shutter.centerYAnchor),
    ])

    sessionQueue.async { self.configureSession() }
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    previewLayer?.frame = view.bounds
  }

  private func configureSession() {
    session.beginConfiguration()
    session.sessionPreset = .photo
    do {
      let input = try AVCaptureDeviceInput(device: device)
      guard session.canAddInput(input), session.canAddOutput(output) else { throw CameraError.setup }
      session.addInput(input)
      session.addOutput(output)
      output.isDepthDataDeliveryEnabled = output.isDepthDataDeliverySupported
      if let connection = output.connection(with: .video), connection.isVideoOrientationSupported {
        connection.videoOrientation = .portrait
      }
      session.commitConfiguration()
      session.startRunning()
      DispatchQueue.main.async {
        self.shutter.isEnabled = true
        self.shutter.alpha = 1
      }
    } catch {
      session.commitConfiguration()
      DispatchQueue.main.async { self.finish(nil, error) }
    }
  }

  @objc private func takePhoto() {
    shutter.isEnabled = false
    shutter.alpha = 0.5
    sessionQueue.async {
      let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
      settings.isDepthDataDeliveryEnabled = self.output.isDepthDataDeliveryEnabled
      settings.isDepthDataFiltered = true
      settings.embedsDepthDataInPhoto = false
      self.output.capturePhoto(with: settings, delegate: self)
    }
  }

  @objc private func cancelTapped() { finish(nil, nil) }

  func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
    if let error = error {
      DispatchQueue.main.async { self.finish(nil, error) }
      return
    }
    let depth = photo.depthData.flatMap { TaskPhotoVision.flatness(of: $0) }
    guard
      let data = photo.fileDataRepresentation(),
      let image = UIImage(data: data),
      let jpeg = TaskPhotoVision.resizedJPEG(image, maxSide: 1600, quality: 0.8)
    else {
      DispatchQueue.main.async { self.finish(nil, CameraError.noImage) }
      return
    }
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("famotive_proof_\(Int(Date().timeIntervalSince1970 * 1000)).jpg")
    do {
      try jpeg.write(to: url, options: .atomic)
    } catch {
      DispatchQueue.main.async { self.finish(nil, error) }
      return
    }
    var result: [String: Any] = ["path": url.path]
    if let depth = depth { result["depth"] = depth }
    DispatchQueue.main.async { self.finish(result, nil) }
  }

  private func finish(_ result: [String: Any]?, _ error: Error?) {
    guard !finished else { return }
    finished = true
    sessionQueue.async {
      if self.session.isRunning { self.session.stopRunning() }
    }
    let done: () -> Void = { self.completion?(result, error) }
    if presentingViewController != nil {
      dismiss(animated: true, completion: done)
    } else {
      done()
    }
  }
}
