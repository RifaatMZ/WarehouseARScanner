import Foundation
import Vision

struct Constants {
    // MARK: - API Configuration
    static let useMockAPI = true
    static let apiBaseURL = "https://api.warehouse.local"
    static let inventoryCheckEndpoint = "/inventory/check"

    // MARK: - Vision Settings
    static let visionRecognitionLevel: VNRequestTextRecognitionLevel = .accurate
    static let visionLanguages = ["en"]
    static let processEveryNthFrame = 5 // Process every 5th frame for performance
    static let ocrConfidenceThreshold: Float = 0.35

    // MARK: - AR Settings
    static let arLightEstimation = true
    static let confidenceThreshold: Float = 0.75
    static let arSessionConfig = "planeDetection"

    // MARK: - UI Constants
    struct Colors {
        static let primary = "0066CC"
        static let success = "34C759"
        static let warning = "FF9500"
        static let error = "FF3B30"
    }

    struct Fonts {
        static let titleSize: CGFloat = 20
        static let labelSize: CGFloat = 16
        static let smallSize: CGFloat = 12
    }

    struct Spacing {
        static let small: CGFloat = 8
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
    }

    // MARK: - Label Format
    static let labelPattern = "^[A-Z]-\\d{2}-\\d{2}$"

    // MARK: - API Endpoints
    static func inventoryCheckURL() -> URL? {
        URL(string: apiBaseURL + inventoryCheckEndpoint)
    }
}

enum APIEndpoint {
    case inventoryCheck

    var path: String {
        switch self {
        case .inventoryCheck:
            return "/inventory/check"
        }
    }
}
