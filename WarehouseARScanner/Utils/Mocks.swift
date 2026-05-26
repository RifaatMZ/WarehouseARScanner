import Foundation

struct MockInventoryData {
    static let sampleItems: [InventoryItem] = [
        InventoryItem(
            id: "INV001",
            sectionId: "A",
            rowId: "12",
            columnId: "34",
            description: "Electronic Components - Resistors",
            quantity: 150,
            lastUpdated: Date().addingTimeInterval(-3600)
        ),
        InventoryItem(
            id: "INV002",
            sectionId: "B",
            rowId: "05",
            columnId: "12",
            description: "Capacitors - 100μF",
            quantity: 300,
            lastUpdated: Date().addingTimeInterval(-7200)
        ),
        InventoryItem(
            id: "INV003",
            sectionId: "C",
            rowId: "15",
            columnId: "08",
            description: "Diodes - 1N4148",
            quantity: 500,
            lastUpdated: Date().addingTimeInterval(-1800)
        ),
        InventoryItem(
            id: "INV004",
            sectionId: "A",
            rowId: "12",
            columnId: "35",
            description: "Inductors - 10μH",
            quantity: 200,
            lastUpdated: Date().addingTimeInterval(-10800)
        ),
        InventoryItem(
            id: "INV005",
            sectionId: "D",
            rowId: "08",
            columnId: "22",
            description: "Transformers - Step Down",
            quantity: 50,
            lastUpdated: Date().addingTimeInterval(-86400)
        ),
    ]

    static func generateResponse(for labels: [InventoryCheckRequest.DetectedLabel]) -> InventoryCheckResponse {
        var matched: [MatchedInventoryItem] = []
        var unmatched: [String] = []

        for label in labels {
            if let components = LabelParser.parse(label.text) {
                let matchedItem = sampleItems.first { item in
                    item.sectionId == components.section &&
                    item.rowId == components.row &&
                    item.columnId == components.column
                }

                if let item = matchedItem {
                    let confidence = min(label.confidence + Float.random(in: 0..<0.1), 1.0)
                    matched.append(
                        MatchedInventoryItem(
                            id: item.id,
                            sectionId: item.sectionId,
                            rowId: item.rowId,
                            columnId: item.columnId,
                            description: item.description,
                            quantity: item.quantity,
                            lastUpdated: item.lastUpdated,
                            confidence: confidence,
                            detected: true
                        )
                    )
                } else {
                    unmatched.append(label.text)
                }
            } else {
                unmatched.append(label.text)
            }
        }

        let overallConfidence = matched.isEmpty ? 0 : matched.map { $0.confidence }.reduce(0, +) / Float(matched.count)

        return InventoryCheckResponse(
            matchedItems: matched,
            unmatched: unmatched,
            overallConfidence: overallConfidence,
            timestamp: Date(),
            message: "Mock API Response - \(matched.count) items matched"
        )
    }
}

struct MockAPIResponses {
    static let successResponse = """
    {
        "success": true,
        "data": {
            "matchedItems": [
                {
                    "id": "INV001",
                    "sectionId": "A",
                    "rowId": "12",
                    "columnId": "34",
                    "description": "Electronic Components",
                    "quantity": 150,
                    "lastUpdated": "2026-05-24T00:00:00Z",
                    "confidence": 0.92
                }
            ],
            "unmatched": [],
            "overallConfidence": 0.92,
            "timestamp": "2026-05-24T00:00:00Z",
            "message": "Success"
        }
    }
    """

    static let errorResponse = """
    {
        "code": "INVALID_REQUEST",
        "message": "No valid labels detected",
        "details": "Empty detection array"
    }
    """
}
