import Foundation
import Network

class NetworkManager {
    static let shared = NetworkManager()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.warehouse.ar.scanner.network")

    @Published var isConnected: Bool = true
    var connectionStatusCallback: ((Bool) -> Void)?

    init() {
        startMonitoring()
    }

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            let isConnected = path.status == .satisfied
            DispatchQueue.main.async {
                self?.isConnected = isConnected
                self?.connectionStatusCallback?(isConnected)

                if isConnected {
                    Logger.shared.info("Network connected")
                } else {
                    Logger.shared.warning("Network disconnected - using mock API")
                }
            }
        }
        monitor.start(queue: queue)
    }

    func stopMonitoring() {
        monitor.cancel()
    }

    static func buildURL(base: String, path: String) -> URL? {
        var components = URLComponents(string: base)
        components?.path = path
        return components?.url
    }

    static func buildRequest(url: URL, method: String = "GET", headers: [String: String]? = nil, body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        headers?.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        request.httpBody = body
        return request
    }
}

// Combine support
import Combine

extension NetworkManager {
    var isConnectedPublisher: AnyPublisher<Bool, Never> {
        $isConnected.eraseToAnyPublisher()
    }
}
