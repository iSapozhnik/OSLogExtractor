import Foundation
import OSLog

public struct LogBundle: Codable, Sendable {
    public let entries: [LogEntry]
    public let metadata: LogMetadata

    public init(entries: [LogEntry], metadata: LogMetadata) {
        self.entries = entries
        self.metadata = metadata
    }
}

public struct LogEntry: Sendable, Equatable, Codable {
    public let date: Date
    public let level: LogLevel
    public let subsystem: String
    public let category: String
    public let process: String
    public let threadID: UInt64
    public let message: String

    public init(
        date: Date,
        level: LogLevel,
        subsystem: String,
        category: String,
        process: String,
        threadID: UInt64,
        message: String
    ) {
        self.date = date
        self.level = level
        self.subsystem = subsystem
        self.category = category
        self.process = process
        self.threadID = threadID
        self.message = message
    }
}

public enum LogLevel: String, Codable, Sendable, CaseIterable {
    case debug, info, notice, error, fault
}
