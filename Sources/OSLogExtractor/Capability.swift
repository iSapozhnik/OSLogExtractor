import Foundation
import OSLog

public enum Capability {
    public static func isStoreAccessible() -> Bool {
        if #available(iOS 15.0, macOS 12.0, *) {
            #if os(iOS) || os(macOS)
            return true
            #else
            return false
            #endif
        } else {
            return false
        }
    }
}
