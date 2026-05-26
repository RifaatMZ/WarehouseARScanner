import SwiftUI

struct ResultsView: View {
    @ObservedObject var scanViewModel: ScanViewModel
    @ObservedObject var inventoryViewModel: InventoryViewModel
    @ObservedObject var comparisonViewModel: ComparisonViewModel
    @State private var lastVerifiedAt: Date?

    var body: some View {
        NavigationView {
            VStack {
                if scanViewModel.shelfRecords.isEmpty && comparisonViewModel.paperRecords.isEmpty && inventoryViewModel.matchedItems.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)

                        Text("No Results Yet")
                            .font(.headline)

                        Text("Scan warehouse labels or check inventory to see results here")
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                } else {
                    List {
                        if !comparisonViewModel.paperRecords.isEmpty || !scanViewModel.shelfRecords.isEmpty {
                            Section("Verification Summary") {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Label("\(matchingResultCount)", systemImage: "checkmark.circle.fill")
                                            .foregroundColor(.green)

                                        Spacer()

                                        Label("\(pendingResultCount)", systemImage: "questionmark.circle.fill")
                                            .foregroundColor(.orange)

                                        Spacer()

                                        Label("\(failedResultCount)", systemImage: "xmark.circle.fill")
                                            .foregroundColor(.red)
                                    }
                                    .font(.caption)

                                    if let lastVerifiedAt {
                                        Text("Verified \(lastVerifiedAt.shortTimeAgo)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("Results update as shelf records are scanned. Tap Verify to mark the current scan set.")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }

                        if !scanViewModel.shelfRecords.isEmpty {
                            Section("Scanned Shelf Records") {
                                ForEach(scanViewModel.shelfRecords) { record in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(record.location)
                                                .font(.headline)
                                                .monospacedDigit()

                                            Spacer()

                                            Text(record.confidence.percentageString)
                                                .font(.caption)
                                                .padding(4)
                                                .background(
                                                    record.confidence >= Constants.confidenceThreshold ?
                                                    Color.green.opacity(0.3) : Color.orange.opacity(0.3)
                                                )
                                                .cornerRadius(4)
                                        }

                                        Text("Item: \(record.itemNumber)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .monospacedDigit()

                                        Text(record.timestamp.formatted(style: .short))
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }

                        if !comparisonViewModel.paperRecords.isEmpty {
                            Section("Paper Records") {
                                ForEach(comparisonViewModel.paperRecords) { record in
                                    let result = comparisonViewModel.verificationResult(
                                        for: record,
                                        shelfRecords: scanViewModel.shelfRecords
                                    )

                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(record.itemNumber)
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                                .monospacedDigit()

                                            Spacer()

                                            Text(record.location)
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                                .monospacedDigit()
                                        }

                                        Text(resultStatusText(for: result))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 8)
                                    .background(resultColor(for: result))
                                    .cornerRadius(6)
                                }
                            }

                            Section("Verification") {
                                ForEach(comparisonViewModel.verificationResults(for: scanViewModel.shelfRecords)) { result in
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Image(systemName: result.matches ? "checkmark.circle.fill" : "xmark.circle.fill")
                                                .foregroundColor(result.matches ? .green : .red)

                                            Text(result.itemNumber)
                                                .font(.headline)
                                                .monospacedDigit()

                                            Spacer()
                                        }

                                        Text(result.statusText)
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundColor(result.matches ? .green : .red)

                                        HStack {
                                            Text("Paper: \(result.expectedLocation)")
                                            Spacer()
                                            Text("Shelf: \(result.actualLocation)")
                                        }
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .monospacedDigit()
                                    }
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                    .background(resultColor(for: result))
                                    .cornerRadius(6)
                                }
                            }
                        }

                        if !inventoryViewModel.matchedItems.isEmpty {
                            Section("Inventory Matches") {
                                ForEach(inventoryViewModel.matchedItems) { item in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(item.formattedLocation)
                                                .font(.headline)
                                                .monospacedDigit()

                                            Spacer()

                                            HStack(spacing: 4) {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(.green)

                                                Text(item.confidence.percentageString)
                                                    .font(.caption)
                                            }
                                        }

                                        Text(item.description)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)

                                        HStack(spacing: 12) {
                                            Label("Qty: \(item.quantity)", systemImage: "cube.fill")
                                                .font(.caption2)

                                            Spacer()

                                            Text("Updated: \(item.lastUpdated.shortTimeAgo)")
                                                .font(.caption2)
                                                .foregroundColor(.gray)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }

                        if let comparisonResult = comparisonViewModel.comparisonResult {
                            Section("Comparison Result") {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("AR Scan")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                            Text(comparisonResult.arLabel)
                                                .font(.headline)
                                                .monospacedDigit()
                                        }

                                        Spacer()

                                        Image(systemName: comparisonResult.match ? "checkmark" : "xmark")
                                            .font(.title2)
                                            .foregroundColor(comparisonResult.match ? .green : .red)

                                        Spacer()

                                        VStack(alignment: .trailing, spacing: 4) {
                                            Text("Paper Scan")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                            Text(comparisonResult.paperLabel)
                                                .font(.headline)
                                                .monospacedDigit()
                                        }
                                    }

                                    HStack {
                                        Text(comparisonResult.description)
                                            .font(.subheadline)
                                            .fontWeight(.bold)
                                            .foregroundColor(comparisonResult.match ? .green : .red)

                                        Spacer()

                                        Text(comparisonResult.confidenceDescription)
                                            .font(.caption)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }

                        if let errorMessage = inventoryViewModel.errorMessage {
                            Section("Error") {
                                Text(errorMessage)
                                    .foregroundColor(.red)
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(action: {
                            lastVerifiedAt = Date()
                        }) {
                            Label("Verify Now", systemImage: "checkmark.seal")
                        }

                        Button(action: {
                            scanViewModel.clearDetections()
                            inventoryViewModel.clearResults()
                            comparisonViewModel.clearComparison()
                            lastVerifiedAt = nil
                        }) {
                            Label("Clear All", systemImage: "trash")
                        }

                        Button(action: {
                            let text = generateReport()
                            UIPasteboard.general.string = text
                        }) {
                            Label("Copy Report", systemImage: "doc.on.clipboard")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }

    private func generateReport() -> String {
        var report = "WarehouseARScanner Report\n"
        report += "=======================\n\n"

        report += "Detected Labels: \(scanViewModel.detectedLabels.count)\n"
        for label in scanViewModel.detectedLabels {
            report += "  - \(label.text) (\(label.confidence.percentageString))\n"
        }

        report += "\nScanned Shelf Records: \(scanViewModel.shelfRecords.count)\n"
        for record in scanViewModel.shelfRecords {
            report += "  - \(record.location): \(record.itemNumber) (\(record.confidence.percentageString))\n"
        }

        report += "\nPaper Records: \(comparisonViewModel.paperRecords.count)\n"
        for record in comparisonViewModel.paperRecords {
            report += "  - \(record.itemNumber): \(record.location)\n"
        }

        let verificationResults = comparisonViewModel.verificationResults(for: scanViewModel.shelfRecords)
        if !verificationResults.isEmpty {
            report += "\nVerification:\n"
            for result in verificationResults {
                let status = result.matches ? "MATCH" : "MISMATCH"
                report += "  - \(result.itemNumber): \(status) paper=\(result.expectedLocation), shelf=\(result.actualLocation)\n"
            }
        }

        report += "\nMatched Items: \(inventoryViewModel.matchedItems.count)\n"
        for item in inventoryViewModel.matchedItems {
            report += "  - \(item.formattedLocation): \(item.description) (Qty: \(item.quantity))\n"
        }

        if let comparison = comparisonViewModel.comparisonResult {
            report += "\nComparison: \(comparison.description)\n"
            report += "  AR: \(comparison.arLabel)\n"
            report += "  Paper: \(comparison.paperLabel)\n"
        }

        return report
    }

    private var currentVerificationResults: [VerificationResult] {
        comparisonViewModel.verificationResults(for: scanViewModel.shelfRecords)
    }

    private var matchingResultCount: Int {
        currentVerificationResults.filter(\.matches).count
    }

    private var pendingResultCount: Int {
        guard scanViewModel.shelfRecords.isEmpty else {
            return 0
        }

        return comparisonViewModel.paperRecords.count
    }

    private var failedResultCount: Int {
        currentVerificationResults.filter { !$0.matches }.count - pendingResultCount
    }

    private func resultColor(for result: VerificationResult) -> Color {
        if result.matches {
            return Color.green.opacity(0.18)
        }

        if scanViewModel.shelfRecords.isEmpty && result.shelfRecord == nil {
            return Color.yellow.opacity(0.22)
        }

        return Color.red.opacity(0.18)
    }

    private func resultStatusText(for result: VerificationResult) -> String {
        if scanViewModel.shelfRecords.isEmpty && result.shelfRecord == nil {
            return "Waiting for AR shelf scan"
        }

        return result.statusText
    }
}

#Preview {
    ResultsView(
        scanViewModel: ScanViewModel(),
        inventoryViewModel: InventoryViewModel(),
        comparisonViewModel: ComparisonViewModel()
    )
}
