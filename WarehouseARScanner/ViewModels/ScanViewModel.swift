import Foundation
import Combine
import Vision
import UIKit
import AudioToolbox

class ScanViewModel: NSObject, ObservableObject {
    @Published var detectedLabels: [StorageLabel] = []
    @Published var shelfRecords: [WarehouseRecord] = []
    @Published var currentARLabel: StorageLabel?
    @Published var currentShelfRecord: WarehouseRecord?
    @Published var liveFeedback: LiveScanFeedback?
    @Published var isScanning: Bool = false
    @Published var averageConfidence: Float = 0
    @Published var lastDetectionTime: Date?
    @Published var errorMessage: String?

    /// Signals to the root tab controller that we should navigate to the Results tab.
    @Published var shouldNavigateToResults = false

    /// Optional active warehouse map loaded from saved templates.
    /// When set, the scanner can provide next-position guidance and
    /// will write live scanned items back into the warehouse positions.
    @Published var activeWarehouse: VirtualWarehouse?

    /// The last location (within the active warehouse) that was successfully matched during this session.
    @Published var lastMatchedWarehouseLocation: VirtualLocation?

    /// If an active warehouse is loaded, this returns the next logical position the user should scan
    /// (within the current section context if possible, otherwise the next unscanned in global order).
    var nextExpectedWarehouseLocation: VirtualLocation? {
        guard let warehouse = activeWarehouse else { return nil }

        let all = warehouse.flattenedLocationsInOrder
        guard !all.isEmpty else { return nil }

        // If we have a last match, try to find the one immediately after it in the ordered list.
        if let last = lastMatchedWarehouseLocation,
           let idx = all.firstIndex(where: { $0.id == last.id }),
           idx + 1 < all.count {
            return all[idx + 1]
        }

        // Otherwise return the first position that has not received a live AR scan yet.
        if let firstUnscanned = all.first(where: { $0.currentItemNumber == nil }) {
            return firstUnscanned
        }

        // All scanned — return the first one as a "loop around" hint.
        return all.first
    }

    /// Returns the list of positions that appear between `lastMatched` and the newly scanned one
    /// in the warehouse order. Used to warn the user about missed bins.
    func missedPositions(between last: VirtualLocation?, and newlyScanned: String, in warehouse: VirtualWarehouse) -> [VirtualLocation] {
        let all = warehouse.flattenedLocationsInOrder
        guard !all.isEmpty else { return [] }

        let newNorm = newlyScanned.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        // Find index of the newly scanned label
        guard let newIdx = all.firstIndex(where: {
            $0.formattedLocation.uppercased() == newNorm || $0.originalLabel?.uppercased() == newNorm
        }) else {
            return []
        }

        var startIdx = 0
        if let last = last,
           let lastIdx = all.firstIndex(where: { $0.id == last.id }) {
            startIdx = lastIdx + 1
        }

        if newIdx <= startIdx { return [] } // no forward skip or going backwards

        return Array(all[startIdx..<newIdx])
    }

    private var cancellables = Set<AnyCancellable>()
    private let visionService = VisionService.shared
    private var detectionCache: [String: StorageLabel] = [:]

    /// Labels (formatted text) that have already been accepted this session.
    /// Prevents the same label from being added repeatedly while continuously scanning.
    private var seenLabels = Set<String>()

    override init() {
        super.init()
        setupVisionCallback()
    }

    private func setupVisionCallback() {
        visionService.detectionCallback = { [weak self] detection in
            self?.processDetection(detection)
        }

        visionService.liveFeedbackCallback = { [weak self] feedback in
            self?.processLiveFeedback(feedback)
        }
    }

    private func processLiveFeedback(_ feedback: LiveScanFeedback) {
        guard isScanning else { return }
        // Defer to avoid "Publishing changes from within view updates" warning
        // when Vision callbacks fire during SwiftUI view updates.
        DispatchQueue.main.async {
            self.liveFeedback = feedback
        }
    }

    func startScanning() {
        // Using asyncAfter is currently the most reliable way to avoid
        // "Publishing changes from within view updates" when the call comes
        // from a UIViewControllerRepresentable lifecycle.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) {
            self.isScanning = true
            self.errorMessage = nil
            Logger.shared.info("Started AR scanning")
        }
    }

    func stopScanning() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) {
            self.isScanning = false
            Logger.shared.info("Stopped AR scanning")
        }
    }

    // MARK: - Full AR Session Control (controls both logical flag + actual ARKit session)
    // Use these from the UI Pause/Resume button to properly manage heat and performance.

    func startARSession() {
        // Start logical scanning + the heavy ARKit session
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            self.isScanning = true
            self.errorMessage = nil
        }
        ARKitService.shared.start()
        Logger.shared.info("Started full AR session (scanning + ARKit)")
    }

    func pauseARSession() {
        // Stop logical scanning + pause the ARKit session (big heat reduction)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            self.isScanning = false
        }
        ARKitService.shared.pause()
        Logger.shared.info("Paused full AR session (scanning + ARKit)")
    }

    private func processDetection(_ detection: DetectionResult) {
        guard isScanning else { return }

        if detection.confidence < Constants.ocrConfidenceThreshold {
            Logger.shared.debug("Low confidence detection: \(detection.detectedText) (\(detection.confidence.percentageString))")
            return
        }

        if let record = LabelParser.parseWarehouseRecord(detection.detectedText, confidence: detection.confidence) {
            let formatted = record.displayText

            // Short-term cache to avoid processing the exact same frame repeatedly
            if let cached = detectionCache[formatted],
               cached.detectionTime.timeIntervalSinceNow > -1.0 {
                // Still update live current detection for feedback, but don't re-process.
                // Double async for safety against view update warnings.
                DispatchQueue.main.async {
                    DispatchQueue.main.async {
                        self.currentARLabel = StorageLabel(text: formatted, confidence: detection.confidence, detectionTime: detection.timestamp)
                        self.currentShelfRecord = record
                    }
                }
                return
            }

            let label = StorageLabel(
                text: formatted,
                confidence: detection.confidence,
                detectionTime: detection.timestamp
            )

            // Double async: VisionService already does one async.
            // We do a second one to push state changes past any active SwiftUI view update.
            DispatchQueue.main.async {
                DispatchQueue.main.async {
                    self.currentARLabel = label
                    self.currentShelfRecord = record
                    self.detectionCache[formatted] = label
                    self.lastDetectionTime = Date()
                    self.updateAverageConfidence()

                    // === Strong session-level deduplication ===
                    let isNew = !self.seenLabels.contains(formatted)

                    if isNew {
                        self.seenLabels.insert(formatted)

                        // === Label Range Filtering (new) ===
                        let currentRange = WarehouseLabelRange.load()
                        let inRange = LabelParser.isLocationInRange(record.location, range: currentRange)

                        if inRange {
                            if !self.detectedLabels.contains(where: { $0.text == formatted }) {
                                self.detectedLabels.append(label)
                            }

                            if !self.shelfRecords.contains(where: { $0.location == record.location }) {
                                self.shelfRecords.append(record)
                            }

                            // === Virtual Warehouse live update + anticipation support ===
                            if var warehouse = self.activeWarehouse {
                                let matched = warehouse.recordARScan(
                                    at: record.location,
                                    itemNumber: record.itemNumber,
                                    timestamp: Date()
                                )
                                if matched {
                                    self.activeWarehouse = warehouse
                                    let previousLast = self.lastMatchedWarehouseLocation
                                    self.lastMatchedWarehouseLocation = warehouse.findLocation(matching: record.location)

                                    // Anticipation / miss warning
                                    let missed = self.missedPositions(between: previousLast, and: record.location, in: warehouse)
                                    if !missed.isEmpty {
                                        let missedLabels = missed.map { $0.formattedLocation }.joined(separator: ", ")
                                        self.errorMessage = "Missed positions: \(missedLabels)"
                                        Logger.shared.warning("User skipped positions in active warehouse: \(missedLabels)")
                                    } else {
                                        // Clear previous skip warning once user is back on track
                                        if self.errorMessage?.hasPrefix("Missed positions") == true {
                                            self.errorMessage = nil
                                        }
                                    }

                                    Logger.shared.info("Updated active warehouse position for \(record.location)")
                                }
                            }

                            Logger.shared.info("New in-range label captured: \(formatted)")
                        } else {
                            Logger.shared.info("Label \(formatted) is outside configured range — not added to results.")
                        }

                        if Constants.autoPauseAfterValidCapture && inRange {
                            self.stopScanning()
                            self.shouldNavigateToResults = true
                            self.triggerCaptureFeedback()
                        }
                    } else {
                        Logger.shared.debug("Duplicate label ignored (already seen this session): \(formatted)")
                    }
                }
            }
        }
    }

    private func updateAverageConfidence() {
        // Defer to prevent publishing during view updates
        DispatchQueue.main.async {
            guard !self.detectedLabels.isEmpty else {
                self.averageConfidence = 0
                return
            }
            self.averageConfidence = self.detectedLabels.map { $0.confidence }.reduce(0, +) / Float(self.detectedLabels.count)
        }
    }

    func clearDetections() {
        // Defer all mutations to avoid publishing during view updates
        // (this method is often called from button actions during view updates)
        DispatchQueue.main.async {
            self.detectedLabels.removeAll()
            self.detectionCache.removeAll()
            self.shelfRecords.removeAll()
            self.seenLabels.removeAll()
            self.currentARLabel = nil
            self.currentShelfRecord = nil
            self.liveFeedback = nil
            self.averageConfidence = 0
            self.lastDetectionTime = nil
            self.shouldNavigateToResults = false
        }
    }

    // MARK: - Capture Feedback (Haptic + Sound)

    private func triggerCaptureFeedback() {
        // Subtle success haptic
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        // Soft camera-like capture sound (very short, non-intrusive)
        AudioServicesPlaySystemSound(1104)
    }
}
