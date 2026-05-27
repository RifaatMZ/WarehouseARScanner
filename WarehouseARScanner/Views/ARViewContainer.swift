import SwiftUI
import ARKit
import SceneKit

struct ARViewContainer: UIViewControllerRepresentable {
    let arService = ARKitService.shared
    var scanViewModel: ScanViewModel?

    func makeUIViewController(context: Context) -> ARViewController {
        let controller = ARViewController()
        controller.scanViewModel = scanViewModel
        return controller
    }

    func updateUIViewController(_ uiViewController: ARViewController, context: Context) {}
}

class ARViewController: UIViewController, ARSCNViewDelegate {
    var arSceneView: ARSCNView?
    var scanViewModel: ScanViewModel?
    private let arService = ARKitService.shared

    override func viewDidLoad() {
        super.viewDidLoad()

        let sceneView = ARSCNView(frame: view.bounds)
        sceneView.delegate = self
        sceneView.autoenablesDefaultLighting = true
        sceneView.automaticallyUpdatesLighting = true
        view.addSubview(sceneView)

        self.arSceneView = sceneView

        arService.initialize(with: sceneView)
        arService.frameCallback = { [weak self] pixelBuffer in
            // Only feed frames to Vision while actively scanning.
            // This stops continuous OCR after we auto-pause on a valid label.
            if self?.scanViewModel?.isScanning == true {
                VisionService.shared.processFrame(pixelBuffer)
            }
        }

        // Add tap gesture to place markers
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        sceneView.addGestureRecognizer(tapGesture)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Do NOT auto-start the AR session.
        // The app should start in a paused state. The user must explicitly
        // tap "Start Scanning" / "Resume Scanning" to begin.
        // This significantly reduces heat and battery usage when the user
        // is not actively scanning.
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        scanViewModel?.stopScanning()
        arService.pause()
    }

    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: arSceneView)

        guard let arSceneView = arSceneView,
              let results = arSceneView.hitTest(location, options: [:]).first else {
            return
        }

        if let currentLabel = scanViewModel?.currentARLabel {
            let textNode = createTextNode(text: currentLabel.text)
            results.node.addChildNode(textNode)

            Logger.shared.debug("Placed label marker: \(currentLabel.text)")
        }
    }

    private func createTextNode(text: String) -> SCNNode {
        let textGeometry = SCNText(string: text, extrusionDepth: 1)
        textGeometry.font = UIFont.systemFont(ofSize: 10, weight: .bold)
        textGeometry.firstMaterial?.diffuse.contents = UIColor.green

        let textNode = SCNNode(geometry: textGeometry)
        textNode.scale = SCNVector3(0.005, 0.005, 0.005)
        textNode.position = SCNVector3(0, 0, -0.1)

        return textNode
    }

    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        Logger.shared.debug("AR anchor added")
    }
}

#Preview {
    ARViewContainer()
}
