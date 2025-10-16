import Foundation

public struct LogFilter: Sendable, Equatable {
    public var startDate: Date?
    public var endDate: Date?
    public var level: LogLevel?
    public var subsystem: String?
    public var category: String?
    public var process: String?
    public var contains: String?

    public init(
        startDate: Date? = nil,
        endDate: Date? = nil,
        level: LogLevel? = nil,
        subsystem: String? = nil,
        category: String? = nil,
        process: String? = nil,
        contains: String? = nil
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.level = level
        self.subsystem = subsystem
        self.category = category
        self.process = process
        self.contains = contains
    }
}
