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

    var body: some View {
        NavigationView {
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

                Spacer()

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
                }
                .padding()
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

                Text("L = letter, N/# = digit, A = letter or digit")
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
