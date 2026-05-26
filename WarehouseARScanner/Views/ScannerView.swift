import SwiftUI

struct ScannerView: View {
    @ObservedObject var scanViewModel: ScanViewModel
    @ObservedObject var inventoryViewModel: InventoryViewModel

    @State private var showCheckAlert = false
    @State private var isCheckingInventory = false

    var body: some View {
        ZStack {
            ARViewContainer(scanViewModel: scanViewModel)
                .ignoresSafeArea()

            floatingRecognitionOverlay

            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AR Scanning")
                            .font(.headline)
                            .foregroundColor(.white)

                        if let lastTime = scanViewModel.lastDetectionTime {
                            Text("Last: \(lastTime.shortTimeAgo)")
                                .font(.caption)
                                .foregroundColor(.gray)
                        } else {
                            Text("Ready to scan")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "square.stack.fill")
                                .font(.caption)
                            Text("\(scanViewModel.shelfRecords.count)")
                        }
                        .font(.caption)
                        .foregroundColor(.white)

                        Text(scanViewModel.averageConfidence.confidenceDescription)
                            .font(.caption)
                            .foregroundColor(
                                scanViewModel.averageConfidence >= Constants.confidenceThreshold ? .green : .orange
                            )
                    }
                }
                .padding()
                .background(Color.black.opacity(0.5))
                .cornerRadius(10)
                .padding()

                liveFeedbackPanel

                Spacer()

                VStack(spacing: 12) {
                    if let currentRecord = scanViewModel.currentShelfRecord {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Current Detection")
                                    .font(.caption)
                                    .foregroundColor(.gray)

                                Text(currentRecord.location)
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)

                                Text("Item: \(currentRecord.itemNumber)")
                                    .font(.caption)
                                    .foregroundColor(.white)

                                Text("Confidence: \(currentRecord.confidence.percentageString)")
                                    .font(.caption2)
                                    .foregroundColor(.cyan)
                            }
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title)
                                .foregroundColor(.green)
                        }
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(10)
                        .padding()
                    }

                    HStack(spacing: 12) {
                        Button(action: {
                            if scanViewModel.isScanning {
                                scanViewModel.stopScanning()
                            } else {
                                scanViewModel.startScanning()
                            }
                        }) {
                            HStack {
                                Image(systemName: scanViewModel.isScanning ? "pause.circle.fill" : "play.circle.fill")
                                Text(scanViewModel.isScanning ? "Pause" : "Start Scanning")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(scanViewModel.isScanning ? Color.orange : Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }

                        Button(action: {
                            isCheckingInventory = true
                            Task {
                                await inventoryViewModel.checkInventory(for: scanViewModel.detectedLabels)
                                isCheckingInventory = false
                                showCheckAlert = true
                            }
                        }) {
                            Image(systemName: "magnifyingglass.circle.fill")
                                .frame(width: 50, height: 50)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .disabled(scanViewModel.detectedLabels.isEmpty || isCheckingInventory)

                        Button(action: {
                            scanViewModel.clearDetections()
                            inventoryViewModel.clearResults()
                        }) {
                            Image(systemName: "trash.circle.fill")
                                .frame(width: 50, height: 50)
                                .background(Color.red.opacity(0.7))
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                    .padding()
                }
            }
        }
        .alert("Inventory Check", isPresented: $showCheckAlert) {
            Button("OK") {}
        } message: {
            if let error = inventoryViewModel.errorMessage {
                Text("Error: \(error)")
            } else {
                Text("\(inventoryViewModel.matchedItems.count) items matched")
            }
        }
    }

    private var liveFeedbackPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: liveFeedbackIconName)
                    .foregroundColor(liveFeedbackColor)

                Text(liveFeedbackTitle)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Spacer()

                if let feedback = scanViewModel.liveFeedback {
                    Text(feedback.timestamp.shortTimeAgo)
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }

            Text(liveFeedbackText)
                .font(.caption)
                .foregroundColor(.white)
                .monospacedDigit()
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color.black.opacity(0.65))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(liveFeedbackColor.opacity(0.8), lineWidth: 1)
        )
        .cornerRadius(10)
        .padding(.horizontal)
    }

    private var floatingRecognitionOverlay: some View {
        GeometryReader { geometry in
            if let feedback = scanViewModel.liveFeedback,
               let bounds = feedback.focusBounds,
               let record = feedback.records.first {
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.location)
                        .font(.caption)
                        .fontWeight(.bold)
                        .monospacedDigit()

                    Text(record.itemNumber)
                        .font(.caption2)
                        .monospacedDigit()
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(Color.green.opacity(0.82))
                .foregroundColor(.white)
                .cornerRadius(8)
                .shadow(radius: 4)
                .position(floatingBadgePosition(for: bounds, in: geometry.size))
            }
        }
        .allowsHitTesting(false)
    }

    private func floatingBadgePosition(for bounds: CGRect, in size: CGSize) -> CGPoint {
        let rawX = (bounds.maxX * size.width) + 70
        let rawY = (1 - bounds.midY) * size.height
        let clampedX = min(max(rawX, 80), size.width - 80)
        let clampedY = min(max(rawY, 100), size.height - 170)

        return CGPoint(x: clampedX, y: clampedY)
    }

    private var liveFeedbackTitle: String {
        guard scanViewModel.isScanning else {
            return "Scanner paused"
        }

        guard let feedback = scanViewModel.liveFeedback else {
            return "Looking for shelf labels"
        }

        return feedback.isRecognizingRecord ? "Shelf record recognized" : "Text seen, no record yet"
    }

    private var liveFeedbackText: String {
        guard scanViewModel.isScanning else {
            return "Tap Start Scanning to resume OCR."
        }

        return scanViewModel.liveFeedback?.previewText ?? "Point the camera at a location label and item number."
    }

    private var liveFeedbackIconName: String {
        guard scanViewModel.isScanning else {
            return "pause.circle.fill"
        }

        guard let feedback = scanViewModel.liveFeedback else {
            return "viewfinder.circle"
        }

        return feedback.isRecognizingRecord ? "checkmark.circle.fill" : "text.viewfinder"
    }

    private var liveFeedbackColor: Color {
        guard scanViewModel.isScanning else {
            return .orange
        }

        guard let feedback = scanViewModel.liveFeedback else {
            return .gray
        }

        return feedback.isRecognizingRecord ? .green : .yellow
    }
}

#Preview {
    ScannerView(scanViewModel: ScanViewModel(), inventoryViewModel: InventoryViewModel())
}
