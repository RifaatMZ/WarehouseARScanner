import Foundation
import ARKit
import SceneKit

class ARKitService: NSObject, ARSessionDelegate {
    static let shared = ARKitService()

    private let arSession = ARSession()
    private var sceneView: ARSCNView?

    var frameCallback: ((CVPixelBuffer) -> Void)?
    var stateCallback: ((ARSessionState) -> Void)?

    enum ARSessionState {
        case notSupported
        case needsPermission
        case running
        case paused
        case failed(String)
    }

    override init() {
        super.init()
        arSession.delegate = self
    }

    func initialize(with sceneView: ARSCNView) {
        self.sceneView = sceneView
        sceneView.session = arSession
        sceneView.delegate = self
    }

    func start() {
        guard ARWorldTrackingConfiguration.isSupported else {
            Logger.shared.error("ARKit is not supported on this device")
            stateCallback?(.notSupported)
            return
        }

        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.environmentTexturing = .none   // Major source of heat - disabled

        // Person segmentation is heavy and not needed for warehouse label scanning
        // if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
        //     configuration.frameSemantics.insert(.personSegmentationWithDepth)
        // }

        arSession.run(configuration)
        Logger.shared.info("AR Session started")
        stateCallback?(.running)
    }

    func pause() {
        arSession.pause()
        Logger.shared.info("AR Session paused")
        stateCallback?(.paused)
    }

    func stop() {
        arSession.pause()
    }

    func addTextOverlay(_ text: String, at position: SCNVector3) {
        guard let sceneView = sceneView else { return }

        let textGeometry = SCNText(string: text, extrusionDepth: 1)
        textGeometry.font = UIFont.systemFont(ofSize: 10)

        let textNode = SCNNode(geometry: textGeometry)
        textNode.position = position
        textNode.scale = SCNVector3(0.01, 0.01, 0.01)

        sceneView.scene.rootNode.addChildNode(textNode)

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            textNode.removeFromParentNode()
        }
    }

    func getScreenCenter() -> CGPoint? {
        guard let sceneView = sceneView else { return nil }
        return CGPoint(x: sceneView.bounds.midX, y: sceneView.bounds.midY)
    }

    func raycastFromCenter() -> [ARRaycastResult]? {
        guard let sceneView = sceneView,
              let query = sceneView.raycastQuery(from: CGPoint(x: sceneView.bounds.midX, y: sceneView.bounds.midY),
                                                 allowing: .estimatedPlane,
                                                 alignment: .horizontal) else {
            return nil
        }
        return arSession.raycast(query)
    }

    // MARK: - ARSessionDelegate
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let pixelBuffer = frame.capturedImage
        frameCallback?(pixelBuffer)
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        Logger.shared.error("AR Session error: \(error)")
        stateCallback?(.failed(error.localizedDescription))
    }

    func sessionWasInterrupted(_ session: ARSession) {
        Logger.shared.info("AR Session interrupted")
        stateCallback?(.paused)
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        Logger.shared.info("AR Session interruption ended")
        stateCallback?(.running)
    }
}

extension ARKitService: ARSCNViewDelegate {
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        // Handle plane anchors
        guard let anchor = anchor as? ARPlaneAnchor else { return }
        Logger.shared.debug("Plane detected: \(anchor.extent)")
    }

    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        // Update plane detection
    }
}
