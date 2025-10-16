import Foundation

public enum ExportFormat: Sendable {
    case json
    case text

    var fileExtension: String {
        switch self {
        case .json: return "json"
        case .text: return "log"
        }
    }
}

protocol StreamExporter {
    @discardableResult
    func export(stream: AsyncThrowingStream<LogEntry, Error>, to url: URL) async throws -> [URL]
}

struct JSONLinesExporter: StreamExporter {
    private let statisticsCollector: StatisticsCollector
    private let metadataCollector: MetadataCollector
    private let redactor: Redactor
    private let contextProvider: () -> MetadataCollector.Context

    init(statisticsCollector: StatisticsCollector, metadataCollector: MetadataCollector = MetadataCollector(), redactor: Redactor, contextProvider: @escaping () -> MetadataCollector.Context) {
        self.statisticsCollector = statisticsCollector
        self.metadataCollector = metadataCollector
        self.redactor = redactor
        self.contextProvider = contextProvider
    }

    func export(stream: AsyncThrowingStream<LogEntry, Error>, to url: URL) async throws -> [URL] {
        let logsURL = try prepare(url: url)
        let logHandle = try FileHandle(forWritingTo: logsURL)
        defer { try? logHandle.close() }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        try logHandle.write(contentsOf: Data("{\"entries\":[".utf8))
        var isFirstEntry = true

        for try await entry in stream {
            statisticsCollector.observe(entry)
            let redactedEntry = redactor.redact(entry: entry)
            let data = try encoder.encode(redactedEntry)
            if isFirstEntry {
                isFirstEntry = false
            } else {
                try logHandle.write(contentsOf: Data(",".utf8))
            }
            try logHandle.write(contentsOf: data)
        }

        let statistics = statisticsCollector.finalize()
        let metadata = metadataCollector.collect(context: contextProvider(), statistics: statistics)
        let metadataData = try encoder.encode(metadata)

        try logHandle.write(contentsOf: Data("]".utf8))
        try logHandle.write(contentsOf: Data(",\"metadata\":".utf8))
        try logHandle.write(contentsOf: metadataData)
        try logHandle.write(contentsOf: Data("}".utf8))

        return [logsURL]
    }
}

struct PlainTextExporter: StreamExporter {
    private let statisticsCollector: StatisticsCollector
    private let metadataCollector: MetadataCollector
    private let redactor: Redactor
    private let contextProvider: () -> MetadataCollector.Context

    init(statisticsCollector: StatisticsCollector, metadataCollector: MetadataCollector = MetadataCollector(), redactor: Redactor, contextProvider: @escaping () -> MetadataCollector.Context) {
        self.statisticsCollector = statisticsCollector
        self.metadataCollector = metadataCollector
        self.redactor = redactor
        self.contextProvider = contextProvider
    }

    func export(stream: AsyncThrowingStream<LogEntry, Error>, to url: URL) async throws -> [URL] {
        let logsURL = try prepare(url: url)
        let metadataURL = logsURL.deletingPathExtension().appendingPathExtension("metadata.json")

        let handle = try FileHandle(forWritingTo: logsURL)
        defer { try? handle.close() }

        let formatter = ISO8601DateFormatter()

        for try await entry in stream {
            statisticsCollector.observe(entry)
            let redacted = redactor.redact(entry: entry)
            let line = "\(formatter.string(from: redacted.date)) [\(redacted.level)] \(redacted.subsystem)/\(redacted.category) \(redacted.process)#\(redacted.threadID): \(redacted.message)\n"
            try handle.write(contentsOf: Data(line.utf8))
        }

        let statistics = statisticsCollector.finalize()
        let metadata = metadataCollector.collect(context: contextProvider(), statistics: statistics)
        try write(metadata: metadata, to: metadataURL)

        return [logsURL, metadataURL]
    }
}

private func prepare(url: URL) throws -> URL {
    let fm = FileManager.default
    if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
    let dir = url.deletingLastPathComponent()
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    fm.createFile(atPath: url.path, contents: nil)
    return url
}

private func write(metadata: LogMetadata, to url: URL) throws {
    let fm = FileManager.default
    if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
    let dir = url.deletingLastPathComponent()
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(metadata)
    fm.createFile(atPath: url.path, contents: data)
}
