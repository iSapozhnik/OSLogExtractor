import Foundation

public enum LogExtractorError: Error, Sendable, Equatable {
    case unavailable(String)
    case permissionDenied
    case unsupportedPlatform
    case zipFailed
}
