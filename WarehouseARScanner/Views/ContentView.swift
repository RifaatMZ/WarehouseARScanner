import SwiftUI

struct ContentView: View {
    @StateObject private var scanViewModel = ScanViewModel()
    @StateObject private var inventoryViewModel = InventoryViewModel()
    @StateObject private var comparisonViewModel = ComparisonViewModel()

    @State private var selectedTab: Int = 0

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                ScannerView(scanViewModel: scanViewModel, inventoryViewModel: inventoryViewModel)
                    .tag(0)
                    .tabItem {
                        Label("AR Scan", systemImage: "arkit")
                    }

                PaperScanView(comparisonViewModel: comparisonViewModel)
                    .tag(1)
                    .tabItem {
                        Label("Paper Scan", systemImage: "doc.text.viewfinder")
                    }

                ResultsView(
                    scanViewModel: scanViewModel,
                    inventoryViewModel: inventoryViewModel,
                    comparisonViewModel: comparisonViewModel
                )
                .tag(2)
                .tabItem {
                    Label("Results", systemImage: "list.clipboard")
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
