import Foundation

public enum RedactionMode {
    case none
    case basic
}

struct Redactor {
    enum Mode {
        case none
        case basic
    }

    private let mode: Mode

    init(mode: RedactionMode = .basic) {
        switch mode {
        case .none:
            self.mode = .none
        case .basic:
            self.mode = .basic
        }
    }

    func redact(entry: LogEntry) -> LogEntry {
        guard mode == .basic else { return entry }
        return LogEntry(
            date: entry.date,
            level: entry.level,
            subsystem: entry.subsystem,
            category: entry.category,
            process: entry.process,
            threadID: entry.threadID,
            message: decodePercentEncoding(in: redact(string: entry.message))
        )
    }

    func redact(string: String) -> String {
        guard mode == .basic else { return string }
        var working = string
        working = redactBearerTokens(in: working)
        working = redactAPIKeys(in: working)
        working = redactEmails(in: working)
        working = redactPhoneNumbers(in: working)
        working = stripQueryParameters(in: working)
        return working
    }

    private func redactBearerTokens(in value: String) -> String {
        value.replacingOccurrences(of: "(Bearer)\\s+([\\w\\-\\._~+/]+=*)", with: "$1 ***", options: [.regularExpression, .caseInsensitive])
    }

    private func redactAPIKeys(in value: String) -> String {
        value.replacingOccurrences(of: "(Api[- ]?Key)\\s+([\\w\\d]+)", with: "$1 ***", options: [.regularExpression, .caseInsensitive])
    }

    private func redactEmails(in value: String) -> String {
        value.replacingOccurrences(of: "[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}", with: "***@***", options: [.regularExpression, .caseInsensitive])
    }

    private func redactPhoneNumbers(in value: String) -> String {
        value.replacingOccurrences(of: "\\b(?:\\+?\\d[\\s-]?)?(?:\\(\\d{3}\\)|\\d{3})[\\s-]?\\d{3}[\\s-]?\\d{4}\\b", with: "***-***-****", options: [.regularExpression])
    }

    private func stripQueryParameters(in value: String) -> String {
        guard let url = URL(string: value),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return value }
        components.query = nil
        return components.string ?? value
    }

    private func decodePercentEncoding(in value: String) -> String {
        guard let decoded = value.removingPercentEncoding else { return value }
        return decoded
    }
}
