import Foundation

// MARK: - Request Models
struct InventoryCheckRequest: Codable {
    let detectedLabels: [DetectedLabel]
    let timestamp: Date
    let deviceId: String?

    struct DetectedLabel: Codable {
        let text: String
        let confidence: Float
        let timestamp: Date
    }
}

// MARK: - Response Models
struct InventoryCheckResponse: Codable {
    let matchedItems: [MatchedInventoryItem]
    let unmatched: [String]
    let overallConfidence: Float
    let timestamp: Date
    let message: String?
}

struct MatchedInventoryItem: Codable, Identifiable {
    let id: String
    let sectionId: String
    let rowId: String
    let columnId: String
    let description: String
    let quantity: Int
    let lastUpdated: Date
    let confidence: Float
    let detected: Bool?

    enum CodingKeys: String, CodingKey {
        case id, sectionId, rowId, columnId, description, quantity, lastUpdated, confidence, detected
    }

    var formattedLocation: String {
        "\(sectionId)-\(rowId)-\(columnId)"
    }
}

// MARK: - API Models
struct InventoryItem: Codable, Identifiable {
    let id: String
    let sectionId: String
    let rowId: String
    let columnId: String
    let description: String
    let quantity: Int
    let lastUpdated: Date

    var formattedLocation: String {
        "\(sectionId)-\(rowId)-\(columnId)"
    }
}

// MARK: - Error Handling
struct APIError: Codable, Error {
    let code: String
    let message: String
    let details: String?

    var localizedDescription: String {
        return message
    }
}

// MARK: - Mock Response Codable
struct MockAPIResponse: Codable {
    let success: Bool
    let data: InventoryCheckResponse
}
