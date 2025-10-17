import Foundation

public struct LogMetadata: Codable, Sendable {
    public struct App: Codable, Sendable {
        public let bundleID: String?
        public let displayName: String?
        public let version: String?
        public let build: String?
    }

    public struct Device: Codable, Sendable {
        public let platform: String
        public let model: String?
        public let osVersion: String
        public let locale: String?
        public let region: String?
        public let timezone: String?
        public let battery: Battery?
        public let lowPowerMode: Bool?

        public struct Battery: Codable, Sendable {
            public let level: Double?
            public let state: String
        }
    }

    public struct Process: Codable, Sendable {
        public let name: String
        public let pid: Int32
        public let parentPid: Int32
        public let arch: String?
        public let bootTime: Date?
        public let appLaunchTime: Date?
        public let uptimeSeconds: TimeInterval?
        public let threadCount: Int?
    }

    public struct Resources: Codable, Sendable {
        public struct Memory: Codable, Sendable {
            public let physical: String?
            public let footprint: String?
            public let free: String?
        }

        public struct Disk: Codable, Sendable {
            public let total: String?
            public let free: String?
            public let appContainerFree: String?
        }

        public let memory: Memory
        public let disk: Disk
    }

    public struct Networking: Codable, Sendable {
        public let reachability: String
        public let isExpensive: Bool?
    }

    public struct LoggingScope: Codable, Sendable {
        public struct Filter: Codable, Sendable {
            public let startDate: Date?
            public let endDate: Date?
            public let levels: [LogLevel]
            public let subsystem: String?
            public let category: String?
            public let process: String?
            public let contains: String?

            public init(
                startDate: Date?,
                endDate: Date?,
                levels: [LogLevel],
                subsystem: String?,
                category: String?,
                process: String?,
                contains: String?
            ) {
                self.startDate = startDate
                self.endDate = endDate
                self.levels = levels
                self.subsystem = subsystem
                self.category = category
                self.process = process
                self.contains = contains
            }
        }

        public let restrictToCurrentProcess: Bool
        public let filter: Filter
        public let includedIntervalSeconds: TimeInterval?
    }

    public struct Statistics: Codable, Sendable {
        public struct CountsByLevel: Codable, Sendable {
            public let debug: Int
            public let info: Int
            public let notice: Int
            public let error: Int
            public let fault: Int
        }

        public struct TopEntry: Codable, Sendable {
            public let name: String
            public let count: Int
        }

        public let countsByLevel: CountsByLevel
        public let topSubsystems: [TopEntry]
        public let topCategories: [TopEntry]
        public let firstTimestamp: Date?
        public let lastTimestamp: Date?
    }

    public let app: App?
    public let device: Device
    public let process: Process
    public let resources: Resources?
    public let networking: Networking?
    public let loggingScope: LoggingScope
    public let statistics: Statistics
}
