import Foundation
import UIKit

extension Date {
    func formatted(style: DateFormatter.Style) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = style
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }

    var shortTimeAgo: String {
        let elapsed = Date().timeIntervalSince(self)
        if elapsed < 60 {
            return "just now"
        } else if elapsed < 3600 {
            let minutes = Int(elapsed / 60)
            return "\(minutes)m ago"
        } else if elapsed < 86400 {
            let hours = Int(elapsed / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(elapsed / 86400)
            return "\(days)d ago"
        }
    }
}

extension String {
    var isValidLabel: Bool {
        let pattern = "^[A-Z]-\\d{2}-\\d{2}$"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(location: 0, length: utf16.count)
        return regex?.firstMatch(in: self, options: [], range: range) != nil
    }

    func extractLabelComponents() -> (section: String, row: String, column: String)? {
        let parts = self.split(separator: "-").map(String.init)
        guard parts.count == 3 else { return nil }
        return (section: parts[0], row: parts[1], column: parts[2])
    }
}

extension Float {
    var percentageString: String {
        String(format: "%.0f%%", self * 100)
    }

    var confidenceDescription: String {
        switch self {
        case 0.9...:
            return "High (\(percentageString))"
        case 0.7..<0.9:
            return "Medium (\(percentageString))"
        default:
            return "Low (\(percentageString))"
        }
    }
}

extension UIImage {
    func resize(to size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}

extension CGPoint {
    func distance(to point: CGPoint) -> CGFloat {
        sqrt(pow(x - point.x, 2) + pow(y - point.y, 2))
    }
}

extension Array where Element: Hashable {
    var unique: [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
