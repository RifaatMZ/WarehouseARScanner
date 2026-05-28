import Foundation

struct StorageLabel: Identifiable, Codable {
    let id: UUID
    let text: String
    let confidence: Float
    let detectionTime: Date
    
    init(
        id: UUID = UUID(),
        text: String,
        confidence: Float,
        detectionTime: Date
    ) {
        self.id = id
        self.text = text
        self.confidence = confidence
        self.detectionTime = detectionTime
    }
    
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

// MARK: - Warehouse Label Range (for pre-defined scanning ranges)

/// Represents one row's column range.
/// This allows different rows to have different numbers of columns.
struct RowRangeDefinition: Codable, Identifiable, Equatable {
    var id = UUID()
    var row: String           // e.g. "05", "12", "3"
    var columnMin: Int
    var columnMax: Int
    var columnDigits: Int = 2
}

/// Represents a user-configured expected range of warehouse shelf labels.
/// Supports both simple global ranges and per-row custom column counts.
struct WarehouseLabelRange: Codable, Equatable {
    /// Whether range filtering is active
    var isEnabled: Bool = false

    // MARK: - Labeling Format (brought back to main settings)
    /// Use a custom labeling pattern (e.g. "LLNNLN", "A-12-34", etc.)
    var useCustomFormat: Bool = false
    var customFormat: String = "LLNNLN"

    /// Allowed sections, e.g. ["A", "B", "C", "D"]
    /// Empty = allow any section
    var allowedSections: [String] = []

    // MARK: - Simple Global Mode (most warehouses)
    var rowMin: Int = 1
    var rowMax: Int = 99
    var rowDigits: Int = 2

    var columnMin: Int = 1
    var columnMax: Int = 99
    var columnDigits: Int = 2

    // MARK: - Advanced Per-Row Mode
    /// When true, the app will use `rowRanges` instead of the global column min/max.
    /// This supports cases where different rows have different numbers of columns.
    var usePerRowRanges: Bool = false
    var rowRanges: [RowRangeDefinition] = []

    /// Default (disabled) range
    static let `default` = WarehouseLabelRange()

    /// Human-readable summary for the UI
    var summary: String {
        guard isEnabled else { return "Range filtering disabled" }

        let sections = allowedSections.isEmpty ? "Any" : allowedSections.joined(separator: ", ")

        if usePerRowRanges {
            let count = rowRanges.count
            return "Sections: \(sections) | \(count) custom row(s) defined"
        } else {
            let rows = "\(String(format: "%0\(rowDigits)d", rowMin))–\(String(format: "%0\(rowDigits)d", rowMax))"
            let cols = "\(String(format: "%0\(columnDigits)d", columnMin))–\(String(format: "%0\(columnDigits)d", columnMax))"
            return "Sections: \(sections) | Rows: \(rows) | Cols: \(cols)"
        }
    }
}

// MARK: - Persistence
extension WarehouseLabelRange {
    private static let storageKey = "warehouseLabelRange"

    static func load() -> WarehouseLabelRange {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let range = try? JSONDecoder().decode(WarehouseLabelRange.self, from: data) else {
            return .default
        }
        return range
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}

// MARK: - Virtual Warehouse Models (for building warehouse from paper scans)

// Represents one physical item scanned at a location (supports multiple items per bin).
struct CurrentItem: Codable, Equatable, Identifiable {
    var id = UUID()
    var itemNumber: String
    var lastScanned: Date?
    var quantity: Int?
    var notes: String?
}

struct VirtualLocation: Identifiable, Codable, Equatable {
    var id = UUID()
    var section: String
    var row: String
    var column: String

    /// Items from the original paper inventory list (reference / expected).
    /// Supports multiple items per location.
    var referenceItems: [String] = []

    /// Items actually found at this position via live AR scanning on the floor.
    /// Supports multiple items per location.
    var currentItems: [CurrentItem] = []

    // --- Legacy single-item fields (kept for migration + backward compat) ---
    /// Legacy: single reference item from paper. Will be migrated into referenceItems on load.
    var referenceItemNumber: String?

    /// Legacy: single current item. Will be migrated into currentItems on load.
    var currentItemNumber: String?

    var description: String?
    var lastScanned: Date?       // from paper
    var lastARScan: Date?        // from live AR

    /// The exact label string as it came from the paper scan / parser
    /// (e.g. "AA01A1"). We prefer this for display so we don't force dashes.
    var originalLabel: String?

    /// Display-friendly label.
    /// If we have the original scanned label, use it. Otherwise fall back to dashed.
    var formattedLocation: String {
        if let original = originalLabel, !original.isEmpty {
            return original
        }
        return "\(section)-\(row)-\(column)"
    }

    /// Convenience for old code / simple display: first current or first reference.
    var effectiveItemNumber: String? {
        currentItems.first?.itemNumber ?? referenceItems.first ?? currentItemNumber ?? referenceItemNumber
    }

    /// All items (current + legacy) for display purposes.
    var allCurrentItems: [String] {
        var items = currentItems.map { $0.itemNumber }
        if let legacy = currentItemNumber, !items.contains(legacy) {
            items.append(legacy)
        }
        return items
    }

    /// Migrates legacy single-item fields into the new array-based fields.
    /// Safe to call multiple times.
    mutating func migrateLegacyItemFields() {
        // Migrate reference
        if let legacyRef = referenceItemNumber, !referenceItems.contains(legacyRef) {
            referenceItems.append(legacyRef)
        }
        referenceItemNumber = nil   // clear legacy after migration

        // Migrate current
        if let legacyCur = currentItemNumber {
            let alreadyExists = currentItems.contains { $0.itemNumber == legacyCur }
            if !alreadyExists {
                currentItems.append(CurrentItem(itemNumber: legacyCur, lastScanned: lastARScan))
            }
        }
        currentItemNumber = nil
    }
}

struct VirtualRow: Identifiable, Codable, Equatable {
    var id = UUID()
    var row: String
    var locations: [VirtualLocation] = []

    var sortedLocations: [VirtualLocation] {
        locations.sorted { VirtualWarehouse.compareWarehouseLabels($0.column, $1.column) }
    }
}

struct VirtualSection: Identifiable, Codable, Equatable {
    var id = UUID()
    var section: String
    var rows: [VirtualRow] = []

    var sortedRows: [VirtualRow] {
        rows.sorted { VirtualWarehouse.compareWarehouseLabels($0.row, $1.row) }
    }
}

struct VirtualWarehouse: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var sections: [VirtualSection] = []
    var createdAt: Date = Date()
    var lastUpdated: Date = Date()
    var notes: String = ""

    var sortedSections: [VirtualSection] {
        sections.sorted { VirtualWarehouse.compareWarehouseLabels($0.section, $1.section) }
    }

    var totalLocations: Int {
        sections.reduce(0) { $0 + $1.rows.reduce(0) { $0 + $1.locations.count } }
    }
}

// MARK: - Warehouse label natural sort helpers

extension VirtualWarehouse {
    /// Natural / human-friendly comparator for warehouse label parts.
    /// Handles:
    /// - Pure numbers (1 < 2 < 10)
    /// - Letters (A < B < C < AA < AB)
    /// - Mixed (A1 < A2 < A10 < B1)
    /// This replaces the broken `Int(...) ?? 0` sorts that collapsed all letters to 0.
    static func compareWarehouseLabels(_ a: String, _ b: String) -> Bool {
        let s1 = a.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let s2 = b.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        let t1 = tokenizeAlphaNumeric(s1)
        let t2 = tokenizeAlphaNumeric(s2)

        for i in 0..<min(t1.count, t2.count) {
            if t1[i] == t2[i] { continue }

            // If both tokens are numeric, compare as numbers
            if let n1 = Int(t1[i]), let n2 = Int(t2[i]) {
                return n1 < n2
            }
            // Otherwise lexical (A before B, AA before AB, etc.)
            return t1[i] < t2[i]
        }
        return s1.count < s2.count
    }

    /// Splits a label into alternating text / number tokens for natural sorting.
    /// "AA01A2" → ["AA","01","A","2"]
    /// "A10"    → ["A","10"]
    /// "B"      → ["B"]
    /// "12"     → ["12"]
    private static func tokenizeAlphaNumeric(_ s: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var isNumber = false

        for ch in s {
            let digit = ch.isNumber
            if digit != isNumber, !current.isEmpty {
                tokens.append(current)
                current = ""
            }
            current.append(ch)
            isNumber = digit
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }
}

// MARK: - VirtualWarehouse Building & Editing Logic

extension VirtualWarehouse {
    /// Builds the virtual warehouse from scanned records.
    /// Pass `labelFormat` (e.g. "LLNNLN") to force the builder to recognize
    /// labels using the exact custom format the user provided during the paper scan.
    mutating func buildFromRecords(_ records: [WarehouseRecord],
                                   replaceExisting: Bool = false,
                                   labelFormat: String? = nil) {
        if replaceExisting {
            self.sections = []
        }

        for record in records {
            // Use the caller-provided format so the virtual warehouse respects
            // the custom labeling the user set in the Paper Scan view.
            guard let components = LabelParser.extractComponents(from: record.location, format: labelFormat) else {
                continue
            }

            let sectionName = components.section
            let rowName = components.row
            let columnName = components.column

            if let sectionIndex = sections.firstIndex(where: { $0.section == sectionName }) {
                var section = sections[sectionIndex]

                if let rowIndex = section.rows.firstIndex(where: { $0.row == rowName }) {
                    var row = section.rows[rowIndex]

                    if let locIndex = row.locations.firstIndex(where: { $0.column == columnName }) {
                        if !record.itemNumber.isEmpty && !row.locations[locIndex].referenceItems.contains(record.itemNumber) {
                            row.locations[locIndex].referenceItems.append(record.itemNumber)
                        }
                        row.locations[locIndex].lastScanned = record.timestamp
                        if row.locations[locIndex].originalLabel == nil {
                            row.locations[locIndex].originalLabel = record.location
                        }
                    } else {
                        let newLoc = VirtualLocation(
                            section: sectionName,
                            row: rowName,
                            column: columnName,
                            referenceItems: record.itemNumber.isEmpty ? [] : [record.itemNumber],
                            lastScanned: record.timestamp,
                            originalLabel: record.location
                        )
                        row.locations.append(newLoc)
                    }
                    section.rows[rowIndex] = row
                } else {
                    let newLoc = VirtualLocation(
                        section: sectionName,
                        row: rowName,
                        column: columnName,
                        referenceItems: record.itemNumber.isEmpty ? [] : [record.itemNumber],
                        lastScanned: record.timestamp,
                        originalLabel: record.location
                    )
                    let newRow = VirtualRow(row: rowName, locations: [newLoc])
                    section.rows.append(newRow)
                }
                sections[sectionIndex] = section
            } else {
                let newLoc = VirtualLocation(
                    section: sectionName,
                    row: rowName,
                    column: columnName,
                    referenceItems: record.itemNumber.isEmpty ? [] : [record.itemNumber],
                    lastScanned: record.timestamp,
                    originalLabel: record.location
                )
                let newRow = VirtualRow(row: rowName, locations: [newLoc])
                let newSection = VirtualSection(section: sectionName, rows: [newRow])
                sections.append(newSection)
            }
        }

        sortAll()
        self.lastUpdated = Date()
    }

    private mutating func sortAll() {
        sections = sections.sorted { VirtualWarehouse.compareWarehouseLabels($0.section, $1.section) }
        for i in sections.indices {
            sections[i].rows = sections[i].rows.sorted { VirtualWarehouse.compareWarehouseLabels($0.row, $1.row) }
            for j in sections[i].rows.indices {
                sections[i].rows[j].locations = sections[i].rows[j].locations.sorted { VirtualWarehouse.compareWarehouseLabels($0.column, $1.column) }
            }
        }
    }

    mutating func updateLocation(id: UUID,
                                 newSection: String? = nil,
                                 newRow: String? = nil,
                                 newColumn: String? = nil,
                                 newItemNumber: String? = nil,
                                 newOriginalLabel: String? = nil) {
        for (sIndex, section) in sections.enumerated() {
            for (rIndex, row) in section.rows.enumerated() {
                if let lIndex = row.locations.firstIndex(where: { $0.id == id }) {
                    var location = row.locations[lIndex]
                    if let newSection { location.section = newSection }
                    if let newRow { location.row = newRow }
                    if let newColumn { location.column = newColumn }
                    if let newItemNumber {
                        if !location.referenceItems.contains(newItemNumber) {
                            location.referenceItems.append(newItemNumber)
                        }
                    }
                    if let newOriginalLabel { location.originalLabel = newOriginalLabel }

                    var updatedRow = row
                    updatedRow.locations[lIndex] = location
                    var updatedSection = section
                    updatedSection.rows[rIndex] = updatedRow
                    sections[sIndex] = updatedSection
                    self.lastUpdated = Date()
                    sortAll()
                    return
                }
            }
        }
    }

    mutating func deleteLocation(id: UUID) {
        for (sIndex, section) in sections.enumerated() {
            for (rIndex, row) in section.rows.enumerated() {
                if let lIndex = row.locations.firstIndex(where: { $0.id == id }) {
                    var updatedRow = row
                    updatedRow.locations.remove(at: lIndex)
                    var updatedSection = section
                    if updatedRow.locations.isEmpty {
                        updatedSection.rows.remove(at: rIndex)
                    } else {
                        updatedSection.rows[rIndex] = updatedRow
                    }
                    sections[sIndex] = updatedSection
                    self.lastUpdated = Date()
                    return
                }
            }
        }
    }

    mutating func addManualLocation(section: String, row: String, column: String, itemNumber: String? = nil) {
        // Preserve the user's label style exactly (no forced dashes).
        // User wants things like "AA01A1", not "AA-0-1A1".
        let cleanOriginal = "\(section)\(row)\(column)"
        let newLoc = VirtualLocation(
            section: section,
            row: row,
            column: column,
            referenceItems: (itemNumber?.isEmpty == false) ? [itemNumber!] : [],
            originalLabel: cleanOriginal
        )
        if let sIndex = sections.firstIndex(where: { $0.section == section }) {
            var sec = sections[sIndex]
            if let rIndex = sec.rows.firstIndex(where: { $0.row == row }) {
                sec.rows[rIndex].locations.append(newLoc)
            } else {
                sec.rows.append(VirtualRow(row: row, locations: [newLoc]))
            }
            sections[sIndex] = sec
        } else {
            let newRow = VirtualRow(row: row, locations: [newLoc])
            sections.append(VirtualSection(section: section, rows: [newRow]))
        }
        sortAll()
        self.lastUpdated = Date()
    }

    /// Prepares the warehouse as a clean template / skeleton for floor use.
    /// Clears any live AR data and (optionally) reference items so the saved
    /// warehouse the user loads contains only positions.
    mutating func prepareAsEmptyTemplate(clearReferenceItems: Bool = false) {
        for sIndex in sections.indices {
            for rIndex in sections[sIndex].rows.indices {
                for lIndex in sections[sIndex].rows[rIndex].locations.indices {
                    if clearReferenceItems {
                        sections[sIndex].rows[rIndex].locations[lIndex].referenceItems = []
                    }
                    sections[sIndex].rows[rIndex].locations[lIndex].currentItems = []
                    sections[sIndex].rows[rIndex].locations[lIndex].lastARScan = nil
                }
            }
        }
        self.lastUpdated = Date()
    }

    /// Finds a location inside this warehouse by its formatted location string (best effort).
    /// Uses multiple normalization strategies to improve matching between paper-built
    /// warehouses and live AR detections.
    func findLocation(matching locationLabel: String) -> VirtualLocation? {
        let raw = locationLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = raw.uppercased()
        let cleaned = cleanForMatching(raw)

        for section in sections {
            for row in section.rows {
                for loc in row.locations {
                    let candidates: [String] = [
                        loc.formattedLocation,
                        loc.originalLabel ?? "",
                        loc.formattedLocation.replacingOccurrences(of: "-", with: ""),
                        loc.originalLabel?.replacingOccurrences(of: "-", with: "") ?? ""
                    ].map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }

                    if candidates.contains(upper) || candidates.contains(cleaned) {
                        return loc
                    }
                }
            }
        }
        return nil
    }

    /// Updates a position with data coming from live AR scanning.
    /// Supports multiple items per location — appends instead of overwriting.
    /// Returns true if a matching position was found and updated.
    mutating func recordARScan(at locationLabel: String, itemNumber: String?, timestamp: Date = Date()) -> Bool {
        guard let item = itemNumber?.trimmingCharacters(in: .whitespacesAndNewlines), !item.isEmpty else {
            return false
        }
        guard let found = findLocation(matching: locationLabel) else {
            return false
        }

        // Find the location by id and append the new item (if not already present)
        for sIndex in sections.indices {
            for rIndex in sections[sIndex].rows.indices {
                if let lIndex = sections[sIndex].rows[rIndex].locations.firstIndex(where: { $0.id == found.id }) {
                    let alreadyExists = sections[sIndex].rows[rIndex].locations[lIndex].currentItems.contains { $0.itemNumber == item }

                    if !alreadyExists {
                        let newItem = CurrentItem(itemNumber: item, lastScanned: timestamp)
                        sections[sIndex].rows[rIndex].locations[lIndex].currentItems.append(newItem)
                    }

                    sections[sIndex].rows[rIndex].locations[lIndex].lastARScan = timestamp
                    self.lastUpdated = Date()
                    return true
                }
            }
        }
        return false
    }

    /// Lightweight normalization used only for matching (not for display or storage).
    private func cleanForMatching(_ input: String) -> String {
        return input.uppercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "–", with: "")
            .replacingOccurrences(of: "—", with: "")
    }

    /// Returns a flattened list of all locations in the logical scanning order
    /// (useful for "next expected" anticipation).
    var flattenedLocationsInOrder: [VirtualLocation] {
        var result: [VirtualLocation] = []
        for section in sortedSections {
            for row in section.sortedRows {
                result.append(contentsOf: row.sortedLocations)
            }
        }
        return result
    }

    /// Migrates legacy single-item data on all locations (called on load).
    mutating func migrateAllLocations() {
        for sIndex in sections.indices {
            for rIndex in sections[sIndex].rows.indices {
                for lIndex in sections[sIndex].rows[rIndex].locations.indices {
                    sections[sIndex].rows[rIndex].locations[lIndex].migrateLegacyItemFields()
                }
            }
        }
    }
}

// MARK: - Simple Persistence (embedded to avoid new file dependency)
extension VirtualWarehouse {
    private static let storageDirectory = "VirtualWarehouses"

    static func save(_ warehouse: VirtualWarehouse) {
        var toSave = warehouse
        toSave.lastUpdated = Date()          // ensure the list shows correct "last modified" time

        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("Cannot save warehouse: no Documents directory")
            return
        }

        let dir = docs.appendingPathComponent(storageDirectory, isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            print("Failed to create VirtualWarehouses directory: \(error)")
            return
        }

        let file = dir.appendingPathComponent("\(toSave.id.uuidString).json")
        do {
            let data = try JSONEncoder().encode(toSave)
            try data.write(to: file, options: .atomic)
            print("Saved virtual warehouse: \(toSave.name) (\(toSave.totalLocations) locations)")
        } catch {
            print("Failed to save warehouse '\(toSave.name)': \(error)")
        }
    }

    static func loadAll() -> [VirtualWarehouse] {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return [] }
        let dir = docs.appendingPathComponent(storageDirectory, isDirectory: true)
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }

        return files.compactMap { url in
            guard url.pathExtension == "json",
                  let data = try? Data(contentsOf: url) else { return nil }
            var warehouse = try? JSONDecoder().decode(VirtualWarehouse.self, from: data)
            warehouse?.migrateAllLocations()
            return warehouse
        }.sorted { $0.lastUpdated > $1.lastUpdated }
    }

    static func delete(id: UUID) {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let file = docs.appendingPathComponent(storageDirectory).appendingPathComponent("\(id.uuidString).json")
        try? fm.removeItem(at: file)
    }

    static func load(id: UUID) -> VirtualWarehouse? {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let file = docs.appendingPathComponent(storageDirectory).appendingPathComponent("\(id.uuidString).json")
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(VirtualWarehouse.self, from: data)
    }
}
