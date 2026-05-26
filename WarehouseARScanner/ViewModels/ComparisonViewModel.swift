import Foundation
import Combine

class ComparisonViewModel: ObservableObject {
    @Published var arResult: StorageLabel?
    @Published var paperResult: StorageLabel?
    @Published var paperRecords: [WarehouseRecord] = []
    @Published var comparisonResult: ComparisonResult?
    @Published var isMatching: Bool = false

    func verificationResults(for shelfRecords: [WarehouseRecord]) -> [VerificationResult] {
        let shelfRecordsByPair = recordsByPair(shelfRecords)
        let paperRecordsByPair = recordsByPair(paperRecords)

        let paperResults = paperRecords.map { paperRecord in
            VerificationResult(
                paperRecord: paperRecord,
                shelfRecord: shelfRecordsByPair[paperRecord.verificationKey]
            )
        }

        let extraShelfResults = shelfRecords
            .filter { paperRecordsByPair[$0.verificationKey] == nil }
            .map { shelfRecord in
                VerificationResult(paperRecord: nil, shelfRecord: shelfRecord)
            }

        return paperResults + extraShelfResults
    }

    func verificationResult(for paperRecord: WarehouseRecord, shelfRecords: [WarehouseRecord]) -> VerificationResult {
        VerificationResult(
            paperRecord: paperRecord,
            shelfRecord: shelfRecords.first { $0.verificationKey == paperRecord.verificationKey }
        )
    }

    func appendPaperRecords(_ records: [WarehouseRecord]) {
        for record in records {
            if !paperRecords.contains(where: { $0.verificationKey == record.verificationKey }) {
                paperRecords.append(record)
            }
        }
    }

    private func recordsByPair(_ records: [WarehouseRecord]) -> [String: WarehouseRecord] {
        records.reduce(into: [:]) { result, record in
            result[record.verificationKey] = record
        }
    }

    func compareScan(arLabel: StorageLabel, paperLabel: StorageLabel) {
        DispatchQueue.main.async {
            self.isMatching = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let match = arLabel.text == paperLabel.text
            let confidence = (arLabel.confidence + paperLabel.confidence) / 2

            let comparison = ComparisonResult(
                arLabel: arLabel.text,
                paperLabel: paperLabel.text,
                match: match,
                confidence: confidence,
                timestamp: Date()
            )

            self.arResult = arLabel
            self.paperResult = paperLabel
            self.comparisonResult = comparison
            self.isMatching = false

            let result = match ? "✓ Match" : "✗ Mismatch"
            Logger.shared.info("Comparison: \(result) - AR: '\(arLabel.text)' vs Paper: '\(paperLabel.text)'")
        }
    }

    func clearComparison() {
        arResult = nil
        paperResult = nil
        paperRecords.removeAll()
        comparisonResult = nil
    }
}
