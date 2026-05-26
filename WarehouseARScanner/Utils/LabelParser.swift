import Foundation

struct LabelParser {
    static let customFormatEnabledKey = "customLabelFormatEnabled"
    static let customFormatKey = "customLabelFormat"
    static let defaultFormat = "LLNNLN"
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

        Logger.shared.warning("Failed to parse label text: '\(text)'")
        return nil
    }

    static func validate(_ components: LabelComponents) -> Bool {
        let sectionValid = components.section.count == 1 && components.section.allSatisfy { $0.isLetter }
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
