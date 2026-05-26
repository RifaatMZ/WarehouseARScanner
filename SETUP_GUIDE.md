# WarehouseARScanner - iOS ARKit App Setup & Installation Guide

## Project Overview

WarehouseARScanner is a complete iOS app that uses ARKit, Vision framework, and SwiftUI to scan warehouse storage labels (e.g., A-12-34) in real-time. The app provides:

- **AR Real-Time Scanning**: Uses ARKit to display AR overlays of detected text labels
- **Vision OCR Recognition**: Detects and parses warehouse label text with confidence scores
- **REST API Integration**: Validates detected labels against inventory database (with mock API included)
- **Paper Scan Mode**: Alternative mode to manually scan paper labels using Vision OCR
- **Label Comparison**: Compare AR-detected labels with paper-scanned labels
- **Results Dashboard**: View all detections, matches, and generate reports

## System Requirements

- **Xcode**: 14.0 or later
- **iOS Target**: 15.0 or higher
- **Device**: iPhone 12 or later with ARKit support (A9+ processor required)
  - ARKit is not supported on simulator; use a real device for testing
- **Swift**: 5.7+
- **Frameworks**: ARKit, Vision, SceneKit, SwiftUI, Combine (all built-in)

## Project Structure

```
WarehouseARScanner/
├── App/
│   └── WarehouseARScannerApp.swift          # SwiftUI entry point
├── Models/
│   ├── StorageLabel.swift                  # Storage label model (existing)
│   ├── APIModels.swift                     # REST API request/response models
│   └── DetectionResult.swift               # Vision detection results
├── Services/
│   ├── ARKitService.swift                  # AR session management
│   ├── VisionService.swift                 # Text recognition service
│   └── APIService.swift                    # REST API client
├── ViewModels/
│   ├── ScanViewModel.swift                 # AR scanning state management
│   ├── InventoryViewModel.swift            # Inventory management
│   └── ComparisonViewModel.swift           # Label comparison logic
├── Views/
│   ├── ContentView.swift                   # Root view with tab navigation
│   ├── ScannerView.swift                   # Main AR scanning UI
│   ├── PaperScanView.swift                 # Manual paper scanning
│   ├── ResultsView.swift                   # Results & inventory display
│   └── ARViewContainer.swift               # ARSCNView wrapper
├── Utils/
│   ├── Constants.swift                     # App configuration
│   ├── Extensions.swift                    # SwiftUI/Foundation extensions
│   ├── Logger.swift                        # Debug logging utility
│   ├── LabelParser.swift                   # Label text parsing (regex)
│   ├── Mocks.swift                         # Mock API responses
│   └── NetworkManager.swift                # Network utilities
└── Info.plist                              # App permissions & metadata
```

## Installation Steps

### Step 1: Clone or Open Project

```bash
cd /Users/rifaat/Projects/WarehouseARScanner
```

### Step 2: Open in Xcode

```bash
open WarehouseARScanner/WarehouseARScanner.xcodeproj
```

Or use Xcode → File → Open → navigate to the project folder.

### Step 3: Configure Build Settings

1. **Select Team for Signing**:
   - In Xcode, select the project in the navigator
   - Select "WarehouseARScanner" target
   - Go to "Signing & Capabilities"
   - Select your Apple Developer Team from dropdown

2. **Set Bundle Identifier**:
   - Keep default or customize: `com.yourcompany.warehouseARScanner`

3. **Set Minimum iOS Deployment Target**:
   - Target: iOS 15.0 or higher

### Step 4: Verify Framework Availability

Xcode should automatically link these frameworks (already included in iOS):
- ARKit
- Vision
- SceneKit
- SwiftUI
- Combine
- AVFoundation

No CocoaPods or SPM dependencies needed.

### Step 5: Run on Device

1. **Connect Your iPhone** (12+ with ARKit support)
2. **Select Device**: In Xcode top toolbar, select your connected device
3. **Run the App**: Press Cmd+R or click "Run" button
4. **Grant Permissions**: When prompted, tap "Allow" for:
   - Camera access (required for AR scanning)
   - Photo library (for paper scanning mode)

## Configuration

### Mock API Setup (Default)

The app comes with mock API enabled. Inventory checks return sample data without network calls.

To use mock API:
- In `Utils/Constants.swift`, ensure:
  ```swift
  static let useMockAPI = true
  ```

### Real API Setup

To connect to a real REST API:

1. **Update Constants.swift**:
   ```swift
   static let useMockAPI = false
   static let apiBaseURL = "https://your-api-url.com"
   ```

2. **API Endpoint Expected**:
   - **POST** `/inventory/check`
   - **Request**: `InventoryCheckRequest` (see APIModels.swift)
   - **Response**: `InventoryCheckResponse` (see APIModels.swift)

3. **Example Request**:
   ```json
   {
     "detectedLabels": [
       {
         "text": "A-12-34",
         "confidence": 0.92,
         "timestamp": "2026-05-24T10:30:00Z"
       }
     ],
     "timestamp": "2026-05-24T10:30:00Z",
     "deviceId": "device-uuid"
   }
   ```

4. **Example Response**:
   ```json
   {
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
     "timestamp": "2026-05-24T10:30:00Z",
     "message": "Success"
   }
   ```

## Features & Usage

### 1. AR Scanning Mode (Tab 1)

**How to Use**:
1. Open the app and go to "AR Scan" tab
2. Point camera at printed warehouse label (A-12-34 format)
3. App automatically detects text and displays overlay
4. Detected labels appear in real-time with confidence scores
5. Tap "Play/Pause" to control scanning
6. Tap magnifying glass to check inventory
7. Tap trash to clear detections

**Label Format Supported**:
- `A-12-34` (preferred)
- `A 12 34` (space-separated)
- `A1234` (no separator)
- Any variation with single letter + two numbers twice

### 2. Paper Scanning Mode (Tab 2)

**How to Use**:
1. Go to "Paper Scan" tab
2. Tap "Select Photo" to choose an image from library
3. App processes the image and extracts text
4. Detected label displays at top
5. Tap "Confirm Detection" to save result
6. Later compare with AR scan in Results tab

### 3. Results Tab (Tab 3)

**Displays**:
- All detected labels with confidence scores
- Parsed components (Section, Row, Column)
- Inventory matches from API
- Item details (quantity, description, location)
- Comparison results (if AR vs Paper scan was done)

**Actions**:
- Menu → "Clear All": Reset all data
- Menu → "Copy Report": Copy results to clipboard as text

## Label Parsing

Labels are automatically parsed into components:

**Input**: `A-12-34`
**Output**:
```swift
LabelComponents(section: "A", row: "12", column: "34")
Formatted: "A-12-34"
```

Parsing handles:
- Missing or extra spaces
- OCR errors (low confidence catches these)
- Multiple format variations

## API Integration Details

### Mock API Responses

Sample inventory data in `Utils/Mocks.swift`:
- 5 pre-configured warehouse items
- Sections A-D with various row/column combinations
- Realistic quantities and descriptions

### Testing with Mock API

1. Ensure `Constants.useMockAPI = true`
2. On "AR Scan" tab, detect any label (e.g., "A-12-34")
3. Tap magnifying glass icon
4. API returns matching item from mock inventory
5. ResultsView displays matched items

### Error Handling

- **Low Confidence Detection**: Ignored if < 75% (configurable in Constants)
- **Invalid Label Format**: Logged as warning, not displayed
- **API Failure**: Shows error message; mock API is fallback
- **Network Disconnect**: NetworkManager detects and logs

## Logging

Debug logs output to:
- **Console**: Xcode debug area
- **OSLog**: System unified logging

Log Levels:
- 🔵 DEBUG: Detailed development info
- ℹ️ INFO: General app flow
- ⚠️ WARNING: Unexpected but recoverable events
- ❌ ERROR: Failures

Access logs via Xcode Console or Console.app.

## Testing Checklist

### Functional Tests

- [ ] App launches without crashes
- [ ] Camera permission request appears and works
- [ ] AR view initializes and shows live camera feed
- [ ] Print an "A-12-34" label, point camera at it
- [ ] Text detection occurs (Vision framework activates)
- [ ] Detected text appears in current detection box
- [ ] Confidence score is 75%+ (marked as high)
- [ ] Tap inventory check button
- [ ] Mock API returns matching item
- [ ] Results tab shows detected label + matched inventory
- [ ] Paper Scan tab: select photo → detect text → compare result
- [ ] Results tab: menu → clear all → data resets

### Edge Cases

- [ ] Low confidence (30-70%): Not displayed
- [ ] Invalid format (e.g., "XYZ123"): Ignored
- [ ] Partial label detection: Shown separately
- [ ] Multiple labels per frame: All detected
- [ ] Permission denied: Shows error screen

### Device Tests

- [ ] Run on iPhone 12 or later (real device required)
- [ ] Test in various lighting (bright, dim, sideways label)
- [ ] AR overlay text renders correctly
- [ ] No crashes during 5-minute scanning session

## Build & Deployment

### Build for Testing

```bash
# In Xcode
Cmd+B (Build)
Cmd+R (Run on selected device)
```

### Archive for App Store

```bash
Product → Archive
```

Then use Xcode's Organizer to distribute.

### System Capabilities Required

In Xcode:
- Project → Signing & Capabilities
- Add: "Network" capability (for API calls)
- "Camera" is implicit in Info.plist

## Performance Optimization

**Current Settings**:
- Process every 5th camera frame (not every frame)
- Vision recognition level: Fast (not accurate)
- AR plane detection: Horizontal + Vertical
- Light estimation: Enabled

**For Better Accuracy** (slower):
- Reduce frame skip: `Constants.processEveryNthFrame = 2`
- Increase recognition level: `VNRequestTextRecognitionLevel.accurate`

**For Better Performance** (faster):
- Increase frame skip: `Constants.processEveryNthFrame = 10`
- Reduce plane detection: Horizontal only

## Troubleshooting

### Issue: "ARKit not supported"
- **Solution**: Use iPhone 12+ with A9 or later processor. Simulator doesn't support ARKit.

### Issue: App crashes on launch
- **Solution**: Check Info.plist permissions are set. Verify Xcode build settings target iOS 15+.

### Issue: No text detection
- **Reason**: Label not in focus or lighting poor
- **Solution**: Print label clearly, point camera from 20-30cm away, good lighting

### Issue: Mock API returns no matches
- **Solution**: Detected label must match sample data. Try "A-12-34" exactly (exists in mock data).

### Issue: Camera permission denied
- **Solution**: Go to iPhone Settings → WarehouseARScanner → enable Camera.

### Issue: Photo Library not accessible in Paper Scan
- **Solution**: Grant photo library permission in app request or Settings.

## Development Notes

### Key Classes

- **ScanViewModel**: Coordinates AR detection and Vision processing
- **ARKitService**: Manages ARSession, frame capture
- **VisionService**: Handles text recognition, calls LabelParser
- **APIService**: Makes REST API calls (with mock fallback)
- **LabelParser**: Regex-based text parsing

### Data Flow

```
Camera Frame
    ↓
ARKitService.session(didUpdate:)
    ↓
VisionService.processFrame()
    ↓
ScanViewModel.processDetection()
    ↓
LabelParser.parse()
    ↓
ScanViewModel.detectedLabels
    ↓
SwiftUI Views update
```

### Extending the App

**Add Real API Endpoint**:
1. Edit `Constants.useMockAPI = false`
2. Update `Constants.apiBaseURL`
3. Update `APIService.checkInventory()` error handling as needed

**Add New Label Formats**:
1. Edit `LabelParser.parse()` regex patterns
2. Add tests for new format

**Add Inventory Sync**:
1. Create `SyncViewModel`
2. Implement periodic API calls
3. Cache inventory locally

## Support & Resources

- **ARKit Documentation**: https://developer.apple.com/arkit/
- **Vision Framework**: https://developer.apple.com/documentation/vision
- **SwiftUI Guide**: https://developer.apple.com/tutorials/swiftui
- **Xcode Help**: Xcode → Help → Developer Documentation

## License

This project is provided as-is for warehouse inventory management use.

---

**Project Created**: 2026-05-24
**Last Updated**: 2026-05-24
**Status**: Complete and ready for deployment
