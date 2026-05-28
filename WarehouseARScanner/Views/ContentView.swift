import SwiftUI

struct ContentView: View {
    @StateObject private var scanViewModel = ScanViewModel()
    @StateObject private var inventoryViewModel = InventoryViewModel()
    @StateObject private var comparisonViewModel = ComparisonViewModel()

    @State private var selectedTab: Int = 0

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                // New dedicated Warehouse management section
                WarehousesTabView(scanViewModel: scanViewModel, selectedTab: $selectedTab)
                    .tag(0)
                    .tabItem {
                        Label("Warehouses", systemImage: "building.2")
                    }

                ScannerView(scanViewModel: scanViewModel, inventoryViewModel: inventoryViewModel)
                    .tag(1)
                    .tabItem {
                        Label("AR Scan", systemImage: "arkit")
                    }

                PaperScanView(comparisonViewModel: comparisonViewModel)
                    .tag(2)
                    .tabItem {
                        Label("Paper Scan", systemImage: "doc.text.viewfinder")
                    }

                ResultsView(
                    scanViewModel: scanViewModel,
                    inventoryViewModel: inventoryViewModel,
                    comparisonViewModel: comparisonViewModel
                )
                .tag(3)
                .tabItem {
                    Label("Results", systemImage: "list.clipboard")
                }
            }
        }
        .onChange(of: scanViewModel.shouldNavigateToResults) { shouldNavigate in
            if shouldNavigate {
                // Auto-advance to Results tab after a successful one-shot capture
                selectedTab = 2
                // Reset the flag so it doesn't keep firing
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    scanViewModel.shouldNavigateToResults = false
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("GoToWarehousesTab"))) { _ in
            selectedTab = 0
        }
    }
}

#Preview {
    ContentView()
}
