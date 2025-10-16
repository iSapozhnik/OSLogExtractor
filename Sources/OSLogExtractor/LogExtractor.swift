import Foundation
import OSLog
import ZipArchive

@available(iOS 15.0, macOS 12.0, *)
public final class LogExtractor: @unchecked Sendable {
    private let store: OSLogStore
    private let restrictToCurrentProcess: Bool
    private let redactor: Redactor

    public convenience init(restrictToCurrentProcess: Bool? = nil, redactionMode: RedactionMode = .basic) throws {
        #if os(iOS) || os(macOS)
        let s = try OSLogStore(scope: .currentProcessIdentifier)
        #if os(iOS)
        let restrict = restrictToCurrentProcess ?? true
        #else
        let restrict = restrictToCurrentProcess ?? false
        #endif
        self.init(store: s, restrictToCurrentProcess: restrict, redactionMode: redactionMode)
        #else
        throw LogExtractorError.unsupportedPlatform
        #endif
    }

    public init(store: OSLogStore, restrictToCurrentProcess: Bool = false, redactionMode: RedactionMode = .basic) {
        self.store = store
        self.restrictToCurrentProcess = restrictToCurrentProcess
        self.redactor = Redactor(mode: redactionMode)
    }

    public func entries(matching filter: LogFilter) -> AsyncThrowingStream<LogEntry, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let startPos: OSLogPosition = store.position(date: filter.startDate ?? .distantPast)

                    var subpredicates: [NSPredicate] = []
                    if let subsystem = filter.subsystem, !subsystem.isEmpty {
                        subpredicates.append(NSPredicate(format: "subsystem == %@", subsystem))
                    }
                    if let category = filter.category, !category.isEmpty {
                        subpredicates.append(NSPredicate(format: "category == %@", category))
                    }
                    if let process = filter.process, !process.isEmpty {
                        subpredicates.append(NSPredicate(format: "process == %@", process))
                    }
                    if restrictToCurrentProcess {
                        let current = ProcessInfo.processInfo.processName
                        subpredicates.append(NSPredicate(format: "process == %@", current))
                    }
                    if let contains = filter.contains, !contains.isEmpty {
                        subpredicates.append(NSPredicate(format: "composedMessage CONTAINS[cd] %@", contains))
                    }

                    let predicate = subpredicates.isEmpty ? nil : NSCompoundPredicate(andPredicateWithSubpredicates: subpredicates)

                    let entries = try store.getEntries(at: startPos, matching: predicate)
                    let endDate = filter.endDate

                    for case let e as OSLogEntryLog in entries {
                        if let end = endDate, e.date > end { break }

                        let mappedLevel: LogLevel
                        switch e.level {
                        case .debug: mappedLevel = .debug
                        case .info: mappedLevel = .info
                        case .notice: mappedLevel = .notice
                        case .error: mappedLevel = .error
                        case .fault: mappedLevel = .fault
                        case .undefined: mappedLevel = .info
                        @unknown default: mappedLevel = .info
                        }

                        if let required = filter.level, required != mappedLevel { continue }

                        continuation.yield(
                            LogEntry(
                                date: e.date,
                                level: mappedLevel,
                                subsystem: e.subsystem,
                                category: e.category,
                                process: e.process,
                                threadID: UInt64(e.threadIdentifier),
                                message: e.composedMessage
                            )
                        )
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func export(matching filter: LogFilter, to url: URL, format: ExportFormat, zip: Bool = true) async throws {
        let collector = StatisticsCollector()
        let stream = entries(matching: filter)

        let contextProvider: () -> MetadataCollector.Context = { [filter] in
            MetadataCollector.Context(
                bundle: .main,
                processInfo: .processInfo,
                filter: filter,
                restrictToCurrentProcess: self.restrictToCurrentProcess
            )
        }

        let exporter: any StreamExporter
        switch format {
        case .json:
            exporter = JSONLinesExporter(statisticsCollector: collector, redactor: redactor, contextProvider: contextProvider)
        case .text:
            exporter = PlainTextExporter(statisticsCollector: collector, redactor: redactor, contextProvider: contextProvider)
        }

        let baseName = "logs-" + LogExtractor.filenameFormatterQueue.sync {
            LogExtractor.filenameFormatter.string(from: Date())
        }

        if zip {
            let workingDirectory = try temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: workingDirectory) }

            let payloadURL = workingDirectory.appendingPathComponent(baseName).appendingPathExtension(format.fileExtension)
            let exportedFiles = try await exporter.export(stream: stream, to: payloadURL)
            let archiveURL = try archiveURL(for: url, baseName: baseName)
            try archive(files: exportedFiles, to: archiveURL)
        } else {
            let destination = try destinationURL(for: url, format: format, baseName: baseName)
            _ = try await exporter.export(stream: stream, to: destination)
        }
    }

    private func destinationURL(for directory: URL, format: ExportFormat, baseName: String) throws -> URL {
        let resolvedDirectory = try resolveDirectory(directory)
        return resolvedDirectory
            .appendingPathComponent(baseName)
            .appendingPathExtension(format.fileExtension)
    }

    private func archiveURL(for directory: URL, baseName: String) throws -> URL {
        let resolvedDirectory = try resolveDirectory(directory)
        return resolvedDirectory
            .appendingPathComponent(baseName)
            .appendingPathExtension("zip")
    }

    private func resolveDirectory(_ directory: URL) throws -> URL {
        let fm = FileManager.default
        let resolvedDirectory: URL
        if directory.hasDirectoryPath {
            resolvedDirectory = directory
        } else {
            resolvedDirectory = directory.appendingPathComponent("", isDirectory: true)
        }
        try fm.createDirectory(at: resolvedDirectory, withIntermediateDirectories: true)
        return resolvedDirectory
    }

    private func temporaryDirectory() throws -> URL {
        let fm = FileManager.default
        let url = fm.temporaryDirectory.appendingPathComponent("OSLogExtractor-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func archive(files: [URL], to archiveURL: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: archiveURL.path) {
            try fm.removeItem(at: archiveURL)
        }
        let paths = files.map { $0.path }
        guard SSZipArchive.createZipFile(atPath: archiveURL.path, withFilesAtPaths: paths) else {
            throw LogExtractorError.zipFailed
        }
    }

    private static let filenameFormatterQueue = DispatchQueue(label: "LogExtractor.filenameFormatter")

    private static let filenameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }()
}
