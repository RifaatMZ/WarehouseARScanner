import SwiftUI

struct ScannerView: View {
    @ObservedObject var scanViewModel: ScanViewModel
    @ObservedObject var inventoryViewModel: InventoryViewModel

    @State private var showCheckAlert = false
    @State private var isCheckingInventory = false
    @State private var showSettings = false
    @State private var autoPauseEnabled: Bool = Constants.autoPauseAfterValidCapture

    var body: some View {
        ZStack {
            ARViewContainer(scanViewModel: scanViewModel)
                .ignoresSafeArea()

            floatingRecognitionOverlay

            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(scanViewModel.isScanning ? "AR Scanning" : "Paused")
                            .font(.headline)
                            .foregroundColor(scanViewModel.isScanning ? .white : .orange)

                        if let lastTime = scanViewModel.lastDetectionTime {
                            Text("Last detection: \(lastTime.shortTimeAgo)")
                                .font(.caption)
                                .foregroundColor(.gray)
                        } else {
                            Text("Point camera at warehouse labels")
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

                    // Gear button
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.title3)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.leading, 12)
                }
                .padding()
                .background(Color.black.opacity(0.5))
                .cornerRadius(10)
                .padding(.horizontal)
                .padding(.top, 8)

                // === Warehouse Guidance Banner (anticipation + miss warning) ===
                if let warehouse = scanViewModel.activeWarehouse {
                    VStack(spacing: 4) {
                        HStack {
                            Image(systemName: "map")
                            Text("Map: \(warehouse.name)")
                                .fontWeight(.semibold)
                            Spacer()
                            Text("\(warehouse.totalLocations) positions")
                                .font(.caption)
                        }
                        .foregroundColor(.white)

                        if let next = scanViewModel.nextExpectedWarehouseLocation {
                            HStack {
                                Text("Next expected:")
                                Text(next.formattedLocation)
                                    .fontWeight(.bold)
                                    .monospacedDigit()
                                    .foregroundColor(.yellow)
                                Spacer()
                            }
                        }

                        if let msg = scanViewModel.errorMessage, msg.hasPrefix("Missed") {
                            Text(msg)
                                .font(.caption)
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(8)
                    .background(Color.black.opacity(0.75))
                    .cornerRadius(8)
                    .padding(.horizontal)
                } else {
                    // Prompt to use the new dedicated Warehouses tab
                    VStack(spacing: 2) {
                        Text("No warehouse map active")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text("Switch to the Warehouses tab to select or create one before scanning.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(8)
                    .padding(.horizontal)
                }

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
                            Image(systemName: "eye.fill")
                                .font(.title)
                                .foregroundColor(.cyan)
                        }
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(10)
                        .padding()
                    }

                    HStack(spacing: 12) {
                        Button(action: {
                            if scanViewModel.isScanning {
                                scanViewModel.pauseARSession()
                            } else {
                                scanViewModel.startARSession()
                            }
                        }) {
                            HStack {
                                Image(systemName: scanViewModel.isScanning ? "pause.circle.fill" : "play.circle.fill")
                                Text(buttonTitle)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(buttonColor)
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
        .sheet(isPresented: $showSettings) {
            CaptureSettingsSheet(autoPauseEnabled: $autoPauseEnabled, scanViewModel: scanViewModel)
                .onDisappear {
                    // Persist the choice when the sheet closes
                    Constants.autoPauseAfterValidCapture = autoPauseEnabled
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
            // Only show live floating AR badge while actively scanning
            if scanViewModel.isScanning,
               let feedback = scanViewModel.liveFeedback,
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
            return "Scanning is paused. Tap Resume Scanning to continue."
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

    // Button text for continuous scanning mode (with deduplication)
    private var buttonTitle: String {
        scanViewModel.isScanning ? "Pause" : "Resume Scanning"
    }

    private var buttonColor: Color {
        scanViewModel.isScanning ? .orange : .green
    }
}

#Preview {
    ScannerView(scanViewModel: ScanViewModel(), inventoryViewModel: InventoryViewModel())
}

// MARK: - Settings Sheet

struct CaptureSettingsSheet: View {
    @Binding var autoPauseEnabled: Bool
    @ObservedObject var scanViewModel: ScanViewModel
    @Environment(\.dismiss) private var dismiss

    // Basic range configuration (user said rough UI is acceptable)
    @State private var range: WarehouseLabelRange = WarehouseLabelRange.load()
    @State private var sectionsText: String = ""

    var body: some View {
        NavigationView {
            Form {
                // Existing one-shot toggle
                Section {
                    Toggle(isOn: $autoPauseEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("One-shot Capture")
                                .font(.headline)
                            Text("After a valid label, auto-pause scanning, play feedback, and switch to Results tab. Most users should leave this off.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                } header: {
                    Text("AR Scan Behavior")
                }

                // === Active Virtual Warehouse Map for anticipation & live updates ===
                Section {
                    let saved = VirtualWarehouse.loadAll()

                    if saved.isEmpty {
                        Text("No saved warehouses yet. Build one in the Paper Scan tab and save it.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Load a saved warehouse as the active map. The scanner will then anticipate the next position and warn you about missed bins.")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            ForEach(saved) { wh in
                                Button {
                                    // Directly load the saved template as the active guidance map
                                    var prepared = wh
                                    prepared.prepareAsEmptyTemplate(clearReferenceItems: false)
                                    scanViewModel.activeWarehouse = prepared
                                    scanViewModel.lastMatchedWarehouseLocation = nil
                                    UserDefaults.standard.set(wh.id.uuidString, forKey: "lastSelectedWarehouseID")
                                    dismiss()
                                } label: {
                                    VStack(alignment: .leading) {
                                        Text(wh.name).font(.headline)
                                        Text("\(wh.totalLocations) positions")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }

                            if scanViewModel.activeWarehouse != nil {
                                Button(role: .destructive) {
                                    scanViewModel.activeWarehouse = nil
                                    scanViewModel.lastMatchedWarehouseLocation = nil
                                    UserDefaults.standard.removeObject(forKey: "lastSelectedWarehouseID")
                                    dismiss()
                                } label: {
                                    Text("Clear Active Warehouse Map")
                                }
                            }
                        }
                    }
                } header: {
                    Text("Warehouse Map Guidance")
                } footer: {
                    Text("When a map is active the scanner will suggest the next logical position and warn if you skip bins.")
                }

                // Warehouse Label Range + Format
                Section {
                    Toggle("Enable Label Range Filtering", isOn: $range.isEnabled)
                        .toggleStyle(.switch)

                    if range.isEnabled {
                        VStack(alignment: .leading, spacing: 16) {

                            // === Labeling Format (brought back to main settings) ===
                            Toggle("Use Custom Labeling Format", isOn: $range.useCustomFormat)
                                .toggleStyle(.switch)

                            if range.useCustomFormat {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Format Pattern (e.g. LLNNLN or A-12-34)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    TextField("LLNNLN", text: $range.customFormat)
                                        .textInputAutocapitalization(.characters)
                                        .autocorrectionDisabled()
                                        .textFieldStyle(.roundedBorder)
                                    Text("L = Letter, N = Number, A = Alphanumeric")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }

                            // Sections
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Allowed Sections")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("A,B,C or A-D", text: $sectionsText)
                                    .textInputAutocapitalization(.characters)
                                    .autocorrectionDisabled()
                                    .textFieldStyle(.roundedBorder)
                            }

                            Divider()

                            // Per-row mode toggle
                            Toggle("Different columns per row", isOn: $range.usePerRowRanges)
                                .toggleStyle(.switch)

                            if range.usePerRowRanges {
                                // Very basic per-row editor (rough UI is acceptable for now)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Define column range for each row")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    ForEach($range.rowRanges) { $rowDef in
                                        HStack(spacing: 8) {
                                            TextField("Row", text: $rowDef.row)
                                                .textFieldStyle(.roundedBorder)
                                                .frame(width: 60)

                                            TextField("Col Min", value: $rowDef.columnMin, format: .number)
                                                .textFieldStyle(.roundedBorder)
                                                .keyboardType(.numberPad)
                                                .frame(width: 70)

                                            TextField("Col Max", value: $rowDef.columnMax, format: .number)
                                                .textFieldStyle(.roundedBorder)
                                                .keyboardType(.numberPad)
                                                .frame(width: 70)

                                            Button(role: .destructive) {
                                                if let index = range.rowRanges.firstIndex(where: { $0.id == rowDef.id }) {
                                                    range.rowRanges.remove(at: index)
                                                }
                                            } label: {
                                                Image(systemName: "trash")
                                            }
                                        }
                                    }

                                    Button {
                                        let newRow = RowRangeDefinition(
                                            row: "\(range.rowRanges.count + 1)",
                                            columnMin: 1,
                                            columnMax: 12,
                                            columnDigits: 2
                                        )
                                        range.rowRanges.append(newRow)
                                    } label: {
                                        Label("Add Row", systemImage: "plus.circle")
                                    }
                                    .buttonStyle(.bordered)
                                }
                            } else {
                                // Simple global column range
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text("Row Min").font(.caption).foregroundColor(.secondary)
                                            TextField("1", value: $range.rowMin, format: .number)
                                                .textFieldStyle(.roundedBorder).keyboardType(.numberPad)
                                        }
                                        VStack(alignment: .leading) {
                                            Text("Row Max").font(.caption).foregroundColor(.secondary)
                                            TextField("99", value: $range.rowMax, format: .number)
                                                .textFieldStyle(.roundedBorder).keyboardType(.numberPad)
                                        }
                                    }

                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text("Col Min").font(.caption).foregroundColor(.secondary)
                                            TextField("1", value: $range.columnMin, format: .number)
                                                .textFieldStyle(.roundedBorder).keyboardType(.numberPad)
                                        }
                                        VStack(alignment: .leading) {
                                            Text("Col Max").font(.caption).foregroundColor(.secondary)
                                            TextField("99", value: $range.columnMax, format: .number)
                                                .textFieldStyle(.roundedBorder).keyboardType(.numberPad)
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        Text("When disabled, the scanner accepts any label that matches the format.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Expected Label Range")
                } footer: {
                    Text(range.isEnabled ? range.summary : "Range filtering is turned off.")
                        .font(.caption2)
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How it works")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        Text("• Point camera at a warehouse label (A-12-34 format)")
                        Text("• The app continuously scans for new labels")
                        Text("• Each unique label is recorded only once per session (strong deduplication)")
                        Text("• Same label won't spam the list or trigger repeated processing")
                        Text("• Tap Pause anytime to stop processing new frames")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
                } header: {
                    Text("Scanning Tips")
                }
            }
            .navigationTitle("Capture Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        // Save range before dismissing
                        saveRange()
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadRangeIntoUI()
            }
        }
    }

    private func loadRangeIntoUI() {
        sectionsText = range.allowedSections.joined(separator: ",")
        // Note: rowRanges, usePerRowRanges, useCustomFormat etc. are already on the @State range
    }

    private func saveRange() {
        // Parse sections
        let cleaned = sectionsText
            .uppercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: ",")

        let sections = cleaned
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        range.allowedSections = sections

        // Persist everything
        range.save()
    }
}
