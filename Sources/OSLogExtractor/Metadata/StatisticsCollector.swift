import Foundation

final class StatisticsCollector {
    private var levelCounts: [LogLevel: Int] = [:]
    private var subsystemCounts: [String: Int] = [:]
    private var categoryCounts: [String: Int] = [:]
    private var firstTimestamp: Date?
    private var lastTimestamp: Date?

    func observe(_ entry: LogEntry) {
        levelCounts[entry.level, default: 0] += 1

        if !entry.subsystem.isEmpty {
            subsystemCounts[entry.subsystem, default: 0] += 1
        }

        if !entry.category.isEmpty {
            categoryCounts[entry.category, default: 0] += 1
        }

        if let currentFirst = firstTimestamp {
            if entry.date < currentFirst { firstTimestamp = entry.date }
        } else {
            firstTimestamp = entry.date
        }

        if let currentLast = lastTimestamp {
            if entry.date > currentLast { lastTimestamp = entry.date }
        } else {
            lastTimestamp = entry.date
        }
    }

    func finalize() -> LogMetadata.Statistics {
        let counts = LogMetadata.Statistics.CountsByLevel(
            debug: levelCounts[.debug] ?? 0,
            info: levelCounts[.info] ?? 0,
            notice: levelCounts[.notice] ?? 0,
            error: levelCounts[.error] ?? 0,
            fault: levelCounts[.fault] ?? 0
        )

        return LogMetadata.Statistics(
            countsByLevel: counts,
            topSubsystems: topEntries(from: subsystemCounts),
            topCategories: topEntries(from: categoryCounts),
            firstTimestamp: firstTimestamp,
            lastTimestamp: lastTimestamp
        )
    }

    private func topEntries(from dictionary: [String: Int], limit: Int = 5) -> [LogMetadata.Statistics.TopEntry] {
        dictionary
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }
            .prefix(limit)
            .map { LogMetadata.Statistics.TopEntry(name: $0.key, count: $0.value) }
    }
}
