import Foundation
import Combine

@MainActor
class InventoryViewModel: ObservableObject {
    @Published var inventoryItems: [InventoryItem] = []
    @Published var matchedItems: [MatchedInventoryItem] = []
    @Published var lastCheckTime: Date?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var overallConfidence: Float = 0

    private var cancellables = Set<AnyCancellable>()
    private let apiService = APIService.shared

    func checkInventory(for detections: [StorageLabel]) async {
        isLoading = true
        errorMessage = nil

        let requests = detections.map { detection in
            InventoryCheckRequest.DetectedLabel(
                text: detection.text,
                confidence: detection.confidence,
                timestamp: detection.detectionTime
            )
        }

        let result = await apiService.checkInventory(labels: requests)

        isLoading = false

        switch result {
        case .success(let response):
            matchedItems = response.matchedItems
            overallConfidence = response.overallConfidence
            lastCheckTime = response.timestamp
            Logger.shared.info("Inventory check: \(response.matchedItems.count) items matched")

        case .failure(let error):
            errorMessage = error.localizedDescription
            Logger.shared.error("Inventory check failed: \(error.localizedDescription)")
        }
    }

    func clearResults() {
        matchedItems.removeAll()
        overallConfidence = 0
        errorMessage = nil
    }
}
