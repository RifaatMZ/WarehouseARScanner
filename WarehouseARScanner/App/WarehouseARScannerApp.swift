import SwiftUI

@main
struct WarehouseARScannerApp: App {
    @State private var hasPermission = false
    @State private var permissionDenied = false

    var body: some Scene {
        WindowGroup {
            if permissionDenied {
                PermissionDeniedView()
            } else if hasPermission {
                ContentView()
            } else {
                PermissionRequestView(hasPermission: $hasPermission, permissionDenied: $permissionDenied)
            }
        }
    }
}

struct PermissionRequestView: View {
    @Binding var hasPermission: Bool
    @Binding var permissionDenied: Bool

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            Text("Camera Permission Required")
                .font(.title2)
                .fontWeight(.bold)

            Text("WarehouseARScanner needs camera access to scan storage labels with AR")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Button(action: requestCameraPermission) {
                Text("Grant Permission")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }

            Button(action: { permissionDenied = true }) {
                Text("Deny")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .foregroundColor(.gray)
                    .cornerRadius(10)
            }
        }
        .padding(30)
    }

    private func requestCameraPermission() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                hasPermission = granted
                if !granted {
                    permissionDenied = true
                }
            }
        }
    }
}

struct PermissionDeniedView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.slash.fill")
                .font(.system(size: 60))
                .foregroundColor(.red)

            Text("Camera Access Denied")
                .font(.title2)
                .fontWeight(.bold)

            Text("WarehouseARScanner cannot function without camera access. Please enable it in Settings → WarehouseARScanner → Camera")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Button(action: openSettings) {
                Text("Open Settings")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .padding(30)
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

import AVFoundation
