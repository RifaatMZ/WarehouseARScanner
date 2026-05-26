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

struct WarehouseRecord: Identifiable, Equatable {
    let id = UUID()
    let location: String
    let itemNumber: String
    let confidence: Float
    let timestamp: Date

    var displayText: String {
        "\(location)  \(itemNumber)"
    }

    var verificationKey: String {
        "\(location)|\(itemNumber)"
    }
}

struct LiveScanFeedback {
    let recognizedLines: [String]
    let records: [WarehouseRecord]
    let focusBounds: CGRect?
    let timestamp: Date

    var previewText: String {
        if !records.isEmpty {
            return records.map(\.displayText).joined(separator: "\n")
        }

        if recognizedLines.isEmpty {
            return "No text found"
        }

        return recognizedLines.prefix(3).joined(separator: "\n")
    }

    var isRecognizingRecord: Bool {
        !records.isEmpty
    }
}

struct VerificationResult: Identifiable {
    let id = UUID()
    let paperRecord: WarehouseRecord?
    let shelfRecord: WarehouseRecord?

    var matches: Bool {
        guard let paperRecord, let shelfRecord else {
            return false
        }

        return paperRecord.verificationKey == shelfRecord.verificationKey
    }

    var itemNumber: String {
        paperRecord?.itemNumber ?? shelfRecord?.itemNumber ?? ""
    }

    var expectedLocation: String {
        paperRecord?.location ?? "Not on paper"
    }

    var actualLocation: String {
        shelfRecord?.location ?? "Not scanned"
    }

    var statusText: String {
        if matches {
            return "Match"
        } else if paperRecord == nil {
            return "On shelf, not on paper"
        } else if shelfRecord == nil {
            return "On paper, not on shelf"
        } else {
            return "Location/item mismatch"
        }
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
