import SwiftUI

struct ResultsView: View {
    @ObservedObject var scanViewModel: ScanViewModel
    @ObservedObject var inventoryViewModel: InventoryViewModel
    @ObservedObject var comparisonViewModel: ComparisonViewModel

    var body: some View {
        NavigationView {
            VStack {
                if scanViewModel.detectedLabels.isEmpty && inventoryViewModel.matchedItems.isEmpty {
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
                        if !scanViewModel.detectedLabels.isEmpty {
                            Section("Detected Labels") {
                                ForEach(scanViewModel.detectedLabels) { label in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(label.text)
                                                .font(.headline)

                                            Spacer()

                                            Text(label.confidence.percentageString)
                                                .font(.caption)
                                                .padding(4)
                                                .background(
                                                    label.confidence >= Constants.confidenceThreshold ?
                                                    Color.green.opacity(0.3) : Color.orange.opacity(0.3)
                                                )
                                                .cornerRadius(4)
                                        }

                                        if let components = label.parsedComponents {
                                            HStack(spacing: 12) {
                                                Label(components.section, systemImage: "rectangle.fill")
                                                Label(components.row, systemImage: "rectangle.fill")
                                                Label(components.column, systemImage: "rectangle.fill")
                                            }
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        }

                                        Text(label.detectionTime.formatted(style: .short))
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                    }
                                    .padding(.vertical, 4)
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
                            scanViewModel.clearDetections()
                            inventoryViewModel.clearResults()
                            comparisonViewModel.clearComparison()
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
}

#Preview {
    ResultsView(
        scanViewModel: ScanViewModel(),
        inventoryViewModel: InventoryViewModel(),
        comparisonViewModel: ComparisonViewModel()
    )
}
