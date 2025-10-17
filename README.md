# OSLogExtractor

Swift package for collecting and exporting Apple unified logging (`OSLog`) entries with structured metadata and redaction.

## Installation

Add `OSLogExtractor` as a package dependency via Xcode or in your `Package.swift`:

```swift
.package(path: "../OSLogExtractor")
```

Then add `OSLogExtractor` to your target dependencies.

## Usage

```swift
import OSLogExtractor

@available(iOS 15.0, macOS 12.0, *)
func exportRecentLogs() async throws {
    let extractor = try LogExtractor()
    let filter = LogFilter(
        startDate: Date().addingTimeInterval(-3600),
        levels: [.info],
        subsystem: "app.speakthis"
    )

    let logsDirectory = FileManager.default.temporaryDirectory

    try await extractor.export(matching: filter, to: logsDirectory, format: .json)
    // Produces logs-YYYYMMdd-HHmmss.zip containing logs-YYYYMMdd-HHmmss.json with entries and metadata.
}
```

To keep the raw files without compression, pass `zip: false`:

```swift
try await extractor.export(matching: filter, to: logsDirectory, format: .json, zip: false)
```

### Filtering by Log Level

`LogFilter` accepts a `levels` array so you can include multiple log levels in a single run. Provide the levels you care about; leave the array empty to include every level.

```swift
// Capture only error and fault entries.
let strictFilter = LogFilter(levels: [.error, .fault])

// Capture all entries regardless of level.
let everythingFilter = LogFilter()
```

## macOS Example

```swift
import AppKit
import OSLogExtractor
import UniformTypeIdentifiers

@available(macOS 12.0, *)
func exportWithSavePanel() {
    let panel = NSOpenPanel()
    panel.canCreateDirectories = true
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.prompt = "Choose"
    panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first

    panel.begin { response in
        guard response == .OK, let directoryURL = panel.url else { return }

        Task {
            do {
                let extractor = try LogExtractor()
                let filter = LogFilter(
                    startDate: Date().addingTimeInterval(-3600),
                    levels: [.info],
                    subsystem: "<subsystem>"
                )
                try await extractor.export(matching: filter, to: directoryURL, format: .json)
            } catch {
                // handle error
            }
        }
    }
}
```

## iOS Example

```swift
import OSLogExtractor
import SwiftUI
import UniformTypeIdentifiers

@available(iOS 15.0, *)
final class LogExportController: NSObject, UIDocumentPickerDelegate {
    func present(from presenter: UIViewController) {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        presenter.present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let directoryURL = urls.first else { return }
        Task {
            do {
                let extractor = try LogExtractor()
                let filter = LogFilter(
                    startDate: Date().addingTimeInterval(-3600),
                    levels: [.info],
                    subsystem: "<subsystem>"
                )
                try await extractor.export(matching: filter, to: directoryURL, format: .text, zip: false)
                // Produces logs-YYYYMMdd-HHmmss.log and logs-YYYYMMdd-HHmmss.metadata.json.
            } catch {
                // handle error
            }
        }
    }
}
```

## Metadata

Each export writes a companion `metadata.json` file containing:

- **app** — bundle identifier, display name, marketing version, and build number discovered from the provided bundle.
- **device** — platform (`iOS`/`macOS`), hardware model identifier (when available), OS version string, locale, region, timezone, battery info (iOS), and low power mode flag (iOS).
- **process** — current process name, PID/parent PID, CPU architecture, system boot time, app launch time, and uptime in seconds.
- **resources** — human-readable byte strings gathered at export time:
  - **memory**: `physical`, `footprint`, and `free` sizes for total RAM, process footprint, and free memory.
  - **disk**: `total`, `free`, and `appContainerFree` (space remaining inside the app's sandbox container).
- **networking** — active reachability (`wifi`, `cellular`, or `none`) and whether the path is marked as expensive.
- **loggingScope** — the effective log filter (start/end dates, level, subsystem, category, process, substring match), whether extraction was `restrictToCurrentProcess`, and the covered interval in seconds.
- **statistics** — counts by log level, top subsystems/categories, and timestamps for the first and last included entries.

Metadata collection is best effort and omits fields when unavailable; all sizes are formatted using `ByteCountFormatter`.

## Redaction

Basic redaction removes or masks:

- Bearer tokens (`Bearer ***`)
- API keys (`ApiKey ***`)
- Email addresses (`***@***`)
- Phone numbers (`***-***-****`)
- URL query parameters

To disable redaction, initialize `LogExtractor` with `redactionMode: .none`:

```swift
let extractor = try LogExtractor(redactionMode: .none)
```

## Testing

Run unit tests:

```bash
swift test --package-path SpeakThis/OSLogExtractor
```

## Notes

- Works on macOS 12+ and iOS 15+ (iOS limited to current process logs).
- Accessing system-wide logs may require running outside the App Store sandbox.
