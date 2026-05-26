import Foundation
import CoreGraphics

struct DetectionResult: Identifiable {
    let id = UUID()
    let detectedText: String
    let bounds: CGRect
    let confidence: Float
    let frameNumber: Int
    let timestamp: Date

    var isHighConfidence: Bool {
        confidence >= Constants.confidenceThreshold
    }

    var formattedConfidence: String {
        confidence.percentageString
    }
}

struct ComparisonResult: Identifiable {
    let id = UUID()
    let arLabel: String
    let paperLabel: String
    let match: Bool
    let confidence: Float
    let timestamp: Date

    var description: String {
        match ? "Labels match ✓" : "Labels don't match ✗"
    }

    var confidenceDescription: String {
        confidence.confidenceDescription
    }
}

struct ScanSession: Identifiable {
    let id = UUID()
    let startTime: Date
    var detections: [DetectionResult] = []
    var inventoryItems: [MatchedInventoryItem] = []
    var comparisonResult: ComparisonResult?

    var endTime: Date?
    var durationSeconds: Int? {
        guard let endTime else { return nil }
        return Int(endTime.timeIntervalSince(startTime))
    }

    mutating func addDetection(_ detection: DetectionResult) {
        detections.append(detection)
    }

    mutating func endSession() {
        endTime = Date()
    }
}
