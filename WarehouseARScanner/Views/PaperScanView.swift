import SwiftUI
import PhotosUI

struct PaperScanView: View {
    @ObservedObject var comparisonViewModel: ComparisonViewModel
    @AppStorage(LabelParser.customFormatEnabledKey) private var customFormatEnabled = false
    @AppStorage(LabelParser.customFormatKey) private var customFormat = LabelParser.defaultFormat
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var selectedImage: UIImage?
    @State private var detectedText: String?
    @State private var detectedRecords: [WarehouseRecord] = []
    @State private var isProcessing = false

    // Virtual Warehouse Builder
    @State private var editingWarehouse: VirtualWarehouse?
    @State private var viewingWarehouseStatus: VirtualWarehouse?   // Read-only current state view (tap from Manage)
    @State private var showSavedWarehouses = false          // Pure "Manage / browse / edit later" mode (orange button)
    @State private var showMergeSelection = false           // "Merge into Existing" flow (indigo button) — forces merge mode
    @State private var mergeLabelFormat: String?            // Captured from the current paper scan session for merge operations

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Paper Label Scanner")
                        .font(.headline)
                        .padding()

                    labelFormatEditor

                    if let image = selectedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 250)
                            .cornerRadius(10)
                            .padding()
                    } else {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(style: StrokeStyle(lineWidth: 2, dash: [5]))
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 250)
                            .overlay(
                                VStack(spacing: 8) {
                                    Image(systemName: "photo.on.rectangle")
                                        .font(.title)
                                        .foregroundColor(.gray)
                                    Text("Select or take a photo")
                                        .foregroundColor(.gray)
                                }
                            )
                            .padding()
                    }

                    if let detected = detectedText {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Detected Text")
                                .font(.caption)
                                .foregroundColor(.gray)

                            Text(detected)
                                .font(.title3)
                                .fontWeight(.bold)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                        }
                        .padding()
                    }

                    if !detectedRecords.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Detected Paper Rows")
                                .font(.caption)
                                .foregroundColor(.gray)

                            ScrollView {
                                VStack(spacing: 6) {
                                    ForEach(detectedRecords) { record in
                                        HStack {
                                            Text(record.itemNumber)
                                                .font(.subheadline)
                                                .monospacedDigit()

                                            Spacer()

                                            Text(record.location)
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                                .monospacedDigit()
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                            }
                            .frame(maxHeight: 180)
                        }
                        .padding()
                    }

                    VStack(spacing: 12) {
                        Button(action: { showCamera = true }) {
                            HStack {
                                Image(systemName: "camera.fill")
                                Text("Scan Paper with Camera")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .disabled(!CameraPicker.isAvailable)

                        Button(action: { showPhotoPicker = true }) {
                            HStack {
                                Image(systemName: "photo.fill")
                                Text(detectedRecords.isEmpty ? "Select from Photos" : "Add from Photos")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }

                        if isProcessing {
                            ProgressView("Processing...")
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else if !detectedRecords.isEmpty {
                            Button(action: {
                                comparisonViewModel.appendPaperRecords(detectedRecords)
                            }) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                    Text("Use Paper Rows")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            }

                            // Virtual Warehouse from current paper scan
                            VStack(spacing: 8) {
                                Button(action: {
                                    // Prefer whatever the user has typed in the local custom format field.
                                    // If empty, fall back to the global setting from the gear/settings.
                                    // This gives the best chance that "the custom label format provided"
                                    // (in this paper scan context or globally) will be used for the build.
                                    let local = customFormat.trimmingCharacters(in: .whitespacesAndNewlines)
                                    let formatToUse = !local.isEmpty ? local : LabelParser.activeCustomFormat
                                    var warehouse = VirtualWarehouse(name: "Warehouse from Paper - \(Date().formatted(date: .abbreviated, time: .omitted))")
                                    warehouse.buildFromRecords(detectedRecords, replaceExisting: true, labelFormat: formatToUse)
                                    editingWarehouse = warehouse
                                }) {
                                    HStack {
                                        Image(systemName: "building.2.fill")
                                        Text("Create New Virtual Warehouse")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.purple)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                                }

                                Button(action: {
                                    // Capture whatever is typed in the custom format field.
                                    let trimmed = customFormat.trimmingCharacters(in: .whitespacesAndNewlines)
                                    mergeLabelFormat = trimmed.isEmpty ? nil : trimmed
                                    showMergeSelection = true
                                }) {
                                    HStack {
                                        Image(systemName: "arrow.triangle.merge")
                                        Text("Merge into Existing Warehouse")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.indigo)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                                }
                            }
                        }

                        Button(action: {
                            selectedImage = nil
                            detectedText = nil
                            detectedRecords = []
                        }) {
                            Text("Clear")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.gray.opacity(0.3))
                                .foregroundColor(.primary)
                                .cornerRadius(10)
                        }

                        // === Virtual Warehouse Management ===
                        Divider()
                            .padding(.vertical, 8)

                        Button {
                            showSavedWarehouses = true
                        } label: {
                            HStack {
                                Image(systemName: "folder")
                                Text("Manage Saved Warehouses")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange.opacity(0.8))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                    }
                    .padding()
                }
            }
            .sheet(isPresented: $showPhotoPicker) {
                PhotoPicker { images in
                    selectedImage = images.last
                    Task {
                        await processSelectedImages(images)
                    }
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraPicker { image in
                    selectedImage = image
                    Task {
                        await processSelectedImages([image])
                    }
                }
            }
            .sheet(item: $editingWarehouse) { warehouse in
                // Wrap in NavigationView so the editor's .navigationTitle + .toolbar (Save button, +, Close) appear reliably.
                NavigationView {
                    VirtualWarehouseEditorView(warehouse: warehouse)
                }
                .navigationViewStyle(.stack)
            }
            .sheet(isPresented: $showSavedWarehouses) {
                SavedVirtualWarehousesView(
                    isMergeMode: false,
                    recordsToMerge: [],
                    labelFormat: nil,
                    onMergeCompleted: nil,
                    onSelectWarehouse: { selected in
                        var prepared = selected
                        prepared.prepareAsEmptyTemplate(clearReferenceItems: false)
                        viewingWarehouseStatus = prepared   // Tap opens the current state view (with "not scanned yet" indicators)
                    }
                )
            }

            // Separate sheet for the "Merge into Existing Warehouse" flow (respects current paper records)
            .sheet(isPresented: $showMergeSelection) {
                SavedVirtualWarehousesView(
                    isMergeMode: true,
                    recordsToMerge: detectedRecords,
                    labelFormat: mergeLabelFormat,
                    onMergeCompleted: { mergedWarehouse in
                        editingWarehouse = mergedWarehouse
                    },
                    onSelectWarehouse: nil
                )
            }

            // Status / Current State sheet for a selected saved warehouse
            .sheet(item: $viewingWarehouseStatus) { warehouse in
                VirtualWarehouseStatusView(warehouse: warehouse) {
                    // "Edit Structure" button action
                    editingWarehouse = warehouse
                }
            }
            // Editing of individual locations is now handled inside the dedicated
            // VirtualWarehouseEditorView (opened via the .sheet(item:) above).
        }
    }

    private var labelFormatEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Custom Label Format", isOn: $customFormatEnabled)

            if customFormatEnabled {
                HStack(spacing: 8) {
                    TextField(LabelParser.defaultFormat, text: $customFormat)
                        .textInputAutocapitalization(.characters)
                        .disableAutocorrection(true)
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                    Button("Reset") {
                        customFormat = LabelParser.defaultFormat
                    }
                    .font(.caption)
                }

                Text("Example AA01A1 = LLNNLN. L = letter, N/# = digit, A = letter or digit")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
    }

    private func processSelectedImages(_ images: [UIImage]) async {
        isProcessing = true

        defer {
            isProcessing = false
        }

        var newRecords: [WarehouseRecord] = []

        for image in images {
            let records = await VisionService.shared.processImageRecords(image)
            newRecords.append(contentsOf: records)
        }

        appendDetectedRecords(newRecords)
        comparisonViewModel.appendPaperRecords(newRecords)
        detectedText = detectedRecords.isEmpty ? nil : detectedRecords.map(\.displayText).joined(separator: "\n")
    }

    private func appendDetectedRecords(_ records: [WarehouseRecord]) {
        for record in records {
            if !detectedRecords.contains(where: { $0.verificationKey == record.verificationKey }) {
                detectedRecords.append(record)
            }
        }
    }
}

private struct PhotoPicker: UIViewControllerRepresentable {
    let onImagesPicked: ([UIImage]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 0

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagesPicked: onImagesPicked)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onImagesPicked: ([UIImage]) -> Void

        init(onImagesPicked: @escaping ([UIImage]) -> Void) {
            self.onImagesPicked = onImagesPicked
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)

            let itemProviders = results
                .map(\.itemProvider)
                .filter { $0.canLoadObject(ofClass: UIImage.self) }

            guard !itemProviders.isEmpty else {
                return
            }

            let group = DispatchGroup()
            let lock = NSLock()
            var images: [UIImage] = []

            for itemProvider in itemProviders {
                group.enter()
                itemProvider.loadObject(ofClass: UIImage.self) { object, error in
                    defer { group.leave() }

                    if let error {
                        Logger.shared.error("Failed to load selected photo: \(error.localizedDescription)")
                        return
                    }

                    guard let image = object as? UIImage else {
                        return
                    }

                    lock.lock()
                    images.append(image)
                    lock.unlock()
                }
            }

            group.notify(queue: .main) { [onImagesPicked] in
                guard !images.isEmpty else {
                    return
                }

                onImagesPicked(images)
            }
        }
    }
}

private struct CameraPicker: UIViewControllerRepresentable {
    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    let onImageCaptured: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImageCaptured: onImageCaptured)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let onImageCaptured: (UIImage) -> Void

        init(onImageCaptured: @escaping (UIImage) -> Void) {
            self.onImageCaptured = onImageCaptured
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            picker.dismiss(animated: true)

            guard let image = info[.originalImage] as? UIImage else {
                return
            }

            onImageCaptured(image)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

#Preview {
    PaperScanView(comparisonViewModel: ComparisonViewModel())
}

// MARK: - Inlined Virtual Warehouse Editor Views
// These are inlined because newly created .swift files are not automatically
// added to the Xcode target (the recurring "Cannot find X in scope" problem).
// Everything below is self-contained and will compile.

struct VirtualWarehouseEditorView: View {
    @State var warehouse: VirtualWarehouse
    @Environment(\.dismiss) private var dismiss

    @State private var showAddLocation = false
    @State private var locationBeingEdited: VirtualLocation?
    @State private var editSection = ""
    @State private var editRow = ""
    @State private var editColumn = ""
    @State private var editItemNumber = ""

    // Manual save flow with naming
    @State private var showSaveSheet = false
    @State private var saveName: String = ""
    @State private var saveFeedback: String? = nil   // temporary "Saved!" message

    var body: some View {
        List {
            Section("Overview") {
                TextField("Warehouse Name", text: $warehouse.name)
                Text("Tip: Tap Save (top right) to choose a final name and add this warehouse to your saved list.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            ForEach(warehouse.sortedSections) { section in
                Section("Row \(section.section)") {
                    ForEach(section.sortedRows) { row in
                        DisclosureGroup("Section \(row.row) — \(row.locations.count) locations") {
                            ForEach(row.sortedLocations) { location in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(location.formattedLocation)
                                            .font(.headline).monospacedDigit()

                                        // Reference from paper (if any)
                                        if let ref = location.referenceItemNumber {
                                            Text("Paper ref: \(ref)").font(.caption).foregroundColor(.secondary)
                                        }

                                        // Live data from AR scanner (the "different section" / current floor state)
                                        if let current = location.currentItemNumber {
                                            Text("Now: \(current)")
                                                .font(.caption)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.green)
                                        } else {
                                            Text("Not yet scanned via AR")
                                                .font(.caption2)
                                                .foregroundColor(.secondary.opacity(0.7))
                                        }
                                    }
                                    Spacer()
                                    Button("Edit") {
                                        locationBeingEdited = location
                                        editSection = location.section
                                        editRow = location.row
                                        editColumn = location.column
                                        editItemNumber = location.referenceItemNumber ?? ""
                                    }
                                    .buttonStyle(.bordered)

                                    Button(role: .destructive) {
                                        warehouse.deleteLocation(id: location.id)
                                        // Safety save — use the explicit Save button when you want to name / register it.
                                        VirtualWarehouse.save(warehouse)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.red)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(warehouse.name)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    // Tip: Use the "Save" button (top right) to give the warehouse a name
                    // and make it appear in "Manage Saved Warehouses".
                    dismiss()
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    saveName = warehouse.name
                    saveFeedback = nil
                    showSaveSheet = true
                } label: {
                    Text("Save")
                        .fontWeight(.semibold)
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddLocation = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddLocation) {
            AddLocationSheet(warehouse: $warehouse)
        }
        .sheet(isPresented: $showSaveSheet) {
            SaveWarehouseSheet(
                currentName: $saveName,
                feedback: $saveFeedback,
                onSave: {
                    // Apply the name the user chose/typed
                    warehouse.name = saveName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if warehouse.name.isEmpty {
                        warehouse.name = "Untitled Warehouse"
                    }
                    VirtualWarehouse.save(warehouse)
                    saveFeedback = "Saved ✓"

                    // Keep the feedback visible briefly, then auto-dismiss the save sheet
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                        showSaveSheet = false
                        saveFeedback = nil
                    }
                }
            )
        }
        .sheet(item: $locationBeingEdited) { loc in
            NavigationView {
                Form {
                    Section("Location Parts") {
                        TextField("Row (e.g. AA)", text: $editSection)
                        TextField("Section within row (e.g. 01)", text: $editRow)
                        TextField("Location within section (e.g. A1)", text: $editColumn)
                    }
                    Section("Item Number (optional)") {
                        TextField("Item", text: $editItemNumber)
                    }
                }
                .navigationTitle("Edit Location")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { locationBeingEdited = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            // IMPORTANT: do NOT insert dashes. Preserve the clean concatenated style the user expects (AA01A1).
                            let newOriginal = "\(editSection)\(editRow)\(editColumn)"
                            warehouse.updateLocation(
                                id: loc.id,
                                newSection: editSection,
                                newRow: editRow,
                                newColumn: editColumn,
                                newItemNumber: editItemNumber.isEmpty ? nil : editItemNumber,
                                newOriginalLabel: newOriginal
                            )
                            // Note: explicit Save button (with naming) is the main way to persist to the Manage list.
                            // We still save here for safety during long editing sessions.
                            VirtualWarehouse.save(warehouse)
                            locationBeingEdited = nil
                        }
                    }
                }
            }
        }
    }
}

private struct AddLocationSheet: View {
    @Binding var warehouse: VirtualWarehouse
    @Environment(\.dismiss) private var dismiss

    @State private var section = ""
    @State private var row = ""
    @State private var column = ""
    @State private var itemNumber = ""

    var body: some View {
        NavigationView {
            Form {
                Section("New Location") {
                    TextField("Row (e.g. AA)", text: $section)
                    TextField("Section within row (e.g. 01)", text: $row)
                    TextField("Location within section (e.g. A1)", text: $column)
                    TextField("Item Number (optional)", text: $itemNumber)
                }
            }
            .navigationTitle("Add Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if !section.isEmpty && !row.isEmpty && !column.isEmpty {
                            warehouse.addManualLocation(
                                section: section.uppercased(),
                                row: row,
                                column: column,
                                itemNumber: itemNumber.isEmpty ? nil : itemNumber
                            )
                            // Safety save during editing. The explicit "Save" button + name is the official way.
                            VirtualWarehouse.save(warehouse)
                            dismiss()
                        }
                    }
                    .disabled(section.isEmpty || row.isEmpty || column.isEmpty)
                }
            }
        }
    }
}

// MARK: - Virtual Warehouse Current State View
// Read-only view showing the live status of every position.
// Clearly indicates "Not scanned yet" for positions without AR data.
private struct VirtualWarehouseStatusView: View {
    let warehouse: VirtualWarehouse
    var onEditRequested: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    private var scannedCount: Int {
        warehouse.flattenedLocationsInOrder.filter { $0.currentItemNumber != nil }.count
    }

    private var totalCount: Int {
        warehouse.totalLocations
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(warehouse.name)
                            .font(.title2).bold()
                        Text("\(scannedCount) of \(totalCount) positions scanned via AR")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        ProgressView(value: Double(scannedCount), total: Double(max(totalCount, 1)))
                            .tint(.green)
                    }
                    .padding(.vertical, 4)
                }

                ForEach(warehouse.sortedSections) { section in
                    Section("Row \(section.section)") {
                        ForEach(section.sortedRows) { row in
                            DisclosureGroup("Section \(row.row) — \(row.locations.count) locations") {
                                ForEach(row.sortedLocations) { location in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(location.formattedLocation)
                                            .font(.headline)
                                            .monospacedDigit()

                                        if let current = location.currentItemNumber {
                                            HStack {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(.green)
                                                Text("Scanned: \(current)")
                                                    .fontWeight(.semibold)
                                            }
                                            if let scannedAt = location.lastARScan {
                                                Text("Last seen: \(scannedAt.formatted(date: .omitted, time: .shortened))")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                        } else {
                                            HStack {
                                                Image(systemName: "exclamationmark.circle")
                                                    .foregroundColor(.orange)
                                                Text("Not scanned yet")
                                                    .fontWeight(.medium)
                                                    .foregroundColor(.orange)
                                            }
                                        }

                                        if let ref = location.referenceItemNumber {
                                            Text("Paper reference: \(ref)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Current State")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit Structure") {
                        dismiss()
                        onEditRequested()
                    }
                }
            }
            .overlay {
                if totalCount == 0 {
                    VStack {
                        Image(systemName: "tray")
                            .font(.largeTitle)
                        Text("This warehouse has no positions.")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("Positions marked “Not scanned yet” have no live AR data. Load this warehouse as the active map in the Scanner gear to populate live items.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemBackground))
            }
        }
    }
}

// Manual save sheet — lets the user name (or rename) the warehouse at the moment of saving.
private struct SaveWarehouseSheet: View {
    @Binding var currentName: String
    @Binding var feedback: String?

    var onSave: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section("Warehouse Name") {
                    TextField("Enter a name for this warehouse", text: $currentName)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)

                    Text("Give it a clear name so you can find it easily later (e.g. \"Main Floor - A Wing\").")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let feedback = feedback {
                    Section {
                        Text(feedback)
                            .foregroundColor(.green)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .navigationTitle("Save Warehouse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Warehouse") {
                        onSave()
                        // The onSave closure handles closing after a short delay when successful
                    }
                    .disabled(currentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct SavedVirtualWarehousesView: View {
    var isMergeMode: Bool
    var recordsToMerge: [WarehouseRecord] = []
    var labelFormat: String? = nil
    var onMergeCompleted: ((VirtualWarehouse) -> Void)? = nil
    var onSelectWarehouse: ((VirtualWarehouse) -> Void)? = nil   // for opening a previously saved warehouse for editing

    @State private var warehouses: [VirtualWarehouse] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List(warehouses) { warehouse in
                VStack(alignment: .leading, spacing: 2) {
                    Text(warehouse.name).font(.headline)
                    Text("\(warehouse.totalLocations) locations  •  \(warehouse.lastUpdated.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Tap to view current scanned / not scanned state")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if isMergeMode {
                        var updated = warehouse
                        updated.buildFromRecords(recordsToMerge, replaceExisting: false, labelFormat: labelFormat)
                        VirtualWarehouse.save(updated)
                        onMergeCompleted?(updated)
                        dismiss()
                    } else {
                        // Normal "Manage" mode → open this warehouse in the editor so user can continue editing it later
                        onSelectWarehouse?(warehouse)
                        dismiss()
                    }
                }
            }
            .overlay {
                if warehouses.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text(isMergeMode ? "No saved warehouses yet." : "No saved warehouses.\nCreate one from a paper scan and tap Save.")
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .navigationTitle(isMergeMode ? "Merge Into..." : "Saved Warehouses")
            .onAppear {
                warehouses = VirtualWarehouse.loadAll()
            }
            .refreshable {
                warehouses = VirtualWarehouse.loadAll()
            }
        }
    }
}
