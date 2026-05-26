import Foundation
import Combine
import Vision

class ScanViewModel: NSObject, ObservableObject {
    @Published var detectedLabels: [StorageLabel] = []
    @Published var currentARLabel: StorageLabel?
    @Published var isScanning: Bool = false
    @Published var averageConfidence: Float = 0
    @Published var lastDetectionTime: Date?
    @Published var errorMessage: String?

    private var cancellables = Set<AnyCancellable>()
    private let visionService = VisionService.shared
    private var detectionCache: [String: StorageLabel] = [:]

    override init() {
        super.init()
        setupVisionCallback()
    }

    private func setupVisionCallback() {
        visionService.detectionCallback = { [weak self] detection in
            self?.processDetection(detection)
        }
    }

    func startScanning() {
        isScanning = true
        errorMessage = nil
        Logger.shared.info("Started AR scanning")
    }

    func stopScanning() {
        isScanning = false
        Logger.shared.info("Stopped AR scanning")
    }

    private func processDetection(_ detection: DetectionResult) {
        guard isScanning else { return }

        if detection.confidence < Constants.ocrConfidenceThreshold {
            Logger.shared.debug("Low confidence detection: \(detection.detectedText) (\(detection.confidence.percentageString))")
            return
        }

        if let formatted = LabelParser.parseLabelText(detection.detectedText) {

            // Avoid duplicate detections in short time window
            if let cached = detectionCache[formatted],
               cached.detectionTime.timeIntervalSinceNow > -1.0 {
                return
            }

            let label = StorageLabel(
                text: formatted,
                confidence: detection.confidence,
                detectionTime: detection.timestamp
            )

            DispatchQueue.main.async {
                self.currentARLabel = label

                // Add to list if not already present
                if !self.detectedLabels.contains(where: { $0.text == formatted }) {
                    self.detectedLabels.append(label)
                }

                self.detectionCache[formatted] = label
                self.lastDetectionTime = Date()
                self.updateAverageConfidence()

                Logger.shared.info("Detection: \(formatted) with confidence \(detection.confidence.percentageString)")
            }
        }
    }

    private func updateAverageConfidence() {
        guard !detectedLabels.isEmpty else {
            averageConfidence = 0
            return
        }
        averageConfidence = detectedLabels.map { $0.confidence }.reduce(0, +) / Float(detectedLabels.count)
    }

    func clearDetections() {
        detectedLabels.removeAll()
        detectionCache.removeAll()
        currentARLabel = nil
        averageConfidence = 0
        lastDetectionTime = nil
    }
}
