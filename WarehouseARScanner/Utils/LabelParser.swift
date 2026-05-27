import Foundation

struct LabelParser {
    static let customFormatEnabledKey = "customLabelFormatEnabled"
    static let customFormatKey = "customLabelFormat"
    static let defaultFormat = "LLNNLN"

    /// Convenience: returns the format the user wants to use for location labels.
    /// Prefers the one stored in the current WarehouseLabelRange when enabled.
    static var activeCustomFormat: String? {
        let range = WarehouseLabelRange.load()
        if range.isEnabled && range.useCustomFormat, !range.customFormat.isEmpty {
            return range.customFormat
        }
        if UserDefaults.standard.bool(forKey: customFormatEnabledKey) {
            return UserDefaults.standard.string(forKey: customFormatKey)
        }
        return nil
    }
    private static let itemNumberPattern = "[0-9OIL|SBZ]{3}\\s*[-–—]?\\s*[0-9OIL|SBZ]{5}"

    static func parseWarehouseRecord(_ text: String, confidence: Float = 0.9) -> WarehouseRecord? {
        parseInventoryRecords(from: text, confidence: confidence).first
    }

    static func parseInventoryRecords(from text: String, confidence: Float = 0.9) -> [WarehouseRecord] {
        let cleanText = normalizeText(text)
        var records = parseRecordsByLine(from: cleanText, confidence: confidence)

        if records.isEmpty {
            records = parseRecordsFromCombinedText(cleanText, confidence: confidence)
        }

        return records.removingDuplicateRecords()
    }

    static func parseLabelText(_ text: String) -> String? {
        if UserDefaults.standard.bool(forKey: customFormatEnabledKey),
           let customFormat = UserDefaults.standard.string(forKey: customFormatKey),
           !customFormat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let customLabel = parseCustomLabel(text, format: customFormat) {
            return customLabel
        }

        return parse(text).map(format)
    }

    static func parse(_ text: String) -> LabelComponents? {
        let cleanText = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "_", with: "-")

        // Pattern: A-12-34, A 12 34, A1234, or the same label embedded in OCR text.
        let patterns = [
            "(?<![A-Z0-9])([A-Z])([0-9OIL|SBZ]{2})([0-9OIL|SBZ]{2})(?![A-Z0-9])",
            "(?<![A-Z0-9])([A-Z])\\s*[-:]?\\s*([0-9OIL|SBZ]{1,3})\\s*[-:\\s]+\\s*([0-9OIL|SBZ]{1,3})(?![A-Z0-9])"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let nsRange = NSRange(location: 0, length: cleanText.utf16.count)
                if let match = regex.firstMatch(in: cleanText, options: [], range: nsRange) {
                    if match.numberOfRanges == 4 {
                        let sectionRange = match.range(at: 1)
                        let rowRange = match.range(at: 2)
                        let columnRange = match.range(at: 3)

                        if let sectionRange = Range(sectionRange, in: cleanText),
                           let rowRange = Range(rowRange, in: cleanText),
                           let columnRange = Range(columnRange, in: cleanText) {
                            let section = String(cleanText[sectionRange])
                            let row = normalizeDigits(String(cleanText[rowRange]))
                            let column = normalizeDigits(String(cleanText[columnRange]))
                            let components = LabelComponents(section: section, row: row, column: column)

                            guard validate(components) else {
                                continue
                            }

                            Logger.shared.debug("Parsed label: \(section)-\(row)-\(column)")
                            return components
                        }
                    }
                }
            }
        }

        // Never log as warning when custom formats are in use — it is normal
        // for the legacy parser to fail on labels like "AA01A1".
        // This is now expected when using custom formats (LLNNLN etc.).
        // Downgrade to debug so it doesn't spam the console as a warning.
        Logger.shared.debug("Failed to parse label text with legacy parser: '\(text)'")
        return nil
    }

    static func validate(_ components: LabelComponents) -> Bool {
        // Relaxed for custom formats: allow multi-letter sections (e.g. "AA" for LLNNLN)
        let sectionValid = !components.section.isEmpty && components.section.allSatisfy { $0.isLetter }
        let rowValid = components.row.allSatisfy { $0.isNumber } && (1...3).contains(components.row.count)
        let columnValid = components.column.allSatisfy { $0.isNumber } && (1...3).contains(components.column.count)

        return sectionValid && rowValid && columnValid
    }

    static func format(_ components: LabelComponents) -> String {
        "\(components.section)-\(components.row)-\(components.column)"
    }

    private static func normalizeDigits(_ text: String) -> String {
        text
            .replacingOccurrences(of: "O", with: "0")
            .replacingOccurrences(of: "I", with: "1")
            .replacingOccurrences(of: "L", with: "1")
            .replacingOccurrences(of: "|", with: "1")
            .replacingOccurrences(of: "S", with: "5")
            .replacingOccurrences(of: "B", with: "8")
            .replacingOccurrences(of: "Z", with: "2")
    }

    private static func parseRecordsByLine(from text: String, confidence: Float) -> [WarehouseRecord] {
        text
            .components(separatedBy: .newlines)
            .compactMap { line in
                guard let location = firstLocation(in: line),
                      let itemNumber = firstItemNumber(in: line) else {
                    return nil
                }

                return WarehouseRecord(
                    location: location,
                    itemNumber: itemNumber,
                    confidence: confidence,
                    timestamp: Date()
                )
            }
    }

    private static func parseRecordsFromCombinedText(_ text: String, confidence: Float) -> [WarehouseRecord] {
        let locations = locationMatches(in: text)
        let itemNumbers = matches(for: itemNumberPattern, in: text).map(normalizeItemNumber)
        let count = min(locations.count, itemNumbers.count)

        guard count > 0 else {
            return []
        }

        return (0..<count).map { index in
            WarehouseRecord(
                location: locations[index],
                itemNumber: itemNumbers[index],
                confidence: confidence,
                timestamp: Date()
            )
        }
    }

    private static func firstLocation(in text: String) -> String? {
        locationMatches(in: text).first
    }

    private static func firstItemNumber(in text: String) -> String? {
        matches(for: itemNumberPattern, in: text).first.map(normalizeItemNumber)
    }

    private static func matches(for pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let nsRange = NSRange(location: 0, length: text.utf16.count)
        return regex.matches(in: text, options: [], range: nsRange).compactMap { match in
            guard let range = Range(match.range, in: text) else {
                return nil
            }

            return String(text[range])
        }
    }

    private static func locationMatches(in text: String) -> [String] {
        let format = activeLocationFormat
        let pattern = customRegexPattern(for: format)

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            Logger.shared.warning("Invalid shelf location format: '\(format)'")
            return []
        }

        let nsRange = NSRange(location: 0, length: text.utf16.count)
        return regex.matches(in: text, options: [], range: nsRange).compactMap { match in
            guard let range = Range(match.range(at: 1), in: text) else {
                return nil
            }

            return normalizeCustomMatch(String(text[range]), format: format)
        }
    }

    private static var activeLocationFormat: String {
        // Prefer the format from the new range configuration when enabled
        if let rangeFormat = activeCustomFormat, !rangeFormat.isEmpty {
            return rangeFormat.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }

        let configuredFormat = UserDefaults.standard.string(forKey: customFormatKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        guard UserDefaults.standard.bool(forKey: customFormatEnabledKey),
              let configuredFormat,
              !configuredFormat.isEmpty else {
            return defaultFormat
        }

        return configuredFormat
    }

    private static func normalizeItemNumber(_ text: String) -> String {
        let digits = normalizeDigits(text).filter { $0.isNumber }

        guard digits.count >= 8 else {
            return digits
        }

        let prefix = digits.prefix(3)
        let suffix = digits.dropFirst(3).prefix(5)
        return "\(prefix)-\(suffix)"
    }

    private static func parseCustomLabel(_ text: String, format: String) -> String? {
        let cleanText = normalizeText(text)
        let cleanFormat = format.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanFormat.isEmpty else { return nil }

        let pattern = customRegexPattern(for: cleanFormat)
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            Logger.shared.warning("Invalid custom label format: '\(format)'")
            return nil
        }

        let nsRange = NSRange(location: 0, length: cleanText.utf16.count)
        guard let match = regex.firstMatch(in: cleanText, options: [], range: nsRange),
              let matchRange = Range(match.range(at: 1), in: cleanText) else {
            return nil
        }

        return normalizeCustomMatch(String(cleanText[matchRange]), format: cleanFormat)
    }

    private static func normalizeText(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "_", with: "-")
    }

    private static func customRegexPattern(for format: String) -> String {
        var body = ""

        for character in format {
            switch character {
            case "L":
                body += "[A-Z]"
            case "N", "#":
                body += "[0-9OIL|SBZ]"
            case "A":
                body += "[A-Z0-9OIL|SBZ]"
            case " ", "-", ":":
                body += "\\s*[-:\\s]?\\s*"
            default:
                body += NSRegularExpression.escapedPattern(for: String(character))
            }
        }

        return "(?<![A-Z0-9])(\(body))(?![A-Z0-9])"
    }

    private static func normalizeCustomMatch(_ match: String, format: String) -> String {
        let matchCharacters = Array(match)
        let formatCharacters = Array(format)
        var normalized = ""
        var matchIndex = 0

        for formatCharacter in formatCharacters {
            guard matchIndex < matchCharacters.count else { break }

            switch formatCharacter {
            case "N", "#":
                normalized.append(normalizeDigits(String(matchCharacters[matchIndex])))
                matchIndex += 1
            case "L", "A":
                normalized.append(matchCharacters[matchIndex])
                matchIndex += 1
            default:
                while matchIndex < matchCharacters.count,
                      !matchCharacters[matchIndex].isLetter,
                      !matchCharacters[matchIndex].isNumber {
                    matchIndex += 1
                }
                normalized.append(formatCharacter)
            }
        }

        return normalized
    }
}

private extension Array where Element == WarehouseRecord {
    func removingDuplicateRecords() -> [WarehouseRecord] {
        var seen = Set<String>()
        return filter { record in
            let key = "\(record.location)|\(record.itemNumber)"
            return seen.insert(key).inserted
        }
    }
}

// MARK: - Warehouse Label Range Support

extension LabelParser {

    /// Returns whether the given shelf location string falls inside the provided range.
    /// Supports both global ranges and per-row custom column definitions.
    static func isLocationInRange(_ location: String, range: WarehouseLabelRange) -> Bool {
        guard range.isEnabled else { return true }

        guard let components = extractComponents(from: location) else {
            // Can't parse → be permissive for now
            return true
        }

        // Section check
        if !range.allowedSections.isEmpty {
            let upperSection = components.section.uppercased()
            let allowed = range.allowedSections.map { $0.uppercased() }
            if !allowed.contains(upperSection) {
                return false
            }
        }

        guard let rowNum = Int(components.row) else {
            return true // can't validate row
        }

        // Per-row mode (most flexible)
        if range.usePerRowRanges {
            if let rowDef = range.rowRanges.first(where: { $0.row == components.row || Int($0.row) == rowNum }) {
                let colNum = Int(components.column) ?? 0
                return colNum >= rowDef.columnMin && colNum <= rowDef.columnMax
            } else {
                // Row not explicitly defined → treat as out of range
                return false
            }
        }

        // Simple global mode
        if rowNum < range.rowMin || rowNum > range.rowMax {
            return false
        }

        if let colNum = Int(components.column) {
            if colNum < range.columnMin || colNum > range.columnMax {
                return false
            }
        }

        return true
    }

    /// Best-effort extraction of section/row/column from a location string.
    /// Supports an optional `format` parameter so callers (e.g. Virtual Warehouse builder)
    /// can force a specific custom format even if the global range settings are not active.
    static func extractComponents(from location: String, format: String? = nil) -> LabelComponents? {
        // When a format is explicitly passed from the paper scan (virtual warehouse builder),
        // use a direct, raw splitter on the original scanned text. This is the most reliable
        // path and does not depend on parseCustomLabel succeeding first.
        if let customFormat = format,
           !customFormat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {

            // When the user provides the format in Paper Scan (virtual warehouse builder),
            // try the most reliable group-based splitters first.
            if let components = directSplitUsingFormatRaw(location, format: customFormat) {
                return components
            }
            if let components = splitByFormatPattern(location, format: customFormat) {
                return components
            }
            if let components = splitCustomLocation(location, usingFormat: customFormat) {
                return components
            }
            if let components = naiveSplitCustomLabel(location) {
                return components
            }
        }

        // Fallback to the normal global custom format path
        let effectiveFormat = format ?? activeCustomFormat

        if let customFormat = effectiveFormat,
           !customFormat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let parsedLocation = parseCustomLabel(location, format: customFormat) {

            if let components = splitCustomLocation(parsedLocation, usingFormat: customFormat) {
                return components
            }
            if let components = splitByFormatPattern(parsedLocation, format: customFormat) {
                return components
            }
            if let components = naiveSplitCustomLabel(parsedLocation) {
                return components
            }
        }

        // Legacy parser only when no custom format at all
        if effectiveFormat == nil {
            if let comps = parse(location) {
                return comps
            }
        }
        if effectiveFormat == nil {
            if let comps = parse(location) {
                return comps
            }
        }

        // 3. Final flexible regex fallback
        let clean = location.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")

        let patterns = [
            "([A-Z]{1,2})[-\\s]?([0-9OIL|SBZ]{1,3})[-\\s]?([0-9OIL|SBZ]{1,3})",
            "([A-Z]{1,2})([0-9OIL|SBZ]{2})([0-9OIL|SBZ]{2})"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let nsRange = NSRange(location: 0, length: clean.utf16.count)
                if let match = regex.firstMatch(in: clean, options: [], range: nsRange),
                   match.numberOfRanges >= 4 {
                    if let sRange = Range(match.range(at: 1), in: clean),
                       let rRange = Range(match.range(at: 2), in: clean),
                       let cRange = Range(match.range(at: 3), in: clean) {

                        let section = String(clean[sRange])
                        let row = normalizeDigits(String(clean[rRange]))
                        let column = normalizeDigits(String(clean[cRange]))

                        let comps = LabelComponents(section: section, row: row, column: column)
                        if validate(comps) {
                            return comps
                        }
                    }
                }
            }
        }

        // If a format was explicitly provided (virtual warehouse builder path),
        // treat failure as debug, not a scary warning.
        if format != nil {
            Logger.shared.debug("Failed to parse label text into components (custom format provided): '\(location)'")
        } else {
            Logger.shared.warning("Failed to parse label text into components: '\(location)'")
        }
        return nil
    }

    /// Attempts to split a custom-formatted location string into section/row/column.
    /// This version is more defensive and handles formats like "LLNNLN" reliably.
    private static func splitCustomLocation(_ location: String, usingFormat format: String) -> LabelComponents? {
        let cleanLoc = cleanForFormatMatching(location)
        let cleanFormat = cleanForFormatMatching(format)

        guard !cleanLoc.isEmpty, cleanLoc.count == cleanFormat.count else {
            return nil
        }

        // Parse format into groups of consecutive types
        let formatGroups = groupFormatRuns(cleanFormat)

        // Consume the location according to the groups
        var groups: [String] = []
        var currentIndex = cleanLoc.startIndex

        for (_, length) in formatGroups {
            guard currentIndex < cleanLoc.endIndex else { break }
            let endIndex = cleanLoc.index(currentIndex, offsetBy: length, limitedBy: cleanLoc.endIndex) ?? cleanLoc.endIndex
            let group = String(cleanLoc[currentIndex..<endIndex])
            groups.append(group)
            currentIndex = endIndex
        }

        // Assign groups using the same semantic the user described:
        // leading letter runs → first component ("Row"), next number runs → second ("Section within row"), rest → location.
        var section = ""
        var row = ""
        var column = ""

        for (i, group) in groups.enumerated() {
            guard i < formatGroups.count else { break }
            let type = formatGroups[i].0

            if type == "L" || type == "A" {
                if section.isEmpty {
                    section = group
                } else {
                    column += group
                }
            } else if type == "N" || type == "#" {
                if row.isEmpty {
                    row = group
                } else {
                    column += group
                }
            }
        }

        // Only use a very conservative fallback if we completely failed to assign.
        let allChars = Array(cleanLoc)
        if section.isEmpty {
            if allChars.count >= 2 {
                section = String(allChars[0..<2])
            } else if allChars.count >= 1 {
                section = String(allChars[0..<1])
            }
        }
        if row.isEmpty && section.count < cleanLoc.count {
            let start = section.count
            let end = min(start + 2, cleanLoc.count)
            row = String(allChars[start..<end])
        }
        if column.isEmpty && (section.count + row.count) < cleanLoc.count {
            let start = section.count + row.count
            column = String(allChars[start...])
        }

        // IMPORTANT: Do not call normalizeDigits here.
        // It turns B→8, L→1, O→0 etc. This is useful for item numbers and legacy
        // numeric-only parsing, but it destroys real letters in custom-format locations
        // (AA01B2, A1, B3, etc. are common and must stay as letters).
        let components = LabelComponents(
            section: section,
            row: row,
            column: column
        )
        return components
    }

    // MARK: - Private helpers

    private static func cleanForFormatMatching(_ input: String) -> String {
        return input.uppercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "–", with: "")
            .replacingOccurrences(of: "—", with: "")
    }

    /// Turns a format like "LLNNLN" into [("L",2), ("N",2), ("L",1), ("N",1)]
    private static func groupFormatRuns(_ format: String) -> [(String, Int)] {
        var result: [(String, Int)] = []
        guard !format.isEmpty else { return result }

        var currentType = String(format.first!)
        var count = 0

        for char in format {
            let type: String
            switch char {
            case "L", "A": type = "L"
            case "N", "#": type = "N"
            default: continue
            }

            if type == currentType {
                count += 1
            } else {
                result.append((currentType, count))
                currentType = type
                count = 1
            }
        }

        if count > 0 {
            result.append((currentType, count))
        }

        return result
    }

    /// Applies the exact grouping from the format string to the location.
    /// Example: format "LLNNLN" + location "AA01A1" → section="AA", row="01", column="A1"
    private static func splitByFormatPattern(_ location: String, format: String) -> LabelComponents? {
        let cleanLoc = cleanForFormatMatching(location)
        let cleanFmt = cleanForFormatMatching(format)

        guard cleanLoc.count == cleanFmt.count else { return nil }

        let groups = groupFormatRuns(cleanFmt)
        var parts: [String] = []
        var idx = cleanLoc.startIndex

        for (_, len) in groups {
            guard idx < cleanLoc.endIndex else { break }
            let end = cleanLoc.index(idx, offsetBy: len, limitedBy: cleanLoc.endIndex) ?? cleanLoc.endIndex
            parts.append(String(cleanLoc[idx..<end]))
            idx = end
        }

        // Assign parts: leading letter groups → section, first number group → row, rest → column
        var section = "", row = "", column = ""
        var i = 0

        // Take leading letter groups for section
        while i < parts.count && groups[i].0 == "L" {
            section += parts[i]
            i += 1
        }

        // Next number group(s) for row
        while i < parts.count && groups[i].0 == "N" {
            row += parts[i]
            i += 1
        }

        // Everything else for column
        while i < parts.count {
            column += parts[i]
            i += 1
        }

        // Do not mangle letters here (B must stay B, not become 8).
        let comps = LabelComponents(section: section, row: row, column: column)
        return comps
    }

    /// Very naive fallback splitter used only when custom format is active.
    /// Tries to handle common real-world patterns like "AA01A1", "A12B3", etc.
    private static func naiveSplitCustomLabel(_ location: String) -> LabelComponents? {
        let clean = cleanForFormatMatching(location)
        let chars = Array(clean)

        guard chars.count >= 3 else { return nil }

        // Common pattern: 1-2 letters, then 1-3 digits, then rest
        var secEnd = 1
        if chars.count >= 2 && chars[1].isLetter { secEnd = 2 }

        let sec = String(chars[0..<secEnd])

        // Find where the next run of digits starts
        var rowStart = secEnd
        while rowStart < chars.count && !chars[rowStart].isNumber {
            rowStart += 1
        }

        // Take up to 3 digits for the row
        let rowEnd = min(rowStart + 3, chars.count)
        let row = String(chars[rowStart..<rowEnd])

        let col = rowEnd < chars.count ? String(chars[rowEnd...]) : ""

        // Preserve original letters (do not run normalizeDigits).
        let comps = LabelComponents(
            section: sec,
            row: row,
            column: col
        )
        return comps
    }

    /// Direct, reliable splitter used when a format is explicitly passed
    /// (the key path for "build virtual warehouse from paper scan").
    /// Uses exact run-length groups from the format (e.g. LLNNLN → 2L, 2N, 1L, 1N)
    /// so "AA01A2" is split as AA / 01 / A2 instead of AA / 0 / 1A2.
    private static func directSplitUsingFormatRaw(_ location: String, format: String) -> LabelComponents? {
        let cleanLoc = cleanForFormatMatching(location)
        let cleanFmt = cleanForFormatMatching(format)

        guard !cleanLoc.isEmpty, !cleanFmt.isEmpty else { return nil }

        let groups = groupFormatRuns(cleanFmt)

        var parts: [String] = []
        var idx = cleanLoc.startIndex

        for (_, len) in groups {
            guard idx < cleanLoc.endIndex else { break }
            let end = cleanLoc.index(idx, offsetBy: len, limitedBy: cleanLoc.endIndex) ?? cleanLoc.endIndex
            parts.append(String(cleanLoc[idx..<end]))
            idx = end
        }

        // Semantic assignment that matches the user's description:
        // - Leading letter run(s) (e.g. "AA") become the first component (shown as "Row" in the editor UI)
        // - Following number run(s) (e.g. "01") become the second component ("Section within row")
        // - Remaining characters (e.g. "A2") become the location within the section
        var section = "", row = "", column = ""
        var i = 0

        // Leading L groups → first bucket (currently stored in LabelComponents.section)
        while i < parts.count && groups[i].0 == "L" {
            section += parts[i]
            i += 1
        }
        // Next N groups → second bucket (LabelComponents.row)
        while i < parts.count && groups[i].0 == "N" {
            row += parts[i]
            i += 1
        }
        // Everything after that → location / column
        while i < parts.count {
            column += parts[i]
            i += 1
        }

        if section.isEmpty {
            return nil
        }

        // Do not normalize letters to digits here.
        // The format already told us which positions are letters (L/A) vs numbers (N/#).
        // normalizeDigits would turn a real 'B' location into '8', etc.
        return LabelComponents(
            section: section,
            row: row,
            column: column
        )
    }
}
