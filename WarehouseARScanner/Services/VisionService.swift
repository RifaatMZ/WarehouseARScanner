import Foundation
import Vision
import CoreImage
import ImageIO
import UIKit

class VisionService {
    static let shared = VisionService()

    private let sequenceHandler = VNSequenceRequestHandler()
    var detectionCallback: ((DetectionResult) -> Void)?
    private var frameCounter = 0

    func processFrame(_ pixelBuffer: CVPixelBuffer) {
        frameCounter += 1

        // Only process every nth frame for performance
        guard frameCounter % Constants.processEveryNthFrame == 0 else { return }

        let request = VNRecognizeTextRequest(completionHandler: handleDetection)
        configure(request)

        do {
            try sequenceHandler.perform([request], on: pixelBuffer, orientation: currentCameraOrientation)
        } catch {
            Logger.shared.error("Vision request error: \(error)")
        }
    }

    func processImage(_ image: UIImage) async -> DetectionResult? {
        guard let cgImage = image.cgImage else {
            Logger.shared.error("Failed to get CGImage from UIImage")
            return nil
        }

        let request = VNRecognizeTextRequest()
        configure(request)

        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: image.cgImagePropertyOrientation,
            options: [:]
        )

        do {
            try handler.perform([request])

            if let results = request.results as? [VNRecognizedTextObservation] {
                let detections = results
                    .flatMap { observation in
                        observation.topCandidates(5).compactMap { candidate -> (text: String, confidence: Float, bounds: CGRect)? in
                            guard let labelText = LabelParser.parseLabelText(candidate.string) else {
                                Logger.shared.debug("Ignoring unparsed OCR text: '\(candidate.string)'")
                                return nil
                            }

                            let confidence = Float(candidate.confidence * observation.confidence)
                            guard confidence >= Constants.ocrConfidenceThreshold else {
                                return nil
                            }

                            return (
                                text: labelText,
                                confidence: confidence,
                                bounds: observation.boundingBox
                            )
                        }
                    }
                    .sorted { $0.confidence > $1.confidence }

                if let topDetection = detections.first {
                    Logger.shared.debug("Image recognition: '\(topDetection.text)' (\(topDetection.confidence.percentageString))")

                    let result = DetectionResult(
                        detectedText: topDetection.text,
                        bounds: topDetection.bounds,
                        confidence: topDetection.confidence,
                        frameNumber: frameCounter,
                        timestamp: Date()
                    )
                    return result
                }
            }
        } catch {
            Logger.shared.error("Image processing error: \(error)")
        }

        return nil
    }

    private func handleDetection(request: VNRequest, error: Error?) {
        if let error = error {
            Logger.shared.warning("Text recognition error: \(error)")
            return
        }

        guard let results = request.results as? [VNRecognizedTextObservation] else {
            return
        }

        for observation in results {
            let candidates = observation.topCandidates(5)

            for candidate in candidates {
                guard let labelText = LabelParser.parseLabelText(candidate.string) else {
                    continue
                }

                let confidence = Float(candidate.confidence * observation.confidence)

                if confidence >= Constants.ocrConfidenceThreshold {
                    let detection = DetectionResult(
                        detectedText: labelText,
                        bounds: observation.boundingBox,
                        confidence: confidence,
                        frameNumber: frameCounter,
                        timestamp: Date()
                    )

                    DispatchQueue.main.async {
                        self.detectionCallback?(detection)
                    }

                    Logger.shared.debug("Detected text: '\(labelText)' (\(confidence.percentageString))")
                }
            }
        }
    }

    private func configure(_ request: VNRecognizeTextRequest) {
        request.recognitionLevel = Constants.visionRecognitionLevel
        request.recognitionLanguages = Constants.visionLanguages
        request.usesLanguageCorrection = false
    }

    private var currentCameraOrientation: CGImagePropertyOrientation {
        switch UIDevice.current.orientation {
        case .landscapeLeft:
            return .up
        case .landscapeRight:
            return .down
        case .portraitUpsideDown:
            return .left
        default:
            return .right
        }
    }
}

private extension UIImage {
    var cgImagePropertyOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up:
            return .up
        case .upMirrored:
            return .upMirrored
        case .down:
            return .down
        case .downMirrored:
            return .downMirrored
        case .left:
            return .left
        case .leftMirrored:
            return .leftMirrored
        case .right:
            return .right
        case .rightMirrored:
            return .rightMirrored
        @unknown default:
            return .up
        }
    }
}
