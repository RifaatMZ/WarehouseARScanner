import Foundation
import os.log

enum LogLevel: Int {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3
}

class Logger {
    static let shared = Logger()

    private let osLog = OSLog(subsystem: "com.warehouse.ar.scanner", category: "app")
    private let logLevel: LogLevel = {
        #if DEBUG
        return .debug
        #else
        return .info
        #endif
    }()

    func log(
        _ message: String,
        level: LogLevel = .info,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        guard level.rawValue >= logLevel.rawValue else { return }

        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let context = "[\(fileName):\(line)] \(function)"

        let logType: OSLogType
        let prefix: String

        switch level {
        case .debug:
            logType = .debug
            prefix = "🔵 DEBUG"
        case .info:
            logType = .info
            prefix = "ℹ️ INFO"
        case .warning:
            logType = .default
            prefix = "⚠️ WARNING"
        case .error:
            logType = .error
            prefix = "❌ ERROR"
        }

        let logMessage = "\(prefix) \(context) - \(message)"
        os_log("%{public}@", log: osLog, type: logType, logMessage)

        #if DEBUG
        print(logMessage)
        #endif
    }

    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .debug, file: file, function: function, line: line)
    }

    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, file: file, function: function, line: line)
    }

    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .warning, file: file, function: function, line: line)
    }

    func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .error, file: file, function: function, line: line)
    }
}
