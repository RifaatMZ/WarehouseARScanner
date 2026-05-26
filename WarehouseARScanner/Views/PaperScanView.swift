import SwiftUI
import PhotosUI

struct PaperScanView: View {
    @ObservedObject var comparisonViewModel: ComparisonViewModel
    @AppStorage(LabelParser.customFormatEnabledKey) private var customFormatEnabled = false
    @AppStorage(LabelParser.customFormatKey) private var customFormat = LabelParser.defaultFormat
    @State private var showPhotoPicker = false
    @State private var selectedImage: UIImage?
    @State private var detectedText: String?
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

                Spacer()

                VStack(spacing: 12) {
                    Button(action: { showPhotoPicker = true }) {
                        HStack {
                            Image(systemName: "photo.fill")
                            Text("Select Photo")
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
                    } else if selectedImage != nil && detectedText != nil {
                        Button(action: {
                            if let detectedLabel = detectedText,
                               let formattedLabel = LabelParser.parseLabelText(detectedLabel) {
                                let paperLabel = StorageLabel(text: formattedLabel, confidence: 0.9, detectionTime: Date())
                                comparisonViewModel.paperResult = paperLabel
                            }
                        }) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Confirm Detection")
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
                PhotoPicker { image in
                    selectedImage = image
                    Task {
                        await processSelectedImage(image)
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

    private func processSelectedImage(_ image: UIImage) async {
        isProcessing = true
        detectedText = nil

        defer {
            isProcessing = false
        }

        let result = await VisionService.shared.processImage(image)
        detectedText = result?.detectedText
    }
}

private struct PhotoPicker: UIViewControllerRepresentable {
    let onImagePicked: (UIImage) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onImagePicked: (UIImage) -> Void

        init(onImagePicked: @escaping (UIImage) -> Void) {
            self.onImagePicked = onImagePicked
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)

            guard let itemProvider = results.first?.itemProvider,
                  itemProvider.canLoadObject(ofClass: UIImage.self) else {
                return
            }

            itemProvider.loadObject(ofClass: UIImage.self) { [onImagePicked] object, error in
                if let error {
                    Logger.shared.error("Failed to load selected photo: \(error.localizedDescription)")
                    return
                }

                guard let image = object as? UIImage else {
                    return
                }

                DispatchQueue.main.async {
                    onImagePicked(image)
                }
            }
        }
    }
}

#Preview {
    PaperScanView(comparisonViewModel: ComparisonViewModel())
}
