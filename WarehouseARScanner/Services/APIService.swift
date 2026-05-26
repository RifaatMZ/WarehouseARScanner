import Foundation

class APIService {
    static let shared = APIService()

    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)

        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
    }

    func checkInventory(labels: [InventoryCheckRequest.DetectedLabel]) async -> Result<InventoryCheckResponse, Error> {
        if Constants.useMockAPI {
            let request = InventoryCheckRequest(
                detectedLabels: labels,
                timestamp: Date(),
                deviceId: UIDevice.current.identifierForVendor?.uuidString
            )
            let response = MockInventoryData.generateResponse(for: labels)
            Logger.shared.info("Mock API: Inventory check returned \(response.matchedItems.count) items")
            return .success(response)
        }

        guard let url = Constants.inventoryCheckURL() else {
            return .failure(APIError(
                code: "INVALID_URL",
                message: "Invalid API URL",
                details: nil
            ))
        }

        let request = InventoryCheckRequest(
            detectedLabels: labels,
            timestamp: Date(),
            deviceId: UIDevice.current.identifierForVendor?.uuidString
        )

        do {
            let data = try encoder.encode(request)
            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = data

            let (responseData, response) = try await session.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(APIError(
                    code: "INVALID_RESPONSE",
                    message: "Invalid HTTP response",
                    details: nil
                ))
            }

            if (200...299).contains(httpResponse.statusCode) {
                let decoded = try decoder.decode(InventoryCheckResponse.self, from: responseData)
                Logger.shared.info("Inventory check successful: \(decoded.matchedItems.count) items matched")
                return .success(decoded)
            } else {
                do {
                    let error = try decoder.decode(APIError.self, from: responseData)
                    return .failure(error)
                } catch {
                    return .failure(APIError(
                        code: "HTTP_\(httpResponse.statusCode)",
                        message: "HTTP Error",
                        details: "Status code: \(httpResponse.statusCode)"
                    ))
                }
            }
        } catch let error as DecodingError {
            Logger.shared.error("Decoding error: \(error)")
            return .failure(APIError(
                code: "DECODE_ERROR",
                message: "Failed to decode response",
                details: error.localizedDescription
            ))
        } catch {
            Logger.shared.error("API request error: \(error)")
            return .failure(error)
        }
    }
}

import UIKit
