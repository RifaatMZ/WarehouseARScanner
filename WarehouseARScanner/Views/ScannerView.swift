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
                            Text("\(scanViewModel.detectedLabels.count)")
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

                Spacer()

                VStack(spacing: 12) {
                    if let currentLabel = scanViewModel.currentARLabel {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Current Detection")
                                    .font(.caption)
                                    .foregroundColor(.gray)

                                Text(currentLabel.text)
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)

                                Text("Confidence: \(currentLabel.confidence.percentageString)")
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
}

#Preview {
    ScannerView(scanViewModel: ScanViewModel(), inventoryViewModel: InventoryViewModel())
}
