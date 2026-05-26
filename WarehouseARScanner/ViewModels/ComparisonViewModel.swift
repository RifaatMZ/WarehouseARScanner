import Foundation
import Combine

class ComparisonViewModel: ObservableObject {
    @Published var arResult: StorageLabel?
    @Published var paperResult: StorageLabel?
    @Published var comparisonResult: ComparisonResult?
    @Published var isMatching: Bool = false

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
        comparisonResult = nil
    }
}
