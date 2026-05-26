import Foundation

struct StorageLabel: Identifiable, Codable {
    let id = UUID()
    let text: String
    let confidence: Float
    let detectionTime: Date
    
    var parsedComponents: LabelComponents? {
        LabelParser.parse(text)
    }
}

struct LabelComponents: Equatable {
    let section: String
    let row: String
    let column: String
    
    var formatted: String {
        "\(section)-\(row)-\(column)"
    }
}
