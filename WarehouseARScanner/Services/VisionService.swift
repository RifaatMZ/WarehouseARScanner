import Foundation
import Vision
import CoreImage
import ImageIO
import UIKit

class VisionService {
    static let shared = VisionService()

    private let sequenceHandler = VNSequenceRequestHandler()
    var detectionCallback: ((DetectionResult) -> Void)?
    var liveFeedbackCallback: ((LiveScanFeedback) -> Void)?
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
        guard let record = await processImageRecords(image).first else {
            return nil
        }

        return DetectionResult(
            detectedText: record.displayText,
            bounds: .zero,
            confidence: record.confidence,
            frameNumber: frameCounter,
            timestamp: record.timestamp
        )
    }

    func processImageRecords(_ image: UIImage) async -> [WarehouseRecord] {
        guard let cgImage = image.cgImage else {
            Logger.shared.error("Failed to get CGImage from UIImage")
            return []
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
                let recognizedLines = recognizedTextLines(from: results)
                let records = LabelParser.parseInventoryRecords(from: recognizedLines.joined(separator: "\n"))
                Logger.shared.debug("Image records: \(records.map(\.displayText).joined(separator: ", "))")
                return records
            }
        } catch {
            Logger.shared.error("Image processing error: \(error)")
        }

        return []
    }

    private func handleDetection(request: VNRequest, error: Error?) {
        if let error = error {
            Logger.shared.warning("Text recognition error: \(error)")
            return
        }

        guard let results = request.results as? [VNRecognizedTextObservation] else {
            return
        }

        let recognizedLines = recognizedTextLines(from: results)
        let positionedRecords = positionedRecords(from: results)
        let records = positionedRecords.isEmpty ?
            LabelParser.parseInventoryRecords(from: recognizedLines.joined(separator: "\n")) :
            positionedRecords.map(\.record)
        let feedback = LiveScanFeedback(
            recognizedLines: recognizedLines,
            records: records,
            focusBounds: combinedBounds(for: positionedRecords.map(\.bounds)),
            timestamp: Date()
        )

        DispatchQueue.main.async {
            self.liveFeedbackCallback?(feedback)
        }

        let detectionRecords: [(record: WarehouseRecord, bounds: CGRect)] = positionedRecords.isEmpty ?
            records.map { ($0, .zero) } :
            positionedRecords

        for positionedRecord in detectionRecords where positionedRecord.record.confidence >= Constants.ocrConfidenceThreshold {
            let record = positionedRecord.record
            let detection = DetectionResult(
                detectedText: record.displayText,
                bounds: positionedRecord.bounds,
                confidence: record.confidence,
                frameNumber: frameCounter,
                timestamp: record.timestamp
            )

            DispatchQueue.main.async {
                self.detectionCallback?(detection)
            }

            Logger.shared.debug("Detected shelf record: '\(record.displayText)' (\(record.confidence.percentageString))")
        }
    }

    private func configure(_ request: VNRecognizeTextRequest) {
        request.recognitionLevel = Constants.visionRecognitionLevel
        request.recognitionLanguages = Constants.visionLanguages
        request.usesLanguageCorrection = false
    }

    private func recognizedTextLines(from observations: [VNRecognizedTextObservation]) -> [String] {
        observations.compactMap { observation in
            observation.topCandidates(1).first?.string
        }
    }

    private func positionedRecords(from observations: [VNRecognizedTextObservation]) -> [(record: WarehouseRecord, bounds: CGRect)] {
        observations.compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string,
                  let record = LabelParser.parseWarehouseRecord(text) else {
                return nil
            }

            return (record, observation.boundingBox)
        }
    }

    private func combinedBounds(for bounds: [CGRect]) -> CGRect? {
        guard let firstBounds = bounds.first else {
            return nil
        }

        return bounds.dropFirst().reduce(firstBounds) { partialResult, bounds in
            partialResult.union(bounds)
        }
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
